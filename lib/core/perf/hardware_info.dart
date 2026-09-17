import 'dart:ffi';
import 'dart:io';

/// 本机硬件快照（启动器启动 / 智能适配时刷新）。
class HardwareInfo {
  final int totalMemoryMb;
  final int freeMemoryMb;
  final int cpuLogicalCores;
  /// 整机 CPU 占用 0–100（按忙闲差分）；探测失败为 null。
  final double? cpuUsagePercent;
  final bool likelySsd;
  final String osLabel;

  const HardwareInfo({
    required this.totalMemoryMb,
    required this.freeMemoryMb,
    required this.cpuLogicalCores,
    required this.likelySsd,
    required this.osLabel,
    this.cpuUsagePercent,
  });

  int get usedMemoryMb => (totalMemoryMb - freeMemoryMb).clamp(0, totalMemoryMb);

  double get memoryUsageRatio =>
      totalMemoryMb <= 0 ? 0 : usedMemoryMb / totalMemoryMb;

  static HardwareInfo? _cached;
  static DateTime? _cachedAt;
  static const _cacheTtl = Duration(seconds: 8);

  static int? _prevIdle100ns;
  static int? _prevKernel100ns;
  static int? _prevUser100ns;

  static Future<HardwareInfo> detect({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      if (Platform.isWindows) {
        final cpu = _sampleSystemCpuPercentWindows();
        if (cpu != null) {
          _cached = HardwareInfo(
            totalMemoryMb: _cached!.totalMemoryMb,
            freeMemoryMb: _cached!.freeMemoryMb,
            cpuLogicalCores: _cached!.cpuLogicalCores,
            likelySsd: _cached!.likelySsd,
            osLabel: _cached!.osLabel,
            cpuUsagePercent: cpu,
          );
        }
      }
      return _cached!;
    }
    final info = await _detectFull();
    _cached = info;
    _cachedAt = now;
    return info;
  }

  static Future<HardwareInfo> _detectFull() async {
    final cores = Platform.numberOfProcessors;
    final os = Platform.operatingSystem;
    if (Platform.isWindows) return _detectWindows(cores, os);
    if (Platform.isLinux) return _detectLinux(cores, os);
    if (Platform.isMacOS) return _detectMac(cores, os);
    return HardwareInfo(
      totalMemoryMb: 8192,
      freeMemoryMb: 4096,
      cpuLogicalCores: cores,
      likelySsd: true,
      osLabel: os,
    );
  }

