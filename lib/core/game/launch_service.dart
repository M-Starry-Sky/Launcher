import 'dart:io';

import '../auth/auth_manager.dart';
import '../auth/token_store.dart';
import '../bedrock/bedrock_install.dart';
import '../bedrock/bedrock_launcher.dart';
import '../config/app_config.dart';
import '../../models/pack.dart';
import '../../services/pack_service.dart';
import '../download/accelerated_downloader.dart';
import '../perf/cache_cleaner.dart';
import '../perf/crash_diagnoser.dart';
import '../perf/fps_presets.dart';
import '../perf/game_session.dart';
import '../perf/gc_presets.dart';
import '../perf/java_env_adapter.dart';
import '../perf/java_options_writer.dart';
import '../perf/mod_conflict_scanner.dart';
import '../perf/perf_config.dart';
import '../perf/perf_mods_installer.dart';
import '../perf/process_boost.dart';
import '../perf/recent_play_store.dart';
import '../perf/soft_memory_trim.dart';
import '../platform/app_permissions.dart';
import 'game_instance.dart';
import 'game_launcher.dart';
import 'java_runtime.dart';
import 'launch_loadout.dart';
import 'android_je_embedded_launcher.dart';
import 'mobile_launch_limits.dart';
import 'version_catalog.dart';
import 'version_installer.dart';

/// 统一安装 + 启动（主页一键启动 / 房间启动共用）。
class LaunchService {
  final AppConfig config;
  final InstanceStore instances;
  final JavaRuntime javaRuntime;
  final GameLauncher launcher;
  final TokenStore tokenStore;
  final AuthManager auth;
  final PackService? packService;
  final PerfConfig? perf;
  final GameSession? session;
  final RecentPlayStore? recent;

  LaunchService({
    required this.config,
    required this.instances,
    required this.javaRuntime,
    required this.launcher,
    required this.tokenStore,
    required this.auth,
    this.packService,
    this.perf,
    this.session,
    this.recent,
  });

