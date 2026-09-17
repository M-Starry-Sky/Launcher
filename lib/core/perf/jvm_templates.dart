import 'gc_presets.dart';
import 'hardware_info.dart';
import 'memory_allocator.dart';

/// 可视化一键套用的 JVM 模板（4 套）。
enum JvmTemplate {
  low4g,
  mid8g,
  highShadow,
  largeTech,
}

extension JvmTemplateX on JvmTemplate {
  String get storageKey => name;

  String get label => switch (this) {
        JvmTemplate.low4g => '低配 4G 以下',
        JvmTemplate.mid8g => '8G 中端平衡',
        JvmTemplate.highShadow => '16G 高配光影',
        JvmTemplate.largeTech => '200+ 大型科技包',
      };

  String get hint => switch (this) {
        JvmTemplate.low4g => 'SerialGC + 1G 堆，老旧本专用',
        JvmTemplate.mid8g => 'G1 + 2G，原版/轻度模组',
        JvmTemplate.highShadow => 'ZGC 倾向 + 6G，光影整合',
        JvmTemplate.largeTech => 'G1 + 8G + 元空间扩容',
      };

  int get memoryMb => switch (this) {
        JvmTemplate.low4g => 1024,
        JvmTemplate.mid8g => 2048,
        JvmTemplate.highShadow => 6144,
        JvmTemplate.largeTech => 8192,
      };

  GcPreset get gcPreset => switch (this) {
        JvmTemplate.low4g => GcPreset.economy,
        JvmTemplate.mid8g => GcPreset.balanced,
        JvmTemplate.highShadow => GcPreset.smooth,
        JvmTemplate.largeTech => GcPreset.balanced,
      };

  bool get largeModpack => this == JvmTemplate.largeTech;

  static JvmTemplate parse(String? raw) {
    switch (raw) {
      case 'mid8g':
        return JvmTemplate.mid8g;
      case 'highShadow':
        return JvmTemplate.highShadow;
      case 'largeTech':
        return JvmTemplate.largeTech;
      default:
        return JvmTemplate.low4g;
    }
  }

  static JvmTemplate suggestFor(HardwareInfo hw) {
    final tier = MemoryRecommendation.forHardware(hw).tier;
    switch (tier) {
      case MemoryTier.low4g:
        return JvmTemplate.low4g;
      case MemoryTier.mid8g:
        return JvmTemplate.mid8g;
      case MemoryTier.high16g:
        return JvmTemplate.highShadow;
      case MemoryTier.ultra16p:
        return JvmTemplate.highShadow;
    }
  }
}