  static Future<HardwareInfo> _detectWindows(int cores, String os) async {
    var totalMb = 8192;
    var freeMb = 4096;
    var ssd = true;

    try {
      final r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'$o=Get-CimInstance Win32_OperatingSystem;'
              r'$m="$($o.TotalVisibleMemorySize),$($o.FreePhysicalMemory)";'
              r'$d=(Get-PhysicalDisk|Select-Object -First 1 -ExpandProperty MediaType);'
              r'Write-Output "$m|$d"',
        ],
      ).timeout(const Duration(seconds: 4), onTimeout: () {
        return ProcessResult(0, 1, '', 'timeout');
      });
      if (r.exitCode == 0) {
        final line = (r.stdout as String).trim();
        final parts = line.split('|');
        if (parts.isNotEmpty) {
          final mem = parts[0].split(',');
          if (mem.length >= 2) {
            final totalKb = int.tryParse(mem[0].trim()) ?? 0;
            final freeKb = int.tryParse(mem[1].trim()) ?? 0;
            if (totalKb > 0) totalMb = (totalKb / 1024).round();
            if (freeKb > 0) freeMb = (freeKb / 1024).round();
          }
        }
        if (parts.length >= 2) {
          final t = parts[1].trim().toLowerCase();
          if (t.contains('hdd') || t.contains('unspecified')) {
            ssd = false;
          } else if (t.contains('ssd') || t.contains('nvme')) {
            ssd = true;
          }
        }
      }
    } catch (_) {}

    _sampleSystemCpuPercentWindows();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final cpu = _sampleSystemCpuPercentWindows();

    return HardwareInfo(
      totalMemoryMb: totalMb,
      freeMemoryMb: freeMb.clamp(0, totalMb),
      cpuLogicalCores: cores,
      likelySsd: ssd,
      osLabel: os,
      cpuUsagePercent: cpu,
    );
  }

  static double? _sampleSystemCpuPercentWindows() {
    try {
      final k32 = DynamicLibrary.open('kernel32.dll');
      final getSystemTimes = k32.lookupFunction<
          Int32 Function(Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
          int Function(Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>)>(
        'GetSystemTimes',
      );
      final idle = _heapU64();
      final kernel = _heapU64();
      final user = _heapU64();
      try {
        if (getSystemTimes(idle, kernel, user) == 0) return null;
        final nowIdle = idle.value;
        final nowKernel = kernel.value;
        final nowUser = user.value;
        final prevI = _prevIdle100ns;
        final prevK = _prevKernel100ns;
        final prevU = _prevUser100ns;
        _prevIdle100ns = nowIdle;
        _prevKernel100ns = nowKernel;
        _prevUser100ns = nowUser;
        if (prevI == null || prevK == null || prevU == null) return null;
        final idleDelta = nowIdle - prevI;
        final totalDelta = (nowKernel - prevK) + (nowUser - prevU);
        if (totalDelta <= 0) return null;
        final busy = totalDelta - idleDelta;
        return ((busy / totalDelta) * 100.0).clamp(0.0, 100.0);
      } finally {
        _free(idle);
        _free(kernel);
        _free(user);
      }
    } catch (_) {
      return null;
    }
  }

  static Pointer<Uint64> _heapU64() {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final getProcessHeap =
        k32.lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap');
    final heapAlloc = k32.lookupFunction<
        IntPtr Function(IntPtr, Uint32, IntPtr),
        int Function(int, int, int)>('HeapAlloc');
    final addr = heapAlloc(getProcessHeap(), 0x8, 8);
    if (addr == 0) throw StateError('HeapAlloc failed');
    return Pointer<Uint64>.fromAddress(addr);
  }

  static void _free(Pointer p) {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final getProcessHeap =
        k32.lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap');
    final heapFree = k32.lookupFunction<
        Int32 Function(IntPtr, Uint32, IntPtr),
        int Function(int, int, int)>('HeapFree');
    heapFree(getProcessHeap(), 0, p.address);
  }

  static Future<HardwareInfo> _detectLinux(int cores, String os) async {
    var totalMb = 8192;
    var freeMb = 4096;
    double? cpu;
    try {
      final f = File('/proc/meminfo');
      if (await f.exists()) {
        final text = await f.readAsString();
        int? kb(String key) {
          final m = RegExp('$key:\\s+(\\d+)').firstMatch(text);
          return m == null ? null : int.tryParse(m.group(1)!);
        }

        final total = kb('MemTotal');
        final avail = kb('MemAvailable') ?? kb('MemFree');
        if (total != null) totalMb = (total / 1024).round();
        if (avail != null) freeMb = (avail / 1024).round();
      }
      cpu = await _sampleLinuxCpu();
    } catch (_) {}
    return HardwareInfo(
      totalMemoryMb: totalMb,
      freeMemoryMb: freeMb.clamp(0, totalMb),
      cpuLogicalCores: cores,
      likelySsd: true,
      osLabel: os,
      cpuUsagePercent: cpu,
    );
  }

  static Future<double?> _sampleLinuxCpu() async {
    try {
      List<int>? read() {
        final line = File('/proc/stat').readAsLinesSync().firstWhere(
              (l) => l.startsWith('cpu '),
              orElse: () => '',
            );
        if (line.isEmpty) return null;
        return line
            .split(RegExp(r'\s+'))
            .skip(1)
            .take(7)
            .map(int.parse)
            .toList();
      }

      final a = read();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final b = read();
      if (a == null || b == null || a.length < 4 || b.length < 4) return null;
      final idleD = b[3] - a[3];
      final totalD = b.reduce((x, y) => x + y) - a.reduce((x, y) => x + y);
      if (totalD <= 0) return null;
      return ((1.0 - idleD / totalD) * 100).clamp(0.0, 100.0);
    } catch (_) {
      return null;
    }
  }

  static Future<HardwareInfo> _detectMac(int cores, String os) async {
    var totalMb = 8192;
    var freeMb = 4096;
    try {
      final hw = await Process.run('sysctl', ['-n', 'hw.memsize']);
      if (hw.exitCode == 0) {
        final bytes = int.tryParse((hw.stdout as String).trim()) ?? 0;
        if (bytes > 0) totalMb = (bytes / (1024 * 1024)).round();
      }
      final vm = await Process.run('vm_stat', []);
      if (vm.exitCode == 0) {
        final out = vm.stdout as String;
        final pageSize = RegExp(r'page size of (\d+)').firstMatch(out);
        final free = RegExp(r'Pages free:\s+(\d+)').firstMatch(out);
        final size = int.tryParse(pageSize?.group(1) ?? '4096') ?? 4096;
        final pages = int.tryParse(free?.group(1) ?? '0') ?? 0;
        freeMb = ((pages * size) / (1024 * 1024)).round();
      }
    } catch (_) {}
    return HardwareInfo(
      totalMemoryMb: totalMb,
      freeMemoryMb: freeMb.clamp(0, totalMb),
      cpuLogicalCores: cores,
      likelySsd: true,
      osLabel: os,
    );
  }
}