  Future<Process?> installAndLaunch(
    GameInstance instance, {
    void Function(String line)? onLog,
    bool autoInstall = true,
    LaunchLoadout? loadout,
    /// 覆盖载入项：直接进入该存档（saves 下文件夹名）
    String? singleplayerWorld,
  }) async {
    void log(String m) => onLog?.call(m);
    final totalSw = Stopwatch()..start();
    String stageMs(Stopwatch s) => '${s.elapsedMilliseconds}ms';

    final includeMods = loadout?.includeMods ?? true;
    final includeServer = loadout?.includeServer ?? false;
    final includePack = loadout?.includePack ?? false;
    final includeSkin = loadout?.includeSkin ?? false;
    final includeWorld = loadout?.includeWorld ?? false;

    // 共享本体：versions / libraries / assets
    // 实例目录：mods / config / saves / logs（启动 gameDir，严格隔离）
    final bodyDir = instances.sharedGameRoot();
    final gameDir = instances.instanceGameDir(instance);
    log('本体目录: ${bodyDir.path}');
    log('实例目录: ${gameDir.path}（模组/存档隔离，不与共享混用）');
    await bodyDir.create(recursive: true);
    await gameDir.create(recursive: true);
    final instanceMods = Directory('${gameDir.path}/mods');
    await instanceMods.create(recursive: true);
    for (final sub in ['config', 'saves', 'resourcepacks', 'shaderpacks', 'logs']) {
      await Directory('${gameDir.path}/$sub').create(recursive: true);
    }
    // 旧版曾把模组写入共享 game/mods；若实例为空则一次性迁入，之后不再读写共享 mods
    await _migrateSharedModsOnce(
      sharedMods: Directory('${bodyDir.path}/mods'),
      instanceMods: instanceMods,
      log: log,
    );
    await _migrateSharedSavesOnce(
      sharedSaves: Directory('${bodyDir.path}/saves'),
      instanceSaves: Directory('${gameDir.path}/saves'),
      log: log,
    );

    final prepSw = Stopwatch()..start();
    if (includePack &&
        loadout?.packId != null &&
        loadout!.packId!.isNotEmpty &&
        packService != null) {
      await _applyPack(loadout.packId!, instanceMods, log);
    }

    if (!includeMods) {
      log('已关闭「载入模组」：仍使用实例目录，请自行管理 mods');
    }

    if (includeSkin &&
        loadout?.skinPath != null &&
        loadout!.skinPath!.isNotEmpty) {
      await _applySkin(loadout.skinPath!, gameDir, log);
    }
    prepSw.stop();

    // 性能中心「启动时自动装性能模组」：原版无法挂 Sodium，自动切到最新 Fabric。
    var launchInstance = instance;
    final wantPerfMods = perf?.fps.autoInstallPerfMods == true;
    if (wantPerfMods && launchInstance.loaderType == 'none') {
      log('已开启自动性能模组：原版实例将自动挂载 Fabric…');
      try {
        final loaders = await VersionCatalog(config: config)
            .listFabricLoaders(launchInstance.gameVersion);
        if (loaders.isEmpty) {
          log('未找到适用于 ${launchInstance.gameVersion} 的 Fabric Loader，跳过自动挂载');
        } else {
          final loaderVer = loaders.first;
          launchInstance = launchInstance.copyWith(
            loaderType: 'fabric',
            loaderVersion: loaderVer,
          );
          await instances.update(launchInstance);
          log('实例已切换为 Fabric $loaderVer（可装 Sodium 等）');
        }
      } catch (e) {
        log('自动挂载 Fabric 失败: $e（将继续以原版启动）');
      }
    }

    final installSw = Stopwatch()..start();
    final installer = VersionInstaller(onProgress: log, config: config);
    var versionId = launchInstance.gameVersion;
    try {
      if (autoInstall) {
        final force = VersionInstaller.needsForcedReinstall(
          bodyDir,
          launchInstance.gameVersion,
        );
        final warm = !force &&
            VersionInstaller.isWarmReady(
              gameDir: bodyDir,
              gameVersion: launchInstance.gameVersion,
              loaderType: launchInstance.loaderType,
              loaderVersion: launchInstance.loaderVersion,
            );
        if (warm) {
          log('本地已就绪，跳过安装检查（快速启动）');
          if (launchInstance.loaderType == 'fabric') {
            versionId = launchInstance.launchVersionId;
          }
        } else {
          log(force
              ? '检测到删除后待重装标记，强制重新下载 ${launchInstance.gameVersion}…'
              : '检查/安装原版 ${launchInstance.gameVersion}…');
          final permitted = await AppPermissions.ensureForDownload(onLog: log);
          if (!permitted) {
            throw StateError('下载权限未就绪，已取消安装');
          }
          await installer.installVanilla(
            launchInstance.gameVersion,
            bodyDir,
            force: force,
          );
          await VersionInstaller.clearReinstallStamp(
            bodyDir,
            launchInstance.gameVersion,
          );

          if (launchInstance.loaderType == 'fabric') {
            final loader = launchInstance.loaderVersion;
            if (loader.isEmpty) {
              throw StateError('请先为实例选择 Fabric Loader 版本');
            }
            log('安装 Fabric $loader…');
            await installer.installFabric(
              launchInstance.gameVersion,
              loader,
              bodyDir,
            );
            versionId = launchInstance.launchVersionId;
          }
        }
      } else if (launchInstance.loaderType == 'fabric') {
        versionId = launchInstance.launchVersionId;
        log('已跳过自动安装，直接解析 $versionId');
      } else {
        log('已跳过自动安装，直接解析 $versionId');
      }
    } finally {
      installer.close();
    }
    installSw.stop();

    // Android：内嵌 OpenJDK + 虚拟按键（全版本）；失败再回退 FCL/Zalith/Pojav
    if (Platform.isAndroid) {
      log(MobileLaunchLimits.javaSkipDesktopJdk);
      await _writeMobileJvmImportHint(
        bodyDir: bodyDir,
        gameDir: gameDir,
        versionId: versionId,
        log: log,
      );
      final metaJava = await VersionInstaller.peekDeclaredJavaMajor(
        bodyDir,
        versionId,
      );
      await AndroidJeEmbeddedLauncher.launch(
        gameDir: bodyDir.path,
        versionId: versionId,
        gameVersion: launchInstance.gameVersion,
        auth: auth,
        javaMajorFromMeta: metaJava,
        onLog: log,
        preferExternalFallback: true,
      );
      totalSw.stop();
      log('手机内嵌 Java 启动完成 · 总耗时 ${stageMs(totalSw)}');
      return null;
    }
    if (Platform.isIOS) {
      throw StateError(
        'iOS 暂未接入 Java 版运行时。Android 请使用内嵌虚拟键启动，或安装 FCL/Zalith/Pojav 作为回退。',
      );
    }

    // 本体就绪后再装 Java，避免 Java 源失败导致「游戏也下不下来」
    final javaSw = Stopwatch()..start();
    log('准备隔离 Java 环境…');
    final adapter = JavaEnvAdapter(config, javaRuntime);
    final metaJava = await VersionInstaller.peekDeclaredJavaMajor(
      bodyDir,
      versionId,
    );
    final resolvedJava = await adapter.ensureIsolatedForGame(
      launchInstance.gameVersion,
      onLog: log,
      javaMajorFromMeta: metaJava,
    );
    if (resolvedJava.warning != null) {
      log('Java 环境提示: ${resolvedJava.warning}');
      if (resolvedJava.warning!.contains('无法') ||
          resolvedJava.warning!.contains('不在允许')) {
        throw StateError(resolvedJava.warning!);
      }
    }
    final javaPath = resolvedJava.path;
    final javaMajor = resolvedJava.probe?.major;
    log('隔离 Java: $javaPath'
        '${javaMajor != null ? ' (major=$javaMajor)' : ''}'
        '${resolvedJava.probe?.isolated == true ? ' [launcher-runtime]' : ''}');
    javaSw.stop();

    final resolveSw = Stopwatch()..start();
    log('解析启动配置…');
    final profileFuture = _resolveProfile();
    final resolvedFuture = installer.resolveVersionChain(versionId, bodyDir);
    final profile = await profileFuture;
    final resolved = await resolvedFuture;
    log('版本链就绪 · 库 ${resolved.classpath.length} 项');
    resolveSw.stop();

    // 硬件探测有进程内缓存；仅缺失时刷新（不再每次启动都跑 PowerShell）
    if (perf != null && perf!.autoMemory && perf!.hardware == null) {
      await perf!.refreshHardware();
    }
    if (perf != null && perf!.autoGc && javaMajor != null) {
      final hw = perf!.hardware;
      if (hw != null) {
        final auto = GcPresetX.autoSelect(hw, javaMajor);
        if (perf!.gcPreset != auto) {
          await perf!.setGcPreset(auto);
          log('已自动切换 GC: ${auto.label}');
        }
      }
    }

    final modsDir = Directory('${gameDir.path}/mods');
    final modJars = <File>[];
    if (await modsDir.exists()) {
      await for (final e in modsDir.list()) {
        if (e is File && e.path.toLowerCase().endsWith('.jar')) {
          modJars.add(e);
        }
      }
    }
    final modCount = modJars.length;
    if (perf != null &&
        adapter.shouldExpandMetaspace(
          largeModpack: perf!.largeModpack,
          modCount: modCount,
        ) &&
        !perf!.largeModpack) {
      await perf!.setLargeModpack(true);
      log('模组数量 $modCount，已启用元空间扩容');
    }

    final fps = perf?.fps;
    final perfModsSw = Stopwatch()..start();
    final gv = launchInstance.gameVersion;
    final canCore = PerfModsInstaller.supportsCoreHud(gv);
    final loaderEarly = launchInstance.loaderType.toLowerCase();
    // Fabric/Quilt：启动前始终清掉文件名标明不适配的自动模组（防 1.20 jar 留在 26.x）
    if (loaderEarly == 'fabric' || loaderEarly == 'quilt') {
      final scrubbed = await PerfModsInstaller(onLog: log)
          .quarantineIncompatibleAutoMods(instanceMods, gv);
      if (scrubbed > 0) {
        log('已隔离 $scrubbed 个不适配 $gv 的自动模组');
      }
    }
    // 性能模组只写入当前实例 mods，绝不碰共享本体
    if (fps != null &&
        fps.autoInstallPerfMods &&
        launchInstance.loaderType != 'none') {
      log(
        canCore
            ? '帧率优化：按 $gv 安装星穹优化（核心+引擎）…'
            : '帧率优化：按 $gv 安装加速引擎（核心需 MC≥1.20）…',
      );
      final result = await PerfModsInstaller(onLog: log).install(
        gameVersion: gv,
        loaderType: launchInstance.loaderType,
        modsDir: instanceMods,
      );
      if (canCore) {
        final coreInst = await PerfModsInstaller(onLog: log).ensureCoreJar(
          instanceMods,
          force: true,
          gameVersion: gv,
        );
        log(
          '星穹优化：写入 ${result.ok} · 已有 ${result.skip} · 失败 ${result.fail}'
          ' · 核心=${coreInst ? "OK" : "缺失"}',
        );
      } else {
        log(
          '加速引擎：写入 ${result.ok} · 已有 ${result.skip} · 不可用 ${result.fail}'
          '（小地图需 Minecraft ≥1.20）',
        );
      }
    } else if (fps != null &&
        fps.autoInstallPerfMods &&
        launchInstance.loaderType == 'none') {
      log('自动星穹优化已开，但实例仍是原版（无 Fabric），已跳过——游戏内不会有模组功能');
    } else if (!canCore) {
      final moved = await PerfModsInstaller(onLog: log)
          .quarantineMismatchedAutoMods(instanceMods, gv);
      if (moved > 0) {
        log('已隔离 $moved 个不适配 $gv 的自动模组');
      }
    }
    perfModsSw.stop();

    // 未开自动性能包时，Fabric≥1.20 仍强制同步核心 jar（保证小窗桥接版本一致）
    final loader = launchInstance.loaderType.toLowerCase();
    if (canCore && (loader == 'fabric' || loader == 'quilt')) {
      final coreInst = await PerfModsInstaller(onLog: log).ensureCoreJar(
        instanceMods,
        force: true,
        gameVersion: gv,
      );
      if (coreInst) {
        log('星穹优化核心已同步（小窗桥接 xingqiong_hud.json）');
      }
    }

    // 弱冲突自动修复后继续启动；强冲突仍可按设置阻止
    final wantAutoFix = perf?.autoFixSoftConflict ?? true;
    if (wantAutoFix) {
      final autoFixed = ModConflictScanner.autoResolve(
        [instanceMods],
        loaderType: launchInstance.loaderType,
      );
      if (autoFixed.isNotEmpty) {
        log('弱冲突已自动修复并继续启动，已删除：${autoFixed.join(', ')}');
      }
    }
    final conflicts = ModConflictScanner.scan(instanceMods);
    for (final c in conflicts) {
      final tag = switch (c.severity) {
        ConflictSeverity.block => '冲突',
        ConflictSeverity.soft => '弱冲突',
        ConflictSeverity.warn => '警告',
      };
      log('$tag: ${c.title} — ${c.suggestion}');
    }
    final softLeft = conflicts.where((c) => c.severity == ConflictSeverity.soft);
    if (softLeft.isNotEmpty && wantAutoFix) {
      // 仍有 soft 说明规则未能删干净，再修一次后继续（不中止）
      final again = ModConflictScanner.autoResolve(
        [instanceMods],
        loaderType: launchInstance.loaderType,
      );
      if (again.isNotEmpty) {
        log('弱冲突二次清理：${again.join(', ')}');
      }
    }
    final hard = ModConflictScanner.scan(instanceMods)
        .where((c) => c.severity == ConflictSeverity.block)
        .toList();
    if (perf?.blockOnModConflict == true && hard.isNotEmpty) {
      final blocked =
          hard.map((c) => '${c.title} — ${c.suggestion}').join('；');
      throw StateError(
        '检测到无法自动修复的模组冲突，已中止启动。冲突: $blocked',
      );
    }

    var fpsSettings = fps;
    if (fpsSettings != null &&
        perf?.hardware != null &&
        !perf!.hardware!.likelySsd &&
        fpsSettings.applyOnLaunch) {
      fpsSettings = fpsSettings.copyWith(
        renderDistance: fpsSettings.renderDistance.clamp(2, 10),
        simulationDistance: fpsSettings.simulationDistance.clamp(2, 8),
      );
      log('检测到 HDD：视距压至 ${fpsSettings.renderDistance}');
    }

    if (fpsSettings != null && fpsSettings.applyOnLaunch) {
      log(
        '写入帧率 options.txt（${fpsSettings.preset.label}'
        '${fpsSettings.vsync ? " · 垂直同步开 · 上限 ${fpsSettings.maxFps}" : " · 同步关"}）…',
      );
      await JavaOptionsWriter.merge(
        gameDir,
        fpsSettings.toOptionsTxtEntries(),
      );
    }

    String? serverHost;
    int? serverPort;
    if (includeServer) {
      final parsed = LaunchLoadout.parseServer(loadout?.serverAddress);
      if (parsed != null) {
        serverHost = parsed.host;
        serverPort = parsed.port;
        log('将直连服务器 $serverHost:$serverPort');
      } else {
        log('已勾选服务器但未选择有效地址，跳过直连');
      }
    }

    final worldName = (singleplayerWorld?.trim().isNotEmpty == true)
        ? singleplayerWorld!.trim()
        : (includeWorld &&
                loadout?.worldName != null &&
                loadout!.worldName!.trim().isNotEmpty)
            ? loadout.worldName!.trim()
            : null;
    if (worldName != null &&
        (serverHost == null || serverHost.isEmpty)) {
      final worldDir = Directory(
        '${gameDir.path}${Platform.pathSeparator}saves'
        '${Platform.pathSeparator}$worldName',
      );
      final levelDat = File(
        '${worldDir.path}${Platform.pathSeparator}level.dat',
      );
      if (!await levelDat.exists()) {
        throw StateError(
          '无法快速进入存档「$worldName」：在 ${gameDir.path}${Platform.pathSeparator}saves 下找不到有效 level.dat。'
          '请确认存档文件夹名（不是游戏内显示名）与选择一致。',
        );
      }
      log('将进入存档「$worldName」→ ${worldDir.path}');
    }

    log('正在拉起游戏进程…');
    final spawnSw = Stopwatch()..start();
    final process = await launcher.launch(
      javaPath: javaPath,
      gameDir: gameDir,
      version: resolved,
      profile: profile,
      serverHost: serverHost,
      serverPort: serverPort,
      singleplayerWorld:
          (serverHost == null || serverHost.isEmpty) ? worldName : null,
      javaMajor: javaMajor,
      instanceJvmArgs: launchInstance.jvmArgs,
      assetsDir: Directory('${bodyDir.path}/assets'),
      onLog: log,
    );
    spawnSw.stop();
    await instances.touchPlayed(launchInstance.id);
    log(
      '启动耗时 总计${stageMs(totalSw)}'
      ' · 准备${stageMs(prepSw)}'
      ' · 安装${stageMs(installSw)}'
      ' · Java${stageMs(javaSw)}'
      ' · 解析${stageMs(resolveSw)}'
      ' · 性能模组${stageMs(perfModsSw)}'
      ' · 拉起${stageMs(spawnSw)}',
    );
    log('游戏进程已启动 (pid=${process.pid})，窗口出现前可能还需加载资源/模组');

    // 非关键路径：进程起来后再收缩启动器 / 清缓存，不挡启动
    if (perf?.trimLauncherOnLaunch == true) {
      // ignore: unawaited_futures
      SoftMemoryTrim.trimLauncher(onLog: log);
    }
    if (perf?.cleanCacheOnLaunch == true) {
      // ignore: unawaited_futures
      CacheCleaner.cleanGameDir(gameDir).then((report) {
        log('启动后清理: ${report.summary}');
      });
    }

    // 秒退检测放到后台：不再白等，和主流启动器一样点完就交还 UI
    // ignore: unawaited_futures
    () async {
      final early = await Future.any<int?>([
        process.exitCode.then((c) => c),
        Future<int?>.delayed(const Duration(seconds: 3), () => null),
      ]);
      if (early == null) return;
      log('游戏进程在启动后立即退出 code=$early');
      try {
        final diagnosis = await CrashDiagnoser.analyze(gameDir);
        for (final f in diagnosis.findings) {
          log('诊断: ${f.title} — ${f.action ?? f.detail}');
        }
      } catch (_) {}
    }();

    if (fpsSettings != null && fpsSettings.boostProcessPriority) {
      // ignore: unawaited_futures
      ProcessBoost.boostHigh(process.pid, onLog: log);
    }

    String? serverDisplayName;
    final serverMap = <String, String>{};
    if (loadout != null) {
      for (final s in loadout.savedServers()) {
        final addr = (s['address'] ?? '').trim();
        final name = (s['name'] ?? '').trim();
        if (addr.isNotEmpty && name.isNotEmpty) {
          serverMap[addr] = name;
          final hostOnly = addr.split(':').first;
          serverMap.putIfAbsent(hostOnly, () => name);
        }
      }
    }
    if (serverHost != null && serverHost.isNotEmpty) {
      final addr =
          serverPort == null ? serverHost : '$serverHost:$serverPort';
      serverDisplayName = serverMap[addr] ?? serverMap[serverHost];
    }

    session?.attach(
      process: process,
      instanceName: launchInstance.name,
      gameDir: gameDir,
      onLog: log,
      serverName: serverDisplayName,
      serverAddress: serverHost == null || serverHost.isEmpty
          ? null
          : (serverPort == null ? serverHost : '$serverHost:$serverPort'),
      serverNameByAddress: serverMap,
    );
    final joinedAddr = serverHost == null || serverHost.isEmpty
        ? null
        : (serverPort == null ? serverHost : '$serverHost:$serverPort');
    // ignore: unawaited_futures
    recent?.recordLaunch(
      instanceId: launchInstance.id,
      instanceName: launchInstance.name,
      gameVersion: launchInstance.gameVersion,
      serverName: serverDisplayName,
      serverAddress: joinedAddr,
    );
    return process;
  }

