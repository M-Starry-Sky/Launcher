import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 录制专用悬浮窗进程（与主窗口分离，随时可停录）。
class RecordingHudLauncher {
  static const argFlag = '--xingqiong-record-hud';
  static Process? _proc;
  static int? _hudPid;

  static Future<Directory> sessionDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'record_hud'));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _sessionFile() async =>
      File(p.join((await sessionDir()).path, 'session.json'));

  static Future<File> _stopFile() async =>
      File(p.join((await sessionDir()).path, 'stop.flag'));

  /// 写入会话并拉起悬浮窗。
  static Future<void> start({
    required DateTime startedAt,
    required String outputPath,
    String label = '录制中',
  }) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return;
    }
    await stop();
    final stopFlag = await _stopFile();
    if (await stopFlag.exists()) {
      try {
        await stopFlag.delete();
      } catch (_) {}
    }
    final dir = await sessionDir();
    final session = File(p.join(dir.path, 'session.json'));
    await session.writeAsString(
      jsonEncode({
        'started_at': startedAt.toIso8601String(),
        'output_path': outputPath,
        'label': label,
      }),
      flush: true,
    );

    final exe = Platform.resolvedExecutable;
    final args = <String>[
      argFlag,
      '--session-dir=${dir.path}',
    ];
    final proc = await Process.start(
      exe,
      args,
      workingDirectory: p.dirname(exe),
      mode: ProcessStartMode.normal,
    );
    _proc = proc;
    _hudPid = proc.pid;
    // 忽略子进程 stdout/stderr，避免管道阻塞
    unawaited(proc.stdout.drain<void>());
    unawaited(proc.stderr.drain<void>());
    unawaited(proc.exitCode.then((code) {
      if (identical(_proc, proc)) {
        _proc = null;
        _hudPid = null;
      }
    }));
  }

  /// 主进程轮询：悬浮窗点了「停止」。
  static Future<bool> consumeStopRequest() async {
    final stop = await _stopFile();
    if (!await stop.exists()) return false;
    try {
      await stop.delete();
    } catch (_) {}
    return true;
  }

  static Future<void> requestStopFromHud(String sessionDirPath) async {
    final stop = File(p.join(sessionDirPath, 'stop.flag'));
    await stop.parent.create(recursive: true);
    await stop.writeAsString('1', flush: true);
  }

  static Future<Map<String, dynamic>?> readSession(String sessionDirPath) async {
    final f = File(p.join(sessionDirPath, 'session.json'));
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString());
      if (j is Map<String, dynamic>) return j;
      if (j is Map) return j.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  static Future<void> stop() async {
    final proc = _proc;
    final pid = _hudPid ?? proc?.pid;
    _proc = null;
    _hudPid = null;
    if (pid != null && pid > 0) {
      try {
        Process.killPid(pid);
      } catch (_) {}
    }
    if (proc != null) {
      try {
        proc.kill();
      } catch (_) {}
    }
  }
}
