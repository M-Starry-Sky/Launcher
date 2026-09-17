import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'drop_import_kind.dart';

/// 根据扩展名与压缩包内条目，判断应落入哪类目录。
class ArchiveClassifier {
  /// 只读条目名，避免整包解压；大文件失败则退回扩展名启发式。
  static Future<DropImportKind> classify(String path) async {
    final lower = path.toLowerCase();
    final base = p.basename(lower);

    if (lower.endsWith('.jar')) return DropImportKind.mod;
    if (lower.endsWith('.png')) return DropImportKind.skin;
    if (lower.endsWith('.mcworld')) return DropImportKind.world;
    if (lower.endsWith('.mrpack')) return DropImportKind.localPack;

    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.directory) {
      return _classifyDir(Directory(path));
    }

    if (lower.endsWith('.zip') ||
        lower.endsWith('.mcpack') ||
        base.endsWith('.zip')) {
      return _classifyZip(path);
    }

    return DropImportKind.unknown;
  }

  static DropImportKind _classifyDir(Directory dir) {
    final level = File(p.join(dir.path, 'level.dat'));
    if (level.existsSync()) return DropImportKind.world;
    final pack = File(p.join(dir.path, 'pack.mcmeta'));
    if (pack.existsSync()) return DropImportKind.resourcePack;
    final shaders = Directory(p.join(dir.path, 'shaders'));
    if (shaders.existsSync()) return DropImportKind.shaderPack;
    final mods = Directory(p.join(dir.path, 'mods'));
    if (mods.existsSync()) return DropImportKind.localPack;
    return DropImportKind.unknown;
  }

  static Future<DropImportKind> _classifyZip(String path) async {
    try {
      final names = await _zipEntryNames(path);
      if (names.isEmpty) return DropImportKind.unknown;

      bool has(String frag) =>
          names.any((n) => n.toLowerCase().contains(frag.toLowerCase()));
      bool ends(String suffix) =>
          names.any((n) => n.toLowerCase().endsWith(suffix.toLowerCase()));

      if (ends('xingqiong_pack.json') || has('xingqiong_pack.json')) {
        return DropImportKind.localPack;
      }
      if (ends('level.dat') || has('/level.dat')) {
        return DropImportKind.world;
      }
      // 光影：shaders/ 或 Iris/OptiFine 结构
      if (has('shaders/') ||
          ends('shaders.properties') ||
          has('/shaders/')) {
        return DropImportKind.shaderPack;
      }
      // 模组误打成 zip / 内含 fabric 描述
      if (ends('fabric.mod.json') ||
          ends('quilt.mod.json') ||
          has('meta-inf/mods.toml') ||
          ends('mods.toml')) {
        return DropImportKind.mod;
      }
      if (ends('pack.mcmeta') || has('/pack.mcmeta')) {
        return DropImportKind.resourcePack;
      }
      // 看起来像整合包：根下有 mods/*.jar
      final jarInMods = names.any((n) {
        final x = n.replaceAll('\\', '/').toLowerCase();
        return x.contains('mods/') && x.endsWith('.jar');
      });
      if (jarInMods) return DropImportKind.localPack;

      // 文件名启发式
      final base = p.basename(path).toLowerCase();
      if (base.contains('shader') || base.contains('光影')) {
        return DropImportKind.shaderPack;
      }
      if (base.contains('resource') ||
          base.contains('材质') ||
          base.contains('资源')) {
        return DropImportKind.resourcePack;
      }
      if (base.contains('world') ||
          base.contains('save') ||
          base.contains('存档') ||
          base.contains('地图')) {
        return DropImportKind.world;
      }

      // 无明确标记的 zip：当作资源包更常见（用户常拖材质）
      return DropImportKind.resourcePack;
    } catch (_) {
      return DropImportKind.resourcePack;
    }
  }

  static Future<List<String>> _zipEntryNames(String path) async {
    final file = File(path);
    final len = await file.length();
    if (len > 256 * 1024 * 1024) {
      // 过大则不解包，交给文件名启发式
      return const [];
    }
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    return archive.files.map((f) => f.name.replaceAll('\\', '/')).toList();
  }
}
