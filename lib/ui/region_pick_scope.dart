import 'dart:async';

import 'package:flutter/material.dart';

/// 挂在 [MaterialApp.builder] 最外层，使框选层盖住圆角窗壳 / 标题栏 / 弹窗。
class RegionPickScope extends StatefulWidget {
  final Widget child;

  const RegionPickScope({super.key, required this.child});

  static _RegionPickScopeState? _of(BuildContext context) {
    return context.findAncestorStateOfType<_RegionPickScopeState>();
  }

  /// 在最外层 Overlay 插入 [page]。
  static Future<T?> present<T>(
    BuildContext context,
    Widget page,
  ) {
    final state = _of(context);
    if (state == null) {
      throw StateError('RegionPickScope 未挂载');
    }
    return state._present<T>(page);
  }

  @override
  State<RegionPickScope> createState() => _RegionPickScopeState();
}

class _RegionPickScopeState extends State<RegionPickScope> {
  final _overlayKey = GlobalKey<OverlayState>();
  OverlayEntry? _childEntry;
  OverlayEntry? _pickEntry;
  Completer<dynamic>? _completer;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _childEntry = OverlayEntry(builder: _buildChild);
  }

  Widget _buildChild(BuildContext context) {
    // 框选时隐藏下层 UI，挖空才能透出真实桌面（透明 HWND）
    return Opacity(
      opacity: _picking ? 0 : 1,
      child: IgnorePointer(
        ignoring: _picking,
        child: widget.child,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant RegionPickScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {
      _childEntry?.markNeedsBuild();
    }
  }

  Future<T?> _present<T>(Widget page) async {
    if (_completer != null) {
      return _completer!.future.then((v) => v as T?);
    }
    final completer = Completer<T?>();
    _completer = completer;

    void finish(T? value) {
      _pickEntry?.remove();
      _pickEntry = null;
      _picking = false;
      _childEntry?.markNeedsBuild();
      final c = _completer;
      _completer = null;
      if (c != null && !c.isCompleted) {
        c.complete(value);
      }
    }

    _picking = true;
    _childEntry?.markNeedsBuild();

    _pickEntry = OverlayEntry(
      builder: (ctx) => _RegionPickCompletion<T>(
        onComplete: finish,
        child: page,
      ),
    );
    final overlay = _overlayKey.currentState;
    if (overlay == null) {
      finish(null);
      return null;
    }
    overlay.insert(_pickEntry!);
    return completer.future;
  }

  @override
  void dispose() {
    _pickEntry?.remove();
    _pickEntry = null;
    _childEntry?.remove();
    _childEntry = null;
    final c = _completer;
    _completer = null;
    if (c != null && !c.isCompleted) c.complete(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      key: _overlayKey,
      initialEntries: [_childEntry!],
    );
  }
}

class _RegionPickCompletion<T> extends InheritedWidget {
  final void Function(T? value) onComplete;

  const _RegionPickCompletion({
    required this.onComplete,
    required super.child,
  });

  static _RegionPickCompletion<T>? of<T>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_RegionPickCompletion<T>>();
  }

  @override
  bool updateShouldNotify(covariant _RegionPickCompletion<T> oldWidget) =>
      onComplete != oldWidget.onComplete;
}

void completeRegionPick<T>(BuildContext context, T? value) {
  final host = _RegionPickCompletion.of<T>(context);
  host?.onComplete(value);
}
