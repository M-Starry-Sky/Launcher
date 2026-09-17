import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Windows 进程轻量探测（无 PowerShell）。
class WinProcess {
  static final DynamicLibrary _k32 = DynamicLibrary.open('kernel32.dll');
  static final DynamicLibrary _psapi = DynamicLibrary.open('psapi.dll');

  static final _openProcess = _k32.lookupFunction<
      IntPtr Function(Uint32, Int32, Uint32),
      int Function(int, int, int)>('OpenProcess');
  static final _closeHandle =
      _k32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'CloseHandle');
  static final _getExitCodeProcess = _k32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)>('GetExitCodeProcess');
  static final _getProcessMemoryInfo = _psapi.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32),
      int Function(int, Pointer<Uint8>, int)>('GetProcessMemoryInfo');

  /// 进程是否仍在运行。
  static bool isAlive(int pid) {
    if (pid <= 0) return false;
    // PROCESS_QUERY_LIMITED_INFORMATION
    const access = 0x1000;
    final h = _openProcess(access, 0, pid);
    if (h == 0) return false;
    try {
      final code = _heapUint32();
      try {
        if (_getExitCodeProcess(h, code) == 0) return false;
        // STILL_ACTIVE = 259
        return code.value == 259;
      } finally {
        _free(code);
      }
    } finally {
      _closeHandle(h);
    }
  }

  static final _getProcessTimes = _k32.lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
      ),
      int Function(
        int,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
      )>('GetProcessTimes');

  /// 内核+用户态累计时间（100ns 单位）；失败返回 null。无 PowerShell。
  static int? cpuTime100ns(int pid) {
    if (pid <= 0) return null;
    const access = 0x1000;
    final h = _openProcess(access, 0, pid);
    if (h == 0) return null;
    try {
      final creation = _heapBytes(8).cast<Uint64>();
      final exit = _heapBytes(8).cast<Uint64>();
      final kernel = _heapBytes(8).cast<Uint64>();
      final user = _heapBytes(8).cast<Uint64>();
      try {
        if (_getProcessTimes(h, creation, exit, kernel, user) == 0) {
          return null;
        }
        // FILETIME 低/高位拼成 UINT64；此处按小端整读
        return kernel.value + user.value;
      } finally {
        _free(creation);
        _free(exit);
        _free(kernel);
        _free(user);
      }
    } finally {
      _closeHandle(h);
    }
  }

  /// Working set MB；失败返回 null。
  static int? workingSetMb(int pid) {
    if (pid <= 0) return null;
    const access = 0x1000;
    final h = _openProcess(access, 0, pid);
    if (h == 0) return null;
    try {
      // PROCESS_MEMORY_COUNTERS: cb + 8 size_t fields ≈ 72 on x64
      final buf = _heapBytes(80);
      try {
        buf.cast<Uint32>().value = 72;
        if (_getProcessMemoryInfo(h, buf, 72) == 0) return null;
        // WorkingSetSize is 2nd SIZE_T after DWORD cb (offset 8)
        final bd = buf.asTypedList(80).buffer.asByteData();
        final ws = bd.getUint64(8, Endian.little);
        if (ws == 0) return null;
        return (ws / (1024 * 1024)).round();
      } finally {
        _free(buf);
      }
    } finally {
      _closeHandle(h);
    }
  }

  static final _getProcessHeap =
      _k32.lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap');
  static final _heapAlloc = _k32.lookupFunction<
      IntPtr Function(IntPtr, Uint32, IntPtr),
      int Function(int, int, int)>('HeapAlloc');
  static final _heapFree = _k32.lookupFunction<
      Int32 Function(IntPtr, Uint32, IntPtr),
      int Function(int, int, int)>('HeapFree');

  static Pointer<Uint32> _heapUint32() {
    final p = _heapBytes(4).cast<Uint32>();
    p.value = 0;
    return p;
  }

  static Pointer<Uint8> _heapBytes(int n) {
    final heap = _getProcessHeap();
    final addr = _heapAlloc(heap, 0x8, n);
    if (addr == 0) throw StateError('HeapAlloc failed');
    return Pointer<Uint8>.fromAddress(addr);
  }

  static void _free(Pointer p) {
    _heapFree(_getProcessHeap(), 0, p.address);
  }
}

/// 跨平台：游戏进程是否存活。
bool gameProcessAlive(int pid) {
  if (pid <= 0) return false;
  if (Platform.isWindows) return WinProcess.isAlive(pid);
  try {
    return File('/proc/$pid').existsSync();
  } catch (_) {
    return false;
  }
}
