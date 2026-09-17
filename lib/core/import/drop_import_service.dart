import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../game/game_instance.dart';
import '../pack/local_pack_store.dart';
import 'archive_classifier.dart';
import 'drop_import_kind.dart';

class DropImportItemResult {
  final String sourcePath;
  final DropImportKind kind;
  final String? destPath;
  final String message;
  final bool ok;

  const DropImportItemResult({
    required this.sourcePath,
    required this.kind,
    required this.message,
    this.destPath,
    this.ok = true,
  });
}

class DropImportBatchResult {
  final List<DropImportItemResult> items;

  const DropImportBatchResult(this.items);

  int get okCount => items.where((e) => e.ok).length;
  int get failCount => items.where((e) => !e.ok).length;

  String summary() {
    if (items.isEmpty) return '没有可导入的文件';
    final parts = <String>[];
    final byKind = <DropImportKind, int>{};
    for (final i in items.where((e) => e.ok)) {
      byKind[i.kind] = (byKind[i.kind] ?? 0) + 1;
    }
    for (final e in byKind.entries) {
      parts.add('${e.value} 个${e.key.label}');
    }
    if (failCount > 0) parts.add('$failCount 个失败');
    if (parts.isEmpty) return items.map((e) => e.message).join('；');
    return '已自动归类：${parts.join('、')}';
  }
}

/// 全局拖放：识别类型并写入当前实例（或皮肤/本地整合包）对应目录。
class DropImportService {
  final InstanceStore store;

  DropImportService(this.store);

  Future<DropImportBatchResult> importPaths(List<String> paths) async {
    final results = <DropImportItemResult>[];
    for (final raw in paths) {
      final path = p.normalize(raw.trim());
      if (path.isEmpty) continue;
      try {
        results.add(await _importOne(path));
      } catch (e) {
        results.add(DropImportItemResult(
          sourcePath: path,
          kind: DropImportKind.unknown,
          ok: false,
          message: '${p.basename(path)} 失败: $e',
        ));
      }
    }
    return DropImportBatchResult(results);
  }

  Future<DropImportItemResult> _importOne(String path) async {
    final kind = await ArchiveClassifier.classify(path);
    final name = p.basename(path);

    if (kind == DropImportKind.unknown) {
      return DropImportItemResult(
        sourcePath: path,
        kind: kind,
        ok: false,
        message: '无法识别「$name」类型',
      );
    }

    if (kind == DropImportKind.skin) {
      final dest = await _copyFile(path, store.skinsDir(), name);
      return DropImportItemResult(
        sourcePath: path,
        kind: kind,
        destPath: dest.path,
        message: '皮肤 → skins/$name',
      );
    }

    if (kind == DropImportKind.localPack) {
      if (FileSystemEntity.isDirectorySync(path)) {
        return DropImportItemResult(
          sourcePath: path,
          kind: kind,
          ok: false,
          message: '请拖放整合包 zip，暂不支持文件夹',
        );
      }
      final lower = path.toLowerCase();
      if (lower.endsWith('.mrpack')) {
        final inst = store.selected;
        if (inst == null) {
          return DropImportItemResult(
            sourcePath: path,
            kind: kind,
            ok: false,
            message: '导入 .mrpack 前请先选择实例',
          );
        }
        final n = await _importMrpack(path, store.instanceGameDir(inst));
        return DropImportItemResult(
          sourcePath: path,
          kind: kind,
          message: 'Modrinth 整合包：已写入 $n 个文件到当前实例',
        );
      }
      final info = await LocalPackStore().importZip(path);
      return DropImportItemResult(
        sourcePath: path,
        kind: kind,
        destPath: info.dirPath,
        message: '整合包「${info.name}」已导入',
      );
    }

    final inst = store.selected;
    if (inst == null) {
      return DropImportItemResult(
        sourcePath: path,
        kind: kind,
        ok: false,
        message: '请先在启动页选择实例，再拖入$name',
      );
    }

    final root = store.instanceGameDir(inst);
    switch (kind) {
      case DropImportKind.mod:
        final dir = Directory(p.join(root.path, 'mods'));
        late final String destPath;
        if (FileSystemEntity.isDirectorySync(path)) {
          final out = await _copyTree(
            Directory(path),
            dir,
            p.basenameWithoutExtension(name),
          );
          destPath = out.path;
        } else {
          final destName =
              name.toLowerCase().endsWith('.jar') ? name : name;
          final out = await _copyFile(path, dir, destName);
          destPath = out.path;
        }
        return DropImportItemResult(
          sourcePath: path,
          kind: kind,
          destPath: destPath,
          message: '模组 → mods/${p.basename(destPath)}',
        );
      case DropImportKind.resourcePack:
        final dir = Directory(p.join(root.path, 'resourcepacks'));
        final dest = await _placePackOrFolder(path, dir, name);
        return DropImportItemResult(
          sourcePath: path,
          kind: kind,
          destPath: dest,
          message: '资源包 → resourcepacks/${p.basename(dest)}',
        );
      case DropImportKind.shaderPack:
        final dir = Directory(p.join(root.path, 'shaderpacks'));
        final dest = await _placePackOrFolder(path, dir, name);
        return DropImportItemResult(
          sourcePath: path,
          kind: kind,
          destPath: dest,
          message: '光影 → shaderpacks/${p.basename(dest)}',
        );
      case DropImportKind.world:
        final dir = Directory(p.join(root.path, 'saves'));
        final dest = await _placeWorld(path, dir, name);
        return DropImportItemResult(
          sourcePath: path,
          kind: kind,
          destPath: dest,
          message: '存档 → saves/${p.basename(dest)}',
        );
      case DropImportKind.skin:
      case DropImportKind.localPack:
      case DropImportKind.unknown:
        throw StateError('unreachable');
    }
  }

