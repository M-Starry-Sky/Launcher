import 'hardware_info.dart';

/// 物理内存分档 → 推荐 / 上限（对齐 PCL2 思路：禁止无脑拉满）。
enum MemoryTier {
  low4g,
  mid8g,
  high16g,
  ultra16p,
}

class MemoryRecommendation {
  final MemoryTier tier;
  final int recommendedMb;
  final int maxSafeMb;
  final int minMb;
  final String label;
  final String hint;

  const MemoryRecommendation({
    required this.tier,
    required this.recommendedMb,
    required this.maxSafeMb,
    required this.minMb,
    required this.label,
    required this.hint,
  });

  /// 按整机物理内存给出分档建议。
  static MemoryRecommendation forHardware(HardwareInfo hw) {
    final total = hw.totalMemoryMb;
    if (total <= 4096) {
      return const MemoryRecommendation(
        tier: MemoryTier.low4g,
        recommendedMb: 1024,
        maxSafeMb: 1024,
        minMb: 512,
        label: '低配 ≤4G',
        hint: '锁定 1024M，强制 SerialGC，避免堆过大触发长时间停顿',
      );
    }
    if (total <= 8192) {
      return const MemoryRecommendation(
        tier: MemoryTier.mid8g,
        recommendedMb: 2048,
        maxSafeMb: 3072,
        minMb: 1024,
        label: '中端 4~8G',
        hint: '推荐 2048M，上限 3072M，留给系统与浏览器余量',
      );
    }
    if (total <= 16384) {
      return const MemoryRecommendation(
        tier: MemoryTier.high16g,
        recommendedMb: 4096,
        maxSafeMb: 6144,
        minMb: 2048,
        label: '高配 8~16G',
        hint: '推荐 4096M，光影/中型整合包更稳',
      );
    }
    return const MemoryRecommendation(
      tier: MemoryTier.ultra16p,
      recommendedMb: 6144,
      maxSafeMb: 12288,
      minMb: 4096,
      label: '旗舰 16G+',
      hint: '推荐 6144~8192M，硬顶 12G，防止超大堆 GC 停顿',
    );
  }

  /// 将用户拖动值钳制在安全区间；低配强制推荐值。
  int clampAllocation(int requestedMb) {
    if (tier == MemoryTier.low4g) return recommendedMb;
    return requestedMb.clamp(minMb, maxSafeMb);
  }

  bool isDangerous(int mb) => mb > maxSafeMb;

  bool isAboveRecommended(int mb) => mb > recommendedMb;
}
