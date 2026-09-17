import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/auth/auth_guard.dart';
import 'core/auth/auth_manager.dart';
import 'core/auth/platform_utils.dart';
import 'core/auth/token_store.dart';
import 'core/config/app_config.dart';
import 'core/dev/mod_dev_controller.dart';
import 'core/download/accelerated_downloader.dart';
import 'core/download/network_env.dart';
import 'core/frp/frp_manager.dart';
import 'core/game/game_instance.dart';
import 'core/game/game_launcher.dart';
import 'core/game/java_runtime.dart';
import 'core/game/launch_loadout.dart';
import 'core/game/launch_service.dart';
import 'core/network/api_client.dart';
import 'core/network/secure_endpoint.dart';
import 'core/perf/game_session.dart';
import 'core/perf/launcher_recording_controller.dart';
import 'core/perf/launcher_sleep.dart';
import 'core/perf/perf_config.dart';
import 'core/perf/recent_play_store.dart';
import 'core/platform/app_permissions.dart';
import 'core/update/app_updater.dart';
import 'core/update/github_update_service.dart';
import 'services/community_service.dart';
import 'services/home_banner_service.dart';
import 'services/home_notice_service.dart';
import 'services/pack_service.dart';
import 'services/room_service.dart';
import 'ui/app_background.dart';
import 'ui/app_theme.dart';
import 'ui/desktop_root_shell.dart';
import 'ui/disclaimer_gate.dart';
import 'ui/game_resources_nav.dart';
import 'ui/global_drop_import_scope.dart';
import 'ui/launcher_shell.dart';
import 'ui/region_pick_scope.dart';
import 'overlay_main.dart';
import 'recording_hud_main.dart';
import 'core/perf/overlay_launcher.dart';
import 'core/perf/recording_hud_launcher.dart';

