import 'hardware_info.dart';
import 'jvm_args_builder.dart';
import 'perf_config.dart';

/// 生成「即将真正传给 Java」的参数预览，方便核对、避免假参数。
class JvmArgsPreview {
  static String build(PerfConfig perf, {int javaMajor = 17}) {
    final args = JvmArgsBuilder(
      heapMb: perf.heapMb,
      gcPreset: perf.gcPreset,
      javaMajor: javaMajor,
      largeModpack: perf.largeModpack,
      aggressiveFps: perf.fps.aggressiveJvmFps,
      extraArgs: perf.customJvmArgs.trim().isEmpty ? null : perf.customJvmArgs,
      hardware: perf.hardware ??
          HardwareInfo(
            totalMemoryMb: 8192,
            freeMemoryMb: 4096,
            cpuLogicalCores: 4,
            likelySsd: true,
            osLabel: 'preview',
          ),
    ).build();
    return args.join('\n');
  }

  static String oneLine(PerfConfig perf, {int javaMajor = 17}) {
    return build(perf, javaMajor: javaMajor).replaceAll('\n', ' ');
  }
}
