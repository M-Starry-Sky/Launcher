import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../download/download_sources.dart';

/// 绿色免安装 FFmpeg：本机没有时自动下载 essentials / 静态构建。
class PortableFfmpegInstaller {
  final void Function(String line)? onLog;

  PortableFfmpegInstaller({this.onLog});

  static const _stallWindow = Duration(seconds: 15);
  static const _minStallBytes = 64 * 1024;
  static const _downloadTimeout = Duration(minutes: 25);

  Future<Directory> _root() async {
    if (Platform.isWindows) {
      final preferred = Directory(r'C:\xingqiong\runtimes\ffmpeg');
      try {
        await preferred.create(recursive: true);
        return preferred;
      } catch (_) {}
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'runtimes', 'ffmpeg'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String?> findInstalled() async {
    final root = await _root();
    final home = Directory(p.join(root.path, 'current'));
    final exe = await _findFfmpegExe(home);
    if (exe != null && await _canRun(exe)) return exe;
    return null;
  }

  /// 已有则直接返回；否则优先包管理器，再多镜像加速下载。
  Future<String> ensure({bool forceReinstall = false}) async {
    if (!forceReinstall) {
      final existing = await findInstalled();
      if (existing != null) {
        onLog?.call('已有绿色 FFmpeg: $existing');
        return existing;
      }
    } else {
      await reinstall();
    }

    onLog?.call('未检测到 FFmpeg，正在自动准备录制环境…');
    final viaPkg = await _trySystemInstall();
    if (viaPkg != null) {
      onLog?.call('已通过包管理器就绪: $viaPkg');
      return viaPkg;
    }

    final archivePath = await _download().timeout(
      _downloadTimeout,
      onTimeout: () => throw TimeoutException('下载 FFmpeg 超时'),
    );
    onLog?.call('解压 FFmpeg…');
    final home = await _extract(archivePath);
    final exe = await _findFfmpegExe(home);
    if (exe == null) {
      throw StateError('解压后未找到 ffmpeg 可执行文件');
    }
    if (!await _canRun(exe)) {
      throw StateError('FFmpeg 解压完成但无法执行 -version');
    }
    onLog?.call('FFmpeg 已就绪: $exe');
    return exe;
  }

  /// winget / scoop / choco 往往走国内 CDN，比直连 GitHub 快很多。
  Future<String?> _trySystemInstall() async {
    if (!Platform.isWindows) return null;
    final probes = <Future<String?>>[
      _runPkgInstall(
        'winget',
        [
          'install',
          '-e',
          '--id',
          'Gyan.FFmpeg',
          '--accept-package-agreements',
          '--accept-source-agreements',
          '--disable-interactivity',
        ],
        label: 'winget',
      ),
      _runPkgInstall(
        'scoop',
        ['install', 'ffmpeg'],
        label: 'scoop',
      ),
    ];
    for (final f in probes) {
      try {
        final path = await f.timeout(const Duration(minutes: 4));
        if (path != null) return path;
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _runPkgInstall(
    String exe,
    List<String> args, {
    required String label,
  }) async {
    try {
      onLog?.call('尝试用 $label 安装 FFmpeg…');
      final r = await Process.run(exe, args, runInShell: true)
          .timeout(const Duration(minutes: 3));
      if (r.exitCode != 0) {
        onLog?.call('$label 不可用或安装失败，换下一方式…');
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return _resolveSystemFfmpeg();
    } catch (_) {
      onLog?.call('$label 未安装，跳过');
      return null;
    }
  }

  Future<String?> _resolveSystemFfmpeg() async {
    final home = Platform.environment['USERPROFILE'] ?? '';
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final candidates = <String>[
      'ffmpeg',
      r'C:\ffmpeg\bin\ffmpeg.exe',
      r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
      r'C:\ProgramData\chocolatey\bin\ffmpeg.exe',
      if (home.isNotEmpty)
        p.join(home, 'scoop', 'apps', 'ffmpeg', 'current', 'bin', 'ffmpeg.exe'),
      if (local.isNotEmpty)
        p.join(local, 'Microsoft', 'WinGet', 'Links', 'ffmpeg.exe'),
    ];
    for (final c in candidates) {
      try {
        if (c != 'ffmpeg' && !File(c).existsSync()) continue;
        if (await _canRun(c)) return c == 'ffmpeg' ? 'ffmpeg' : c;
      } catch (_) {}
    }
    return null;
  }

  Future<void> reinstall() async {
    final root = await _root();
    final home = Directory(p.join(root.path, 'current'));
    final staging = Directory(p.join(root.path, 'staging'));
    for (final d in [home, staging]) {
      if (d.existsSync()) {
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    }
    final zip = File(p.join(root.path, 'ffmpeg-download.zip'));
    if (zip.existsSync()) {
      try {
        await zip.delete();
      } catch (_) {}
    }
  }

  Future<bool> _canRun(String ffmpeg) async {
    try {
      final r = await Process.run(ffmpeg, ['-version'])
          .timeout(const Duration(seconds: 12));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _findFfmpegExe(Directory home) async {
    if (!home.existsSync()) return null;
    final direct = Platform.isWindows
        ? File(p.join(home.path, 'bin', 'ffmpeg.exe'))
        : File(p.join(home.path, 'bin', 'ffmpeg'));
    if (direct.existsSync()) return direct.path;
    final flat = Platform.isWindows
        ? File(p.join(home.path, 'ffmpeg.exe'))
        : File(p.join(home.path, 'ffmpeg'));
    if (flat.existsSync()) return flat.path;
    try {
      await for (final e in home.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final name = p.basename(e.path).toLowerCase();
        if (name == 'ffmpeg.exe' || name == 'ffmpeg') return e.path;
      }
    } catch (_) {}
    return null;
  }

  Future<String> _download() async {
    final root = await _root();
    final outFile = File(p.join(root.path, 'ffmpeg-download.zip'));
    final uris = _candidateUris();
    onLog?.call('测速挑选最快镜像（共 ${uris.length} 个）…');
    final ranked = await _rankBySpeed(uris);
    Object? lastError;
    for (final uri in ranked) {
      try {
        if (outFile.existsSync()) {
          try {
            await outFile.delete();
          } catch (_) {}
        }
        onLog?.call('下载 ${uri.host}…');
        await _downloadUri(uri, outFile);
        if (await outFile.length() < 1024 * 1024) {
          throw StateError('下载文件过小，可能不是完整包');
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
    throw StateError('所有 FFmpeg 下载源均失败: $lastError');
  }

  List<Uri> _candidateUris() {
    final out = <Uri>[];
    final seen = <String>{};
    void add(String s) {
      if (seen.add(s)) out.add(Uri.parse(s));
    }

    if (Platform.isWindows) {
      // essentials 体积更小；BtbN 走多家 GitHub 加速
      const gyan =
          'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip';
      const btbn =
          'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl-shared.zip';
      const btbnEssentials =
          'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';
      for (final prefix in const [
        'https://ghfast.top/',
        'https://gh-proxy.com/',
        'https://mirror.ghproxy.com/',
        'https://ghproxy.net/',
        'https://gitproxy.click/',
      ]) {
        add('$prefix$btbnEssentials');
        add('$prefix$btbn');
      }
      add(gyan);
      add(btbnEssentials);
      add(btbn);
    } else if (Platform.isLinux) {
      const staticBuild =
          'https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz';
      add(staticBuild);
    }
    return out;
  }

  /// 并行探测 TTFB，按快慢排序（失败的排后）。
  Future<List<Uri>> _rankBySpeed(List<Uri> uris) async {
    Future<({Uri uri, int ms})> probe(Uri uri) async {
      final sw = Stopwatch()..start();
      final client = http.Client();
      try {
        final req = http.Request('GET', uri);
        req.headers.addAll({
          'User-Agent': DownloadSources.userAgent,
          'Range': 'bytes=0-65535',
          'Accept': '*/*',
        });
        final res =
            await client.send(req).timeout(const Duration(seconds: 8));
        if (res.statusCode >= 400) {
          throw StateError('HTTP ${res.statusCode}');
        }
        // 读一小块确认真能下
        await res.stream.first.timeout(const Duration(seconds: 6));
        sw.stop();
        return (uri: uri, ms: sw.elapsedMilliseconds);
      } catch (_) {
        return (uri: uri, ms: 1 << 30);
      } finally {
        client.close();
      }
    }

    final results = await Future.wait(uris.map(probe));
    results.sort((a, b) => a.ms.compareTo(b.ms));
    for (final r in results.take(3)) {
      if (r.ms < (1 << 30)) {
        onLog?.call('测速 ${r.uri.host}: ${r.ms} ms');
      }
    }
    return results.map((e) => e.uri).toList();
  }

  Future<void> _downloadUri(Uri uri, File outFile) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      req.headers.addAll({
        'User-Agent': DownloadSources.userAgent,
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
          const Duration(seconds: 45),
          onTimeout: (s) {
            s.addError(TimeoutException('下载空闲超时，切换源'));
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
                'FFmpeg 下载 $pct% ${(got / (1024 * 1024)).toStringAsFixed(1)}/'
                '${(total / (1024 * 1024)).toStringAsFixed(1)} MB',
              );
            } else {
              onLog?.call(
                'FFmpeg 下载 ${(got / (1024 * 1024)).toStringAsFixed(1)} MB',
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

  Future<Directory> _extract(String archivePath) async {
    final root = await _root();
    final target = Directory(p.join(root.path, 'current'));
    final staging = Directory(p.join(root.path, 'staging'));
    if (target.existsSync()) {
      await target.delete(recursive: true);
    }
    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    final lower = archivePath.toLowerCase();
    if (lower.endsWith('.zip')) {
      await extractFileToDisk(archivePath, staging.path, asyncWrite: true);
    } else if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
      // Linux 静态包：走系统 tar
      final r = await Process.run('tar', ['-xJf', archivePath, '-C', staging.path]);
      if (r.exitCode != 0) {
        throw StateError('解压失败: ${r.stderr}');
      }
    } else {
      throw StateError('未知压缩格式');
    }

    Directory content = staging;
    final children = staging.listSync();
    if (children.length == 1 && children.first is Directory) {
      content = children.first as Directory;
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

    try {
      await staging.delete(recursive: true);
    } catch (_) {}
    try {
      await File(archivePath).delete();
    } catch (_) {}

    await File(p.join(target.path, '.xingqiong-runtime.json')).writeAsString(
      jsonEncode({'at': DateTime.now().toIso8601String(), 'kind': 'ffmpeg'}),
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
}
