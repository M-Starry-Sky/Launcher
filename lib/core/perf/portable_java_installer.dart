import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../download/download_sources.dart';
import '../download/network_env.dart';

/// 绿色免安装 JDK/JRE：自动探测网络，切换国内镜像 / 官方源。
class PortableJavaInstaller {
  final void Function(String line)? onLog;

  PortableJavaInstaller({this.onLog});

  static const _stallWindow = Duration(seconds: 12);
  static const _minStallBytes = 64 * 1024;
  static const _downloadTimeout = Duration(minutes: 20);

  Future<Directory> _root() async {
    if (Platform.isWindows) {
      final preferred = Directory(r'C:\xingqiong\runtimes\java');
      try {
        await preferred.create(recursive: true);
        return preferred;
      } catch (_) {}
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'runtimes', 'java'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String?> findInstalled(int major) async {
    final root = await _root();
    final home = Directory(p.join(root.path, 'jdk-$major'));
    if (!home.existsSync()) return null;
    final exe = Platform.isWindows
        ? p.join(home.path, 'bin', 'java.exe')
        : p.join(home.path, 'bin', 'java');
    if (File(exe).existsSync()) return exe;
    return _findJavaExe(home);
  }

  Future<String> ensure(int major, {bool forceReinstall = false}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      throw StateError(
        '手机端不安装桌面 Temurin。'
        'Java 版请通过 FCL/Zalith/Pojav 的 Android OpenJDK 运行'
        '（与主流手机启动器相同方案）。',
      );
    }
    if (!forceReinstall) {
      final existing = await findInstalled(major);
      if (existing != null) {
        if (await _canRun(existing)) {
          onLog?.call('已有绿色 Java $major: $existing');
          return existing;
        }
        onLog?.call('已有 Java $major 无法运行，准备重装…');
        await reinstall(major);
      }
    } else {
      await reinstall(major);
    }
    await NetworkEnv.instance.ensureProbed(onLog: onLog);
    onLog?.call('正在下载 Temurin Java $major（自动择优下载源）…');
    final archivePath = await _download(major).timeout(
      _downloadTimeout,
      onTimeout: () => throw TimeoutException('下载 Java $major 超时'),
    );
    onLog?.call('解压中…');
    final home = await _extract(archivePath, major);
    final exe = Platform.isWindows
        ? p.join(home.path, 'bin', 'java.exe')
        : p.join(home.path, 'bin', 'java');
    if (!File(exe).existsSync()) {
      // Temurin 偶发多一层目录：jdk-17.x.x+n/bin/java
      final nested = await _findJavaExe(home);
      if (nested == null) {
        throw StateError('解压后未找到 java 可执行文件');
      }
      onLog?.call('Java $major 已就绪: $nested');
      return nested;
    }
    if (!await _canRun(exe)) {
      throw StateError('Java $major 解压完成但无法执行 -version');
    }
    onLog?.call('Java $major 已就绪: $exe');
    return exe;
  }

  Future<void> reinstall(int major) async {
    final root = await _root();
    final home = Directory(p.join(root.path, 'jdk-$major'));
    final staging = Directory(p.join(root.path, 'jdk-$major.staging'));
    for (final d in [home, staging]) {
      if (d.existsSync()) {
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    }
    for (final ext in ['zip', 'tar.gz']) {
      final f = File(p.join(root.path, 'jdk-$major-download.$ext'));
      if (f.existsSync()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<bool> _canRun(String javaExe) async {
    try {
      final r = await Process.run(javaExe, ['-version'])
          .timeout(const Duration(seconds: 15));
      final out = '${r.stderr}${r.stdout}'.toLowerCase();
      return out.contains('version') || out.contains('openjdk');
    } catch (_) {
      if (!Platform.isWindows) return false;
      try {
        final r = await Process.run(
          'cmd',
          ['/c', '"$javaExe" -version'],
        ).timeout(const Duration(seconds: 15));
        final out = '${r.stderr}${r.stdout}'.toLowerCase();
        return out.contains('version') || out.contains('openjdk');
      } catch (_) {
        return false;
      }
    }
  }

  Future<String?> _findJavaExe(Directory home) async {
    final direct = Platform.isWindows
        ? File(p.join(home.path, 'bin', 'java.exe'))
        : File(p.join(home.path, 'bin', 'java'));
    if (direct.existsSync()) return direct.path;
    try {
      await for (final e in home.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final name = p.basename(e.path).toLowerCase();
        if (name == 'java.exe' || name == 'java') {
          final parent = p.basename(p.dirname(e.path)).toLowerCase();
          if (parent == 'bin') return e.path;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String> _download(int major) async {
    final os = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
            ? 'mac'
            : 'linux';
    final arch = _arch();
    final ext = Platform.isWindows ? 'zip' : 'tar.gz';
    final root = await _root();
    final outFile = File(p.join(root.path, 'jdk-$major-download.$ext'));

    // JRE 体积更小，优先；失败再 JDK。
    final imageTypes = <String>['jre', 'jdk'];
    Object? lastError;

    for (final imageType in imageTypes) {
      final uris = await NetworkEnv.instance.rankedJavaBinaryUris(
        major: major,
        os: os,
        arch: arch,
        imageType: imageType,
        onLog: onLog,
      );
      for (final uri in uris) {
        try {
          if (outFile.existsSync()) {
            try {
              await outFile.delete();
            } catch (_) {}
          }
          onLog?.call('尝试 ${uri.host}（$imageType）…');
          await _downloadUri(uri, outFile);
          if (await outFile.length() < 1024 * 1024) {
            throw StateError('下载文件过小，可能不是完整安装包');
          }
          onLog?.call('已从 ${uri.host} 完成下载');
          return outFile.path;
        } catch (e) {
          lastError = e;
          onLog?.call('源失败 ${uri.host}: $e，切换下一源…');
          try {
            if (outFile.existsSync()) await outFile.delete();
          } catch (_) {}
        }
      }
    }
    throw StateError('所有 Java 下载源均失败: $lastError');
  }

  Future<void> _downloadUri(Uri uri, File outFile) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      req.headers.addAll({
        'User-Agent': DownloadSources.userAgent,
        'Accept': '*/*',
      });
      final streamed = await client
          .send(req)
          .timeout(const Duration(seconds: 25));
      if (streamed.statusCode < 200 || streamed.statusCode >= 400) {
        throw StateError('HTTP ${streamed.statusCode}');
      }
      final total = streamed.contentLength ?? 0;
      var got = 0;
      var lastLog = DateTime.now();
      var lastStallCheck = DateTime.now();
      var gotAtStallCheck = 0;
      final sink = outFile.openWrite();
      try {
        await for (final chunk in streamed.stream.timeout(
          const Duration(seconds: 45),
          onTimeout: (sink) {
            sink.addError(TimeoutException('下载空闲超时，切换源'));
            sink.close();
          },
        )) {
          sink.add(chunk);
          got += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastLog).inSeconds >= 2) {
            lastLog = now;
            if (total > 0) {
              final mb = got / (1024 * 1024);
              final tmb = total / (1024 * 1024);
              final pct = (got * 100 / total).clamp(0, 100).toStringAsFixed(0);
              onLog?.call(
                'Java 下载中 $pct% ${mb.toStringAsFixed(1)}/${tmb.toStringAsFixed(1)} MB @ ${uri.host}',
              );
            } else {
              onLog?.call(
                'Java 下载中 ${(got / (1024 * 1024)).toStringAsFixed(1)} MB @ ${uri.host}',
              );
            }
          }
          if (now.difference(lastStallCheck) >= _stallWindow) {
            final delta = got - gotAtStallCheck;
            if (delta < _minStallBytes) {
              throw TimeoutException(
                '下载几乎停滞（${_stallWindow.inSeconds}s < ${_minStallBytes ~/ 1024}KB），切换源',
              );
            }
            lastStallCheck = now;
            gotAtStallCheck = got;
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  Future<Directory> _extract(String archivePath, int major) async {
    final root = await _root();
    final target = Directory(p.join(root.path, 'jdk-$major'));
    final staging = Directory(p.join(root.path, 'jdk-$major.staging'));
    if (target.existsSync()) {
      await target.delete(recursive: true);
    }
    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    // 流式解压到磁盘，避免整包读入内存（JDK zip 可达 100MB+）
    await extractFileToDisk(archivePath, staging.path, asyncWrite: true);

    String? top;
    final children = staging.listSync();
    Directory content = staging;
    if (children.length == 1 && children.first is Directory) {
      content = children.first as Directory;
      top = p.basename(content.path);
    }

    await target.create(recursive: true);
    for (final e in content.listSync()) {
      final name = p.basename(e.path);
      final dest = p.join(target.path, name);
      try {
        await e.rename(dest);
      } catch (_) {
        if (e is File) {
          await e.copy(dest);
        } else if (e is Directory) {
          await _copyDir(e, Directory(dest));
        }
      }
    }
    // 若解压后 java 不在 bin/，把内层 jdk-* 目录内容再抬一层
    final javaExe = await _findJavaExe(target);
    if (javaExe != null) {
      final binDir = Directory(p.dirname(javaExe));
      final expectedBin = Directory(p.join(target.path, 'bin'));
      if (binDir.path.toLowerCase() != expectedBin.path.toLowerCase()) {
        final nestedHome = binDir.parent;
        onLog?.call('校正 Java 目录层级…');
        final tmp = Directory(p.join(root.path, 'jdk-$major.flatten'));
        if (tmp.existsSync()) await tmp.delete(recursive: true);
        await tmp.create(recursive: true);
        await _copyDir(nestedHome, tmp);
        await target.delete(recursive: true);
        await tmp.rename(target.path);
      }
    }
    try {
      await staging.delete(recursive: true);
    } catch (_) {}
    try {
      await File(archivePath).delete();
    } catch (_) {}
    await File(p.join(target.path, '.xingqiong-runtime.json')).writeAsString(
      jsonEncode({
        'major': major,
        'top': top,
        'at': DateTime.now().toIso8601String(),
      }),
    );
    return target;
  }

  Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list(recursive: true)) {
      final rel = p.relative(e.path, from: from.path);
      final dest = p.join(to.path, rel);
      if (e is Directory) {
        await Directory(dest).create(recursive: true);
      } else if (e is File) {
        await File(dest).parent.create(recursive: true);
        await e.copy(dest);
      }
    }
  }

  String _arch() {
    final info = Platform.version.toLowerCase();
    if (info.contains('arm') || info.contains('aarch64')) return 'aarch64';
    return 'x64';
  }
}