  Future<String> _placePackOrFolder(
    String path,
    Directory destDir,
    String name,
  ) async {
    await destDir.create(recursive: true);
    if (FileSystemEntity.isDirectorySync(path)) {
      final out = await _copyTree(
        Directory(path),
        destDir,
        p.basename(path),
      );
      return out.path;
    }
    // zip / mcpack 保持压缩包形式放入目录（MC 原生支持）
    final dest = await _copyFile(path, destDir, name);
    return dest.path;
  }

  Future<String> _placeWorld(
    String path,
    Directory savesDir,
    String name,
  ) async {
    await savesDir.create(recursive: true);
    if (FileSystemEntity.isDirectorySync(path)) {
      final folder = _uniqueName(savesDir, p.basename(path));
      final out = await _copyTree(Directory(path), savesDir, folder);
      return out.path;
    }

    // zip / mcworld：解压到 saves/<名>
    final folder = _uniqueName(
      savesDir,
      p.basenameWithoutExtension(name),
    );
    final target = Directory(p.join(savesDir.path, folder));
    await target.create(recursive: true);
    await extractFileToDisk(path, target.path, asyncWrite: true);

    // 若解压后多包一层且内层有 level.dat，抬一层
    await _flattenWorldIfNeeded(target);
    return target.path;
  }

  Future<void> _flattenWorldIfNeeded(Directory target) async {
    final level = File(p.join(target.path, 'level.dat'));
    if (level.existsSync()) return;
    final children = target.listSync().whereType<Directory>().toList();
    if (children.length != 1) return;
    final inner = children.first;
    if (!File(p.join(inner.path, 'level.dat')).existsSync()) return;
    final tmp = Directory('${target.path}.flatten_tmp');
    if (tmp.existsSync()) await tmp.delete(recursive: true);
    await inner.rename(tmp.path);
    for (final e in target.listSync()) {
      try {
        await e.delete(recursive: true);
      } catch (_) {}
    }
    for (final e in tmp.listSync()) {
      final dest = p.join(target.path, p.basename(e.path));
      try {
        await e.rename(dest);
      } catch (_) {
        if (e is File) {
          await e.copy(dest);
        } else if (e is Directory) {
          await _copyTree(e, target, p.basename(e.path));
        }
      }
    }
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }

  /// Modrinth .mrpack：抽出 overrides/ 到实例根，jar 进 mods（不拉远程文件）。
  Future<int> _importMrpack(String path, Directory instanceRoot) async {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    var count = 0;
    final modsDir = Directory(p.join(instanceRoot.path, 'mods'));
    await modsDir.create(recursive: true);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      final lower = name.toLowerCase();
      if (lower.startsWith('overrides/')) {
        final rel = name.substring('overrides/'.length);
        if (rel.isEmpty || rel.endsWith('/')) continue;
        final out = File(p.join(instanceRoot.path, rel));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>);
        count++;
      } else if (lower.endsWith('.jar') && !lower.contains('/')) {
        final out = File(p.join(modsDir.path, p.basename(name)));
        await out.writeAsBytes(f.content as List<int>);
        count++;
      }
    }
    return count;
  }

  Future<File> _copyFile(String src, Directory destDir, String fileName) async {
    await destDir.create(recursive: true);
    final unique = _uniqueFileName(destDir, fileName);
    final dest = File(p.join(destDir.path, unique));
    await File(src).copy(dest.path);
    return dest;
  }

  Future<Directory> _copyTree(
    Directory src,
    Directory destParent,
    String folderName,
  ) async {
    final unique = _uniqueName(destParent, folderName);
    final dest = Directory(p.join(destParent.path, unique));
    await dest.create(recursive: true);
    await for (final e in src.list(recursive: true, followLinks: false)) {
      final rel = p.relative(e.path, from: src.path);
      final out = p.join(dest.path, rel);
      if (e is Directory) {
        await Directory(out).create(recursive: true);
      } else if (e is File) {
        await File(out).parent.create(recursive: true);
        await e.copy(out);
      }
    }
    return dest;
  }

  String _uniqueName(Directory parent, String name) {
    var candidate = name;
    var i = 2;
    while (Directory(p.join(parent.path, candidate)).existsSync() ||
        File(p.join(parent.path, candidate)).existsSync()) {
      candidate = '$name ($i)';
      i++;
    }
    return candidate;
  }

  String _uniqueFileName(Directory parent, String fileName) {
    final stem = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var candidate = fileName;
    var i = 2;
    while (File(p.join(parent.path, candidate)).existsSync()) {
      candidate = '$stem ($i)$ext';
      i++;
    }
    return candidate;
  }
}
