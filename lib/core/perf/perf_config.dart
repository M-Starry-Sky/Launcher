import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'bedrock_render_presets.dart';
import 'fps_presets.dart';
import 'gc_presets.dart';
import 'hardware_info.dart';
import 'jvm_templates.dart';
import 'memory_allocator.dart';
import 'perf_profiles.dart';

/// 性能优化中心状态（持久化到 SharedPreferences）。
class PerfConfig extends ChangeNotifier {
  static const keyHeapMb = 'perf_heap_mb';
  static const keyGcPreset = 'perf_gc_preset';
  static const keyJvmTemplate = 'perf_jvm_template';
  static const keyLargeModpack = 'perf_large_modpack';
  static const keyAutoMemory = 'perf_auto_memory';
  static const keyAutoGc = 'perf_auto_gc';
  static const keyAdvancedMode = 'perf_advanced_mode';
  static const keyPerfMode = 'perf_launcher_lite';
  /// 开启性能模式前备份的玻璃档位，关闭时还原。
  static const keyGlassBackup = 'perf_glass_mode_backup';
  static const keyCustomJvm = 'perf_custom_jvm_args';
  static const keyBedrockJson = 'perf_bedrock_render';
  static const keyEditionTab = 'perf_edition_tab';
  static const keyFpsJson = 'perf_java_fps';
  static const keyActiveProfile = 'perf_active_profile';
  static const keyBlockOnConflict = 'perf_block_on_mod_conflict';
  static const keyAutoFixSoftConflict = 'perf_auto_fix_soft_conflict';
  static const keyCleanCacheOnLaunch = 'perf_clean_cache_on_launch';
  static const keyAutoFixJava = 'perf_auto_fix_java';
  static const keyTrimLauncherOnLaunch = 'perf_trim_launcher_on_launch';
  /// 开启性能模式前的玻璃档位，关闭时还原。
  static const keyGlassBeforePerf = 'perf_glass_mode_before';

  final AppConfig config;
  HardwareInfo? _hardware;
  MemoryRecommendation? _memoryRec;
  bool _probing = false;

  PerfConfig(this.config) {
    config.addListener(_onConfigChanged);
  }

  void _onConfigChanged() => notifyListeners();

  @override
  void dispose() {
    config.removeListener(_onConfigChanged);
    super.dispose();
  }

  HardwareInfo? get hardware => _hardware;
  MemoryRecommendation? get memoryRecommendation => _memoryRec;
  bool get probing => _probing;

  int get heapMb => config.maxMemoryMb;

  GcPreset get gcPreset =>
      GcPresetX.parse(config.getStringOr(keyGcPreset, 'balanced'));

  JvmTemplate get jvmTemplate =>
      JvmTemplateX.parse(config.getStringOr(keyJvmTemplate, 'mid8g'));

  bool get largeModpack => config.getBoolOr(keyLargeModpack, false);
  bool get autoMemory => config.getBoolOr(keyAutoMemory, true);
  bool get autoGc => config.getBoolOr(keyAutoGc, true);
  bool get advancedMode => config.getBoolOr(keyAdvancedMode, false);
  bool get launcherPerfMode => config.getBoolOr(keyPerfMode, false);
  String get customJvmArgs => config.getStringOr(keyCustomJvm, '');
  String get editionTab => config.getStringOr(keyEditionTab, 'java');
  bool get blockOnModConflict => config.getBoolOr(keyBlockOnConflict, true);
  /// 弱冲突（ViaFabric/Plus、OptiFine+Sodium 等）启动时自动删 jar 并继续。
  bool get autoFixSoftConflict =>
      config.getBoolOr(keyAutoFixSoftConflict, true);
  bool get cleanCacheOnLaunch => config.getBoolOr(keyCleanCacheOnLaunch, false);
  bool get autoFixJava => config.getBoolOr(keyAutoFixJava, true);
  bool get trimLauncherOnLaunch =>
      config.getBoolOr(keyTrimLauncherOnLaunch, false);

  PerfProfileId? get activeProfile =>
      PerfProfileIdX.parse(config.getStringOr(keyActiveProfile, ''));

  JavaFpsSettings get fps {
    final raw = config.getJson(keyFpsJson);
    if (raw.isEmpty) {
      return JavaFpsSettings.fromPreset(FpsPreset.competitive);
    }
    return JavaFpsSettings.fromJson(raw);
  }

  BedrockRenderSettings get bedrock {
    final raw = config.getJson(keyBedrockJson);
    if (raw.isEmpty) {
      return BedrockRenderSettings.fromPreset(BedrockRenderPreset.balanced);
    }
    return BedrockRenderSettings.fromJson(raw);
  }

  Future<void> refreshHardware() async {
    _probing = true;
    notifyListeners();
    try {
      _hardware = await HardwareInfo.detect();
      _memoryRec = MemoryRecommendation.forHardware(_hardware!);
    } finally {
      _probing = false;
      notifyListeners();
    }
  }

  FpsPreset suggestFpsPreset(HardwareInfo hw) {
    final mem = MemoryRecommendation.forHardware(hw);
    if (mem.tier == MemoryTier.low4g || hw.cpuLogicalCores <= 2) {
      return FpsPreset.extremeLow;
    }
    if (!hw.likelySsd) return FpsPreset.extremeLow;
    if (mem.tier == MemoryTier.mid8g) return FpsPreset.balanced;
    return FpsPreset.competitive;
  }