  /// 检测本机基岩版 → 写 options → 可选同步整合包 → 启动。
  Future<BedrockInstallInfo> launchBedrock({
    void Function(String line)? onLog,
    LaunchLoadout? loadout,
  }) async {
    void log(String m) => onLog?.call(m);

    final install = await BedrockInstall.detect();
    if (install == null) {
      if (Platform.isAndroid) {
        throw StateError(
          '未检测到已安装的基岩版（com.mojang.minecraftpe）。'
          '请先从应用商店安装 Minecraft，本启动器不托管版本体下载。',
        );
      }
      throw StateError(
        '未检测到已安装的基岩版。请先从微软商店安装 Minecraft，本启动器不托管版本体下载。',
      );
    }
    log('已检测 ${install.label}'
        '${install.displayVersion != null ? ' · ${install.displayVersion}' : ''}');

    final bedrock = BedrockLauncher(onLog: log);
    if (perf != null) {
      await bedrock.applyRenderSettings(install, perf!.bedrock);
    }

    if (loadout?.includePack == true &&
        loadout?.packId != null &&
        loadout!.packId!.isNotEmpty &&
        packService != null) {
      await applyBedrockPack(loadout.packId!, install, log);
    }

    await bedrock.launch(install);
    return install;
  }

  /// 将基岩整合包的行为包/资源包同步到本机 com.mojang 目录。
  Future<void> applyBedrockPack(
    String packId,
    BedrockInstallInfo install,
    void Function(String) log,
  ) async {
    final packs = packService!;
    log('载入基岩整合包 $packId…');
    final resp = await packs.manifest(packId);
    if (resp.gameType != 'bedrock') {
      log('警告：整合包 game_type=${resp.gameType}，仍按基岩资源同步');
    }

    final tmpRoot = Directory(
      '${Directory.systemTemp.path}/xq_bedrock_pack_$packId',
    );
    final resDir = Directory('${tmpRoot.path}/resource_packs');
    final behDir = Directory('${tmpRoot.path}/behavior_packs');
    await resDir.create(recursive: true);
    await behDir.create(recursive: true);

    final downloader = AcceleratedDownloader(config: config, onLog: log);
    Future<void> fetchEntry(ManifestEntry entry, Directory destRoot) async {
      final name = entry.filename ??
          entry.fileId ??
          entry.slug ??
          'pack_${entry.hashCode}';
      final out = File('${destRoot.path}/$name');
      if (out.existsSync()) return;
      try {
        // 1) 清单已带直链（R2/CDN）→ 前端直连，不经后端中转
        if (entry.downloadUrl != null && entry.downloadUrl!.isNotEmpty) {
          await downloader.downloadTo(
            Uri.parse(entry.downloadUrl!),
            out,
            expectedSha1: entry.sha1,
          );
        } else if (entry.type == 'modrinth' && entry.versionId != null) {
          // 2) Modrinth：API/CDN 走 MCIM，文件直连
          final client = ModrinthClient(
            useMirrors: config.downloadAccelEnabled,
          );
          final info = await client.versionFile(entry.versionId!);
          final file = File('${destRoot.path}/${info.filename}');
          await downloader.downloadTo(
            Uri.parse(info.url),
            file,
            expectedSha1: entry.sha1 ?? info.sha1,
          );
          log('基岩资源 ${info.filename}');
          return;
        } else if (entry.fileId != null) {
          // 3) 仅有 fileId：后端只 302 换直链，字节流仍直连存储
          final token = auth.currentAccessToken ?? '';
          final url = await packs.downloadUrl(entry.fileId!, token);
          if (url.isEmpty) return;
          await downloader.downloadTo(
            Uri.parse(url),
            out,
            expectedSha1: entry.sha1,
          );
        } else {
          return;
        }
        log('基岩资源 $name');
      } catch (e) {
        log('基岩资源失败 $name: $e');
      }
    }

    for (final e in resp.manifest.resourcePacks) {
      await fetchEntry(e, resDir);
    }
    for (final e in resp.manifest.behaviorPacks) {
      await fetchEntry(e, behDir);
    }

    final bedrock = BedrockLauncher(onLog: log);
    await bedrock.syncPackFolders(
      install: install,
      resourcePacksSource: resDir,
      behaviorPacksSource: behDir,
    );
  }

