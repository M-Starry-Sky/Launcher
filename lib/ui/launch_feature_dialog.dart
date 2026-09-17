import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'glass/liquid_glass.dart';

/// 启动页顶栏功能弹窗（下载 / 实例 / 游戏资源二级项等）。
Future<void> openLaunchFeatureDialog({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  final size = MediaQuery.sizeOf(context);
  final compact = size.width < 720;
  final width = compact
      ? size.width - 24
      : (size.width * 0.82).clamp(520.0, 980.0);
  final height = compact
      ? size.height - 48
      : (size.height * 0.82).clamp(420.0, 720.0);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: 0.38),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, anim, secondary) {
      return SafeArea(
        child: Center(
          child: LiquidGlass(
            width: width,
            height: height,
            borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
            fillBoost: 0.1,
            // Chip / InkWell 等需要 Material 祖先；玻璃壳本身不提供。
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 6, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style:
                                Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: Theme.of(ctx)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.45),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
