import 'dart:io';

import 'package:flutter/foundation.dart';

/// 手机端启动能力说明（Java 版需桌面 JVM，不能跑 Temurin linux 包）。
class MobileLaunchLimits {
  MobileLaunchLimits._();

  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const javaUnsupported =
      '手机端无法运行 Java 版：需要桌面 JVM，'
      '当前环境不能执行 java -version。'
      '请改用「基岩版」，或在电脑端启动 Java 版。';

  static const javaSkipInstall =
      '手机端跳过隔离 Java 安装（无法在此执行桌面 JDK）';
}
