import 'package:flutter/material.dart';

/// 玻璃通透档位：液态 / 磨砂 / 全透明 / 纯净关闭。
enum GlassMode {
  /// 液态：中模糊 + 虹彩边 + 轻填充（默认）
  liquid,

  /// 磨砂：强模糊 + 较高填充，偏静态毛玻璃
  frosted,

  /// 全透明：弱模糊、高通透（文字区需自带衬底）
  clear,

  /// 纯净：无 BackdropFilter，实色面板（低配）
  off,
}

extension GlassModeX on GlassMode {
  String get storageKey => name;

  String get label => switch (this) {
        GlassMode.liquid => '液态',
        GlassMode.frosted => '磨砂',
        GlassMode.clear => '全透明',
        GlassMode.off => '纯净',
      };

  String get hint => switch (this) {
        GlassMode.liquid => '流体感边光，实时吸取背景色调',
        GlassMode.frosted => '更强虚化，适合亮色壁纸上的可读性',
        GlassMode.clear => '高通透，重要文字需衬底',
        GlassMode.off => '关闭模糊与虹彩，最低开销',
      };

  static GlassMode parse(String? raw) {
    switch (raw) {
      case 'frosted':
        return GlassMode.frosted;
      case 'clear':
        return GlassMode.clear;
      case 'off':
        return GlassMode.off;
      default:
        return GlassMode.liquid;
    }
  }
}

/// 由档位推导的渲染参数（性能与观感平衡）。
class GlassLook {
  final double blurSigma;
  final double fillAlpha;
  final double rimAlpha;
  final bool backdrop;
  final bool iridescent;
  final double elevation;

  const GlassLook({
    required this.blurSigma,
    required this.fillAlpha,
    required this.rimAlpha,
    required this.backdrop,
    required this.iridescent,
    required this.elevation,
  });

  factory GlassLook.of(GlassMode mode, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    switch (mode) {
      case GlassMode.liquid:
        return GlassLook(
          blurSigma: dark ? 14 : 18,
          fillAlpha: dark ? 0.22 : 0.38,
          rimAlpha: 0.55,
          backdrop: true,
          iridescent: true,
          elevation: 8,
        );
      case GlassMode.frosted:
        return GlassLook(
          blurSigma: dark ? 22 : 28,
          fillAlpha: dark ? 0.42 : 0.58,
          rimAlpha: 0.35,
          backdrop: true,
          iridescent: false,
          elevation: 4,
        );
      case GlassMode.clear:
        return GlassLook(
          blurSigma: dark ? 8 : 10,
          fillAlpha: dark ? 0.12 : 0.22,
          rimAlpha: 0.42,
          backdrop: true,
          iridescent: true,
          elevation: 6,
        );
      case GlassMode.off:
        return GlassLook(
          blurSigma: 0,
          fillAlpha: dark ? 0.88 : 0.92,
          rimAlpha: 0.2,
          backdrop: false,
          iridescent: false,
          elevation: 1,
        );
    }
  }
}

/// 星穹液态玻璃色：低饱和蓝紫青虹彩。
class GlassPalette {
  static const cyan = Color(0xFF7EE8FF);
  static const magenta = Color(0xFFC084FC);
  static const violet = Color(0xFF818CF8);
  static const edgeLight = Color(0xE6FFFFFF);

  static LinearGradient rimGradient({required double alpha}) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        cyan.withValues(alpha: alpha),
        magenta.withValues(alpha: alpha * 0.85),
        violet.withValues(alpha: alpha * 0.7),
        cyan.withValues(alpha: alpha * 0.55),
      ],
      stops: const [0.0, 0.35, 0.7, 1.0],
    );
  }

  static LinearGradient sheen({required bool hover}) {
    final a = hover ? 0.14 : 0.08;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: a),
        Colors.transparent,
        cyan.withValues(alpha: a * 0.28),
      ],
      stops: const [0.0, 0.45, 1.0],
    );
  }
}
