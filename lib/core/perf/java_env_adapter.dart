import 'dart:async';
import 'dart:io';

import '../config/app_config.dart';
import '../game/java_runtime.dart';
import '../game/mobile_launch_limits.dart';
import 'portable_java_installer.dart';

/// MC 版本 → 推荐 / 允许的 Java 主版本（启动器按此安装隔离运行时）。
class JavaVersionPolicy {
  /// 最低需求：1.18+ → 17；1.20.5 及之后所有版本（含 1.21/1.22）→ 21；1.16- → 8。
  /// [fromMeta] 优先：Mojang 版本 JSON 的 `javaVersion.majorVersion`。
  static int requiredMajor(String gameVersion, {int? fromMeta}) {
    if (fromMeta != null && fromMeta > 0) return fromMeta;
    final v = _parse(gameVersion);
    if (v == null) {
      // 快照等非 x.y.z（如 25w14a）：近年默认需 21
      return 21;
    }
    // 正确语义：1.20.5+，以及 minor>20 的全部后续大版本
    if (v.major >= 1 &&
        (v.minor > 20 || (v.minor == 20 && (v.patch ?? 0) >= 5))) {
      return 21;
    }
    if (v.major >= 1 && v.minor >= 18) return 17;
    if (v.major >= 1 && v.minor >= 17) return 16;
    return 8;
  }

  /// 上限：过高（如系统 Java 24）会导致 1.20.1 等直接崩。
  static int maxSupportedMajor(String gameVersion, {int? fromMeta}) {
    final need = requiredMajor(gameVersion, fromMeta: fromMeta);
    if (need >= 21) return 25;
    if (need >= 17) return 21;
    if (need >= 16) return 17;
    return 8;
  }

  /// 隔离安装目标主版本（与 required 一致）。
  static int isolatedMajor(String gameVersion, {int? fromMeta}) =>
      requiredMajor(gameVersion, fromMeta: fromMeta);

  static bool isCompatible(int major, String gameVersion, {int? fromMeta}) {
    return major >= requiredMajor(gameVersion, fromMeta: fromMeta) &&
        major <= maxSupportedMajor(gameVersion, fromMeta: fromMeta);
  }

  /// 从版本 id / Fabric profile id 解析 MC 语义化版本。
  static _SemVer? _parse(String raw) {
    final s = raw.trim();
    final fabric =
        RegExp(r'fabric-loader-[^-]+-(\d+\.\d+(?:\.\d+)?)').firstMatch(s);
    if (fabric != null) return _semVer(fabric.group(1)!);
    // 仅接受以数字开头的正式版号，避免误吃 loader 前缀
    final m = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(s);
    if (m == null) return null;
    return _SemVer(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      m.group(3) == null ? null : int.parse(m.group(3)!),
    );
  }

  static _SemVer _semVer(String s) {
    final m = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(s)!;
    return _SemVer(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      m.group(3) == null ? null : int.parse(m.group(3)!),
    );
  }
}

class _SemVer {
  final int major;
  final int minor;
  final int? patch;
  _SemVer(this.major, this.minor, this.patch);
}

class JavaProbeResult {
  final String path;
  final int? major;
  final bool is64Bit;
  final String rawVersionLine;
  final bool isolated;

  const JavaProbeResult({
    required this.path,
    required this.major,
    required this.is64Bit,
    required this.rawVersionLine,
    this.isolated = false,
  });
}

/// Java 环境适配：按游戏版本安装并使用启动器隔离的绿色 JDK。
class JavaEnvAdapter {
  final AppConfig config;
  final JavaRuntime runtime;

  /// 进程内缓存：同一 java 路径不反复 -version。
  static final Map<String, JavaProbeResult?> _probeCache = {};

  JavaEnvAdapter(this.config, this.runtime);

