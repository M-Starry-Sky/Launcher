import 'package:flutter/material.dart';

import '../core/game/mobile_launch_limits.dart';

/// 手机端启动图（竖图：门户 +「星穹次元」+ 连接中文案）。
const String kSplashBackgroundMobileAsset =
    'assets/images/splash_background_mobile.png';

/// 电脑端启动图（横图，与轮播回退一致）。
const String kSplashBackgroundDesktopAsset =
    'assets/images/splash_background_desktop.png';

/// 当前平台启动页背景（手机 / 电脑资源隔离）。
String splashBackgroundAssetForPlatform() => MobileLaunchLimits.isMobile
    ? kSplashBackgroundMobileAsset
    : kSplashBackgroundDesktopAsset;

/// 应用启动后、配置/会话恢复完成前的全屏加载页。
/// 手机与 [android launch_background] 同用竖图；电脑用独立横图，避免闪白与比例错乱。
class BootLoadingPage extends StatelessWidget {
  const BootLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final asset = splashBackgroundAssetForPlatform();
    return Scaffold(
      backgroundColor: const Color(0xFF07061A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: AssetImage(asset),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            alignment: Alignment.center,
          ),
          // 手机图内已有「连接中」与底栏；电脑横图仅叠进度条
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(48, 0, 48, 36),
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Color(0x334B2A7A),
                color: Color(0xFF7EE8FF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