  Future<void> _applyPack(
    String packId,
    Directory modsDir,
    void Function(String) log,
  ) async {
    final packs = packService!;
    log('载入整合包 $packId…');
    final resp = await packs.manifest(packId);
    final downloader = AcceleratedDownloader(config: config, onLog: log);
    final modrinth = ModrinthClient(
      useMirrors: config.downloadAccelEnabled,
    );
    final token = auth.currentAccessToken ?? '';

    Future<void> fetchOne(ManifestEntry entry) async {
      try {
        // 直链优先（manifest 已展开 R2/CDN），文件不经后端中转
        if (entry.downloadUrl != null && entry.downloadUrl!.isNotEmpty) {
          final name = entry.filename ??
              entry.downloadUrl!.split('/').last.split('?').first;
          final out = File('${modsDir.path}/$name');
          if (out.existsSync()) {
            log('整合包已有 $name');
            return;
          }
          await downloader.downloadTo(
            Uri.parse(entry.downloadUrl!),
            out,
            expectedSha1: entry.sha1,
          );
          log('整合包文件 $name');
          return;
        }
        if (entry.type == 'modrinth' &&
            entry.versionId != null &&
            entry.versionId!.isNotEmpty) {
          final info = await modrinth.versionFile(entry.versionId!);
          final out = File('${modsDir.path}/${info.filename}');
          if (out.existsSync()) {
            log('整合包已有 ${info.filename}');
            return;
          }
          await downloader.downloadTo(
            Uri.parse(info.url),
            out,
            expectedSha1: entry.sha1 ?? info.sha1,
          );
          log('整合包模组 ${info.filename}');
          return;
        }
        if (entry.fileId != null) {
          final url = await packs.downloadUrl(entry.fileId!, token);
          if (url.isEmpty) return;
          final name = entry.filename ?? '${entry.fileId}.jar';
          final out = File('${modsDir.path}/$name');
          if (out.existsSync()) {
            log('整合包已有 $name');
            return;
          }
          await downloader.downloadTo(
            Uri.parse(url),
            out,
            expectedSha1: entry.sha1,
          );
          log('整合包文件 $name');
        }
      } catch (e) {
        log('整合包条目失败: $e');
      }
    }

    // 有限并发直连（全局限流仍由 AcceleratedDownloader 闸门约束）
    const batch = 6;
    final mods = resp.manifest.mods;
    for (var i = 0; i < mods.length; i += batch) {
      final slice = mods.skip(i).take(batch);
      await Future.wait(slice.map(fetchOne));
    }
  }