  Future<JavaProbeResult?> probe(
    String javaPath, {
    bool isolated = false,
    bool bypassCache = false,
  }) async {
    final key = '$javaPath|${isolated ? 1 : 0}';
    if (!bypassCache && _probeCache.containsKey(key)) return _probeCache[key];
    try {
      ProcessResult? result;
      try {
        result = await Process.run(javaPath, ['-version'])
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        // Windows 偶发直接 CreateProcess 失败时，走 shell 再试一次
        if (Platform.isWindows) {
          result = await Process.run(
            'cmd',
            ['/c', '"$javaPath" -version'],
            runInShell: false,
          ).timeout(const Duration(seconds: 15));
        } else {
          rethrow;
        }
      }
      final output = '${result.stderr}${result.stdout}';
      var major = _parseMajor(output);
      major ??= await runtime.detectVersion(javaPath);
      final lower = output.toLowerCase();
      final is64 = lower.contains('64-bit') ||
          lower.contains('amd64') ||
          lower.contains('x86_64') ||
          lower.contains('aarch64') ||
          !lower.contains('32-bit');
      final line = output
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => output.trim());
      final probed = JavaProbeResult(
        path: javaPath,
        major: major,
        is64Bit: is64,
        rawVersionLine: line,
        isolated: isolated,
      );
      _probeCache[key] = probed;
      return probed;
    } catch (_) {
      _probeCache[key] = null;
      return null;
    }
  }

  static int? _parseMajor(String output) {
    final match = RegExp(r'version "(\d+)(\.(\d+))?').firstMatch(output);
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    if (major == null) return null;
    if (major == 1) return int.tryParse(match.group(3) ?? '');
    return major;
  }

  static void clearProbeCache() => _probeCache.clear();

  /// 下载/启动前调用：确保本游戏版本有隔离 Java，不误用系统过高 JDK。
  ///
  /// [javaMajorFromMeta]：版本 JSON 声明的 `javaVersion.majorVersion`（优先于启发式）。
  Future<({String path, JavaProbeResult? probe, String? warning})>
      ensureIsolatedForGame(
    String gameVersion, {
    void Function(String line)? onLog,
    bool allowSettingsOverride = true,
    int? javaMajorFromMeta,
  }) async {
    if (MobileLaunchLimits.isMobile) {
      throw StateError(MobileLaunchLimits.javaUnsupported);
    }
    final need = JavaVersionPolicy.isolatedMajor(
      gameVersion,
      fromMeta: javaMajorFromMeta,
    );
    final max = JavaVersionPolicy.maxSupportedMajor(
      gameVersion,
      fromMeta: javaMajorFromMeta,
    );
    onLog?.call(
      '游戏 $gameVersion 需要隔离 Java $need（允许 ≤$max）'
      '${javaMajorFromMeta != null ? '（版本元数据）' : ''}',
    );

    if (allowSettingsOverride) {
      final configured = config.javaPath;
      if (configured != 'java' && File(configured).existsSync()) {
        final p = await probe(configured, bypassCache: true);
        if (p != null &&
            p.is64Bit &&
            p.major != null &&
            JavaVersionPolicy.isCompatible(
              p.major!,
              gameVersion,
              fromMeta: javaMajorFromMeta,
            )) {
          onLog?.call('使用设置中的兼容 Java ${p.major}: $configured');
          return (path: configured, probe: p, warning: null);
        }
        if (p?.major != null) {
          onLog?.call(
            '设置中的 Java ${p!.major} 不兼容本版本，改用隔离运行时…',
          );
        }
      }
    }

    final installer = PortableJavaInstaller(onLog: onLog);
    // 已有隔离运行时：优先精确 major，其次允许范围内的其它隔离包
    for (final major in _preferMajors(need, max)) {
      final existing = await installer.findInstalled(major);
      if (existing == null) continue;
      final p = await probe(existing, isolated: true, bypassCache: true);
      if (p != null &&
          p.is64Bit &&
          p.major != null &&
          JavaVersionPolicy.isCompatible(
            p.major!,
            gameVersion,
            fromMeta: javaMajorFromMeta,
          )) {
        onLog?.call('使用隔离 Java ${p.major}: $existing');
        return (path: existing, probe: p, warning: null);
      }
      onLog?.call('隔离目录 Java $major 无法运行，将重新安装…');
      await installer.reinstall(major);
    }

    onLog?.call('正在安装隔离 Java $need（目录独立，不影响系统 Java）…');
    clearProbeCache();
    final path = await installer.ensure(need, forceReinstall: false);
    var p = await probe(path, isolated: true, bypassCache: true);
    if (p == null || !p.is64Bit || p.major == null) {
      onLog?.call('首次校验失败，强制重装 Java $need…');
      clearProbeCache();
      final rebuilt = await installer.ensure(need, forceReinstall: true);
      p = await probe(rebuilt, isolated: true, bypassCache: true);
      if (p == null || !p.is64Bit || p.major == null) {
        return (
          path: rebuilt,
          probe: p,
          warning:
              '隔离 Java $need 已下载但无法校验（java -version 失败）。请到「性能」重装绿色 Java，或手动指定 java.exe',
        );
      }
      return _finishProbe(
        rebuilt,
        p,
        gameVersion,
        need,
        max,
        onLog,
        javaMajorFromMeta,
      );
    }
    return _finishProbe(
      path,
      p,
      gameVersion,
      need,
      max,
      onLog,
      javaMajorFromMeta,
    );
  }

  ({String path, JavaProbeResult? probe, String? warning}) _finishProbe(
    String path,
    JavaProbeResult p,
    String gameVersion,
    int need,
    int max,
    void Function(String line)? onLog,
    int? javaMajorFromMeta,
  ) {
    if (!JavaVersionPolicy.isCompatible(
      p.major!,
      gameVersion,
      fromMeta: javaMajorFromMeta,
    )) {
      return (
        path: path,
        probe: p,
        warning: '隔离 Java ${p.major} 仍不在允许范围 $need–$max',
      );
    }
    onLog?.call('隔离 Java ${p.major} 已就绪: $path');
    return (path: path, probe: p, warning: null);
  }

  /// 兼容旧调用：默认走隔离安装。
  Future<({String path, JavaProbeResult? probe, String? warning})>
      resolveForGame(
    String gameVersion, {
    bool autoInstallPortable = true,
    void Function(String line)? onLog,
    int? javaMajorFromMeta,
  }) async {
    if (!autoInstallPortable) {
      // 仅探测：仍优先隔离目录，其次系统兼容版本
      final need = JavaVersionPolicy.requiredMajor(
        gameVersion,
        fromMeta: javaMajorFromMeta,
      );
      final max = JavaVersionPolicy.maxSupportedMajor(
        gameVersion,
        fromMeta: javaMajorFromMeta,
      );
      final portable =
          await PortableJavaInstaller(onLog: onLog).findInstalled(need);
      if (portable != null) {
        final p = await probe(portable, isolated: true);
        if (p != null &&
            p.is64Bit &&
            p.major != null &&
            JavaVersionPolicy.isCompatible(
              p.major!,
              gameVersion,
              fromMeta: javaMajorFromMeta,
            )) {
          return (path: portable, probe: p, warning: null);
        }
      }
      try {
        final path =
            await runtime.findCompatibleJava(need: need, maxMajor: max);
        final p = await probe(path);
        return (path: path, probe: p, warning: null);
      } on JavaNotFoundException {
        return (
          path: 'java',
          probe: null,
          warning: '未找到兼容 Java $need–$max，请开启自动安装或手动指定',
        );
      }
    }
    return ensureIsolatedForGame(
      gameVersion,
      onLog: onLog,
      javaMajorFromMeta: javaMajorFromMeta,
    );
  }

  bool shouldExpandMetaspace({required bool largeModpack, int? modCount}) {
    if (largeModpack) return true;
    if (modCount != null && modCount >= 80) return true;
    return false;
  }

  /// 安装优先级：精确 need → 常见 LTS → 其它允许版本。
  List<int> _preferMajors(int need, int max) {
    final lts = [8, 11, 17, 21];
    final out = <int>[need];
    for (final m in lts) {
      if (m >= need && m <= max && !out.contains(m)) out.add(m);
    }
    for (var m = need; m <= max; m++) {
      if (!out.contains(m)) out.add(m);
    }
    return out;
  }
}