  Future<void> smartAdapt({int? javaMajor}) async {
    if (_hardware == null) await refreshHardware();
    final hw = _hardware!;
    final mem = MemoryRecommendation.forHardware(hw);
    final gc = GcPresetX.autoSelect(hw, javaMajor);
    final tpl = JvmTemplateX.suggestFor(hw);
    var fpsSettings = JavaFpsSettings.fromPreset(suggestFpsPreset(hw));
    // 机械盘：视距再压一档，减少区块 IO 卡顿（真实 options 生效）
    if (!hw.likelySsd) {
      fpsSettings = fpsSettings.copyWith(
        renderDistance: fpsSettings.renderDistance.clamp(2, 8),
        simulationDistance: fpsSettings.simulationDistance.clamp(2, 6),
      );
    }
    await setHeapMb(mem.recommendedMb);
    await setGcPreset(gc);
    await setJvmTemplate(tpl);
    await setLargeModpack(tpl.largeModpack);
    await setFps(fpsSettings);
    await config.set(AppConfig.keyMaxMemoryMb, mem.recommendedMb);
    if (mem.tier == MemoryTier.low4g || hw.cpuLogicalCores <= 2) {
      await setLauncherPerfMode(true);
    }
    notifyListeners();
  }

  Future<void> applyProfile(PerfProfileId id) async {
    await config.set(keyActiveProfile, id.storageKey);
    switch (id) {
      case PerfProfileId.pvp:
        await applyFpsPreset(FpsPreset.competitive);
        await setGcPreset(GcPreset.balanced);
        break;
      case PerfProfileId.building:
        await applyFpsPreset(FpsPreset.balanced);
        await setFps(fps.copyWith(renderDistance: 14, maxFps: 60, vsync: true));
        break;
      case PerfProfileId.shadowLive:
        await applyFpsPreset(FpsPreset.quality);
        await setGcPreset(GcPreset.smooth);
        await setLargeModpack(true);
        break;
      case PerfProfileId.lowEnd:
        await applyFpsPreset(FpsPreset.extremeLow);
        await setGcPreset(GcPreset.economy);
        await setLauncherPerfMode(true);
        break;
    }
    notifyListeners();
  }

  Future<void> setHeapMb(int mb) async {
    final clamped = _memoryRec?.clampAllocation(mb) ?? mb.clamp(512, 12288);
    await config.setJson(keyHeapMb, {'v': clamped});
    await config.set(AppConfig.keyMaxMemoryMb, clamped);
    notifyListeners();
  }

  Future<void> setGcPreset(GcPreset p) async {
    await config.set(keyGcPreset, p.storageKey);
    notifyListeners();
  }

  Future<void> setJvmTemplate(JvmTemplate t) async {
    await config.set(keyJvmTemplate, t.storageKey);
    await setHeapMb(t.memoryMb);
    await setGcPreset(t.gcPreset);
    await setLargeModpack(t.largeModpack);
    notifyListeners();
  }

  Future<void> setLargeModpack(bool v) async {
    await config.setBool(keyLargeModpack, v);
    notifyListeners();
  }

  Future<void> setAutoMemory(bool v) async {
    await config.setBool(keyAutoMemory, v);
    notifyListeners();
  }

  Future<void> setAutoGc(bool v) async {
    await config.setBool(keyAutoGc, v);
    notifyListeners();
  }

  Future<void> setAdvancedMode(bool v) async {
    await config.setBool(keyAdvancedMode, v);
    notifyListeners();
  }

  Future<void> setLauncherPerfMode(bool v) async {
    await config.setBool(keyPerfMode, v);
    if (v) {
      final current = config.glassModeRaw;
      // 已是纯净则保留先前备份，避免把备份覆盖成 off
      if (current != 'off') {
        await config.set(keyGlassBackup, current);
      } else if (config.getStringOr(keyGlassBackup, '').isEmpty) {
        await config.set(keyGlassBackup, 'liquid');
      }
      await config.set(AppConfig.keyGlassMode, 'off');
    } else {
      final backup = config.getStringOr(keyGlassBackup, 'liquid');
      final restore =
          (backup.isEmpty || backup == 'off') ? 'liquid' : backup;
      await config.set(AppConfig.keyGlassMode, restore);
    }
    notifyListeners();
  }

  Future<void> setCustomJvmArgs(String v) async {
    await config.set(keyCustomJvm, v);
    notifyListeners();
  }

  Future<void> setEditionTab(String v) async {
    await config.set(keyEditionTab, v);
    notifyListeners();
  }

  Future<void> setBlockOnModConflict(bool v) async {
    await config.setBool(keyBlockOnConflict, v);
    notifyListeners();
  }

  Future<void> setAutoFixSoftConflict(bool v) async {
    await config.setBool(keyAutoFixSoftConflict, v);
    notifyListeners();
  }

  Future<void> setCleanCacheOnLaunch(bool v) async {
    await config.setBool(keyCleanCacheOnLaunch, v);
    notifyListeners();
  }

  Future<void> setAutoFixJava(bool v) async {
    await config.setBool(keyAutoFixJava, v);
    notifyListeners();
  }

  Future<void> setTrimLauncherOnLaunch(bool v) async {
    await config.setBool(keyTrimLauncherOnLaunch, v);
    notifyListeners();
  }

  Future<void> setBedrock(BedrockRenderSettings s) async {
    await config.setJson(keyBedrockJson, s.toJson());
    notifyListeners();
  }

  Future<void> applyBedrockPreset(BedrockRenderPreset p) async {
    await setBedrock(BedrockRenderSettings.fromPreset(p));
  }

  Future<void> setFps(JavaFpsSettings s) async {
    await config.setJson(keyFpsJson, s.toJson());
    notifyListeners();
  }

  Future<void> applyFpsPreset(FpsPreset p) async {
    await setFps(JavaFpsSettings.fromPreset(p));
  }
}
