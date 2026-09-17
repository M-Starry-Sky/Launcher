import 'dart:ffi';
import 'dart:io';

/// 游戏进程调度提权（Windows High / 其它平台尽力而为）。
class ProcessBoost {
  /// 将 MC 进程优先级提到 High，减少被系统抢占掉帧。
  static Future<bool> boostHigh(int pid, {void Function(String)? onLog}) async {
    if (pid <= 0) return false;
    try {
      if (Platform.isWindows) {
        final ok = _boostWindows(pid);
        if (ok) {
          onLog?.call('已将游戏进程优先级设为 High (pid=$pid)');
          return true;
        }
        onLog?.call('进程提权未生效');
        return false;
      }
      if (Platform.isLinux) {
        final r = await Process.run('renice', ['-n', '-5', '-p', '$pid']);
        if (r.exitCode == 0) {
          onLog?.call('已 renice 游戏进程 (pid=$pid)');
          return true;
        }
      }
    } catch (e) {
      onLog?.call('进程提权异常: $e');
    }
    return false;
  }

  static bool _boostWindows(int processId) {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final openProcess = k32.lookupFunction<
        IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)>('OpenProcess');
    final closeHandle =
        k32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'CloseHandle');
    final setPriorityClass = k32.lookupFunction<
        Int32 Function(IntPtr, Uint32),
        int Function(int, int)>('SetPriorityClass');

    // PROCESS_SET_INFORMATION | PROCESS_QUERY_LIMITED_INFORMATION
    const access = 0x0200 | 0x1000;
    const highPriorityClass = 0x00000080;
    final h = openProcess(access, 0, processId);
    if (h == 0) return false;
    try {
      return setPriorityClass(h, highPriorityClass) != 0;
    } finally {
      closeHandle(h);
    }
  }
}
