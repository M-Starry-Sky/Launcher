import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../download/download_sources.dart';
import '../perf/java_env_adapter.dart';

/// Android 专用 OpenJDK（对齐 Pojav/FCL：按 ABI 下载，不是桌面 Temurin）。
///
/// 产物布局：`…/runtimes/android-jdk-{major}/` 下含 `lib/**/libjvm.so`。
class AndroidOpenJdkInstaller {
  final void Function(String line)? onLog;

  AndroidOpenJdkInstaller({this.onLog});

  void _log(String m) => onLog?.call(m);

  Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'runtimes', 'android-jdk'));
    await dir.create(recursive: true);
    return dir;
  }

  /// 当前设备 ABI：优先 arm64-v8a。
  static String abi() {
    // Flutter 不直接暴露 ABI；用 uname / 环境启发式
    try {
      final r = Process.runSync('getprop', ['ro.product.cpu.abi']);
      final abi = '${r.stdout}'.trim();
      if (abi.contains('arm64')) return 'arm64-v8a';
      if (abi.contains('armeabi')) return 'armeabi-v7a';
      if (abi.contains('x86_64')) return 'x86_64';
      if (abi.contains('x86')) return 'x86';
      if (abi.isNotEmpty) return abi;
    } catch (_) {}
    return 'arm64-v8a';
  }

  Future<String?> findInstalled(int major) async {
    final home = Directory(p.join((await _root()).path, 'jdk-$major'));
    if (!home.existsSync()) return null;
    if (_findLibjvm(home) != null) return home.path;
    return null;
  }

  File? _findLibjvm(Directory home) {
    final candidates = [
      p.join(home.path, 'lib', 'server', 'libjvm.so'),
      p.join(home.path, 'lib', 'libjvm.so'),
      p.join(home.path, 'lib', 'aarch64', 'server', 'libjvm.so'),
      p.join(home.path, 'lib', 'arm64', 'server', 'libjvm.so'),
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f;
    }
    try {
      for (final e in home.listSync(recursive: true)) {
        if (e is File && p.basename(e.path) == 'libjvm.so') return e;
      }
    } catch (_) {}
    return null;
  }

  /// 确保 [major] 可用；缺则从镜像下载（Pojav 系 Android JRE）。
  Future<String> ensure(int major, {bool force = false}) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('仅 Android 需要手机 OpenJDK');
    }
    if (!force) {
      final existing = await findInstalled(major);
      if (existing != null) {
        _log('已有 Android OpenJDK $major: $existing');
        return existing;
      }
    }
    _log('正在下载 Android OpenJDK $major（${abi()}，对齐 Pojav/FCL）…');
    final archive = await _download(major);
    _log('解压 Android JRE…');
    final home = await _extract(archive, major);
    final jvm = _findLibjvm(home);
    if (jvm == null) {
      throw StateError('解压后未找到 libjvm.so，请检查运行时包');
    }
    _log('Android OpenJDK $major 就绪: ${home.path}');
    return home.path;
  }

  Future<File> _download(int major) async {
    final root = await _root();
    final out = File(p.join(root.path, 'jdk-$major-android.tar.xz'));
    final arch = abi() == 'arm64-v8a'
        ? 'aarch64'
        : abi() == 'armeabi-v7a'
            ? 'arm'
            : abi() == 'x86_64'
                ? 'x86_64'
                : 'x86';

    // 公开镜像候选（Pojav android-openjdk / 社区镜像）。失败则换源。
    final uris = <Uri>[
      // 社区常用：按 major+arch 命名的包（若 404 会自动换）
      Uri.parse(
        'https://mirror.ghproxy.com/https://github.com/PojavLauncherTeam/'
        'android-openjdk-build-multiarch/releases/download/'
        'jre$major-android/jre$major-android-$arch.tar.xz',
      ),
      Uri.parse(
        'https://github.com/PojavLauncherTeam/android-openjdk-build-multiarch/'
        'releases/download/jre$major-android/jre$major-android-$arch.tar.xz',
      ),
      Uri.parse(
        'https://gitee.com/mirrors_PojavLauncherTeam/android-openjdk-build-multiarch/'
        'releases/download/jre$major-android/jre$major-android-$arch.tar.xz',
      ),
    ];

    Object? last;
    final client = http.Client();
    try {
      for (final uri in uris) {
        try {
          _log('尝试 ${uri.host}${uri.path} …');
          final req = http.Request('GET', uri);
          req.headers['user-agent'] = DownloadSources.userAgent;
          final res = await client.send(req).timeout(const Duration(minutes: 3));
          if (res.statusCode < 200 || res.statusCode >= 300) {
            throw StateError('HTTP ${res.statusCode}');
          }
          final sink = out.openWrite();
          var n = 0;
          await for (final chunk in res.stream) {
            sink.add(chunk);
            n += chunk.length;
          }
          await sink.close();
          if (n < 1024 * 1024) throw StateError('文件过小 ($n)');
          _log('已下载 ${(n / (1024 * 1024)).toStringAsFixed(1)} MB');
          return out;
        } catch (e) {
          last = e;
          _log('源失败: $e');
          try {
            if (out.existsSync()) await out.delete();
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }

    // 下载失败：创建本地占位目录 + 说明，便于用户手动导入
    final home = Directory(p.join((await _root()).path, 'jdk-$major'));
    await home.create(recursive: true);
    final tip = File(p.join(home.path, 'README_IMPORT.txt'));
    await tip.writeAsString(
      '请将 Android OpenJDK $major（含 libjvm.so）解压到本目录。\n'
      '可从 PojavLauncherTeam/android-openjdk-build-multiarch 获取。\n'
      'ABI: ${abi()} / arch=$arch\n'
      '上次错误: $last\n',
    );
    throw StateError(
      '无法自动下载 Android OpenJDK $major（$last）。'
      '请将运行时手动放入: ${home.path}',
    );
  }

  Future<Directory> _extract(File archive, int major) async {
    final root = await _root();
    final target = Directory(p.join(root.path, 'jdk-$major'));
    final staging = Directory(p.join(root.path, 'jdk-$major.staging'));
    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    // tar.xz：优先系统 tar，再尝试 archive 包
    final tar = await Process.run('tar', [
      '-xJf',
      archive.path,
      '-C',
      staging.path,
    ]);
    if (tar.exitCode != 0) {
      // 部分环境无 xz：尝试当 zip
      try {
        final bytes = await archive.readAsBytes();
        final zip = ZipDecoder().decodeBytes(bytes, verify: false);
        for (final f in zip.files) {
          final outPath = p.join(staging.path, f.name);
          if (f.isFile) {
            final out = File(outPath);
            await out.parent.create(recursive: true);
            await out.writeAsBytes(f.content as List<int>);
          } else {
            await Directory(outPath).create(recursive: true);
          }
        }
      } catch (e) {
        throw StateError('解压失败（需要 tar.xz）: ${tar.stderr} / $e');
      }
    }

    if (target.existsSync()) {
      await target.delete(recursive: true);
    }
    // 若解压后多一层目录，抬升含 libjvm 的那一层
    Directory lift = staging;
    final jvm = _findLibjvm(staging);
    if (jvm != null) {
      var dir = jvm.parent;
      // …/lib/server/libjvm.so → home
      while (dir.path != staging.path && dir.parent.path != staging.path) {
        if (p.basename(dir.path) == 'lib' || p.basename(dir.path) == 'server') {
          dir = dir.parent;
          continue;
        }
        break;
      }
      if (p.basename(jvm.parent.path) == 'server') {
        lift = jvm.parent.parent.parent; // server -> lib -> home
      } else if (p.basename(jvm.parent.path) == 'lib') {
        lift = jvm.parent.parent;
      }
    }
    if (lift.path == staging.path) {
      await staging.rename(target.path);
    } else {
      await lift.rename(target.path);
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
    }
    await File(p.join(target.path, '.xingqiong-android-jdk.json')).writeAsString(
      jsonEncode({
        'major': major,
        'abi': abi(),
        'at': DateTime.now().toIso8601String(),
      }),
    );
    return target;
  }

  /// 按游戏版本选 Java major（与桌面策略一致，适配全版本）。
  static int majorForGame(String gameVersion, {int? fromMeta}) =>
      JavaVersionPolicy.isolatedMajor(gameVersion, fromMeta: fromMeta);
}