  Future<void> _applySkin(
    String path,
    Directory gameDir,
    void Function(String) log,
  ) async {
    final src = File(path);
    if (!src.existsSync()) {
      log('皮肤文件不存在: $path');
      return;
    }
    final destDir = Directory('${gameDir.path}/xingqiong_skins');
    await destDir.create(recursive: true);
    final dest = File('${destDir.path}/selected.png');
    await src.copy(dest.path);
    log('已准备皮肤 ${src.uri.pathSegments.last}（需皮肤模组/正版档案生效）');
  }

  Future<LaunchProfile> _resolveProfile() async {
    final session = await tokenStore.readGameSession();
    var name = session['name'] ?? auth.username ?? 'Player';
    var uuid = session['uuid'] ?? '';
    var token = session['access_token'] ?? auth.currentAccessToken ?? '';
    final offline =
        uuid.isEmpty || token.isEmpty || token == '0';
    if (offline) {
      final safe = AuthManager.sanitizeMinecraftUsername(name);
      if (safe != name) {
        // 旧会话可能仍是中文昵称，启动前强制纠正，否则进不去单人世界
        name = safe;
      }
      uuid = AuthManager.offlineUuidFor(name);
      if (token.isEmpty) token = '0';
      return LaunchProfile(
        username: name,
        uuid: uuid,
        accessToken: token,
        userType: 'legacy',
      );
    }
    return LaunchProfile(
      username: name,
      uuid: uuid,
      accessToken: token,
      userType: 'msa',
    );
  }

