import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 是否走 App 端独立布局（与桌面侧栏壳分离）。
///
/// - Android / iOS：始终走 App 布局
/// - 其它平台：宽度 &lt; 960 时走 App 布局（窄窗 / 预览）
bool useAppLayout(BuildContext context) {
  if (!kIsWeb) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        break;
    }
  }
  return MediaQuery.sizeOf(context).width < 960;
}
