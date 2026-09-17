import 'package:flutter/material.dart';

/// 启动页品牌图（竖图：门户 +「星穹次元」+ 连接中文案）。
const String kSplashBackgroundAsset = 'assets/images/splash_background.png';

/// 应用启动后、配置/会话恢复完成前的全屏加载页。
/// 与 Android 冷启动 [launch_background] 同一张图，避免闪白。
class BootLoadingPage extends StatelessWidget {
  const BootLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF07061A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: AssetImage(kSplashBackgroundAsset),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            alignment: Alignment.center,
          ),
          // 图内已有「连接中」与底栏；底部再叠一条细进度，表示仍在初始化
          Align(
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
