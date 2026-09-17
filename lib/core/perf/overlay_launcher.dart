import 'dart:io';

import 'package:path/path.dart' as p;

/// 拉起独立置顶悬浮窗进程（与主启动器分离，不挡游戏操作）。
class OverlayLauncher {
  static const argFlag = '--xingqiong-overlay';
  static Process? _proc;
  static int? _overlayPid;

  /// 启动悬浮窗；已有则先关掉再建。
  static Future<void> start({
    required int gamePid,
    required Directory gameDir,
    String? serverName,
    String? serverAddress,
    Map<String, String> serverNameByAddress = const {},
    bool clickThrough = false,
    String? recordDir,
    String? ffmpegPath,
    bool startAsBall = true,
  }) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return;
    }
    await stop();

    final exe = Platform.resolvedExecutable;
    final args = <String>[
      argFlag,
      '--pid=$gamePid',
      '--game-dir=${gameDir.path}',
      if (serverName != null && serverName.isNotEmpty) '--server-name=$serverName',
      if (serverAddress != null && serverAddress.isNotEmpty)
        '--server-address=$serverAddress',
      if (clickThrough) '--click-through=1' else '--click-through=0',
      if (startAsBall) '--ball=1' else '--ball=0',
      if (serverNameByAddress.isNotEmpty)
        '--server-map=${_encodeMap(serverNameByAddress)}',
      if (recordDir != null && recordDir.isNotEmpty) '--record-dir=$recordDir',
      if (ffmpegPath != null && ffmpegPath.isNotEmpty) '--ffmpeg=$ffmpegPath',
    ];

    _proc = await Process.start(
      exe,
      args,
      mode: ProcessStartMode.detached,
      workingDirectory: p.dirname(exe),
    );
    _overlayPid = _proc!.pid;
  }

  static Future<void> stop() async {
    final proc = _proc;
    final pid = _overlayPid ?? proc?.pid;
    _proc = null;
    _overlayPid = null;
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

  static String _encodeMap(Map<String, String> map) {
    return map.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join(';');
  }

  static Map<String, String> decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final out = <String, String>{};
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[Uri.decodeComponent(part.substring(0, i))] =
          Uri.decodeComponent(part.substring(i + 1));
    }
    return out;
  }
}
