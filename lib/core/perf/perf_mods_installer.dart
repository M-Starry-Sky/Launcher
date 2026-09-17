import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/pack_service.dart';

/// 渲染加速依赖（Modrinth）。对用户呈现为「星穹优化」整包的一部分，不单独做成多个星穹模组。
class _EngineDep {
  final String slug;
  final bool required;
  const _EngineDep(this.slug, {this.required = false});
}

/// 一键安装「星穹优化」：
/// - 自研 HUD 核心：Minecraft 1.20 → 当前最新（含 26.x 日历版本）；更旧仅装引擎
/// - Sodium / Lithium / Fabric API 等：按当前实例版本从 Modrinth 精确（同大版本可邻近）拉取
class PerfModsInstaller {
  static const jarName = 'xingqiong-perf.jar';
  /// Minecraft 26.1+（去混淆）专用核心；与 [jarName] 不可混装。
  static const jarName26 = 'xingqiong-perf-26.jar';
  static const legacyJarName = 'xingqiong-hud-bridge.jar';
  static const _metaName = '.xingqiong_perf_installed.json';

  /// 日历版 26.1+：需 Mojang 去混淆 jar（xingqiong-perf-26.jar）。
  static bool needsUnobfuscatedCore(String gameVersion) {
    final v = gameVersion.trim();
    final m = RegExp(r'^(\d+)\.(\d+)').firstMatch(v);
    if (m == null) return false;
    final maj = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    return maj > 26 || (maj == 26 && min >= 1);
  }

  /// HUD 核心：1.20–1.21.x 用 Yarn jar；26.1+ 用去混淆 jar。
  static bool supportsCoreHud(String gameVersion) {
    final v = gameVersion.trim();
    if (v.isEmpty) return false;
    final m = RegExp(r'^(\d+)\.(\d+)').firstMatch(v);
    if (m == null) {
      // 快照如 24w14a：仍尝试装核心（由 fabric 依赖与运行时兼容层兜底）
      return RegExp(r'^\d{2}w\d{2}', caseSensitive: false).hasMatch(v);
    }
    final maj = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    // 26.3 等新编号
    if (maj >= 20) return true;
    // 传统 1.20 / 1.21 / …
    if (maj == 1 && min >= 20) return true;
    return false;
  }

  /// 当前版本应安装的核心 jar 文件名。
  static String coreJarNameFor(String gameVersion) =>
      needsUnobfuscatedCore(gameVersion) ? jarName26 : jarName;

  /// 任意已识别的 MC 版本都尝试装加速引擎（Modrinth 无包则跳过）。
  static bool supportsEnginePack(String gameVersion) {
    final v = gameVersion.trim();
    if (v.isEmpty) return false;
    return RegExp(r'^\d').hasMatch(v);
  }

  /// 兼容旧调用名。
  static bool supportsGameVersion(String gameVersion) =>
      supportsCoreHud(gameVersion);

  final void Function(String line)? onLog;

  PerfModsInstaller({this.onLog});

  static const _fabricEngines = <_EngineDep>[
    _EngineDep('fabric-api', required: true),
    _EngineDep('cloth-config', required: true),
    _EngineDep('sodium', required: true),
    _EngineDep('lithium', required: true),
    _EngineDep('entityculling'),
    _EngineDep('immediatelyfast'),
    _EngineDep('ferrite-core'),
    _EngineDep('modernfix'),
    _EngineDep('krypton'),
    _EngineDep('indium'),
    _EngineDep('sodium-extra'),
    _EngineDep('moreculling'),
  ];

  static const _forgeEngines = <_EngineDep>[
    _EngineDep('embeddium', required: true),
    _EngineDep('entityculling'),
    _EngineDep('ferrite-core'),
    _EngineDep('modernfix'),
  ];