  /// 旧共享 mods → 当前实例：仅当实例 mods 为空时迁一次，不反向污染共享。
  Future<void> _migrateSharedModsOnce({
    required Directory sharedMods,
    required Directory instanceMods,
    required void Function(String) log,
  }) async {
    if (!await sharedMods.exists()) return;
    final sharedJars = sharedMods
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jar'))
        .toList();
    if (sharedJars.isEmpty) return;
    final instJars = instanceMods.existsSync()
        ? instanceMods
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.jar'))
            .toList()
        : <File>[];
    if (instJars.isNotEmpty) return;
    await instanceMods.create(recursive: true);
    var n = 0;
    for (final f in sharedJars) {
      final name = f.uri.pathSegments.last;
      final dest = File('${instanceMods.path}/$name');
      if (dest.existsSync()) continue;
      try {
        await f.copy(dest.path);
        n++;
      } catch (_) {}
    }
    if (n > 0) {
      log('已将共享 mods 中 $n 个 jar 迁入本实例（此后仅用实例目录）');
    }
  }

  /// 写入手机端说明（内嵌路径 + 外部回退导入）。
  Future<void> _writeMobileJvmImportHint({
    required Directory bodyDir,
    required Directory gameDir,
    required String versionId,
    required void Function(String) log,
  }) async {
    try {
      final hint = File('${bodyDir.path}${Platform.pathSeparator}星穹次元-手机Java导入说明.txt');
      await hint.writeAsString(
        '星穹次元启动器 · 手机内嵌 Java 版\n'
        '\n'
        '主路径：本应用内嵌 Android OpenJDK + 虚拟按键（横屏触控）。\n'
        '适配：按版本自动选择 Java 8/11/17/21，已下载的版本均可走同一套启动。\n'
        '\n'
        '本体目录：\n'
        '${bodyDir.path}\n'
        '实例目录（模组/存档）：\n'
        '${gameDir.path}\n'
        '版本：$versionId\n'
        '\n'
        '若内嵌 natives 未打包完整，可回退安装 FCL / Zalith / Pojav，\n'
        '在对方启动器中「添加游戏目录」指向上述本体路径。\n',
      );
      log('已写入导入说明: ${hint.path}');
    } catch (e) {
      log('写入导入说明失败: $e');
    }
  }

