import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_theme.dart';

/// 桌面圆角窗框：透明 HWND 外裁切圆角；最大化时取消圆角。
class RoundedWindowFrame extends StatefulWidget {
  final Widget child;

  const RoundedWindowFrame({super.key, required this.child});

  @override
  State<RoundedWindowFrame> createState() => _RoundedWindowFrameState();
}

class _RoundedWindowFrameState extends State<RoundedWindowFrame>
    with WindowListener {
  bool _isMaximized = false;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refresh();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    final maxed = await windowManager.isMaximized();
    final full = await windowManager.isFullScreen();
    if (!mounted) return;
    if (maxed != _isMaximized || full != _isFullScreen) {
      setState(() {
        _isMaximized = maxed;
        _isFullScreen = full;
      });
    }
  }

  @override
  void onWindowMaximize() => _refresh();

  @override
  void onWindowUnmaximize() => _refresh();

  @override
  void onWindowEnterFullScreen() => _refresh();

  @override
  void onWindowLeaveFullScreen() => _refresh();

  @override
  void onWindowRestore() => _refresh();

  @override
  Widget build(BuildContext context) {
    final flat = _isMaximized || _isFullScreen;
    final radius = flat ? 0.0 : AppTheme.radiusWindow;

    return DragToResizeArea(
      enableResizeEdges: flat
          ? const []
          : const [
              ResizeEdge.topLeft,
              ResizeEdge.top,
              ResizeEdge.topRight,
              ResizeEdge.left,
              ResizeEdge.right,
              ResizeEdge.bottomLeft,
              ResizeEdge.bottom,
              ResizeEdge.bottomRight,
            ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: flat
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  ),
                ],
          border: flat
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 1,
                ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: widget.child,
        ),
      ),
    );
  }
}
