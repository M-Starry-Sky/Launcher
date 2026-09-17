import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/perf/launcher_sleep.dart';

/// 自定义窗口壳：隐藏系统标题栏，自绘拖拽区与最小化/最大化/关闭。
/// 背景由外层 [AppBackground] 铺满，标题栏保持透明/半透明。
class AppWindowShell extends StatefulWidget {
  final Widget child;
  final String title;

  const AppWindowShell({
    super.key,
    required this.child,
    this.title = '星穹次元启动器',
  });

  @override
  State<AppWindowShell> createState() => _AppWindowShellState();
}

class _AppWindowShellState extends State<AppWindowShell> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refreshMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowRestore() {
    _refreshMaximized();
    // 用户从任务栏点开时唤醒休眠
    context.read<LauncherSleepController>().leave();
  }

  @override
  void onWindowFocus() {
    // 聚焦时若仍处于休眠且未最小化，也唤醒
    () async {
      try {
        final minimized = await windowManager.isMinimized();
        if (!minimized && mounted) {
          final sleep = context.read<LauncherSleepController>();
          if (sleep.isAsleep) await sleep.leave();
        }
      } catch (_) {}
    }();
  }

  Future<void> _refreshMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && maximized != _isMaximized) {
      setState(() => _isMaximized = maximized);
    }
  }

  @override
  void onWindowMaximize() => _refreshMaximized();

  @override
  void onWindowUnmaximize() => _refreshMaximized();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Material(
          color: scheme.surface.withValues(alpha: 0.22),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 48,
                            height: 48,
                            child: Image(
                              image: AssetImage('assets/images/logo.png'),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            widget.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _WindowButton(
                  icon: Icons.remove,
                  onPressed: () => windowManager.minimize(),
                ),
                _WindowButton(
                  icon: _isMaximized
                      ? Icons.fullscreen_exit_outlined
                      : Icons.crop_square_outlined,
                  onPressed: () async {
                    if (await windowManager.isMaximized()) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                  },
                ),
                _WindowButton(
                  icon: Icons.close,
                  isClose: true,
                  onPressed: () => windowManager.close(),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: SizedBox(
        width: 40,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            hoverColor: isClose
                ? const Color(0xFFE81123).withValues(alpha: 0.9)
                : scheme.onSurface.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Icon(icon,
              size: 16, color: isClose ? null : scheme.onSurfaceVariant),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
