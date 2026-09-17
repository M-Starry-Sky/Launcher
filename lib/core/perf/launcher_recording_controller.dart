import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import 'record_paths.dart';
import 'recording_hud_launcher.dart';
import 'screen_recorder.dart';

/// 启动器级录制会话：与「录像」弹窗生命周期解耦，关掉弹窗也不停录、不杀悬浮窗。
class LauncherRecordingController extends ChangeNotifier {
  final AppConfig config;
  final ScreenRecorder _recorder = ScreenRecorder();
  Timer? _poll;
  bool _busy = false;
  String? _status;
  String? _lastError;

  LauncherRecordingController(this.config);

  ScreenRecorder get recorder => _recorder;
  bool get busy => _busy;
  bool get isRecording => _recorder.isRecording;
  String? get status => _status;
  String? get lastError => _lastError;
  Duration? get elapsed => _recorder.elapsed;

  Future<void> start({
    required RecordTarget target,
    required String label,
    bool systemAudio = true,
    bool microphone = false,
    int fps = 30,
  }) async {
    if (_busy || _recorder.isRecording) return;
    _busy = true;
    _lastError = null;
    _status = '正在启动录制…';
    notifyListeners();
    try {
      final dir = await resolveRecordSaveDir(config.recordSaveDir);
      _status = '正在检查录制环境…';
      notifyListeners();
      final ff = await ScreenRecorder.ensureFfmpeg(
        configured:
            config.ffmpegPath.trim().isEmpty ? null : config.ffmpegPath,
        onLog: (line) {
          _status = line;
          notifyListeners();
        },
      );
      if (config.ffmpegPath.trim().isEmpty && ff != 'ffmpeg') {
        await config.set(AppConfig.keyFfmpegPath, ff);
      }
      _status = '正在启动录制…';
      notifyListeners();
      final path = await _recorder.start(
        target: target,
        saveDir: dir,
        ffmpegPath: ff,
        fps: fps,
        systemAudio: systemAudio,
        microphone: microphone,
      );
      final audio = _recorder.hasAudio ? '（含音频）' : '（仅画面）';
      _status = '录制中$audio → ${p.basename(path)}';
      _busy = false;
      notifyListeners();
      _ensurePoll();
      await RecordingHudLauncher.start(
        startedAt: _recorder.startedAt ?? DateTime.now(),
        outputPath: path,
        label: label,
      );
    } catch (e) {
      _busy = false;
      _lastError = '$e';
      _status = '$e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_busy && !_recorder.isRecording) return;
    _busy = true;
    notifyListeners();
    _poll?.cancel();
    _poll = null;
    final out = await _recorder.stop();
    await RecordingHudLauncher.stop();
    _busy = false;
    _status = out == null ? '已停止' : '已保存 ${p.basename(out)}';
    notifyListeners();
  }

  void _ensurePoll() {
    _poll?.cancel();
    if (!_recorder.isRecording) return;
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (await RecordingHudLauncher.consumeStopRequest()) {
        await stop();
        return;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    // 不在 dispose 里停录：Controller 随 App 存活；进程退出时系统回收 ffmpeg
    super.dispose();
  }
}
