import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'core/config/app_config.dart';
import 'core/perf/game_hud_monitor.dart';
import 'core/perf/overlay_launcher.dart';
import 'core/perf/record_paths.dart';
import 'ui/game_overlay_page.dart';
import 'ui/region_pick_scope.dart';

/// 解析 `--key=value` / `--flag`。
Map<String, String> parseOverlayArgs(List<String> args) {
  final out = <String, String>{};
  for (final a in args) {
    if (!a.startsWith('--')) continue;
    final body = a.substring(2);
    final i = body.indexOf('=');
    if (i < 0) {
      out[body] = '1';
    } else {
      out[body.substring(0, i)] = body.substring(i + 1);
    }
  }
  return out;
}

Future<void> _bringOverlayFront() async {
  try {
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.show();
  } catch (_) {}
}

/// 独立悬浮窗入口（由主启动器 Process.start 拉起）。
Future<void> runOverlayApp(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final map = parseOverlayArgs(args);
  final pid = int.tryParse(map['pid'] ?? '') ?? 0;
  final gameDirPath = map['game-dir'] ?? '';
  final serverName = map['server-name'];
  final serverAddress = map['server-address'];
  final clickThrough = map['click-through'] == '1';
  final startAsBall = map['ball'] != '0';
  final serverMap = OverlayLauncher.decodeMap(map['server-map']);

  if (pid <= 0 || gameDirPath.isEmpty) {
    exit(2);
  }

  final prefs = await SharedPreferences.getInstance();
  final recordDir = await resolveRecordSaveDir(
    map['record-dir'] ?? prefs.getString(AppConfig.keyRecordSaveDir) ?? '',
  );
  final ffmpegPath = map['ffmpeg'] ??
      prefs.getString(AppConfig.keyFfmpegPath) ??
      '';

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
    // 全透明窗体：只靠 UI 里的球/面板挡画面，避免整块黑底
    final windowOptions = WindowOptions(
      size: startAsBall ? const Size(56, 56) : const Size(280, 480),
      minimumSize: startAsBall ? const Size(48, 48) : const Size(220, 320),
      maximumSize: startAsBall ? const Size(72, 72) : const Size(360, 640),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      title: '星穹 HUD',
      alwaysOnTop: true,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setResizable(false);
      await windowManager.setBackgroundColor(Colors.transparent);
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        await Window.setEffect(
          effect: WindowEffect.transparent,
          color: Colors.transparent,
        );
      }
      try {
        final display = WidgetsBinding.instance.platformDispatcher.views.first;
        final size = display.physicalSize / display.devicePixelRatio;
        if (startAsBall) {
          await windowManager.setPosition(
            Offset((size.width - 72).clamp(8.0, size.width - 8), 48),
          );
        } else {
          await windowManager.setPosition(
            Offset((size.width - 300).clamp(8.0, size.width - 8), 40),
          );
        }
      } catch (_) {
        await windowManager.setPosition(const Offset(48, 48));
      }
      await _bringOverlayFront();
    });
  }

  final monitor = GameHudMonitor(
    pid: pid,
    gameDir: Directory(gameDirPath),
    initialServerName: serverName,
    initialServerAddress: serverAddress,
    serverNameByAddress: serverMap,
  );

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      builder: (context, child) => RegionPickScope(
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: GameOverlayPage(
          monitor: monitor,
          initialClickThrough: clickThrough,
          initialBall: startAsBall,
          recordSaveDir: recordDir,
          ffmpegPath: ffmpegPath.isEmpty ? null : ffmpegPath,
        ),
      ),
    ),
  );
}
