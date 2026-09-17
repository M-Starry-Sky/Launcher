import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../config/app_config.dart';
import 'soft_memory_trim.dart';

/// 游戏运行期间让启动器「休眠」：最小化、降优先级、关玻璃、收缩内存。
class LauncherSleepController extends ChangeNotifier {
  static const String keyGlassBackup = 'launcher_sleep_glass_backup';

  final AppConfig config;
  bool _asleep = false;
  String? _lastNote;

  LauncherSleepController(this.config);

  bool get isAsleep => _asleep;
  String? get lastNote => _lastNote;

  /// 游戏进程已起来后调用：最小化 + 降载休眠。
  Future<void> enter({void Function(String line)? onLog}) async {
    void log(String m) {
      _lastNote = m;
      onLog?.call(m);
    }

    if (_asleep) {
      // 已休眠时仍尽量再最小化一次
      try {
        await windowManager.minimize();
      } catch (_) {}
      return;
    }

    _asleep = true;
    notifyListeners();

    // 1) 关掉液态玻璃，避免 BackdropFilter 抢 GPU/CPU
    final glass = config.glassModeRaw;
    if (glass != 'off') {
      await config.set(keyGlassBackup, glass);
      await config.set(AppConfig.keyGlassMode, 'off');
      log('休眠：已关闭液态玻璃（原档位 $glass）');
    }

    // 2) 最小化主窗
    try {
      await windowManager.minimize();
      log('休眠：已最小化启动器');
    } catch (e) {
      log('休眠：最小化失败 $e');
    }

    // 3) 启动器进程优先级降到低于正常，少抢游戏调度
    await _setSelfPriorityBelowNormal(onLog: log);

    // 4) 收缩工作集
    await SoftMemoryTrim.trimLauncher(onLog: log);

    notifyListeners();
  }

  /// 游戏退出或用户恢复窗口时唤醒。
  Future<void> leave({void Function(String line)? onLog}) async {
    if (!_asleep) return;
    void log(String m) {
      _lastNote = m;
      onLog?.call(m);
    }

    _asleep = false;

    // 还原玻璃
    final backup = config.getStringOr(keyGlassBackup, '');
    if (backup.isNotEmpty) {
      await config.set(AppConfig.keyGlassMode, backup);
      await config.set(keyGlassBackup, '');
      log('唤醒：已还原液态玻璃 ($backup)');
    }

    await _setSelfPriorityNormal(onLog: log);
    notifyListeners();
  }

  static Future<void> _setSelfPriorityBelowNormal({
    void Function(String)? onLog,
  }) async {
    if (!Platform.isWindows) return;
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'try { \$p = Get-Process -Id $pid -ErrorAction Stop; '
            '\$p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal; '
            '"ok" } catch { \$_.Exception.Message }',
      ]);
      final out = '${r.stdout}${r.stderr}'.trim();
      if (out.contains('ok')) {
        onLog?.call('休眠：启动器优先级 → BelowNormal');
      } else {
        onLog?.call('休眠：降优先级未生效 ($out)');
      }
    } catch (e) {
      onLog?.call('休眠：降优先级异常 $e');
    }
  }

  static Future<void> _setSelfPriorityNormal({
    void Function(String)? onLog,
  }) async {
    if (!Platform.isWindows) return;
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'try { \$p = Get-Process -Id $pid -ErrorAction Stop; '
            '\$p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal; '
            '"ok" } catch { \$_.Exception.Message }',
      ]);
      if ('${r.stdout}'.contains('ok')) {
        onLog?.call('唤醒：启动器优先级 → Normal');
      }
    } catch (_) {}
  }
}
