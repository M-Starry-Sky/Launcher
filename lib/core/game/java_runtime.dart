import 'dart:io';

import '../config/app_config.dart';
import '../perf/portable_java_installer.dart';

/// Java 运行时探测（系统候选）；游戏启动优先走隔离绿色包。
class JavaRuntime {
  final AppConfig config;

  JavaRuntime(this.config);

  /// 找到任意可用 java（兼容旧逻辑）；不保证版本匹配。
  Future<String> findJava() async {
    final configured = config.javaPath;
    if (configured != 'java' && File(configured).existsSync()) {
      return configured;
    }
    final all = await listCandidates();
    if (all.isNotEmpty) return all.first;
    throw const JavaNotFoundException();
  }

  /// 在候选中找 [need]…[maxMajor] 的 java.exe，优先精确匹配 [need]。
  Future<String> findCompatibleJava({
    required int need,
    required int maxMajor,
  }) async {
    final scored = <({String path, int major, int score})>[];
    for (final path in await listCandidates()) {
      final major = await detectVersion(path);
      if (major == null) continue;
      if (major < need || major > maxMajor) continue;
      // 越接近 need 越好；同 major 优先
      final score = 1000 - (major - need).abs() * 10;
      scored.add((path: path, major: major, score: score));
    }
    if (scored.isEmpty) throw const JavaNotFoundException();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.first.path;
  }

  /// 枚举本机可能的 java 路径（设置 / JAVA_HOME / PATH / 常见目录）。
  Future<List<String>> listCandidates() async {
    final out = <String>[];
    final seen = <String>{};

    void add(String? path) {
      if (path == null || path.isEmpty) return;
      final norm = path.replaceAll('/', Platform.pathSeparator);
      if (!File(norm).existsSync()) return;
      if (seen.add(norm.toLowerCase())) out.add(norm);
    }

    final configured = config.javaPath;
    if (configured != 'java') add(configured);

    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null) add(_exe('$javaHome/bin'));

    try {
      final result = Platform.isWindows
          ? await Process.run('where', ['java'])
          : await Process.run('which', ['java']);
      if (result.exitCode == 0) {
        for (final line in (result.stdout as String).split(RegExp(r'\r?\n'))) {
          final t = line.trim();
          if (t.isNotEmpty) add(t);
        }
      }
    } catch (_) {}

    if (Platform.isWindows) {
      // 启动器旁内置运行时
      final bundled = PortableJavaInstaller.bundledRoot();
      if (bundled != null) {
        try {
          if (bundled.existsSync()) {
            for (final entry in bundled.listSync(recursive: true)) {
              if (entry is! File) continue;
              final name = entry.path.toLowerCase();
              if (name.endsWith(r'\bin\java.exe')) add(entry.path);
            }
          }
        } catch (_) {}
      }
      for (final dir in const [
        r'C:\xingqiong\runtimes\java',
        r'E:\JAVA',
        r'C:\Program Files\Java',
        r'C:\Program Files\Eclipse Adoptium',
        r'C:\Program Files\Microsoft',
      ]) {
        final base = Directory(dir);
        if (!base.existsSync()) continue;
        try {
          for (final entry in base.listSync(recursive: true)) {
            if (entry is! File) continue;
            final name = entry.path.toLowerCase();
            if (name.endsWith('${Platform.pathSeparator}bin${Platform.pathSeparator}java.exe') ||
                name.endsWith(r'\bin\java.exe')) {
              add(entry.path);
            }
          }
        } catch (_) {}
      }
    } else if (Platform.isMacOS) {
      add(_exe(
          '/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home/bin'));
      add(_exe(
          '/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home/bin'));
    }

    return out;
  }

  Future<int?> detectVersion(String javaPath) async {
    try {
      final result = await Process.run(javaPath, ['-version']);
      final output = '${result.stderr}${result.stdout}';
      final match = RegExp(r'version "(\d+)(\.(\d+))?').firstMatch(output);
      if (match == null) return null;
      final major = int.parse(match.group(1)!);
      if (major == 1) {
        return int.tryParse(match.group(3) ?? '');
      }
      return major;
    } catch (_) {
      return null;
    }
  }

  String? _exe(String binDir) {
    final java = Platform.isWindows ? '$binDir/java.exe' : '$binDir/java';
    final normalized = java.replaceAll('/', Platform.pathSeparator);
    return File(normalized).existsSync() ? normalized : null;
  }
}

class JavaNotFoundException implements Exception {
  const JavaNotFoundException();

  @override
  String toString() => '未找到可用的 Java，请在设置中手动指定 Java 路径';
}
