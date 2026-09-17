import 'dart:io';

import 'package:flutter/services.dart';

import '../auth/auth_manager.dart';
import 'android_java_launch_bridge.dart';
import 'android_openjdk_installer.dart';
import 'mobile_launch_limits.dart';

/// 内嵌启动 Java 版：准备 Android OpenJDK → 打开带虚拟键的 JeGameActivity。
///
/// 适配全版本：按游戏版本 / 元数据选 Java major（8/11/17/21）。
class AndroidJeEmbeddedLauncher {
  AndroidJeEmbeddedLauncher._();

  static const _channel = MethodChannel('xingqiong/android_launch');

  static Future<void> launch({
    required String gameDir,
    required String versionId,
    required String gameVersion,
    required AuthManager auth,
    int? javaMajorFromMeta,
    void Function(String line)? onLog,
    bool preferExternalFallback = true,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('内嵌 Java 版仅支持 Android');
    }
    onLog?.call(MobileLaunchLimits.javaEmbeddedMode);

    final major = AndroidOpenJdkInstaller.majorForGame(
      gameVersion,
      fromMeta: javaMajorFromMeta,
    );
    onLog?.call('目标 Java major=$major（版本 $gameVersion / $versionId）');

    final installer = AndroidOpenJdkInstaller(onLog: onLog);
    String jreHome = '';
    try {
      jreHome = await installer.ensure(major);
    } catch (e) {
      onLog?.call('Android OpenJDK 未自动就绪: $e');
      // 仍打开游戏页，便于看到虚拟键与导入说明；也可回退外部启动器
      final existing = await installer.findInstalled(major);
      jreHome = existing ?? '';
      if (jreHome.isEmpty && preferExternalFallback) {
        onLog?.call('回退：唤起已安装的 FCL/Zalith/Pojav…');
        await AndroidJavaLaunchBridge.launchExternal(
          gameRoot: gameDir,
          versionId: versionId,
          onLog: onLog,
        );
        return;
      }
    }

    final raw = auth.username?.trim() ?? '';
    final username = raw.isNotEmpty
        ? AuthManager.sanitizeMinecraftUsername(raw)
        : 'Player';

    onLog?.call(MobileLaunchLimits.javaVirtualControlsReady);
    final ok = await _channel.invokeMethod<bool>('startEmbeddedJe', {
      'gameDir': gameDir,
      'versionId': versionId,
      'jreHome': jreHome,
      'username': username,
      'javaMajor': major,
    });
    if (ok != true) {
      if (preferExternalFallback) {
        onLog?.call('内嵌页打开失败，回退外部启动器…');
        await AndroidJavaLaunchBridge.launchExternal(
          gameRoot: gameDir,
          versionId: versionId,
          onLog: onLog,
        );
        return;
      }
      throw StateError('无法打开内嵌游戏页');
    }
    onLog?.call(
      jreHome.isEmpty
          ? MobileLaunchLimits.javaEmbeddedWaitingJre
          : MobileLaunchLimits.javaEmbeddedOpened,
    );
  }
}
