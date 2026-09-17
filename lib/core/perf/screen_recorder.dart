import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'portable_ffmpeg_installer.dart';

/// 录制目标：整窗标题、屏幕矩形，或整块桌面。
sealed class RecordTarget {
  const RecordTarget();
}

class RecordWindowTarget extends RecordTarget {
  final String title;
  final int? pid;

  const RecordWindowTarget({required this.title, this.pid});
}

class RecordRegionTarget extends RecordTarget {
  final int x;
  final int y;
  final int width;
  final int height;

  const RecordRegionTarget({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// Windows gdigrab 的整桌面（所有显示器主屏虚拟桌面区域）。
class RecordDesktopTarget extends RecordTarget {
  const RecordDesktopTarget();
}

class CapturableWindow {
  final int pid;
  final String title;

  const CapturableWindow({required this.pid, required this.title});
}

/// 基于 FFmpeg gdigrab / x11grab 的屏幕录制（可带系统声 / 麦克风）。
class ScreenRecorder {
  Process? _proc;
  StreamSubscription? _errSub;
  final StringBuffer _errBuf = StringBuffer();
  String? _outputPath;
  DateTime? _startedAt;
  bool _hasAudio = false;

  bool get isRecording => _proc != null;
  bool get hasAudio => _hasAudio;
  String? get outputPath => _outputPath;
  DateTime? get startedAt => _startedAt;

  Duration? get elapsed {
    final s = _startedAt;
    if (s == null || !isRecording) return null;
    return DateTime.now().difference(s);
  }

  /// 解析 ffmpeg：自定义路径 → 绿色运行时 → PATH → 常见安装位。
  static Future<String?> resolveFfmpeg([String? configured]) async {
    final home = Platform.environment['USERPROFILE'] ?? '';
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    String? portable;
    try {
      portable = await PortableFfmpegInstaller().findInstalled();
    } catch (_) {}
    final candidates = <String>[
      if (configured != null && configured.trim().isNotEmpty) configured.trim(),
      if (portable != null) portable,
      'ffmpeg',
      if (Platform.isWindows) ...[
        r'C:\xingqiong\runtimes\ffmpeg\current\bin\ffmpeg.exe',
        r'C:\ffmpeg\bin\ffmpeg.exe',
        r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
        r'C:\Program Files (x86)\ffmpeg\bin\ffmpeg.exe',
        r'C:\ProgramData\chocolatey\bin\ffmpeg.exe',
        if (home.isNotEmpty) ...[
          p.join(home, 'scoop', 'apps', 'ffmpeg', 'current', 'bin', 'ffmpeg.exe'),
          p.join(home, 'ffmpeg', 'bin', 'ffmpeg.exe'),
        ],
        if (local.isNotEmpty)
          p.join(local, 'Microsoft', 'WinGet', 'Links', 'ffmpeg.exe'),
      ],
    ];
    for (final c in candidates) {
      try {
        if (c != 'ffmpeg' && !File(c).existsSync()) continue;
        final r = await Process.run(c, ['-version'], runInShell: false);
        if (r.exitCode == 0) return c == 'ffmpeg' ? 'ffmpeg' : c;
      } catch (_) {}
    }
    return null;
  }

  /// 本机没有 FFmpeg 时自动下载绿色包，返回可用路径。
  static Future<String> ensureFfmpeg({
    String? configured,
    void Function(String line)? onLog,
  }) async {
    final found = await resolveFfmpeg(configured);
    if (found != null) return found;
    return PortableFfmpegInstaller(onLog: onLog).ensure();
  }

  static Future<List<CapturableWindow>> listWindows() async {
    if (!Platform.isWindows) return const [];
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'''
Get-Process | Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle.Trim() -ne '' } |
  Select-Object Id, MainWindowTitle |
  ForEach-Object { '{0}|{1}' -f $_.Id, ($_.MainWindowTitle -replace '\|','/') }
''',
      ]);
      final out = <CapturableWindow>[];
      for (final line in '${r.stdout}'.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final i = t.indexOf('|');
        if (i <= 0) continue;
        final id = int.tryParse(t.substring(0, i));
        final title = t.substring(i + 1).trim();
        if (id == null || title.isEmpty) continue;
        if (title.contains('星穹 HUD') || title.contains('星穹次元')) continue;
        out.add(CapturableWindow(pid: id, title: title));
      }
      out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 优先选 Minecraft / 游戏窗口。
  static CapturableWindow? preferGameWindow(List<CapturableWindow> wins) {
    const keys = [
      'minecraft',
      'javaw',
      'lwjgl',
      'fabric',
      'forge',
      'neoforge',
      'quilt',
    ];
    for (final w in wins) {
      final t = w.title.toLowerCase();
      if (keys.any(t.contains)) return w;
    }
    return null;
  }

  static Future<String?> _firstDshowAudio(String ffmpeg) async {
    try {
      final r = await Process.run(
        ffmpeg,
        ['-hide_banner', '-list_devices', 'true', '-f', 'dshow', '-i', 'dummy'],
        runInShell: false,
      );
      final text = '${r.stderr}\n${r.stdout}';
      final m = RegExp(r'"([^"]+)"\s*\(audio\)').firstMatch(text);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  List<String> _videoArgs(RecordTarget target, int fps) {
    final args = <String>[];
    if (Platform.isWindows) {
      args.addAll(['-f', 'gdigrab', '-framerate', '$fps', '-draw_mouse', '1']);
      switch (target) {
        case RecordWindowTarget(:final title):
          // gdigrab 对标题敏感：去掉易炸字符
          final safe = title
              .replaceAll(RegExp(r'[\r\n\t]'), ' ')
              .replaceAll('"', '')
              .trim();
          if (safe.isEmpty) {
            args.addAll(['-i', 'desktop']);
          } else {
            args.addAll(['-i', 'title=$safe']);
          }
        case RecordDesktopTarget():
          args.addAll(['-i', 'desktop']);
        case RecordRegionTarget(:final x, :final y, :final width, :final height):
          final w = width.isEven ? width : width - 1;
          final h = height.isEven ? height : height - 1;
          if (w < 2 || h < 2) {
            throw StateError('录制范围太小');
          }
          args.addAll([
            '-offset_x',
            '$x',
            '-offset_y',
            '$y',
            '-video_size',
            '${w}x$h',
            '-i',
            'desktop',
          ]);
      }
    } else if (Platform.isLinux) {
      args.addAll(['-f', 'x11grab', '-framerate', '$fps']);
      switch (target) {
        case RecordWindowTarget():
          throw StateError('当前平台窗口录制请改用全桌面或范围录制');
        case RecordDesktopTarget():
          args.addAll(['-i', ':0.0']);
        case RecordRegionTarget(:final x, :final y, :final width, :final height):
          final w = width.isEven ? width : width - 1;
          final h = height.isEven ? height : height - 1;
          args.addAll(['-video_size', '${w}x$h', '-i', ':0.0+$x,$y']);
      }
    } else {
      throw StateError('当前系统暂不支持录制');
    }
    return args;
  }

  Future<String> start({
    required RecordTarget target,
    required String saveDir,
    String? ffmpegPath,
    int fps = 30,
    bool systemAudio = true,
    bool microphone = false,
  }) async {
    if (isRecording) {
      throw StateError('已在录制中');
    }
    try {
      return await _startOnce(
        target: target,
        saveDir: saveDir,
        ffmpegPath: ffmpegPath,
        fps: fps,
        systemAudio: systemAudio,
        microphone: microphone,
      );
    } catch (e) {
      // 窗口标题抓取常失败 → 自动改全桌面，避免启动器直接红字
      if (target is RecordWindowTarget) {
        return _startOnce(
          target: const RecordDesktopTarget(),
          saveDir: saveDir,
          ffmpegPath: ffmpegPath,
          fps: fps,
          systemAudio: systemAudio,
          microphone: microphone,
        );
      }
      rethrow;
    }
  }

  Future<String> _startOnce({
    required RecordTarget target,
    required String saveDir,
    String? ffmpegPath,
    int fps = 30,
    bool systemAudio = true,
    bool microphone = false,
  }) async {
    final String ff;
    try {
      ff = await ensureFfmpeg(configured: ffmpegPath);
    } catch (e) {
      throw StateError(
        '录制环境未就绪（FFmpeg）：$e。也可在「设置 → 视频录制」手动填写 ffmpeg.exe 路径。',
      );
    }

    final dir = Directory(saveDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final out = p.join(dir.path, 'xingqiong_$stamp.mp4');

    Future<String?> tryStart(List<String> args, {required bool withAudio}) async {
      _errBuf.clear();
      final proc = await Process.start(ff, args, runInShell: false);
      final sub = proc.stderr
          .transform(utf8.decoder)
          .listen(_errBuf.write, onError: (_) {});
      // 部分机器 ffmpeg 启动较慢，过短会误判失败
      final early = await Future.any<int?>([
        proc.exitCode.then((c) => c),
        Future<int?>.delayed(const Duration(milliseconds: 1600), () => null),
      ]);
      if (early != null) {
        await sub.cancel();
        try {
          proc.kill();
        } catch (_) {}
        return null;
      }
      _errSub = sub;
      _proc = proc;
      _outputPath = out;
      _startedAt = DateTime.now();
      _hasAudio = withAudio;
      unawaited(proc.exitCode.then((_) async {
        await _errSub?.cancel();
        _errSub = null;
        if (identical(_proc, proc)) {
          _proc = null;
        }
      }));
      return out;
    }

    final video = _videoArgs(target, fps);
    final encode = <String>[
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '23',
      '-pix_fmt',
      'yuv420p',
      '-movflags',
      '+faststart',
      out,
    ];

    // 先纯画面（最稳），再尝试带声；避免 wasapi 缺失直接整段失败
    final videoOnly = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      ...video,
      ...encode,
    ];
    final plain = await tryStart(videoOnly, withAudio: false);
    if (plain != null) return plain;

    if (systemAudio || microphone) {
      final withAudio = <String>['-y', '-hide_banner', '-loglevel', 'error', ...video];
      var audioCount = 0;
      if (Platform.isWindows && systemAudio) {
        // 优先 dshow 立体声混音类设备，wasapi 很多发行版未编译
        final loop = await _firstDshowAudio(ff);
        if (loop != null) {
          withAudio.addAll(['-f', 'dshow', '-i', 'audio=$loop']);
          audioCount++;
        } else {
          withAudio.addAll(['-f', 'wasapi', '-i', 'default']);
          audioCount++;
        }
      } else if (Platform.isLinux && systemAudio) {
        withAudio.addAll(['-f', 'pulse', '-i', 'default']);
        audioCount++;
      }
      if (Platform.isWindows && microphone) {
        final mic = await _firstDshowAudio(ff);
        if (mic != null && audioCount < 2) {
          withAudio.addAll(['-f', 'dshow', '-i', 'audio=$mic']);
          audioCount++;
        }
      }
      if (audioCount == 1) {
        withAudio.addAll([
          '-map',
          '0:v',
          '-map',
          '1:a?',
          '-c:a',
          'aac',
          '-b:a',
          '160k',
          ...encode,
        ]);
      } else if (audioCount >= 2) {
        withAudio.addAll([
          '-filter_complex',
          '[1:a][2:a]amix=inputs=2:duration=longest[aout]',
          '-map',
          '0:v',
          '-map',
          '[aout]',
          '-c:a',
          'aac',
          '-b:a',
          '192k',
          ...encode,
        ]);
      } else {
        withAudio.addAll(encode);
      }

      if (audioCount > 0) {
        final ok = await tryStart(withAudio, withAudio: true);
        if (ok != null) return ok;
      }
    }

    // 再试一次纯画面
    final ok = await tryStart(videoOnly, withAudio: false);
    if (ok != null) return ok;
    final err = _errBuf.toString().trim();
    final brief = err.isEmpty
        ? 'FFmpeg 启动失败'
        : err.split('\n').where((l) => l.trim().isNotEmpty).take(3).join(' · ');
    throw StateError(brief);
  }

  Future<String?> stop() async {
    final proc = _proc;
    final out = _outputPath;
    _proc = null;
    _startedAt = null;
    _hasAudio = false;
    if (proc == null) return out;

    try {
      proc.stdin.write('q');
      await proc.stdin.flush();
    } catch (_) {
      try {
        proc.kill(ProcessSignal.sigint);
      } catch (_) {
        proc.kill();
      }
    }
    try {
      await proc.exitCode.timeout(const Duration(seconds: 8));
    } catch (_) {
      try {
        proc.kill();
      } catch (_) {}
    }
    await _errSub?.cancel();
    _errSub = null;
    _outputPath = null;
    return out;
  }
}
