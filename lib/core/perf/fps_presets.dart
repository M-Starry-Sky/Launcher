/// Java 版帧率档位（对标 Sodium 生态：画质砍负载 + 上限帧）。
enum FpsPreset {
  /// 竞技 / PVP：极限帧，画质压到最低可用
  competitive,

  /// 均衡：流畅与观感折中
  balanced,

  /// 画质优先：高视距，帧率上限显示器常见刷新
  quality,

  /// 极低配：轻薄本 / 集显保底可玩
  extremeLow,
}

extension FpsPresetX on FpsPreset {
  String get storageKey => name;

  String get label => switch (this) {
        FpsPreset.competitive => '竞技极致帧',
        FpsPreset.balanced => '均衡流畅',
        FpsPreset.quality => '画质优先',
        FpsPreset.extremeLow => '极低配保帧',
      };

  String get subtitle => switch (this) {
        FpsPreset.competitive =>
            '关垂直同步 · 无上限帧 · 快速画面 · 低视距 · 对标 Sodium 竞技党',
        FpsPreset.balanced =>
            '开垂直同步 · 60 帧贴屏 · 中视距 · 真实帧稳少抖',
        FpsPreset.quality =>
            '开垂直同步 · 60 帧贴屏 · 高视距 · 精美且稳',
        FpsPreset.extremeLow =>
            '开垂直同步 · 60 帧硬顶 · 视距 6 · 老本保帧',
      };

  static FpsPreset parse(String? raw) {
    switch (raw) {
      case 'competitive':
        return FpsPreset.competitive;
      case 'quality':
        return FpsPreset.quality;
      case 'extremeLow':
        return FpsPreset.extremeLow;
      default:
        return FpsPreset.balanced;
    }
  }
}

/// 写入 options.txt 的帧率相关键（兼容新旧键名一并写入）。
class JavaFpsSettings {
  final FpsPreset preset;
  final int renderDistance;
  final int simulationDistance;
  final int maxFps; // 260 在原版常被视作「无上限」
  final bool vsync;
  final bool fancyGraphics;
  final bool fabulous; // Fabulous 图形（极耗）
  final String particles; // minimal | decreased | all
  final bool entityShadows;
  final String clouds; // false | fast | true
  final bool ambientOcclusion;
  final int mipmapLevels;
  final int biomeBlendRadius;
  final bool prioritizeChunkUpdatesByPlayer;
  final bool fullscreen;
  final bool applyOnLaunch;
  final bool autoInstallPerfMods;
  final bool boostProcessPriority;
  final bool aggressiveJvmFps;

  const JavaFpsSettings({
    required this.preset,
    required this.renderDistance,
    required this.simulationDistance,
    required this.maxFps,
    required this.vsync,
    required this.fancyGraphics,
    required this.fabulous,
    required this.particles,
    required this.entityShadows,
    required this.clouds,
    required this.ambientOcclusion,
    required this.mipmapLevels,
    required this.biomeBlendRadius,
    required this.prioritizeChunkUpdatesByPlayer,
    required this.fullscreen,
    required this.applyOnLaunch,
    required this.autoInstallPerfMods,
    required this.boostProcessPriority,
    required this.aggressiveJvmFps,
  });

