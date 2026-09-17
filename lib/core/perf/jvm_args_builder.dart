import 'gc_presets.dart';
import 'hardware_info.dart';

/// 组装启动用 JVM 参数。
/// 只保留对客户端有实测意义的旗标；不写「看起来很强」但无效/有害的参数。
class JvmArgsBuilder {
  final int heapMb;
  final GcPreset gcPreset;
  final int javaMajor;
  final bool largeModpack;
  final bool aggressiveFps;
  final String? extraArgs;
  final HardwareInfo? hardware;

  const JvmArgsBuilder({
    required this.heapMb,
    required this.gcPreset,
    required this.javaMajor,
    this.largeModpack = false,
    this.aggressiveFps = true,
    this.extraArgs,
    this.hardware,
  });

  List<String> build() {
    // Xms 远小于 Xmx：避免一启动就提交整堆（4G+ 时进程已起却长时间无窗口）
    final xms = _startupHeapMb(heapMb);
    final args = <String>[
      '-Xms${xms}M',
      '-Xmx${heapMb}M',
      ...GcArgsBuilder.build(gcPreset, javaMajor: javaMajor),
    ];

    if (largeModpack) {
      args.addAll(const [
        '-XX:MetaspaceSize=256M',
        '-XX:MaxMetaspaceSize=512M',
      ]);
    }

    // ParallelGCThreads 仅对 G1/Parallel 有意义；ZGC/Serial 不加，避免无效噪声。
    final cores = hardware?.cpuLogicalCores ?? 0;
    if (gcPreset == GcPreset.balanced && cores >= 4) {
      final parallel = (cores / 2).floor().clamp(2, 8);
      args.add('-XX:ParallelGCThreads=$parallel');
      args.add('-XX:ConcGCThreads=${(parallel / 2).ceil().clamp(1, 4)}');
    }

    if (aggressiveFps) {
      args.addAll(_fpsClientFlags(gcPreset: gcPreset));
    }

    final extra = extraArgs?.trim() ?? '';
    if (extra.isNotEmpty) {
      args.addAll(_splitArgs(extra));
    }
    return args;
  }

  /// 启动期初始堆：小堆快速出窗，再按需扩到 Xmx。
  static int _startupHeapMb(int heapMb) {
    if (heapMb <= 1024) return heapMb;
    return (heapMb ~/ 4).clamp(512, 1024);
  }

  /// 有依据的客户端抗卡顿旗标：
  /// - PerfDisableSharedMem：减少 Windows 上 hsperfdata 抖动
  /// - DisableExplicitGC：忽略 System.gc() 强制停顿
  /// 不加 AlwaysPreTouch：4G+ 堆预提交会让进程「已启动」却长时间无窗口。
  static List<String> _fpsClientFlags({required GcPreset gcPreset}) {
    final list = <String>[
      '-XX:+DisableExplicitGC',
      '-XX:+PerfDisableSharedMem',
      '-Dfile.encoding=UTF-8',
    ];
    if (gcPreset == GcPreset.balanced) {
      // G1NewSizePercent / G1MaxNewSizePercent 在 Java17 仍属实验项，
      // 必须先 Unlock，否则 JVM 直接拒绝启动（表现为「游戏打不开」）。
      list.addAll(const [
        '-XX:+UnlockExperimentalVMOptions',
        '-XX:G1NewSizePercent=30',
        '-XX:G1MaxNewSizePercent=40',
        '-XX:G1ReservePercent=20',
        '-XX:InitiatingHeapOccupancyPercent=15',
      ]);
    }
    return list;
  }

  static List<String> _splitArgs(String raw) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c == '"') {
        inQuote = !inQuote;
        continue;
      }
      if (!inQuote && (c == ' ' || c == '\t' || c == '\n' || c == '\r')) {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
        continue;
      }
      buf.write(c);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }
}