  /// 旧共享 saves → 当前实例：仅当实例 saves 为空时迁一次。
  Future<void> _migrateSharedSavesOnce({
    required Directory sharedSaves,
    required Directory instanceSaves,
    required void Function(String) log,
  }) async {
    if (!await sharedSaves.exists()) return;
    final worlds = sharedSaves
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((d) {
          final name = d.path
              .split(RegExp(r'[\\/]'))
              .where((s) => s.isNotEmpty)
              .last;
          if (name.startsWith('.')) return false;
          return File('${d.path}${Platform.pathSeparator}level.dat')
              .existsSync();
        })
        .toList();
    if (worlds.isEmpty) return;
    await instanceSaves.create(recursive: true);
    final existing = instanceSaves
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((d) =>
            File('${d.path}${Platform.pathSeparator}level.dat').existsSync())
        .toList();
    if (existing.isNotEmpty) return;
    var n = 0;
    for (final w in worlds) {
      final name = w.path
          .split(RegExp(r'[\\/]'))
          .where((s) => s.isNotEmpty)
          .last;
      final dest = Directory('${instanceSaves.path}${Platform.pathSeparator}$name');
      if (dest.existsSync()) continue;
      try {
        await _copyDir(w, dest);
        n++;
      } catch (_) {}
    }
    if (n > 0) {
      log('已将共享 saves 中 $n 个存档迁入本实例（此后仅用实例目录）');
    }
  }

  Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list(recursive: true, followLinks: false)) {
      final rel = e.path.substring(from.path.length);
      final destPath = '${to.path}$rel';
      if (e is Directory) {
        await Directory(destPath).create(recursive: true);
      } else if (e is File) {
        await File(destPath).parent.create(recursive: true);
        await e.copy(destPath);
      }
    }
  }
}
