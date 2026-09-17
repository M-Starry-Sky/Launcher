import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../download/download_sources.dart';
import '../update/app_version.dart';

/// 星穹优化（xingqiong-perf）源码获取：本地目录优先，否则从 GitHub 打包下载。
class PerfModSource {
  static const modId = 'xingqiong-perf';
  static const license = 'MIT';
  static const relativeInRepo = 'tool/xingqiong_hud_bridge';

  static String get githubTreeUrl =>
      '${AppVersion.githubRepoUrl}/tree/main/$relativeInRepo';

  static String get githubZipUrl =>
      '${AppVersion.githubRepoUrl}/archive/refs/heads/main.zip';

  static const apiDocHint =
      '对外 API：com.xingqiong.hud.api.XingqiongPerfApi · 构建见目录内 README';

  /// 在启动器旁 / 工程内寻找已有源码树。
  static Directory? resolveLocalSource() {
    final candidates = <String>[
      p.join(Directory.current.path, relativeInRepo),
      p.join(Directory.current.path, 'frontend', relativeInRepo),
      p.join(Directory.current.path, 'tool', 'xingqiong_hud_bridge'),
    ];
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.addAll([
        p.join(exeDir, relativeInRepo),
        p.join(exeDir, '..', relativeInRepo),
        p.join(exeDir, '..', '..', relativeInRepo),
        p.join(exeDir, '..', '..', '..', relativeInRepo),
      ]);
    } catch (_) {}

    for (final raw in candidates) {
      final dir = Directory(p.normalize(raw));
      if (_looksLikeSource(dir)) return dir;
    }
    return null;
  }

  static bool _looksLikeSource(Directory dir) {
    if (!dir.existsSync()) return false;
    final buildGradle = File(p.join(dir.path, 'build.gradle'));
    final fabric =
        File(p.join(dir.path, 'src', 'main', 'resources', 'fabric.mod.json'));
    return buildGradle.existsSync() || fabric.existsSync();
  }

  /// 默认导出目录：文档/Xingqiong/xingqiong-perf-src
  static Future<Directory> defaultExportDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'Xingqiong', 'xingqiong-perf-src'));
  }

  /// 下载 GitHub 仓库 zip，抽出模组源码目录到 [targetDir]。
  static Future<Directory> downloadSource({
    Directory? targetDir,
    void Function(String line)? onLog,
  }) async {
    final dest = targetDir ?? await defaultExportDir();
    onLog?.call('准备下载星穹优化源码…');
    onLog?.call('源：$githubZipUrl');

    final client = http.Client();
    try {
      final res = await client
          .get(
            Uri.parse(githubZipUrl),
            headers: {
              'User-Agent': DownloadSources.userAgent,
              'Accept': 'application/zip',
            },
          )
          .timeout(const Duration(minutes: 3));
      if (res.statusCode != 200) {
        throw StateError('下载失败 HTTP ${res.statusCode}');
      }
      onLog?.call(
        '已下载 ${(res.bodyBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB，正在解压…',
      );

      final archive = ZipDecoder().decodeBytes(res.bodyBytes, verify: true);
      if (dest.existsSync()) {
        await dest.delete(recursive: true);
      }
      await dest.create(recursive: true);

      var written = 0;
      for (final entry in archive) {
        final rel = _relUnderModSource(entry.name);
        if (rel == null) continue;
        if (rel.isEmpty) continue;
        if (_shouldSkip(rel)) continue;
        final outPath = p.join(dest.path, rel);
        if (!entry.isFile || entry.name.endsWith('/')) {
          await Directory(outPath).create(recursive: true);
          continue;
        }
        final out = File(outPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.content as List<int>, flush: true);
        written++;
      }

      if (written == 0) {
        throw StateError(
          '压缩包中未找到 $relativeInRepo（请到 GitHub 手动获取）',
        );
      }
      await File(p.join(dest.path, 'OPEN_SOURCE.txt')).writeAsString(
        '星穹优化（$modId）源码\n'
        '许可证：$license\n'
        '仓库：${AppVersion.githubRepoUrl}\n'
        '路径：$relativeInRepo\n'
        '构建：在本目录执行 .\\build_and_copy.ps1（Windows）或 ./gradlew build\n'
        'API：$apiDocHint\n',
        flush: true,
      );
      onLog?.call('源码已解压到 ${dest.path}（$written 个文件）');
      return dest;
    } finally {
      client.close();
    }
  }

  /// 若本地已有源码则复制到导出目录；否则走网络。
  static Future<Directory> obtainSource({
    Directory? targetDir,
    void Function(String line)? onLog,
    bool preferLocalCopy = true,
  }) async {
    final dest = targetDir ?? await defaultExportDir();
    if (preferLocalCopy) {
      final local = resolveLocalSource();
      if (local != null) {
        onLog?.call('发现本地源码：${local.path}');
        await _copyTree(local, dest, onLog: onLog);
        await File(p.join(dest.path, 'OPEN_SOURCE.txt')).writeAsString(
          '星穹优化（$modId）源码（自本地工程复制）\n'
          '原路径：${local.path}\n'
          '许可证：$license\n'
          'API：$apiDocHint\n',
          flush: true,
        );
        onLog?.call('已复制到 ${dest.path}');
        return dest;
      }
    }
    return downloadSource(targetDir: dest, onLog: onLog);
  }

  /// 返回相对于模组源码根的路径；非模组文件返回 null。
  static String? _relUnderModSource(String zipEntryName) {
    final n = zipEntryName.replaceAll('\\', '/');
    const marker = '$relativeInRepo/';
    final idx = n.indexOf(marker);
    if (idx < 0) return null;
    return n.substring(idx + marker.length);
  }

  static bool _shouldSkip(String rel) {
    final lower = rel.replaceAll('\\', '/').toLowerCase();
    if (lower.startsWith('build/')) return true;
    if (lower.startsWith('.gradle/')) return true;
    if (lower.startsWith('.git/')) return true;
    if (lower.contains('/build/')) return true;
    if (lower.endsWith('.jar')) return true;
    return false;
  }

  static Future<void> _copyTree(
    Directory src,
    Directory dest, {
    void Function(String line)? onLog,
  }) async {
    if (dest.existsSync()) {
      await dest.delete(recursive: true);
    }
    await dest.create(recursive: true);
    var n = 0;
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final rel = p.relative(entity.path, from: src.path);
      if (_shouldSkip(rel.replaceAll('\\', '/'))) continue;
      final outPath = p.join(dest.path, rel);
      if (entity is Directory) {
        await Directory(outPath).create(recursive: true);
      } else if (entity is File) {
        await File(outPath).parent.create(recursive: true);
        await entity.copy(outPath);
        n++;
      }
    }
    onLog?.call('已复制 $n 个文件');
  }
}
