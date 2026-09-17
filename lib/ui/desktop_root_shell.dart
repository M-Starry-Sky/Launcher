import 'package:flutter/material.dart';

import 'app_background.dart';
import 'app_window_shell.dart';
import 'rounded_window_frame.dart';

/// 桌面根层：外层 Overlay 供下拉菜单逃出圆角裁切；内层才是圆角窗壳。
class DesktopRootShell extends StatefulWidget {
  final Widget child;

  const DesktopRootShell({super.key, required this.child});

  @override
  State<DesktopRootShell> createState() => _DesktopRootShellState();
}

class _DesktopRootShellState extends State<DesktopRootShell> {
  OverlayEntry? _shellEntry;

  @override
  void initState() {
    super.initState();
    _shellEntry = OverlayEntry(
      builder: (context) => RoundedWindowFrame(
        child: AppBackground(
          child: AppWindowShell(child: widget.child),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant DesktopRootShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {
      _shellEntry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _shellEntry?.remove();
    _shellEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [_shellEntry!],
    );
  }
}
