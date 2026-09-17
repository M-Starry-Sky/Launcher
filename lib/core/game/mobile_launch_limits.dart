import 'dart:io';

import 'package:flutter/foundation.dart';

/// 手机端 Java 版能力说明。
///
/// 方案（对齐 FCL / Zalith / Pojav）：
/// 1. **Android OpenJDK**（libjvm.so），不是桌面 Temurin；
/// 2. LWJGL + GL4ES/Zink 渲染桥；
/// 3. 独立 Activity + **虚拟按键** 内嵌启动（本应用主路径）。
class MobileLaunchLimits {
  MobileLaunchLimits._();

  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get supportsJavaViaExternalJvm =>
      !kIsWeb && Platform.isAndroid;

  static bool get supportsEmbeddedJe =>
      !kIsWeb && Platform.isAndroid;

  static const javaEmbeddedMode =
      '内嵌模式：Android OpenJDK + 虚拟按键（适配已下载的全部版本）';

  static const javaVirtualControlsReady =
      '虚拟按键已就绪（摇杆 / 跳潜攻用 / 快捷栏 / 视角）';

  static const javaEmbeddedOpened =
      '已打开内嵌游戏页。若 natives 未打包，页面会提示；虚拟键层仍可用。';

  static const javaEmbeddedWaitingJre =
      '已打开内嵌页；请导入 Android OpenJDK 或等待自动下载完成后再启动。';

  static const javaNeedsMobileJvm =
      '手机 Java 版使用 Android 专用 JVM（与 FCL/Zalith/Pojav 同方案），'
      '不能执行桌面 java -version。';

  static const javaSkipDesktopJdk =
      '手机端跳过桌面 JDK；改用内嵌 Android OpenJDK + 虚拟按键';

  static const javaNoRuntimeInstalled =
      '未检测到可用的 Android OpenJDK，且未安装 FCL / Zalith / Pojav。'
      '请允许下载手机 Java 运行时，或安装其一作为回退。';

  @Deprecated('改用 javaNeedsMobileJvm')
  static const javaUnsupported = javaNeedsMobileJvm;

  @Deprecated('改用 javaSkipDesktopJdk')
  static const javaSkipInstall = javaSkipDesktopJdk;
}
