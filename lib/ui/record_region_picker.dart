import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'region_pick_scope.dart';

/// 全屏拖选录制矩形；确认后返回屏幕像素坐标。
class RecordRegionPickerPage extends StatefulWidget {
  const RecordRegionPickerPage({super.key});

  @override
  State<RecordRegionPickerPage> createState() => _RecordRegionPickerPageState();
}

class _RecordRegionPickerPageState extends State<RecordRegionPickerPage> {
  Offset? _start;
  Offset? _current;

  Rect? get _rect {
    final a = _start;
    final b = _current;
    if (a == null || b == null) return null;
    return Rect.fromPoints(a, b).normalize;
  }

  Future<void> _confirm() async {
    final r = _rect;
    if (r == null || r.width < 8 || r.height < 8) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pos = await windowManager.getPosition();
    final left = ((pos.dx + r.left) * dpr).round();
    final top = ((pos.dy + r.top) * dpr).round();
    final width = (r.width * dpr).round();
    final height = (r.height * dpr).round();
    if (!mounted) return;
    completeRegionPick<Map<String, int>>(context, {
      'x': left,
      'y': top,
      'width': width,
      'height': height,
    });
  }

  void _cancel() => completeRegionPick<Map<String, int>>(context, null);

  @override
  Widget build(BuildContext context) {
    final r = _rect;
    final size = MediaQuery.sizeOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _CancelIntent(),
        },
        child: Actions(
          actions: {
            _CancelIntent: CallbackAction<_CancelIntent>(
              onInvoke: (_) {
                _cancel();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => setState(() {
                    _start = d.localPosition;
                    _current = d.localPosition;
                  }),
                  onPanUpdate: (d) =>
                      setState(() => _current = d.localPosition),
                  child: CustomPaint(
                    painter: _RegionPainter(rect: r),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xCC12161C),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Text(
                          '拖拽框选桌面范围 · Esc 取消',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ),
                if (r != null && r.width >= 8 && r.height >= 8)
                  Positioned(
                    left: (r.center.dx - 70)
                        .clamp(8.0, math.max(8.0, size.width - 148)),
                    top: (r.bottom + 12)
                        .clamp(8.0, math.max(8.0, size.height - 48)),
                    child: FilledButton(
                      onPressed: _confirm,
                      child: Text(
                        '${r.width.round()} × ${r.height.round()} 确认',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}

class _RegionPainter extends CustomPainter {
  final Rect? rect;

  _RegionPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final r = rect;
    // 半透明遮罩 + 选区挖空，露出透明 HWND 下的真实桌面。
    canvas.saveLayer(full.inflate(1), Paint());
    canvas.drawRect(full, Paint()..color = const Color(0x99000000));
    if (r != null) {
      canvas.drawRect(r, Paint()..blendMode = BlendMode.clear);
      canvas.drawRect(
        r,
        Paint()
          ..color = const Color(0xFF7EB6FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RegionPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

extension on Rect {
  Rect get normalize {
    final l = left < right ? left : right;
    final t = top < bottom ? top : bottom;
    final r = left < right ? right : left;
    final b = top < bottom ? bottom : top;
    return Rect.fromLTRB(l, t, r, b);
  }
}

class _WindowSnap {
  final Size size;
  final Offset position;
  final bool resizable;
  final bool alwaysOnTop;
  final Size? restoreMinimumSize;
  final Size? restoreMaximumSize;

  const _WindowSnap({
    required this.size,
    required this.position,
    required this.resizable,
    required this.alwaysOnTop,
    this.restoreMinimumSize,
    this.restoreMaximumSize,
  });
}

Future<_WindowSnap> _snapshotWindow({
  Size? restoreMinimumSize,
  Size? restoreMaximumSize,
}) async {
  return _WindowSnap(
    size: await windowManager.getSize(),
    position: await windowManager.getPosition(),
    resizable: await windowManager.isResizable(),
    alwaysOnTop: await windowManager.isAlwaysOnTop(),
    restoreMinimumSize: restoreMinimumSize,
    restoreMaximumSize: restoreMaximumSize,
  );
}

Future<void> _restoreWindow(_WindowSnap snap) async {
  try {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
  } catch (_) {}
  // 先放开约束再恢复几何，避免 setSize 被旧 max 卡住
  try {
    await windowManager.setMinimumSize(const Size(0, 0));
    await windowManager.setMaximumSize(const Size(100000, 100000));
  } catch (_) {}
  try {
    await windowManager.setSize(snap.size);
    await windowManager.setPosition(snap.position);
  } catch (_) {}
  try {
    await windowManager.setMinimumSize(
      snap.restoreMinimumSize ?? const Size(0, 0),
    );
  } catch (_) {}
  try {
    await windowManager.setMaximumSize(
      snap.restoreMaximumSize ?? const Size(100000, 100000),
    );
  } catch (_) {}
  try {
    await windowManager.setResizable(snap.resizable);
  } catch (_) {}
  try {
    await windowManager.setAlwaysOnTop(snap.alwaysOnTop);
  } catch (_) {}
}

Future<ui.Rect> _virtualDesktopLogical() async {
  try {
    final displays = await screenRetriever.getAllDisplays();
    if (displays.isNotEmpty) {
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = -double.infinity;
      var maxY = -double.infinity;
      for (final d in displays) {
        final pos = d.visiblePosition ?? Offset.zero;
        final sz = d.visibleSize ?? d.size;
        minX = math.min(minX, pos.dx);
        minY = math.min(minY, pos.dy);
        maxX = math.max(maxX, pos.dx + sz.width);
        maxY = math.max(maxY, pos.dy + sz.height);
      }
      if (minX.isFinite && maxX > minX && maxY > minY) {
        return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
      }
    }
  } catch (_) {}
  try {
    final primary = await screenRetriever.getPrimaryDisplay();
    final pos = primary.visiblePosition ?? Offset.zero;
    final sz = primary.visibleSize ?? primary.size;
    return pos & sz;
  } catch (_) {}
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final screen = view.physicalSize / view.devicePixelRatio;
  return Offset.zero & screen;
}

/// 把当前窗口铺满虚拟桌面，再在最外层 Overlay 框选；返回物理像素矩形。
///
/// [restoreMinimumSize] / [restoreMaximumSize]：框选结束后写回的窗体约束
///（window_manager 0.4 无 getter，需调用方传入）。
Future<Map<String, int>?> pickRecordRegion(
  BuildContext context, {
  Size? restoreMinimumSize,
  Size? restoreMaximumSize,
}) async {
  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
    return null;
  }

  final snap = await _snapshotWindow(
    restoreMinimumSize: restoreMinimumSize,
    restoreMaximumSize: restoreMaximumSize,
  );
  try {
    await windowManager.setIgnoreMouseEvents(false);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(0, 0));
    await windowManager.setMaximumSize(const Size(100000, 100000));
    await windowManager.setAlwaysOnTop(true);
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
    } catch (_) {}

    final desk = await _virtualDesktopLogical();
    await windowManager.setBackgroundColor(Colors.transparent);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await Window.setEffect(
          effect: WindowEffect.transparent,
          color: Colors.transparent,
        );
      } catch (_) {}
    }
    await windowManager.setSize(Size(desk.width, desk.height));
    await windowManager.setPosition(Offset(desk.left, desk.top));
    await windowManager.show();
    await windowManager.focus();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await WidgetsBinding.instance.endOfFrame;

    if (!context.mounted) return null;
    return await RegionPickScope.present<Map<String, int>>(
      context,
      const RecordRegionPickerPage(),
    );
  } finally {
    await _restoreWindow(snap);
  }
}
