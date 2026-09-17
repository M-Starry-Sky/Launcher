import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/perf/recording_hud_launcher.dart';

/// 解析 `--key=value`。
Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (final a in args) {
    if (!a.startsWith('--')) continue;
    final body = a.substring(2);
    final i = body.indexOf('=');
    if (i < 0) {
      out[body] = '1';
    } else {
      out[body.substring(0, i)] = body.substring(i + 1);
    }
  }
  return out;
}

/// 录制专用小悬浮窗入口。
Future<void> runRecordingHudApp(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final map = _parseArgs(args);
  final sessionDir = map['session-dir'] ?? '';
  if (sessionDir.isEmpty) {
    exit(2);
  }

  final isDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(260, 100),
      minimumSize: Size(240, 90),
      maximumSize: Size(320, 140),
      center: false,
      backgroundColor: Color(0xFF2A1010),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: '星穹录制',
      alwaysOnTop: true,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(true);
      await windowManager.setResizable(false);
      await windowManager.setBackgroundColor(const Color(0xFF2A1010));
      try {
        final display = WidgetsBinding.instance.platformDispatcher.views.first;
        final size = display.physicalSize / display.devicePixelRatio;
        await windowManager.setPosition(
          Offset((size.width - 280).clamp(16.0, size.width - 16), 32),
        );
      } catch (_) {
        await windowManager.setPosition(const Offset(48, 32));
      }
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(RecordingHudApp(sessionDir: sessionDir));
}

class RecordingHudApp extends StatelessWidget {
  final String sessionDir;

  const RecordingHudApp({super.key, required this.sessionDir});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF2A1010),
        body: _RecordingHudBody(sessionDir: sessionDir),
      ),
    );
  }
}

class _RecordingHudBody extends StatefulWidget {
  final String sessionDir;

  const _RecordingHudBody({required this.sessionDir});

  @override
  State<_RecordingHudBody> createState() => _RecordingHudBodyState();
}

class _RecordingHudBodyState extends State<_RecordingHudBody> {
  DateTime? _startedAt;
  String _label = '录制中';
  Timer? _tick;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await RecordingHudLauncher.readSession(widget.sessionDir);
    if (!mounted || s == null) return;
    final raw = s['started_at']?.toString();
    setState(() {
      _startedAt = raw == null ? DateTime.now() : DateTime.tryParse(raw);
      _label = (s['label']?.toString().trim().isNotEmpty == true)
          ? s['label'].toString()
          : '录制中';
    });
  }

  String _elapsed() {
    final s = _startedAt;
    if (s == null) return '00:00';
    final d = DateTime.now().difference(s);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$sec';
    return '$m:$sec';
  }

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    await RecordingHudLauncher.requestStopFromHud(widget.sessionDir);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) {
      try {
        await windowManager.close();
      } catch (_) {
        exit(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Material(
        color: const Color(0xE31A1010),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFF5555), width: 1.5),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              const Icon(Icons.fiber_manual_record,
                  color: Color(0xFFFF4444), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _elapsed(),
                      style: const TextStyle(
                        color: Color(0xFFFFB4B4),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _stopping ? null : _stop,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4444),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 36),
                ),
                child: Text(_stopping ? '…' : '停止'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