  factory JavaFpsSettings.fromPreset(FpsPreset preset) {
    switch (preset) {
      case FpsPreset.competitive:
        return const JavaFpsSettings(
          preset: FpsPreset.competitive,
          renderDistance: 8,
          simulationDistance: 6,
          maxFps: 260,
          vsync: false,
          fancyGraphics: false,
          fabulous: false,
          particles: 'minimal',
          entityShadows: false,
          clouds: 'false',
          ambientOcclusion: false,
          mipmapLevels: 2,
          biomeBlendRadius: 0,
          prioritizeChunkUpdatesByPlayer: false,
          fullscreen: false,
          applyOnLaunch: true,
          autoInstallPerfMods: true,
          boostProcessPriority: true,
          aggressiveJvmFps: true,
        );
      case FpsPreset.balanced:
        return const JavaFpsSettings(
          preset: FpsPreset.balanced,
          renderDistance: 12,
          simulationDistance: 8,
          maxFps: 60,
          vsync: true,
          fancyGraphics: false,
          fabulous: false,
          particles: 'decreased',
          entityShadows: false,
          clouds: 'fast',
          ambientOcclusion: true,
          mipmapLevels: 3,
          biomeBlendRadius: 1,
          prioritizeChunkUpdatesByPlayer: false,
          fullscreen: false,
          applyOnLaunch: true,
          autoInstallPerfMods: true,
          boostProcessPriority: true,
          aggressiveJvmFps: true,
        );
      case FpsPreset.quality:
        return const JavaFpsSettings(
          preset: FpsPreset.quality,
          renderDistance: 16,
          simulationDistance: 12,
          maxFps: 60,
          vsync: true,
          fancyGraphics: true,
          fabulous: false,
          particles: 'all',
          entityShadows: true,
          clouds: 'true',
          ambientOcclusion: true,
          mipmapLevels: 4,
          biomeBlendRadius: 2,
          prioritizeChunkUpdatesByPlayer: true,
          fullscreen: false,
          applyOnLaunch: true,
          autoInstallPerfMods: true,
          boostProcessPriority: false,
          aggressiveJvmFps: false,
        );
      case FpsPreset.extremeLow:
        return const JavaFpsSettings(
          preset: FpsPreset.extremeLow,
          renderDistance: 6,
          simulationDistance: 4,
          maxFps: 60,
          vsync: true,
          fancyGraphics: false,
          fabulous: false,
          particles: 'minimal',
          entityShadows: false,
          clouds: 'false',
          ambientOcclusion: false,
          mipmapLevels: 0,
          biomeBlendRadius: 0,
          prioritizeChunkUpdatesByPlayer: false,
          fullscreen: false,
          applyOnLaunch: true,
          autoInstallPerfMods: true,
          boostProcessPriority: true,
          aggressiveJvmFps: true,
        );
    }
  }

  JavaFpsSettings copyWith({
    FpsPreset? preset,
    int? renderDistance,
    int? simulationDistance,
    int? maxFps,
    bool? vsync,
    bool? fancyGraphics,
    bool? fabulous,
    String? particles,
    bool? entityShadows,
    String? clouds,
    bool? ambientOcclusion,
    int? mipmapLevels,
    int? biomeBlendRadius,
    bool? prioritizeChunkUpdatesByPlayer,
    bool? fullscreen,
    bool? applyOnLaunch,
    bool? autoInstallPerfMods,
    bool? boostProcessPriority,
    bool? aggressiveJvmFps,
  }) {
    return JavaFpsSettings(
      preset: preset ?? this.preset,
      renderDistance: renderDistance ?? this.renderDistance,
      simulationDistance: simulationDistance ?? this.simulationDistance,
      maxFps: maxFps ?? this.maxFps,
      vsync: vsync ?? this.vsync,
      fancyGraphics: fancyGraphics ?? this.fancyGraphics,
      fabulous: fabulous ?? this.fabulous,
      particles: particles ?? this.particles,
      entityShadows: entityShadows ?? this.entityShadows,
      clouds: clouds ?? this.clouds,
      ambientOcclusion: ambientOcclusion ?? this.ambientOcclusion,
      mipmapLevels: mipmapLevels ?? this.mipmapLevels,
      biomeBlendRadius: biomeBlendRadius ?? this.biomeBlendRadius,
      prioritizeChunkUpdatesByPlayer:
          prioritizeChunkUpdatesByPlayer ?? this.prioritizeChunkUpdatesByPlayer,
      fullscreen: fullscreen ?? this.fullscreen,
      applyOnLaunch: applyOnLaunch ?? this.applyOnLaunch,
      autoInstallPerfMods: autoInstallPerfMods ?? this.autoInstallPerfMods,
      boostProcessPriority: boostProcessPriority ?? this.boostProcessPriority,
      aggressiveJvmFps: aggressiveJvmFps ?? this.aggressiveJvmFps,
    );
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.storageKey,
        'render_distance': renderDistance,
        'simulation_distance': simulationDistance,
        'max_fps': maxFps,
        'vsync': vsync,
        'fancy_graphics': fancyGraphics,
        'fabulous': fabulous,
        'particles': particles,
        'entity_shadows': entityShadows,
        'clouds': clouds,
        'ambient_occlusion': ambientOcclusion,
        'mipmap_levels': mipmapLevels,
        'biome_blend_radius': biomeBlendRadius,
        'prioritize_chunk_updates': prioritizeChunkUpdatesByPlayer,
        'fullscreen': fullscreen,
        'apply_on_launch': applyOnLaunch,
        'auto_install_perf_mods': autoInstallPerfMods,
        'boost_process_priority': boostProcessPriority,
        'aggressive_jvm_fps': aggressiveJvmFps,
      };

