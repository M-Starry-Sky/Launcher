import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import 'glass/glass_tokens.dart';

/// 内置启动后默认背景（用户未自定义时使用）。
const String kDefaultBackgroundAsset = 'assets/images/default_background.png';

/// 应用背景层：铺满整窗（含标题栏），默认资源图 / 用户自定义图。
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final path = context.select<AppConfig, String>((c) => c.backgroundImagePath);
    final glassRaw = context.select<AppConfig, String>((c) => c.glassModeRaw);
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassModeX.parse(glassRaw);
    // 玻璃开启时减弱整窗蒙版，让透射模糊能「吸」到壁纸色
    final veil = switch (glass) {
      GlassMode.off => 0.28,
      GlassMode.frosted => 0.18,
      GlassMode.clear => 0.08,
      GlassMode.liquid => 0.12,
    };
    final customProvider = (!kIsWeb && path.isNotEmpty)
        ? FileImage(File(path))
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surface),
        Positioned.fill(
          child: customProvider != null
              ? Image(
                  image: customProvider,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Image.asset(kDefaultBackgroundAsset, fit: BoxFit.cover),
                )
              : Image.asset(
                  kDefaultBackgroundAsset,
                  fit: BoxFit.cover,
                ),
        ),
        ColoredBox(color: scheme.surface.withValues(alpha: veil)),
        child,
      ],
    );
  }

  /// 将用户选择的图片复制到应用目录并写入配置。
  static Future<String> savePickedImage(
      AppConfig config, String sourcePath) async {
    final src = File(sourcePath);
    if (!src.existsSync()) {
      throw StateError('文件不存在');
    }
    final ext = p.extension(sourcePath).toLowerCase();
    final allowed = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'};
    if (!allowed.contains(ext)) {
      throw StateError('仅支持 png / jpg / webp / bmp / gif');
    }
    final dir = await getApplicationSupportDirectory();
    final destDir = Directory(p.join(dir.path, 'backgrounds'));
    if (!destDir.existsSync()) {
      await destDir.create(recursive: true);
    }
    final dest = File(p.join(destDir.path, 'user_bg$ext'));
    await src.copy(dest.path);
    await config.set(AppConfig.keyBackgroundImagePath, dest.path);
    return dest.path;
  }
}
