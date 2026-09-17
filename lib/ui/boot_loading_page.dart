import 'package:flutter/material.dart';

/// 启动初始化转圈页背景（品牌图，左侧 logo，右侧留给指示器）。
const String kSplashBackgroundAsset = 'assets/images/splash_background.png';

/// 应用启动后、配置/会话恢复完成前的全屏加载页。
class BootLoadingPage extends StatelessWidget {
  const BootLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            kSplashBackgroundAsset,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
          // 右侧留白区放转圈，避开左侧品牌
          const Align(
            alignment: Alignment(0.42, 0.08),
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF7EE8FF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