  static List<String> get _autoSlugNeedles {
    final out = <String>{
      'xingqiongperf',
      'xingqionghudbridge',
      'viafabricplus',
      'transition',
      'trender',
    };
    for (final e in [..._fabricEngines, ..._forgeEngines]) {
      out.add(e.slug.toLowerCase().replaceAll('-', ''));
    }
    return out.toList();
  }

  /// 安装整包到 [modsDir]。核心：1.20→最新；引擎：当前版本精确拉取（日历版禁止邻近回退）。
  Future<({int ok, int skip, int fail})> install({
    required String gameVersion,
    required String loaderType,
    required Directory modsDir,
  }) async {
    final gv = gameVersion.trim();
    if (!supportsEnginePack(gv) && !supportsCoreHud(gv)) {
      onLog?.call('无法识别游戏版本「$gv」，跳过星穹优化安装');
      return (ok: 0, skip: 0, fail: 0);
    }
    final loader = switch (loaderType.toLowerCase()) {
      'neoforge' => 'neoforge',
      'forge' => 'forge',
      'quilt' => 'quilt',
      'fabric' => 'fabric',
      _ => '',
    };
    if (loader.isEmpty) {
      onLog?.call('当前加载器「$loaderType」无法安装星穹优化（需 Fabric/Forge）');
      return (ok: 0, skip: 0, fail: 0);
    }

    await modsDir.create(recursive: true);
    _removeLegacyJars(modsDir);

    // 先隔离文件名标明不适配当前 MC 的自动模组（避免 1.20.1 jar 留在 26.3）
    final scrubbed = await quarantineIncompatibleAutoMods(modsDir, gv);
    if (scrubbed > 0) {
      onLog?.call('已隔离 $scrubbed 个不适配 $gv 的自动模组');
    }

    // 换版本：整批清掉自动模组再重装
    final prev = await _readInstalledGameVersion(modsDir);
    if (prev != null && prev != gv) {
      onLog?.call('检测到版本变更 $prev → $gv，清理上一版自动模组…');
      await quarantineAutoMods(modsDir, holdSuffix: prev);
    } else if (!supportsCoreHud(gv)) {
      await quarantineAutoMods(modsDir, holdSuffix: 'stale');
    }

    var ok = 0;
    var skip = 0;
    var fail = 0;

    if (supportsCoreHud(gv)) {
      onLog?.call(
        needsUnobfuscatedCore(gv)
            ? '安装星穹优化核心（26.x 小地图/桥接）…'
            : '安装星穹优化核心（HUD/小地图）…',
      );
      final coreOk = await ensureCoreJar(
        modsDir,
        force: false,
        gameVersion: gv,
      );
      if (coreOk) {
        ok++;
      } else {
        fail++;
      }
    } else {
      await _quarantineCoreOnly(modsDir, gv);
      onLog?.call(
        '当前 $gv 早于 1.20，跳过 HUD 核心；仍按该版本安装加速引擎（有则装）',
      );
    }

    final engines = ((loader == 'forge' || loader == 'neoforge')
            ? _forgeEngines
            : _fabricEngines)
        .where((e) => _engineAllowedFor(gv, e.slug))
        .toList();
    if (needsUnobfuscatedCore(gv)) {
      onLog?.call(
        '日历版 $gv：跳过暂无适配的引擎（entityculling/ferrite-core/modernfix/krypton/indium）',
      );
    }

    // 日历版（26.x）禁止 1.20 邻近回退，必须精确命中
    final allowNear = !needsUnobfuscatedCore(gv);
    // 同版本已装过：无 MC 标记的引擎 jar 可信任，避免每次启动重下
    final trustUnmarked = prev == gv;

    onLog?.call('按 $gv 精确拉取加速引擎 ${engines.length} 项…');
    final jarNames = _listJarNames(modsDir);
    final missing = <_EngineDep>[];
    for (final dep in engines) {
      if (_hasCompatibleEngineJar(
        jarNames,
        dep.slug,
        gv,
        trustUnmarked: trustUnmarked,
      )) {
        skip++;
      } else {
        // 同 slug 但错版：先移走再下
        await _quarantineSlug(modsDir, dep.slug, gv);
        missing.add(dep);
      }
    }

    if (missing.isNotEmpty) {
      final client = ModrinthClient();
      const concurrency = 4;
      var next = 0;
      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= missing.length) return;
          final dep = missing[i];
          try {
            await client.downloadLatestForGame(
              projectId: dep.slug,
              gameVersion: gv,
              targetDir: modsDir,
              loader: loader,
              allowNearFallback: allowNear,
            );
            ok++;
            onLog?.call('已安装 ${dep.slug}（$gv）');
          } catch (e) {
            final msg = '$e';
            final noVersion = msg.contains('未找到') ||
                msg.contains('无 $gv') ||
                msg.contains('精确匹配') ||
                msg.contains('不适配');
            if (!dep.required && noVersion) {
              // 可选模组无对应版本：不算失败，避免「失败四个」误报
              skip++;
              onLog?.call('可选 ${dep.slug}：暂无 $gv 包，已跳过');
            } else if (dep.required) {
              fail++;
              onLog?.call('必要依赖 ${dep.slug} 安装失败: $e');
            } else {
              fail++;
              onLog?.call('可选 ${dep.slug} 下载失败: $e');
            }
          }
        }
      }

      final n = concurrency.clamp(1, missing.length);
      await Future.wait(List.generate(n, (_) => worker()));
    }

    await _writeInstalledMeta(modsDir, gv, loader);
    onLog?.call(
      '星穹优化安装结束（目标 $gv）· 写入 $ok · 已有/跳过 $skip · 失败 $fail',
    );
    return (ok: ok, skip: skip, fail: fail);
  }

  /// 仅确保自研一体化 jar 在 mods 目录（启动同步用）。
  Future<bool> ensureCoreJar(
    Directory modsDir, {
    bool force = false,
    String? gameVersion,
  }) async {
    if (gameVersion != null && !supportsCoreHud(gameVersion)) {
      onLog?.call(
        '当前 $gameVersion 过旧，不安装星穹优化核心（需 ≥1.20）',
      );
      await _quarantineCoreOnly(modsDir, gameVersion);
      return false;
    }
    final want26 = gameVersion != null && needsUnobfuscatedCore(gameVersion);
    final targetName = gameVersion != null
        ? coreJarNameFor(gameVersion)
        : jarName;
    await modsDir.create(recursive: true);
    _removeLegacyJars(modsDir);
    // 避免 1.20 Yarn jar 与 26 去混淆 jar 同目录混装
    final otherName = want26 ? jarName : jarName26;
    final other = File(p.join(modsDir.path, otherName));
    if (other.existsSync()) {
      try {
        await other.delete();
        onLog?.call('已移除不适配核心 $otherName');
      } catch (_) {}
    }
    final dest = File(p.join(modsDir.path, targetName));
    // 暖路径：目标已在且未强制，跳过打包源搜索
    if (!force && dest.existsSync() && dest.lengthSync() > 1024) {
      onLog?.call('星穹优化已在位 → ${dest.path}');
      return true;
    }
    if (force) {
      _searched = false;
      _cachedJar = null;
    }
    final src = _findBundledJar(prefer26: want26);
    if (src == null) {
      onLog?.call(
        want26
            ? '未找到 $jarName26（请构建 tool/xingqiong_hud_bridge_26）。'
                '当前工作目录: ${Directory.current.path}'
            : '未找到 $jarName（请确认 assets/mods 或重新构建 tool/xingqiong_hud_bridge）。'
                '当前工作目录: ${Directory.current.path}',
      );
      return false;
    }
    onLog?.call('星穹优化核心源: ${src.path}');
    try {
      if (!force &&
          dest.existsSync() &&
          dest.lengthSync() == src.lengthSync() &&
          dest.lastModifiedSync().isAfter(
                src.lastModifiedSync().subtract(const Duration(seconds: 2)),
              )) {
        onLog?.call('星穹优化已在位 → ${dest.path}');
        return true;
      }
      await src.copy(dest.path);
      onLog?.call('已安装星穹优化 → ${dest.path} (${dest.lengthSync()} B)');
      return true;
    } catch (e) {
      onLog?.call('星穹优化安装失败: $e');
      return false;
    }
  }

  /// 隔离启动器自动装过的模组（换版本前调用）。
  Future<int> quarantineAutoMods(
    Directory modsDir, {
    String holdSuffix = 'stale',
  }) async {
    if (!modsDir.existsSync()) return 0;
    final safe = holdSuffix.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final hold = Directory(
      p.join(modsDir.path, '.xingqiong_disabled_$safe'),
    );
    await hold.create(recursive: true);
    final needles = _autoSlugNeedles;
    var n = 0;
    for (final e in modsDir.listSync(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      final lower = name.toLowerCase();
      if (!lower.endsWith('.jar')) continue;
      final compact = lower.replaceAll('-', '').replaceAll('_', '');
      if (!needles.any(compact.contains)) continue;
      final dest = File(p.join(hold.path, name));
      try {
        if (dest.existsSync()) await dest.delete();
        await e.rename(dest.path);
        n++;
        onLog?.call('已隔离自动模组: $name');
      } catch (_) {
        try {
          await e.copy(dest.path);
          await e.delete();
          n++;
          onLog?.call('已隔离自动模组: $name');
        } catch (err) {
          onLog?.call('隔离失败 $name: $err');
        }
      }
    }
    if (n > 0) {
      onLog?.call('已隔离 $n 个模组 → ${hold.path}');
    }
    return n;
  }

  /// 按文件名 / 已知不适配列表，隔离不适配 [gameVersion] 的自动模组。
  /// 26.x 上会清掉所有带 1.20/1.21 标记的引擎，以及 ViaFabricPlus 系。
  Future<int> quarantineIncompatibleAutoMods(
    Directory modsDir,
    String gameVersion,
  ) async {
    if (!modsDir.existsSync()) return 0;
    final gv = gameVersion.trim();
    final safe = gv.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final hold = Directory(
      p.join(modsDir.path, '.xingqiong_disabled_bad_$safe'),
    );
    final needles = _autoSlugNeedles;
    var n = 0;
    for (final e in modsDir.listSync(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      final lower = name.toLowerCase();
      if (!lower.endsWith('.jar')) continue;
      final compact = lower.replaceAll('-', '').replaceAll('_', '');
      if (!needles.any(compact.contains)) continue;
      if (!_shouldQuarantineAsIncompatible(lower, gv)) continue;
      await hold.create(recursive: true);
      final dest = File(p.join(hold.path, name));
      try {
        if (dest.existsSync()) await dest.delete();
        await e.rename(dest.path);
        n++;
        onLog?.call('已隔离不适配 $gv: $name');
      } catch (_) {
        try {
          await e.copy(dest.path);
          await e.delete();
          n++;
          onLog?.call('已隔离不适配 $gv: $name');
        } catch (err) {
          onLog?.call('隔离失败 $name: $err');
        }
      }
    }
    return n;
  }

  /// 兼容旧名：隔离错版 / 版本变更残留的自动模组。
  Future<int> quarantineMismatchedAutoMods(
    Directory modsDir,
    String gameVersion,
  ) async {
    final scrubbed = await quarantineIncompatibleAutoMods(modsDir, gameVersion);
    final prev = await _readInstalledGameVersion(modsDir);
    if (prev != null && prev != gameVersion.trim()) {
      return scrubbed +
          await quarantineAutoMods(modsDir, holdSuffix: gameVersion);
    }
    return scrubbed;
  }

  /// 按游戏版本过滤引擎：避免对无包版本硬拉导致「失败 N 个」。
  bool _engineAllowedFor(String gv, String slug) {
    final s = slug.toLowerCase();
    if (needsUnobfuscatedCore(gv)) {
      // 26.x：Modrinth 上常缺这些；Indium 已并入新 Sodium
      const drop26 = {
        'indium',
        'entityculling',
        'ferrite-core',
        'modernfix',
        'krypton',
      };
      return !drop26.contains(s);
    }
    // 1.21.4+：Indium 无独立包（Sodium 自带 FRAPI）
    if (s == 'indium' && _mcAtLeast(gv, 1, 21, 4)) return false;
    return true;
  }

  static bool _mcAtLeast(String gv, int maj, int min, int pat) {
    final m = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(gv.trim());
    if (m == null) return false;
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    final c = int.tryParse(m.group(3) ?? '0') ?? 0;
    if (a != maj) return a > maj;
    if (b != min) return b > min;
    return c >= pat;
  }

  /// 同 slug 且文件名表明适配 [gv] 才视为「已有」。
  /// [trustUnmarked]：meta 已记录同版本成功安装时，允许无 MC 标记的引擎跳过重下。
  bool _hasCompatibleEngineJar(
    List<String> jarNames,
    String slug,
    String gv, {
    bool trustUnmarked = false,
  }) {
    final needle = slug.toLowerCase().replaceAll('-', '');
    for (final name in jarNames) {
      final compact = name.replaceAll('-', '').replaceAll('_', '');
      if (!compact.contains(needle)) continue;
      if (_jarCompatibleWithGame(name, gv, trustUnmarked: trustUnmarked)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _quarantineSlug(
    Directory modsDir,
    String slug,
    String gv,
  ) async {
    if (!modsDir.existsSync()) return;
    final needle = slug.toLowerCase().replaceAll('-', '');
    final safe = gv.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final hold = Directory(
      p.join(modsDir.path, '.xingqiong_disabled_bad_$safe'),
    );
    for (final e in modsDir.listSync(followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      final lower = name.toLowerCase();
      if (!lower.endsWith('.jar')) continue;
      final compact = lower.replaceAll('-', '').replaceAll('_', '');
      if (!compact.contains(needle)) continue;
      if (!_shouldQuarantineAsIncompatible(lower, gv)) continue;
      await hold.create(recursive: true);
      final dest = File(p.join(hold.path, name));
      try {
        if (dest.existsSync()) await dest.delete();
        await e.rename(dest.path);
        onLog?.call('已移走错版 ${slug}: $name');
      } catch (_) {}
    }
  }

  /// 仅隔离「明确不适配」的 jar（有错误 MC 标记 / Via / 旧 Cloth）。
  /// 无标记的引擎不因日历版而误删——避免每次启动清掉再重下。
  bool _shouldQuarantineAsIncompatible(String fileNameLower, String gv) {
    final n = fileNameLower.toLowerCase();
    final compact = n.replaceAll('-', '').replaceAll('_', '');
    if (needsUnobfuscatedCore(gv)) {
      if (compact.contains('viafabric') ||
          compact.contains('transition') ||
          compact.contains('trender')) {
        return true;
      }
    }
    if (compact.contains('clothconfig')) {
      final vm = RegExp(r'cloth[-_]?config[-_]?(\d+)').firstMatch(n);
      final major = vm != null ? int.tryParse(vm.group(1)!) : null;
      if (needsUnobfuscatedCore(gv)) {
        return major == null || major < 16;
      }
      return major != null && major < 11;
    }
    final markers = _extractMcMarkers(n);
    if (markers.isEmpty) return false;
    return !markers.any((m) => _mcVersionsCompatible(m, gv));
  }

  /// 文件名是否像适配 [gv]。日历版上：带 1.20/1.21 标记 → 否；Via 系 → 否。
  bool _jarCompatibleWithGame(
    String fileNameLower,
    String gv, {
    bool trustUnmarked = false,
  }) {
    // 明确不适配 → 否
    if (_shouldQuarantineAsIncompatible(fileNameLower, gv)) return false;
    final n = fileNameLower.toLowerCase();
    final compact = n.replaceAll('-', '').replaceAll('_', '');
    // Cloth 已在 quarantine 规则里处理；走到这里即视为可兼容
    if (compact.contains('clothconfig')) return true;

    final markers = _extractMcMarkers(n);
    if (markers.isEmpty) {
      if (needsUnobfuscatedCore(gv)) return trustUnmarked;
      return true;
    }
    return markers.any((m) => _mcVersionsCompatible(m, gv));
  }

  static List<String> _extractMcMarkers(String lowerName) {
    final out = <String>[];
    // 日历版 25.x / 26.x
    for (final m in RegExp(r'(?:^|[^0-9])(2[5-9]|[3-9]\d)\.(\d+)(?:[^0-9]|$)')
        .allMatches(lowerName)) {
      out.add('${m.group(1)}.${m.group(2)}');
    }
    // 传统 1.16–1.21.x
    for (final m in RegExp(r'(?:mc)?1\.(1[6-9]|2[0-1])(?:\.(\d+))?')
        .allMatches(lowerName)) {
      final patch = m.group(2);
      out.add(patch != null ? '1.${m.group(1)}.$patch' : '1.${m.group(1)}');
    }
    // 紧凑 mc1201
    for (final m in RegExp(r'mc1(1[6-9]|2[0-1])(\d)').allMatches(lowerName)) {
      out.add('1.${m.group(1)}.${m.group(2)}');
    }
    return out;
  }

  static bool _mcVersionsCompatible(String candidate, String target) {
    if (candidate.trim() == target.trim()) return true;
    final pa = _parseMc(candidate);
    final pb = _parseMc(target);
    if (pa == null || pb == null) return false;
    if (pa.$1 != pb.$1) return false;
    if (pa.$1 == 1) return pa.$2 == pb.$2;
    return true;
  }

  static (int, int, int?)? _parseMc(String raw) {
    final m = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(raw.trim());
    if (m == null) return null;
    return (
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      m.group(3) != null ? int.parse(m.group(3)!) : null,
    );
  }

  Future<void> _quarantineCoreOnly(Directory modsDir, String gameVersion) async {
    if (!modsDir.existsSync()) return;
    for (final name in [jarName, jarName26, legacyJarName, 'xingqiong-hud-bridge.jar']) {
      final f = File(p.join(modsDir.path, name));
      if (!f.existsSync()) continue;
      final hold = Directory(
        p.join(modsDir.path, '.xingqiong_disabled_core'),
      );
      await hold.create(recursive: true);
      final dest = File(p.join(hold.path, name));
      try {
        if (dest.existsSync()) await dest.delete();
        await f.rename(dest.path);
        onLog?.call('已移走不适配 $gameVersion 的核心模组 $name');
      } catch (_) {}
    }
  }

  Future<String?> _readInstalledGameVersion(Directory modsDir) async {
    final f = File(p.join(modsDir.path, _metaName));
    if (!f.existsSync()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final v = '${j['gameVersion'] ?? ''}'.trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeInstalledMeta(
    Directory modsDir,
    String gameVersion,
    String loader,
  ) async {
    final f = File(p.join(modsDir.path, _metaName));
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'gameVersion': gameVersion,
        'loader': loader,
        'coreHud': supportsCoreHud(gameVersion),
        'at': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
  }

  void _removeLegacyJars(Directory modsDir) {
    for (final name in [legacyJarName, 'xingqiong-hud-bridge.jar']) {
      final f = File(p.join(modsDir.path, name));
      if (f.existsSync()) {
        try {
          f.deleteSync();
          onLog?.call('已移除旧分体模组 $name');
        } catch (_) {}
      }
    }
  }

  static File? _cachedJar;
  static bool _searched = false;
  static bool? _searchedPrefer26;

  static File? _findBundledJar({bool prefer26 = false}) {
    if (_searched && _searchedPrefer26 == prefer26) return _cachedJar;
    _searched = true;
    _searchedPrefer26 = prefer26;
    _cachedJar = null;
    final primary = prefer26 ? jarName26 : jarName;
    final fallback = prefer26 ? jarName : jarName26;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      p.join(exeDir, 'data', 'flutter_assets', 'assets', 'mods', primary),
      p.join(exeDir, 'assets', 'mods', primary),
      p.join(Directory.current.path, 'assets', 'mods', primary),
      p.join(Directory.current.path, 'frontend', 'assets', 'mods', primary),
      p.normalize(
          p.join(exeDir, '..', '..', '..', '..', 'assets', 'mods', primary)),
      p.normalize(p.join(
          exeDir, '..', '..', '..', '..', '..', 'assets', 'mods', primary)),
      if (prefer26) ...[
        p.join(Directory.current.path, 'tool', 'xingqiong_hud_bridge_26',
            'build', 'libs', primary),
        p.join(Directory.current.path, 'frontend', 'tool',
            'xingqiong_hud_bridge_26', 'build', 'libs', primary),
      ] else ...[
        p.join(Directory.current.path, 'tool', 'xingqiong_hud_bridge', 'build',
            'libs', primary),
        p.join(Directory.current.path, 'frontend', 'tool', 'xingqiong_hud_bridge',
            'build', 'libs', primary),
      ],
      // 仅当主 jar 缺失时才回退（开发期兜底）
      p.join(Directory.current.path, 'assets', 'mods', fallback),
      p.join(Directory.current.path, 'frontend', 'assets', 'mods', fallback),
      p.join(Directory.current.path, 'assets', 'mods', legacyJarName),
      p.join(Directory.current.path, 'frontend', 'assets', 'mods', legacyJarName),
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync() && f.lengthSync() > 1024) {
        // 回退到错系列 jar 时给出提示由调用方处理；此处仍返回文件
        if (p.basename(f.path) == fallback && prefer26) {
          // 不要用 1.20 jar 冒充 26
          continue;
        }
        if (p.basename(f.path) == fallback && !prefer26) {
          continue;
        }
        _cachedJar = f;
        return f;
      }
    }
    for (final libsRoot in [
      if (prefer26) ...[
        p.join(Directory.current.path, 'tool', 'xingqiong_hud_bridge_26',
            'build', 'libs'),
        p.join(Directory.current.path, 'frontend', 'tool',
            'xingqiong_hud_bridge_26', 'build', 'libs'),
      ] else ...[
        p.join(Directory.current.path, 'tool', 'xingqiong_hud_bridge', 'build',
            'libs'),
        p.join(Directory.current.path, 'frontend', 'tool', 'xingqiong_hud_bridge',
            'build', 'libs'),
      ],
    ]) {
      final libs = Directory(libsRoot);
      if (!libs.existsSync()) continue;
      final jars = libs
          .listSync()
          .whereType<File>()
          .where((f) {
            final n = p.basename(f.path);
            final okName = prefer26
                ? (n.startsWith('xingqiong-perf') && n.contains('26'))
                : ((n.startsWith('xingqiong-perf') && !n.contains('26')) ||
                    n.startsWith('xingqiong-hud-bridge'));
            return okName &&
                n.endsWith('.jar') &&
                !n.contains('-sources') &&
                !n.contains('-dev');
          })
          .toList();
      if (jars.isNotEmpty) {
        jars.sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        _cachedJar = jars.first;
        return jars.first;
      }
    }
    return null;
  }

  List<String> _listJarNames(Directory modsDir) {
    if (!modsDir.existsSync()) return const [];
    return modsDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last.toLowerCase())
        .where((n) => n.endsWith('.jar'))
        .toList();
  }

}
