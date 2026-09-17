import 'dart:io';

import 'package:flutter/services.dart';

import 'mobile_launch_limits.dart';

/// 已安装的手机 Java 启动器（Pojav 系后端），作内嵌失败时的回退。
class MobileJvmLauncherApp {
  final String packageName;
  final String label;

  const MobileJvmLauncherApp({
    required this.packageName,
    required this.label,
  });
}

/// 检测并唤起 FCL / Zalith / Pojav（内嵌 JVM 未就绪时的回退路径）。
class AndroidJavaLaunchBridge {
  AndroidJavaLaunchBridge._();

  static const _channel = MethodChannel('xingqiong/android_launch');

  /// 常见包名（多渠道 APK 可能不同，按顺序探测）。
  static const candidates = <MobileJvmLauncherApp>[
    MobileJvmLauncherApp(packageName: 'com.tungsten.fcl', label: 'Fold Craft Launcher'),
    MobileJvmLauncherApp(packageName: 'com.tungsten.fclauncher', label: 'FCL'),
    MobileJvmLauncherApp(packageName: 'com.movtery.zalithlauncher', label: 'Zalith Launcher'),
    MobileJvmLauncherApp(packageName: 'com.movtery.zalithlauncher2', label: 'Zalith Launcher 2'),
    MobileJvmLauncherApp(packageName: 'com.zalithlauncher', label: 'Zalith'),
    MobileJvmLauncherApp(packageName: 'net.kdt.pojavlaunch', label: 'PojavLauncher'),
    MobileJvmLauncherApp(packageName: 'net.kdt.pojavlaunch.app', label: 'PojavLauncher'),
    MobileJvmLauncherApp(packageName: 'net.kdt.pojavlaunch.free', label: 'PojavLauncher'),
  ];

  static Future<List<MobileJvmLauncherApp>> listInstalled({
    void Function(String line)? onLog,
  }) async {
    if (!Platform.isAndroid) return const [];
    final found = <MobileJvmLauncherApp>[];
    for (final app in candidates) {
      final ok = await _isInstalled(app.packageName);
      if (ok) {
        onLog?.call('已检测到 ${app.label}（${app.packageName}）');
        found.add(app);
      }
    }
    return found;
  }

  static Future<bool> _isInstalled(String packageName) async {
    try {
      final r = await _channel.invokeMethod<bool>('isPackageInstalled', {
        'package': packageName,
      });
      if (r == true) return true;
    } catch (_) {}
    try {
      final r = await Process.run('pm', ['path', packageName]);
      return r.exitCode == 0 && '${r.stdout}'.contains('package:');
    } catch (_) {
      return false;
    }
  }

  /// 唤起外部手机 Java 启动器；[gameRoot] 为本应用下载的本体目录。
  static Future<MobileJvmLauncherApp> launchExternal({
    required String gameRoot,
    String? versionId,
    void Function(String line)? onLog,
  }) async {
    if (!Platform.isAndroid) {
      throw StateError('仅 Android 支持手机 Java 启动桥');
    }
    onLog?.call(MobileLaunchLimits.javaNeedsMobileJvm);
    final installed = await listInstalled(onLog: onLog);
    if (installed.isEmpty) {
      onLog?.call(MobileLaunchLimits.javaNoRuntimeInstalled);
      await _openInstallHint();
      throw StateError(MobileLaunchLimits.javaNoRuntimeInstalled);
    }
    final app = installed.first;
    onLog?.call('本体目录（可在 ${app.label} 中导入）: $gameRoot');
    if (versionId != null && versionId.isNotEmpty) {
      onLog?.call('目标版本: $versionId');
    }
    onLog?.call('正在唤起 ${app.label}…');
    final ok = await _launchPackage(app.packageName);
    if (!ok) {
      throw StateError('无法启动 ${app.label}，请手动打开该应用');
    }
    onLog?.call(
      '${app.label} 已唤起。请在该启动器中选择/导入本目录下的版本后开始游戏。',
    );
    return app;
  }

  static Future<bool> _launchPackage(String packageName) async {
    try {
      final r = await _channel.invokeMethod<bool>('launchPackage', {
        'package': packageName,
      });
      if (r == true) return true;
    } catch (_) {}
    try {
      final r = await Process.run('am', [
        'start',
        '-a',
        'android.intent.action.MAIN',
        '-c',
        'android.intent.category.LAUNCHER',
        packageName,
      ]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _openInstallHint() async {
    try {
      await _channel.invokeMethod<void>('searchMarket', {
        'query': 'Fold Craft Launcher',
      });
    } catch (_) {
      try {
        await Process.run('am', [
          'start',
          '-a',
          'android.intent.action.VIEW',
          '-d',
          'market://search?q=Fold%20Craft%20Launcher',
        ]);
      } catch (_) {}
    }
  }
}
