import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/perf/launcher_sleep.dart';
import '../app_theme.dart';
import 'glass_tokens.dart';

/// 液态玻璃面板：透射模糊 + 虹彩描边 + 轻悬浮阴影。
/// [interactive] 开启悬停时微缩放与高光增强（轻量流体反馈）。
class LiquidGlass extends StatefulWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool interactive;
  final bool clip;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final VoidCallback? onTap;

  /// 额外加深填充（重要文字区可读性）
  final double fillBoost;

  /// 为 false 时强制不使用 BackdropFilter（内层面板，避免嵌套模糊吃满 CPU）
  final bool allowBackdrop;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.interactive = false,
    this.clip = true,
    this.width,
    this.height,
    this.alignment,
    this.onTap,
    this.fillBoost = 0,
    this.allowBackdrop = true,
  });

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // 只订阅玻璃档位，避免任意配置变更触发全窗模糊重建
    final modeRaw = context.select<AppConfig, String>((c) => c.glassModeRaw);
    var mode = GlassModeX.parse(modeRaw);
    // 休眠时强制纯净，杜绝 BackdropFilter 抢资源
    final asleep = context.select<LauncherSleepController, bool>(
      (s) => s.isAsleep,
    );
    if (asleep) mode = GlassMode.off;
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    var look = GlassLook.of(mode, brightness);
    final isWin = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (!widget.allowBackdrop) {
      // 内层：只用实色衬底，禁止再套 BackdropFilter
      look = GlassLook(
        blurSigma: 0,
        fillAlpha: (look.fillAlpha < 0.5 ? 0.58 : look.fillAlpha),
        rimAlpha: look.rimAlpha,
        backdrop: false,
        iridescent: false,
        elevation: look.elevation * 0.5,
      );
    } else if (isWin && look.backdrop) {
      // 外壳仅保留一层弱模糊
      look = GlassLook(
        blurSigma: look.blurSigma.clamp(0, 6),
        fillAlpha: look.fillAlpha,
        rimAlpha: look.rimAlpha,
        backdrop: true,
        iridescent: look.iridescent,
        elevation: look.elevation,
      );
    }
    final radius = widget.borderRadius ??
        BorderRadius.circular(AppTheme.radiusGlass);
    final fill = scheme.surface.withValues(
      alpha: (look.fillAlpha + widget.fillBoost).clamp(0.05, 0.95),
    );

    Widget body = widget.child;
    if (widget.padding != null) {
      body = Padding(padding: widget.padding!, child: body);
    }
    if (widget.alignment != null) {
      body = Align(alignment: widget.alignment!, child: body);
    }

    final panel = _GlassSurface(
      look: look,
      radius: radius,
      fill: fill,
      hover: _hover && widget.interactive,
      clip: widget.clip,
      child: body,
    );

    Widget core = panel;
    if (widget.onTap != null) {
      core = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: radius,
          child: panel,
        ),
      );
    }
    if (widget.interactive || widget.onTap != null) {
      core = MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          scale: _hover && widget.interactive ? 1.01 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: core,
        ),
      );
    }

    return RepaintBoundary(
      child: Container(
        width: widget.width,
        height: widget.height,
        margin: widget.margin,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: look.elevation * 0.018),
              blurRadius: look.elevation,
              offset: Offset(0, look.elevation * 0.35),
            ),
          ],
        ),
        child: core,
      ),
    );
  }
}

class _GlassSurface extends StatelessWidget {
  final GlassLook look;
  final BorderRadius radius;
  final Color fill;
  final bool hover;
  final bool clip;
  final Widget child;

  const _GlassSurface({
    required this.look,
    required this.radius,
    required this.fill,
    required this.hover,
    required this.clip,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final rimAlpha = look.rimAlpha * (hover ? 1.25 : 1.0);

    Widget layered = Stack(
      fit: StackFit.passthrough,
      children: [
        // 填充 / 透射
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
            ),
          ),
        ),
        // 边缘高光（克制，不铺满）
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: GlassPalette.sheen(hover: hover),
              ),
            ),
          ),
        ),
        child,
        // 虹彩 / 普通描边
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GlassRimPainter(
                radius: radius,
                iridescent: look.iridescent,
                alpha: rimAlpha.clamp(0.05, 1.0),
              ),
            ),
          ),
        ),
      ],
    );

    if (look.backdrop && look.blurSigma > 0) {
      layered = ClipRRect(
        borderRadius: radius,
        clipBehavior: clip ? Clip.antiAlias : Clip.hardEdge,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: look.blurSigma,
            sigmaY: look.blurSigma,
          ),
          child: layered,
        ),
      );
    } else if (clip) {
      layered = ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: layered,
      );
    }

    return layered;
  }
}

class _GlassRimPainter extends CustomPainter {
  final BorderRadius radius;
  final bool iridescent;
  final double alpha;

  _GlassRimPainter({
    required this.radius,
    required this.iridescent,
    required this.alpha,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(Offset.zero & size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;
    if (iridescent) {
      paint.shader = GlassPalette.rimGradient(alpha: alpha)
          .createShader(Offset.zero & size);
    } else {
      paint.color = Colors.white.withValues(alpha: alpha * 0.55);
    }
    canvas.drawRRect(rrect.deflate(0.6), paint);
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter old) =>
      old.alpha != alpha ||
      old.iridescent != iridescent ||
      old.radius != radius;
}

/// 替代 [Card] 的液态玻璃卡片。
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      margin: margin,
      borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.radiusGlass),
      padding: padding,
      fillBoost: 0.03,
      child: child,
    );
  }
}
