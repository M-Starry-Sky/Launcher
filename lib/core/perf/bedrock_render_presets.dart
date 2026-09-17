/// 基岩版渲染预设。
/// 只落盘已被 Windows 基岩 options.txt 广泛验证的键；无可靠键的项不写入、不装作生效。
enum BedrockRenderPreset {
  low,
  balanced,
  ultra,
}

extension BedrockRenderPresetX on BedrockRenderPreset {
  String get storageKey => name;

  String get label => switch (this) {
        BedrockRenderPreset.low => '流畅低配',
        BedrockRenderPreset.balanced => '均衡标准',
        BedrockRenderPreset.ultra => '高清顶配',
      };

  String get subtitle => switch (this) {
        BedrockRenderPreset.low =>
            '视距 8 · 关精美天空/平滑光照 · 关 VSync · 帧率上限 60',
        BedrockRenderPreset.balanced =>
            '视距 16 · 精美天空 · 关 VSync · 帧率上限 120',
        BedrockRenderPreset.ultra =>
            '视距 28 · 精美画面 · 帧率上限 0(不限制) · 需独显',
      };

  static BedrockRenderPreset parse(String? raw) {
    switch (raw) {
      case 'low':
        return BedrockRenderPreset.low;
      case 'ultra':
        return BedrockRenderPreset.ultra;
      default:
        return BedrockRenderPreset.balanced;
    }
  }
}

class BedrockRenderSettings {
  final BedrockRenderPreset preset;
  final int renderDistance;
  final bool fancySkies;
  final bool fancyGraphics;
  final bool smoothLighting;
  final bool vsync;
  final bool fullscreen;
  final int maxFramerate; // 0 = 不限制（基岩常见写法）
  final bool multithreadedRenderer;

  const BedrockRenderSettings({
    required this.preset,
    required this.renderDistance,
    required this.fancySkies,
    required this.fancyGraphics,
    required this.smoothLighting,
    required this.vsync,
    required this.fullscreen,
    required this.maxFramerate,
    required this.multithreadedRenderer,
  });

  factory BedrockRenderSettings.fromPreset(BedrockRenderPreset preset) {
    switch (preset) {
      case BedrockRenderPreset.low:
        return const BedrockRenderSettings(
          preset: BedrockRenderPreset.low,
          renderDistance: 8,
          fancySkies: false,
          fancyGraphics: false,
          smoothLighting: false,
          vsync: true,
          fullscreen: true,
          maxFramerate: 60,
          multithreadedRenderer: true,
        );
      case BedrockRenderPreset.balanced:
        return const BedrockRenderSettings(
          preset: BedrockRenderPreset.balanced,
          renderDistance: 16,
          fancySkies: true,
          fancyGraphics: true,
          smoothLighting: true,
          vsync: true,
          fullscreen: false,
          maxFramerate: 60,
          multithreadedRenderer: true,
        );
      case BedrockRenderPreset.ultra:
        return const BedrockRenderSettings(
          preset: BedrockRenderPreset.ultra,
          renderDistance: 28,
          fancySkies: true,
          fancyGraphics: true,
          smoothLighting: true,
          vsync: false,
          fullscreen: true,
          maxFramerate: 0,
          multithreadedRenderer: true,
        );
    }
  }

  BedrockRenderSettings copyWith({
    BedrockRenderPreset? preset,
    int? renderDistance,
    bool? fancySkies,
    bool? fancyGraphics,
    bool? smoothLighting,
    bool? vsync,
    bool? fullscreen,
    int? maxFramerate,
    bool? multithreadedRenderer,
  }) {
    return BedrockRenderSettings(
      preset: preset ?? this.preset,
      renderDistance: renderDistance ?? this.renderDistance,
      fancySkies: fancySkies ?? this.fancySkies,
      fancyGraphics: fancyGraphics ?? this.fancyGraphics,
      smoothLighting: smoothLighting ?? this.smoothLighting,
      vsync: vsync ?? this.vsync,
      fullscreen: fullscreen ?? this.fullscreen,
      maxFramerate: maxFramerate ?? this.maxFramerate,
      multithreadedRenderer:
          multithreadedRenderer ?? this.multithreadedRenderer,
    );
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.storageKey,
        'render_distance': renderDistance,
        'fancy_skies': fancySkies,
        'fancy_graphics': fancyGraphics,
        'smooth_lighting': smoothLighting,
        'vsync': vsync,
        'fullscreen': fullscreen,
        'max_framerate': maxFramerate,
        'multithreaded_renderer': multithreadedRenderer,
      };

  factory BedrockRenderSettings.fromJson(Map<String, dynamic> json) {
    // 兼容旧字段：若只有旧 json，按 preset 重建
    if (!json.containsKey('max_framerate') && json.containsKey('preset')) {
      return BedrockRenderSettings.fromPreset(
        BedrockRenderPresetX.parse(json['preset'] as String?),
      );
    }
    final preset = BedrockRenderPresetX.parse(json['preset'] as String?);
    final base = BedrockRenderSettings.fromPreset(preset);
    return base.copyWith(
      renderDistance: (json['render_distance'] as num?)?.toInt(),
      fancySkies: json['fancy_skies'] as bool?,
      fancyGraphics: json['fancy_graphics'] as bool?,
      smoothLighting: json['smooth_lighting'] as bool?,
      vsync: json['vsync'] as bool?,
      fullscreen: json['fullscreen'] as bool?,
      maxFramerate: (json['max_framerate'] as num?)?.toInt(),
      multithreadedRenderer: json['multithreaded_renderer'] as bool?,
    );
  }

  /// 仅写入确认存在的 options.txt 键。
  Map<String, String> toOptionsTxtEntries() {
    return {
      'gfx_viewdistance': '$renderDistance',
      'gfx_fancyskies': fancySkies ? '1' : '0',
      'gfx_fancygraphics': fancyGraphics ? '1' : '0',
      'gfx_smoothlighting': smoothLighting ? '1' : '0',
      'gfx_vsync': vsync ? '1' : '0',
      'gfx_fullscreen': fullscreen ? '1' : '0',
      'gfx_max_framerate': '$maxFramerate',
      'gfx_multithreaded_renderer': multithreadedRenderer ? '1' : '0',
    };
  }
}
