import 'dart:ffi';
import 'dart:io';

/// 仅收缩「启动器自身」工作集，不杀其它进程、不碰系统缓存。
/// Windows 走 psapi EmptyWorkingSet（无 PowerShell，毫秒级）。
class SoftMemoryTrim {
  static Future<bool> trimLauncher({void Function(String)? onLog}) async {
    if (!Platform.isWindows) {
      onLog?.call('当前平台不支持工作集收缩');
      return false;
    }
    final selfPid = pid;
    try {
      final ok = _trimWindows(selfPid);
      if (ok) {
        onLog?.call('已收缩启动器工作集 (pid=$selfPid)');
        return true;
      }
      onLog?.call('工作集收缩未生效');
      return false;
    } catch (e) {
      onLog?.call('工作集收缩异常: $e');
      return false;
    }
  }

  static bool _trimWindows(int processId) {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final psapi = DynamicLibrary.open('psapi.dll');

    final openProcess = k32.lookupFunction<
        IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)>('OpenProcess');
    final closeHandle =
        k32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'CloseHandle');
    final emptyWorkingSet =
        psapi.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'EmptyWorkingSet');

    // PROCESS_QUERY_INFORMATION | PROCESS_SET_QUOTA
    const access = 0x0400 | 0x0100;
    final h = openProcess(access, 0, processId);
    if (h == 0) return false;
    try {
      return emptyWorkingSet(h) != 0;
    } finally {
      closeHandle(h);
    }
  }
}
