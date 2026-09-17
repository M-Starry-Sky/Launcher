import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cache_cleaner.dart';
import 'crash_diagnoser.dart';
import 'launcher_sleep.dart';
import 'overlay_launcher.dart';
import 'perf_config.dart';
import 'record_paths.dart';

/// 跟踪当前 Java 版游戏进程：退出码、异常退出自动诊断。
/// [attach] 立即返回；退出监听在后台进行，不阻塞启动流程。
class GameSession extends ChangeNotifier {
  final PerfConfig? perf;
  final LauncherSleepController? sleep;

  Process? _process;
  int? _pid;
  DateTime? _startedAt;
  int? _lastExitCode;
  String? _lastInstanceName;
  Directory? _lastGameDir;
  CrashDiagnosis? _lastDiagnosis;
  String? _lastNote;
  bool _watching = false;
  int _attachGen = 0;

  GameSession({this.perf, this.sleep});

  bool get isRunning => _process != null;
  bool get watching => _watching;
  int? get pid => _pid;
  DateTime? get startedAt => _startedAt;
  int? get lastExitCode => _lastExitCode;
  String? get lastInstanceName => _lastInstanceName;
  CrashDiagnosis? get lastDiagnosis => _lastDiagnosis;
  String? get lastNote => _lastNote;

  Duration? get runningFor {
    final s = _startedAt;
    if (s == null || !isRunning) return null;
    return DateTime.now().difference(s);
  }

  /// 挂接已启动的游戏进程（不阻塞；不结束旧游戏进程）。
  void attach({
    required Process process,
    required String instanceName,
    required Directory gameDir,
    void Function(String line)? onLog,
    String? serverName,
    String? serverAddress,
    Map<String, String> serverNameByAddress = const {},
  }) {
    final gen = ++_attachGen;
    _process = process;
    _pid = process.pid;
    _startedAt = DateTime.now();
    _lastInstanceName = instanceName;
    _lastGameDir = gameDir;
    _lastExitCode = null;
    _lastDiagnosis = null;
    _lastNote = null;
    _watching = true;
    notifyListeners();
    onLog?.call('已跟踪游戏进程 pid=${process.pid}');

    final showHud = perf?.config.gameHudOverlay ?? true;
    if (showHud) {
      () async {
        try {
          final recordDir =
              await resolveRecordSaveDir(perf?.config.recordSaveDir ?? '');
          final ffmpeg = perf?.config.ffmpegPath.trim();
          await OverlayLauncher.start(
            gamePid: process.pid,
            gameDir: gameDir,
            serverName: serverName,
            serverAddress: serverAddress,
            serverNameByAddress: serverNameByAddress,
            recordDir: recordDir,
            ffmpegPath: (ffmpeg == null || ffmpeg.isEmpty) ? null : ffmpeg,
          );
          onLog?.call('已打开游戏悬浮窗（帧率 / 录制 / 服务器 / 世界）');
        } catch (e) {
          onLog?.call('悬浮窗启动失败: $e');
        }
      }();
    }

    process.exitCode.then((code) async {
      if (gen != _attachGen) return; // 已被更新的会话取代
      await OverlayLauncher.stop();
      await sleep?.leave(onLog: onLog);
      _lastExitCode = code;
      _process = null;
      _watching = false;
      final elapsed = _startedAt == null
          ? null
          : DateTime.now().difference(_startedAt!);
      onLog?.call(
        '游戏已退出 code=$code'
        '${elapsed != null ? " · 运行 ${elapsed.inMinutes}分${elapsed.inSeconds % 60}秒" : ""}',
      );

      if (code != 0 && _lastGameDir != null) {
        onLog?.call('非零退出，分析崩溃日志…');
        try {
          _lastDiagnosis = await CrashDiagnoser.analyze(_lastGameDir!);
          for (final f in _lastDiagnosis!.findings) {
            onLog?.call('诊断: ${f.title} — ${f.action ?? f.detail}');
          }
        } catch (e) {
          onLog?.call('诊断失败: $e');
        }
      } else if (code == 0) {
        _lastNote = '正常退出';
      }

      if (perf?.cleanCacheOnLaunch == true && _lastGameDir != null) {
        try {
          final report = await CacheCleaner.cleanGameDir(_lastGameDir!);
          onLog?.call('退出后清理: ${report.summary}');
        } catch (e) {
          onLog?.call('退出后清理失败: $e');
        }
      }
      notifyListeners();
    }).catchError((Object e) {
      if (gen != _attachGen) return;
      OverlayLauncher.stop();
      sleep?.leave(onLog: onLog);
      _process = null;
      _watching = false;
      _lastNote = '跟踪异常: $e';
      onLog?.call(_lastNote!);
      notifyListeners();
    });
  }

  void clearDiagnosis() {
    _lastDiagnosis = null;
    _lastNote = null;
    notifyListeners();
  }
}
