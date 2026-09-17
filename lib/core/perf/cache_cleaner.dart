import 'dart:io';

import '../bedrock/bedrock_install.dart';

/// 真实磁盘清理：只删可再生成的垃圾，回报释放字节数。
class CacheCleaner {
  /// 清理游戏目录下的日志、崩溃报告、Mixin 缓存等。
  /// 不删存档、资源索引、libraries。
  static Future<CacheCleanReport> cleanGameDir(Directory gameDir) async {
    var files = 0;
    var bytes = 0;
    final notes = <String>[];

    Future<void> wipeDir(String rel, {bool onlyOld = false}) async {
      final dir = Directory('${gameDir.path}/$rel');
      if (!dir.existsSync()) return;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        if (onlyOld) {
          final age = DateTime.now().difference(e.lastModifiedSync());
          if (age.inDays < 3) continue;
        }
        try {
          final len = e.lengthSync();
          await e.delete();
          files++;
          bytes += len;
        } catch (_) {}
      }
      notes.add(rel);
    }

    await wipeDir('logs');
    await wipeDir('crash-reports');
    await wipeDir('.mixin.out');
    await wipeDir('natives');
    for (final name in const ['hs_err_pid', 'replay_pid']) {
      if (!gameDir.existsSync()) break;
      for (final e in gameDir.listSync().whereType<File>()) {
        final base = e.uri.pathSegments.last.toLowerCase();
        if (base.startsWith(name) || base.endsWith('.hprof')) {
          try {
            final len = e.lengthSync();
            await e.delete();
            files++;
            bytes += len;
            notes.add(base);
          } catch (_) {}
        }
      }
    }

    return CacheCleanReport(filesDeleted: files, bytesFreed: bytes, paths: notes);
  }

  static Future<CacheCleanReport> cleanInstance(Directory instanceDir) async {
    var files = 0;
    var bytes = 0;
    for (final rel in const ['.mixin.out', 'logs', 'crash-reports']) {
      final dir = Directory('${instanceDir.path}/$rel');
      if (!dir.existsSync()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        try {
          final len = e.lengthSync();
          await e.delete();
          files++;
          bytes += len;
        } catch (_) {}
      }
    }
    return CacheCleanReport(
      filesDeleted: files,
      bytesFreed: bytes,
      paths: [instanceDir.path],
    );
  }

  /// 基岩 UWP 临时缓存：只清 LocalCache / TempState，不动存档与资源包。
  static Future<CacheCleanReport> cleanBedrockTemps({
    BedrockInstallInfo? install,
  }) async {
    final info = install ?? await BedrockInstall.detect();
    if (info == null) {
      return const CacheCleanReport(
        filesDeleted: 0,
        bytesFreed: 0,
        paths: [],
      );
    }
    var files = 0;
    var bytes = 0;
    final notes = <String>[];

    Future<void> wipeTree(Directory dir, String label) async {
      if (!dir.existsSync()) return;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        try {
          final len = e.lengthSync();
          await e.delete();
          files++;
          bytes += len;
        } catch (_) {}
      }
      notes.add(label);
    }

    final root = info.packageRoot;
    await wipeTree(
      Directory('$root${Platform.pathSeparator}TempState'),
      'TempState',
    );
    await wipeTree(
      Directory('$root${Platform.pathSeparator}LocalCache'),
      'LocalCache',
    );
    for (final name in const ['treatment_pack', 'premium_cache']) {
      await wipeTree(
        Directory('${info.comMojangRoot}${Platform.pathSeparator}$name'),
        name,
      );
    }

    return CacheCleanReport(
      filesDeleted: files,
      bytesFreed: bytes,
      paths: notes,
    );
  }
}

class CacheCleanReport {
  final int filesDeleted;
  final int bytesFreed;
  final List<String> paths;

  const CacheCleanReport({
    required this.filesDeleted,
    required this.bytesFreed,
    required this.paths,
  });

  String get mbLabel => (bytesFreed / (1024 * 1024)).toStringAsFixed(1);

  String get summary =>
      filesDeleted == 0 ? '没有可清理的垃圾文件' : '已删除 $filesDeleted 个文件，约释放 $mbLabel MB';
}