  factory JavaFpsSettings.fromJson(Map<String, dynamic> json) {
    final preset = FpsPresetX.parse(json['preset'] as String?);
    final base = JavaFpsSettings.fromPreset(preset);
    return base.copyWith(
      renderDistance: (json['render_distance'] as num?)?.toInt(),
      simulationDistance: (json['simulation_distance'] as num?)?.toInt(),
      maxFps: (json['max_fps'] as num?)?.toInt(),
      vsync: json['vsync'] as bool?,
      fancyGraphics: json['fancy_graphics'] as bool?,
      fabulous: json['fabulous'] as bool?,
      particles: json['particles'] as String?,
      entityShadows: json['entity_shadows'] as bool?,
      clouds: json['clouds'] as String?,
      ambientOcclusion: json['ambient_occlusion'] as bool?,
      mipmapLevels: (json['mipmap_levels'] as num?)?.toInt(),
      biomeBlendRadius: (json['biome_blend_radius'] as num?)?.toInt(),
      prioritizeChunkUpdatesByPlayer:
          json['prioritize_chunk_updates'] as bool?,
      fullscreen: json['fullscreen'] as bool?,
      applyOnLaunch: json['apply_on_launch'] as bool?,
      autoInstallPerfMods: json['auto_install_perf_mods'] as bool?,
      boostProcessPriority: json['boost_process_priority'] as bool?,
      aggressiveJvmFps: json['aggressive_jvm_fps'] as bool?,
    );
  }

  /// options.txt：1.16+ 起 particles / graphicsMode / prioritizeChunkUpdates
  /// 必须是数字枚举；写成 minimal/fast 会导致解析失败甚至黑屏卡住。
  Map<String, String> toOptionsTxtEntries() {
    final graphicsMode = fabulous ? 2 : (fancyGraphics ? 1 : 0);
    final particlesMode = switch (particles) {
      'all' => 2,
      'decreased' => 1,
      _ => 0, // minimal
    };
    final chunk = prioritizeChunkUpdatesByPlayer ? 1 : 0;
    return {
      'maxFps': '$maxFps',
      'enableVsync': '$vsync',
      'renderDistance': '$renderDistance',
      'simulationDistance': '$simulationDistance',
      'particles': '$particlesMode',
      'entityShadows': '$entityShadows',
      'clouds': clouds,
      'ao': ambientOcclusion ? 'true' : 'false',
      'fancyGraphics': '$fancyGraphics',
      'graphicsMode': '$graphicsMode',
      'mipmapLevels': '$mipmapLevels',
      'biomeBlendRadius': '$biomeBlendRadius',
      'prioritizeChunkUpdates': '$chunk',
      'fullscreen': '$fullscreen',
      'entityDistanceScaling':
          preset == FpsPreset.extremeLow ? '0.75' : '1.0',
    };
  }
}
