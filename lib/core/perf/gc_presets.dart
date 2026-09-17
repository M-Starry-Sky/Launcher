import 'hardware_info.dart';
import 'memory_allocator.dart';

/// GC 策略预设（新手一键，无需手写 JVM 参数）。
enum GcPreset {
  /// G1：全版本默认平衡
  balanced,

  /// ZGC / 分代 ZGC：高配流畅
  smooth,

  /// Serial：低配节能
  economy,
}

extension GcPresetX on GcPreset {
  String get storageKey => name;

  String get label => switch (this) {
        GcPreset.balanced => '平衡通用',
        GcPreset.smooth => '极致流畅',
        GcPreset.economy => '低配节能',
      };

  String get subtitle => switch (this) {
        GcPreset.balanced => 'G1GC · 原版/中小型模组默认',
        GcPreset.smooth => 'ZGC · Java15+ / Java21 分代',
        GcPreset.economy => 'SerialGC · ≤4G 或双核强制',
      };

  static GcPreset parse(String? raw) {
    switch (raw) {
      case 'smooth':
        return GcPreset.smooth;
      case 'economy':
        return GcPreset.economy;
      default:
        return GcPreset.balanced;
    }
  }

  /// 按硬件与 Java 主版本自动挑选；≤4G / 双核强制 Serial。
  static GcPreset autoSelect(HardwareInfo hw, int? javaMajor) {
    final mem = MemoryRecommendation.forHardware(hw);
    if (mem.tier == MemoryTier.low4g || hw.cpuLogicalCores <= 2) {
      return GcPreset.economy;
    }
    if (mem.tier == MemoryTier.ultra16p &&
        javaMajor != null &&
        javaMajor >= 15) {
      return GcPreset.smooth;
    }
    return GcPreset.balanced;
  }
}

/// 生成对应 GC 的 JVM 参数片段。
class GcArgsBuilder {
  static List<String> build(GcPreset preset, {required int javaMajor}) {
    switch (preset) {
      case GcPreset.economy:
        return const [
          '-XX:+UseSerialGC',
        ];
      case GcPreset.smooth:
        if (javaMajor < 15) {
          // 降级到 G1，避免老 Java 无法识别 ZGC
          return _g1();
        }
        if (javaMajor >= 21) {
          return const [
            '-XX:+UseZGC',
            '-XX:+ZGenerational',
          ];
        }
        return const [
          '-XX:+UseZGC',
        ];
      case GcPreset.balanced:
        return _g1();
    }
  }

  static List<String> _g1() => const [
        '-XX:+UseG1GC',
        // 更短停顿目标：减少真实帧率「掉崖」式抖动
        '-XX:MaxGCPauseMillis=20',
        '-XX:+ParallelRefProcEnabled',
        '-XX:G1HeapRegionSize=16M',
      ];
}