Future<void> main(List<String> args) async {
  if (args.contains(OverlayLauncher.argFlag)) {
    await runOverlayApp(args);
    return;
  }
  if (args.contains(RecordingHudLauncher.argFlag)) {
    await runRecordingHudApp(args);
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();

  final isDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  if (isDesktop) {
    await windowManager.ensureInitialized();
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      await Window.initialize();
    }
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(960, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: '星穹次元启动器',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(true);
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        await Window.setEffect(
          effect: WindowEffect.transparent,
          color: Colors.transparent,
        );
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final appConfig = AppConfig();
  await appConfig.load();
  await InstanceStore.preparePlatformRoots();
  await AppPermissions.warmUp();
  final tokenStore = TokenStore();
  final instanceStore = InstanceStore(appConfig);
  await instanceStore.load();
  await instanceStore.ensurePathsPersisted();

  // 手机 / PC：启动即探测 BMCLAPI；桌面另预热局域网互传
  unawaited(NetworkEnv.instance.ensureProbed());
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      appConfig.downloadAccelEnabled &&
      appConfig.downloadPeerEnabled) {
    unawaited(AcceleratedDownloader(config: appConfig).ensurePeerRunning());
  }

  AuthManager? authManagerRef;
  final apiClient = ApiClient(
    baseUrl: () => appConfig.backendBaseUrl,
    tokenProvider: () async => authManagerRef?.currentAccessToken,
  );
  final authManager = AuthManager(config: appConfig, tokenStore: tokenStore);
  authManagerRef = authManager;
  final javaRuntime = JavaRuntime(appConfig);
  final perfConfig = PerfConfig(appConfig);
  final launcherSleep = LauncherSleepController(appConfig);
  final gameSession = GameSession(perf: perfConfig, sleep: launcherSleep);
  final gameLauncher = GameLauncher(config: appConfig, perf: perfConfig);
  final recentPlay = RecentPlayStore(appConfig);
  final launcherRecording = LauncherRecordingController(appConfig);

  runApp(MultiProvider(
    providers: [
      Provider<TokenStore>.value(value: tokenStore),
      Provider<ApiClient>.value(value: apiClient),
      ChangeNotifierProvider<AppConfig>.value(value: appConfig),
      ChangeNotifierProvider<InstanceStore>.value(value: instanceStore),
      ChangeNotifierProvider<PerfConfig>.value(value: perfConfig),
      ChangeNotifierProvider<LauncherSleepController>.value(value: launcherSleep),
      ChangeNotifierProvider<GameSession>.value(value: gameSession),
      ChangeNotifierProvider<RecentPlayStore>.value(value: recentPlay),
      ChangeNotifierProvider<LauncherRecordingController>.value(
        value: launcherRecording,
      ),
      ChangeNotifierProvider<GlobalConfigProvider>(
        create: (_) => GlobalConfigProvider(
          appConfig: appConfig,
          fetchConfig: () => apiClient.getPublic(SecureRoutes.config),
        ),
      ),
      ChangeNotifierProvider<AuthManager>.value(value: authManager),
      Provider<PackService>(create: (_) => PackService(apiClient)),
      Provider<RoomService>(create: (_) => RoomService(apiClient)),
      Provider<CommunityService>(create: (_) => CommunityService(apiClient)),
      Provider<HomeBannerService>(create: (_) => HomeBannerService(apiClient)),
      Provider<HomeNoticeService>(create: (_) => HomeNoticeService(apiClient)),
      ChangeNotifierProvider<LaunchLoadout>(
        create: (_) => LaunchLoadout(appConfig),
      ),
      ChangeNotifierProvider<GameResourcesNav>(
        create: (_) => GameResourcesNav(),
      ),
      ChangeNotifierProvider<ModDevController>(
        create: (ctx) => ModDevController(
          config: appConfig,
          instances: ctx.read<InstanceStore>(),
        ),
      ),
      Provider<JavaRuntime>.value(value: javaRuntime),
      Provider<GameLauncher>.value(value: gameLauncher),
      Provider<FrpManager>(create: (_) => FrpManager(appConfig)),
      Provider<LaunchService>(
        create: (ctx) => LaunchService(
          config: appConfig,
          instances: instanceStore,
          javaRuntime: javaRuntime,
          launcher: gameLauncher,
          tokenStore: tokenStore,
          auth: authManager,
          packService: ctx.read<PackService>(),
          perf: perfConfig,
          session: gameSession,
          recent: recentPlay,
        ),
      ),
    ],
    child: const XingqiongApp(),
  ));
}

class XingqiongApp extends StatefulWidget {
  const XingqiongApp({super.key});

  @override
  State<XingqiongApp> createState() => _XingqiongAppState();
}

class _XingqiongAppState extends State<XingqiongApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthManager>();
      final globalConfig = context.read<GlobalConfigProvider>();
      // 先拉后台授权配置，再恢复会话，避免微软登录仍用空 Client ID
      await globalConfig.refresh();
      await auth.restore();
      // 每次启动向 GitHub 校验版本；有更新则自动下载并安装
      try {
        final update = await GithubUpdateService().check();
        if (!mounted || !update.hasUpdate) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('发现新版本 ${update.remoteVersion}，正在自动更新…'),
            duration: const Duration(seconds: 8),
          ),
        );
        String lastTip = '';
        try {
          await AppUpdater(
            onLog: (line) {
              if (!mounted || line == lastTip) return;
              lastTip = line;
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(line),
                  duration: const Duration(seconds: 6),
                ),
              );
            },
          ).downloadAndApply(update);
        } catch (e) {
          if (!mounted) return;
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text('自动更新失败: $e'),
              action: SnackBarAction(
                label: '打开下载',
                onPressed: () {
                  final url = update.downloadUrl ?? update.releasePageUrl;
                  if (url != null && url.isNotEmpty) {
                    openUrlInBrowser(url);
                  }
                },
              ),
              duration: const Duration(seconds: 12),
            ),
          );
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    return MaterialApp(
      title: '星穹次元启动器',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: AppTheme.parseThemeMode(config.themeModeRaw),
      // 不固定 locale：界面语言跟随操作系统
      locale: null,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en', 'US'),
        Locale('en'),
      ],
      localeListResolutionCallback: (locales, supported) {
        if (locales == null || locales.isEmpty) {
          return const Locale('zh', 'CN');
        }
        for (final device in locales) {
          for (final s in supported) {
            if (s.languageCode == device.languageCode &&
                (s.countryCode == null ||
                    s.countryCode!.isEmpty ||
                    s.countryCode == device.countryCode)) {
              return s;
            }
          }
          for (final s in supported) {
            if (s.languageCode == device.languageCode) return s;
          }
        }
        return const Locale('zh', 'CN');
      },
      color: Colors.transparent,
      builder: (context, child) {
        final page = child ?? const SizedBox.shrink();
        final Widget framed;
        if (kIsWeb ||
            !(defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.linux)) {
          framed = AppBackground(child: page);
        } else {
          // 外层 Overlay 挂菜单；内层圆角裁切，避免下拉被 ClipRRect 切掉
          framed = DesktopRootShell(child: page);
        }
        // 再包一层：桌面框选必须盖住窗壳/弹窗，不能嵌在页面里
        // 全局拖放：任意界面识别压缩包/JAR/皮肤并归入对应目录
        return RegionPickScope(
          child: GlobalDropImportScope(child: framed),
        );
      },
      home: DisclaimerGate(
        child: AuthGuard(
          onReady: (_) => const LauncherShell(),
        ),
      ),
    );
  }
}
