import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_version.dart';
import 'github_update_service.dart';

/// 下载安装包并拉起静默更新（Windows Setup / 便携 zip）。
class AppUpdater {
  final void Function(String line)? onLog;

  AppUpdater({this.onLog});

  static const _downloadTimeout = Duration(minutes: 30);
  static const _stallWindow = Duration(seconds: 20);
  static const _minStallBytes = 64 * 1024;

  /// 有更新时下载并应用；成功后本进程会退出。
  Future<void> downloadAndApply(UpdateCheckResult update) async {
    if (!update.hasUpdate) {
      throw StateError('当前无需更新');
    }
    final url = (update.downloadUrl ?? '').trim();
    if (url.isEmpty || !_isDirectPackage(url)) {
      throw StateError('更新地址不可直接下载，请手动打开发布页');
    }

    onLog?.call('正在下载 ${update.remoteVersion}…');
    final file = await _download(url).timeout(
      _downloadTimeout,
      onTimeout: () => throw TimeoutException('下载更新超时'),
    );
    onLog?.call('下载完成，准备安装…');
    await _apply(file);
  }

  bool _isDirectPackage(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('/releases') && !lower.contains('/download/')) {
      return false;
    }
    return lower.endsWith('.exe') ||
        lower.endsWith('.zip') ||
        lower.endsWith('.msix');
  }

  Future<File> _download(String url) async {
    final dir = await _cacheDir();
    final name = _fileNameFromUrl(url);
    final out = File(p.join(dir.path, name));
    if (out.existsSync()) {
      try {
        await out.delete();
      } catch (_) {}
    }

    final uris = _downloadCandidates(url);
    Object? lastError;
    for (final uri in uris) {
      try {
        onLog?.call('尝试 ${uri.host}…');
        await _downloadUri(uri, out);
        final len = await out.length();
        if (len < 256 * 1024) {
          throw StateError('安装包过小（$len bytes）');
        }
        onLog?.call(
          '已下载 ${(len / (1024 * 1024)).toStringAsFixed(1)} MB',
        );
        return out;
      } catch (e) {
        lastError = e;
        onLog?.call('源失败 ${uri.host}: $e');
        try {
          if (out.existsSync()) await out.delete();
        } catch (_) {}
      }
    }
    throw StateError('更新下载失败: $lastError');
  }

  List<Uri> _downloadCandidates(String url) {
    final official = Uri.parse(url);
    final out = <Uri>[];
    final seen = <String>{};
    void add(Uri u) {
      if (seen.add(u.toString())) out.add(u);
    }

    final raw = official.toString();
    for (final prefix in const [
      'https://ghfast.top/',
      'https://mirror.ghproxy.com/',
      'https://ghproxy.net/',
    ]) {
      add(Uri.parse('$prefix$raw'));
    }
    add(official);
    return out;
  }

  Future<void> _downloadUri(Uri uri, File outFile) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      req.headers.addAll({
        'User-Agent': 'XingqiongLauncher/${AppVersion.version}',
        'Accept': '*/*',
      });
      final streamed =
          await client.send(req).timeout(const Duration(seconds: 30));
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
          const Duration(seconds: 60),
          onTimeout: (s) {
            s.addError(TimeoutException('下载空闲超时'));
            s.close();
          },
        )) {
          sink.add(chunk);
          got += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastLog).inSeconds >= 2) {
            lastLog = now;
            if (total > 0) {
              final pct = (got * 100 / total).clamp(0, 100).toStringAsFixed(0);
              onLog?.call(
                '更新下载 $pct% ${(got / (1024 * 1024)).toStringAsFixed(1)}/'
                '${(total / (1024 * 1024)).toStringAsFixed(1)} MB',
              );
            } else {
              onLog?.call(
                '更新下载 ${(got / (1024 * 1024)).toStringAsFixed(1)} MB',
              );
            }
          }
          if (now.difference(lastStallCheck) >= _stallWindow) {
            final delta = got - gotAtStallCheck;
            if (delta < _minStallBytes) {
              throw TimeoutException('下载几乎停滞，切换源');
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

  Future<void> _apply(File package) async {
    final lower = package.path.toLowerCase();
    if (lower.endsWith('.exe')) {
      await _runSetup(package);
      return;
    }
    if (lower.endsWith('.zip')) {
      await _applyPortableZip(package);
      return;
    }
    throw StateError('暂不支持该安装包格式');
  }

  Future<void> _runSetup(File setup) async {
    if (!Platform.isWindows) {
      throw StateError('当前系统请手动安装更新包');
    }
    final args = <String>[
      '/VERYSILENT',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/FORCECLOSEAPPLICATIONS',
      '/SUPPRESSMSGBOXES',
    ];
    onLog?.call('正在启动安装程序…');
    await Process.start(
      setup.path,
      args,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    exit(0);
  }

  Future<void> _applyPortableZip(File zip) async {
    final exe = Platform.resolvedExecutable;
    final appDir = Directory(p.dirname(exe));
    final staging = Directory(
      p.join(
        (await getTemporaryDirectory()).path,
        'xingqiong_update_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await staging.create(recursive: true);

    onLog?.call('正在解压便携包…');
    final ok = await _extractZip(zip.path, staging.path);
    if (!ok) {
      throw StateError('解压更新包失败');
    }

    final payload = _findPayloadRoot(staging);
    if (payload == null) {
      throw StateError('更新包内未找到可执行文件');
    }

    if (Platform.isWindows) {
      final bat = File(p.join(staging.path, 'apply_update.bat'));
      final exeName = p.basename(exe);
      final script = '''
@echo off
timeout /t 2 /nobreak >nul
xcopy /E /Y /I /Q "${payload.path}\\*" "${appDir.path}\\"
start "" "${p.join(appDir.path, exeName)}"
del /F /Q "%~f0"
''';
      await bat.writeAsString(script);
      await Process.start(
        'cmd.exe',
        ['/c', bat.path],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    }
    throw StateError('当前系统的便携更新请手动替换文件');
  }

  Future<bool> _extractZip(String zipPath, String dest) async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          'Expand-Archive -LiteralPath ${_psQuote(zipPath)} '
              '-DestinationPath ${_psQuote(dest)} -Force',
        ]);
        return r.exitCode == 0;
      }
      final r = await Process.run('unzip', ['-o', zipPath, '-d', dest]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _psQuote(String s) => "'${s.replaceAll("'", "''")}'";

  Directory? _findPayloadRoot(Directory staging) {
    bool hasExe(Directory d) {
      try {
        for (final e in d.listSync()) {
          if (e is File && e.path.toLowerCase().endsWith('.exe')) return true;
        }
      } catch (_) {}
      return false;
    }

    if (hasExe(staging)) return staging;
    try {
      for (final e in staging.listSync()) {
        if (e is Directory && hasExe(e)) return e;
      }
    } catch (_) {}
    return null;
  }

  Future<Directory> _cacheDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'updates'));
    await dir.create(recursive: true);
    return dir;
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.parse(url);
    final name = p.basename(uri.path);
    if (name.isNotEmpty && name.contains('.')) return name;
    return 'XingqiongLauncher-update.bin';
  }
}
