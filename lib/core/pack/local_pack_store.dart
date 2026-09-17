import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/pack.dart';

/// 本地整合包（不依赖后端）：制作 / 列表 / 导出 zip / 从 zip 导入。
class LocalPackStore {
  static const manifestName = 'xingqiong_pack.json';

  Future<Directory> _root() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'local_packs'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<List<LocalPackInfo>> list() async {
    final root = await _root();
    final out = <LocalPackInfo>[];
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final meta = File(p.join(e.path, manifestName));
      if (!await meta.exists()) continue;
      try {
        final j = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        out.add(LocalPackInfo.fromJson(j, e.path));
      } catch (_) {}
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  /// 制作本地整合包目录，并把 [jarPaths] 拷入 mods/。
  Future<LocalPackInfo> create({
    required String name,
    required String gameVersion,
    required String gameType,
    required String loaderType,
    String? loaderVersion,
    List<String> jarPaths = const [],
  }) async {
    final id = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final root = await _root();
    final dir = Directory(p.join(root.path, id));
    await dir.create(recursive: true);
    final modsDir = Directory(p.join(dir.path, 'mods'));
    await modsDir.create(recursive: true);
    final copied = <String>[];
    for (final path in jarPaths) {
      final src = File(path);
      if (!await src.exists()) continue;
      final nameOnly = p.basename(path);
      await src.copy(p.join(modsDir.path, nameOnly));
      copied.add(nameOnly);
    }
    final info = LocalPackInfo(
      id: id,
      name: name.trim().isEmpty ? '未命名整合包' : name.trim(),
      gameVersion: gameVersion,
      gameType: gameType,
      loaderType: loaderType,
      loaderVersion: loaderVersion,
      modFiles: copied,
      dirPath: dir.path,
      updatedAt: DateTime.now(),
    );
    await _writeMeta(info);
    return info;
  }

  Future<void> _writeMeta(LocalPackInfo info) async {
    final f = File(p.join(info.dirPath, manifestName));
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert(info.toJson()),
    );
  }

  /// 导出为 zip（含 manifest + mods/*.jar）。
  Future<File> exportZip(LocalPackInfo info, String destZipPath) async {
    final archive = Archive();
    final meta = File(p.join(info.dirPath, manifestName));
    if (await meta.exists()) {
      final bytes = await meta.readAsBytes();
      archive.addFile(ArchiveFile(manifestName, bytes.length, bytes));
    }
    final modsDir = Directory(p.join(info.dirPath, 'mods'));
    if (await modsDir.exists()) {
      await for (final e in modsDir.list()) {
        if (e is! File) continue;
        final bytes = await e.readAsBytes();
        final name = 'mods/${p.basename(e.path)}';
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw StateError('打包失败');
    final out = File(destZipPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(encoded, flush: true);
    return out;
  }

  /// 从 zip 导入本地整合包。
  Future<LocalPackInfo> importZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final id = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final root = await _root();
    final dir = Directory(p.join(root.path, id));
    await dir.create(recursive: true);
    await Directory(p.join(dir.path, 'mods')).create(recursive: true);

    Map<String, dynamic>? meta;
    final modFiles = <String>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      if (name.endsWith(manifestName) || name == manifestName) {
        meta = jsonDecode(utf8.decode(f.content as List<int>))
            as Map<String, dynamic>;
        continue;
      }
      if (name.contains('mods/') && name.toLowerCase().endsWith('.jar')) {
        final base = p.basename(name);
        final out = File(p.join(dir.path, 'mods', base));
        await out.writeAsBytes(f.content as List<int>);
        modFiles.add(base);
      }
    }

    final info = LocalPackInfo(
      id: id,
      name: (meta?['name'] as String?)?.trim().isNotEmpty == true
          ? meta!['name'] as String
          : p.basenameWithoutExtension(zipPath),
      gameVersion: '${meta?['game_version'] ?? '1.20.1'}',
      gameType: '${meta?['game_type'] ?? 'java'}',
      loaderType: '${meta?['loader_type'] ?? 'fabric'}',
      loaderVersion: meta?['loader_version'] as String?,
      modFiles: modFiles.isNotEmpty
          ? modFiles
          : ((meta?['mod_files'] as List?)?.map((e) => '$e').toList() ??
              const []),
      dirPath: dir.path,
      updatedAt: DateTime.now(),
    );
    await _writeMeta(info);
    return info;
  }

  /// 将本地包 mods 安装到实例 mods 目录。
  Future<int> installToModsDir(LocalPackInfo info, Directory modsDir) async {
    await modsDir.create(recursive: true);
    final src = Directory(p.join(info.dirPath, 'mods'));
    if (!await src.exists()) return 0;
    var n = 0;
    await for (final e in src.list()) {
      if (e is! File) continue;
      if (!e.path.toLowerCase().endsWith('.jar')) continue;
      final dest = File(p.join(modsDir.path, p.basename(e.path)));
      await e.copy(dest.path);
      n++;
    }
    return n;
  }
}

class LocalPackInfo {
  final String id;
  final String name;
  final String gameVersion;
  final String gameType;
  final String loaderType;
  final String? loaderVersion;
  final List<String> modFiles;
  final String dirPath;
  final DateTime updatedAt;

  const LocalPackInfo({
    required this.id,
    required this.name,
    required this.gameVersion,
    required this.gameType,
    required this.loaderType,
    required this.modFiles,
    required this.dirPath,
    required this.updatedAt,
    this.loaderVersion,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'game_version': gameVersion,
        'game_type': gameType,
        'loader_type': loaderType,
        if (loaderVersion != null) 'loader_version': loaderVersion,
        'mod_files': modFiles,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory LocalPackInfo.fromJson(Map<String, dynamic> j, String dirPath) {
    return LocalPackInfo(
      id: '${j['id'] ?? p.basename(dirPath)}',
      name: '${j['name'] ?? '未命名'}',
      gameVersion: '${j['game_version'] ?? ''}',
      gameType: '${j['game_type'] ?? 'java'}',
      loaderType: '${j['loader_type'] ?? 'fabric'}',
      loaderVersion: j['loader_version'] as String?,
      modFiles: (j['mod_files'] as List? ?? const []).map((e) => '$e').toList(),
      dirPath: dirPath,
      updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  PackSummary get asSummary => PackSummary(
        packId: id,
        name: '$name（本地）',
        gameVersion: gameVersion,
        gameType: gameType,
        loaderType: loaderType,
        shareCode: 'LOCAL',
      );
}
