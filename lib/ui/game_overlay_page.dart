import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/app_config.dart';
import '../core/perf/game_hud_monitor.dart';
import '../core/perf/player_state_reader.dart';
import '../core/perf/recording_hud_launcher.dart';
import '../core/perf/screen_recorder.dart';
import 'record_region_picker.dart';
import 'pick_record_window.dart';

/// 游戏置顶悬浮 HUD：帧率 / 服务器 / 世界 / 录制。
/// 支持「悬浮窗」与「悬浮球」两种形态。
class GameOverlayPage extends StatefulWidget {
  final GameHudMonitor monitor;
  final bool initialClickThrough;
  final String recordSaveDir;
  final String? ffmpegPath;
  final bool initialBall;

  const GameOverlayPage({
    super.key,
    required this.monitor,
    this.initialClickThrough = true,
    required this.recordSaveDir,
    this.ffmpegPath,
    this.initialBall = true,
  });

  @override
  State<GameOverlayPage> createState() => _GameOverlayPageState();
}

class _GameOverlayPageState extends State<GameOverlayPage> with WindowListener {
  /// 默认可交互；穿透需手动开启，否则按钮永远点不到。
  bool _clickThrough = false;
  bool _ballMode = true;
  int _deadStreak = 0;
  final _recorder = ScreenRecorder();
  Timer? _recTimer;
  Timer? _topmostTimer;
  String? _recStatus;
  bool _busy = false;
  bool _systemAudio = true;
  bool _mic = false;
  int _fps = 30;
  final FocusNode _hotkeyFocus = FocusNode();

  static const _panelSize = Size(300, 560);
  static const _ballSize = Size(72, 72);

  @override
  void initState() {
    super.initState();
    _clickThrough = false;
    _ballMode = widget.initialBall;
    windowManager.addListener(this);
    widget.monitor.addListener(_onSnap);
    widget.monitor.start();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRecordPrefs();
      await _applyClickThrough();
      await _applyWindowShape(ball: _ballMode);
      await _ensureVisible();
      _hotkeyFocus.requestFocus();
    });
    // 只维持置顶，绝不抢游戏焦点（放缓，降低无谓窗口调用）
    _topmostTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      windowManager.setAlwaysOnTop(true);
    });
  }

  Future<void> _loadRecordPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _systemAudio = prefs.getBool(AppConfig.keyRecordSystemAudio) ?? true;
        _mic = prefs.getBool(AppConfig.keyRecordMic) ?? false;
        _fps = prefs.getInt(AppConfig.keyRecordFps) ?? 30;
        if (_fps < 15) _fps = 15;
        if (_fps > 60) _fps = 60;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _topmostTimer?.cancel();
    _hotkeyFocus.dispose();
    windowManager.removeListener(this);
    widget.monitor.removeListener(_onSnap);
    widget.monitor.dispose();
    if (_recorder.isRecording) {
      unawaited(_recorder.stop());
    }
    unawaited(RecordingHudLauncher.stop());
    super.dispose();
  }

  @override
  void onWindowBlur() {
    // 失焦后仍保持置顶（不抢输入焦点）
    windowManager.setAlwaysOnTop(true);
  }

  @override
  void onWindowRestore() {
    _ensureVisible();
  }

  Future<void> _ensureVisible() async {
    try {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      // 不调用 focus()，避免抢走游戏键鼠
    } catch (_) {}
  }

  void _onSnap() {
    if (!mounted) return;
    final s = widget.monitor.snapshot;
    if (!s.processAlive) {
      _deadStreak++;
      // 连续 3 次判定死亡再关，避免瞬时误判
      if (_deadStreak >= 3) {
        if (_recorder.isRecording) {
          _recorder.stop();
        }
        windowManager.close();
      }
      return;
    }
    _deadStreak = 0;
    setState(() {});
  }

  Future<void> _applyWindowShape({required bool ball}) async {
    try {
      final size = ball ? _ballSize : _panelSize;
      await windowManager.setMinimumSize(
        ball ? const Size(64, 64) : const Size(240, 360),
      );
      await windowManager.setMaximumSize(
        ball ? const Size(88, 88) : const Size(380, 680),
      );
      await windowManager.setSize(size);
      try {
        await windowManager.setBackgroundColor(Colors.transparent);
      } catch (_) {}
      try {
        final display = WidgetsBinding.instance.platformDispatcher.views.first;
        final screen = display.physicalSize / display.devicePixelRatio;
        if (ball) {
          await windowManager.setPosition(
            Offset((screen.width - 72).clamp(8.0, screen.width - 8), 48),
          );
        } else {
          await windowManager.setPosition(
            Offset((screen.width - 300).clamp(8.0, screen.width - 8), 40),
          );
        }
      } catch (_) {}
      await _ensureVisible();
    } catch (_) {}
  }

  Future<void> _setBallMode(bool ball) async {
    if (_ballMode == ball) return;
    setState(() => _ballMode = ball);
    if (ball && _clickThrough) {
      _clickThrough = false;
      await _applyClickThrough();
    }
    await _applyWindowShape(ball: ball);
  }

  Future<void> _applyClickThrough() async {
    try {
      // forward:false：穿透时完全忽略鼠标，避免半穿透导致点不中按钮
      await windowManager.setIgnoreMouseEvents(_clickThrough, forward: false);
    } catch (_) {}
  }

  Future<void> _toggleClickThrough() async {
    setState(() => _clickThrough = !_clickThrough);
    await _applyClickThrough();
  }

  Future<void> _ensureInteractive() async {
    if (_clickThrough) {
      setState(() => _clickThrough = false);
      await _applyClickThrough();
    }
  }

  Future<void> _startWindowRecord() async {
    await _ensureInteractive();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _recStatus = '选择桌面窗口…';
    });
    try {
      final picked = await pickCapturableWindow(context, preferGame: true);
      if (picked == null || !mounted) {
        setState(() {
          _busy = false;
          _recStatus = null;
        });
        await _applyClickThrough();
        return;
      }
      await _beginRecord(
        RecordWindowTarget(title: picked.title, pid: picked.pid),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _recStatus = '$e';
      });
    }
  }

  Future<void> _quickToggleRecord() async {
    if (_busy) return;
    if (_recorder.isRecording) {
      await _stopRecord();
      return;
    }
    await _startWindowRecord();
  }

  Future<void> _startDesktopRecord() async {
    await _ensureInteractive();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _recStatus = '录制全桌面…';
    });
    try {
      await _beginRecord(const RecordDesktopTarget());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _recStatus = '$e';
      });
    }
  }

  Future<void> _startRegionRecord() async {
    await _ensureInteractive();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _recStatus = '框选范围…';
    });
    try {
      final region = await pickRecordRegion(
        context,
        restoreMinimumSize:
            _ballMode ? const Size(64, 64) : const Size(240, 360),
        restoreMaximumSize:
            _ballMode ? const Size(88, 88) : const Size(380, 680),
      );
      if (!mounted) return;
      if (region == null) {
        setState(() {
          _busy = false;
          _recStatus = null;
        });
        await _applyClickThrough();
        return;
      }
      await _beginRecord(
        RecordRegionTarget(
          x: region['x']!,
          y: region['y']!,
          width: region['width']!,
          height: region['height']!,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _recStatus = '$e';
      });
    }
  }

  Future<void> _beginRecord(RecordTarget target) async {
    try {
      await _loadRecordPrefs();
      final path = await _recorder.start(
        target: target,
        saveDir: widget.recordSaveDir,
        ffmpegPath: widget.ffmpegPath,
        fps: _fps,
        systemAudio: _systemAudio,
        microphone: _mic,
      );
      if (!mounted) return;
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!mounted) return;
        if (await RecordingHudLauncher.consumeStopRequest()) {
          await _stopRecord();
          return;
        }
        setState(() {});
      });
      final audioHint = _recorder.hasAudio
          ? (_mic ? '画面+系统声+麦克风' : '画面+系统声')
          : '仅画面（系统声不可用已自动降级）';
      setState(() {
        _busy = false;
        _recStatus = 'REC $_fps fps · $audioHint\n${p.basename(path)}';
        _ballMode = false;
        _clickThrough = false;
      });
      await _applyWindowShape(ball: false);
      await _applyClickThrough();
      final label = switch (target) {
        RecordWindowTarget(:final title) => '窗口 · $title',
        RecordDesktopTarget() => '全桌面',
        RecordRegionTarget() => '框选范围',
      };
      try {
        await RecordingHudLauncher.start(
          startedAt: _recorder.startedAt ?? DateTime.now(),
          outputPath: path,
          label: label,
        );
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _recStatus = '$e';
      });
    }
  }

  Future<void> _stopRecord() async {
    setState(() => _busy = true);
    _recTimer?.cancel();
    final out = await _recorder.stop();
    await RecordingHudLauncher.stop();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _recStatus = out == null ? '已停止' : '已保存 ${p.basename(out)}';
    });
  }

  String _fmtElapsed(Duration? d) {
    if (d == null) return '00:00';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.monitor.snapshot;
    const fg = Color(0xFFF2F5FA);
    const muted = Color(0xFFB7C0CC);
    const accent = Color(0xFF7EB6FF);
    final recording = _recorder.isRecording;

    final body = _ballMode
        ? _buildBall(s, recording, accent)
        : _buildPanel(s, recording, fg, muted, accent);

    return Focus(
      focusNode: _hotkeyFocus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // F9：开始/停止录制（焦点在 HUD 时）
        if (event.logicalKey == LogicalKeyboardKey.f9) {
          _quickToggleRecord();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: body,
    );
  }

  Widget _buildBall(GameHudSnapshot s, bool recording, Color accent) {
      // 窗外全透明，只画半透明小球（FittedBox 避免小窗溢出黄条）
      return Material(
        type: MaterialType.transparency,
        child: DragToMoveArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setBallMode(false),
            onLongPress: recording ? _stopRecord : _quickToggleRecord,
            child: Center(
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: recording
                      ? const Color(0xCC3A1010)
                      : const Color(0xB3181E28),
                  border: Border.all(
                    color: recording
                        ? const Color(0xFFFF4444)
                        : const Color(0x997EB6FF),
                    width: recording ? 2.5 : 1.5,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          recording
                              ? 'REC'
                              : (s.fps != null ? '${s.fps}' : '…'),
                          style: TextStyle(
                            color: recording
                                ? const Color(0xFFFF6B6B)
                                : accent,
                            fontWeight: FontWeight.w800,
                            fontSize: recording ? 14 : 20,
                            height: 1.0,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        if (recording) ...[
                          const SizedBox(height: 2),
                          Text(
                            _fmtElapsed(_recorder.elapsed),
                            style: const TextStyle(
                              color: Color(0xFFFFB4B4),
                              fontSize: 11,
                              height: 1.0,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  }

  Widget _buildPanel(
    GameHudSnapshot s,
    bool recording,
    Color fg,
    Color muted,
    Color accent,
  ) {
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x9912161C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: recording
                    ? const Color(0x88FF5C5C)
                    : const Color(0x33FFFFFF),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 240,
                maxWidth: 320,
                maxHeight: 560,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DragToMoveArea(
                      child: Row(
                        children: [
                          Icon(
                            recording
                                ? Icons.fiber_manual_record
                                : Icons.speed,
                            size: 18,
                            color:
                                recording ? const Color(0xFFFF6B6B) : accent,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '星穹 HUD',
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: '收成悬浮球',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () => _setBallMode(true),
                            icon: Icon(
                              Icons.circle_outlined,
                              size: 16,
                              color: muted,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: _clickThrough
                                ? '恢复点击（可操作按钮）'
                                : '开启穿透（不挡鼠标）',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: _toggleClickThrough,
                            icon: Icon(
                              _clickThrough
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin,
                              size: 16,
                              color: _clickThrough ? muted : accent,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: '关闭',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () async {
                              if (_recorder.isRecording) {
                                await _recorder.stop();
                              }
                              await windowManager.close();
                            },
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    _metricRow(
                      label: '帧率',
                      value: s.fps != null ? '${s.fps}' : '…',
                      unit: s.fps != null
                          ? (s.fpsSource == 'gpu'
                              ? 'FPS·呈'
                              : s.fpsSource == 'file'
                                  ? 'FPS·准'
                                  : 'FPS')
                          : '',
                      emphasize: true,
                    ),
                    _metricRow(
                      label: '内存',
                      value: s.memoryMb != null ? '${s.memoryMb}' : '—',
                      unit: s.memoryMb != null ? 'MB' : '',
                    ),
                    if (s.cpuPercent != null)
                      _metricRow(
                        label: '游戏CPU',
                        value: s.cpuPercent!.toStringAsFixed(0),
                        unit: '%',
                      ),
                    const SizedBox(height: 4),
                    Divider(
                      height: 12,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    _playerBlock(s),
                    Divider(
                      height: 12,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    if (s.multiplayer ||
                        (s.serverName != null && s.serverName!.isNotEmpty) ||
                        (s.serverAddress != null &&
                            s.serverAddress!.isNotEmpty))
                      _infoLine(
                        icon: Icons.dns_outlined,
                        title: '服务器',
                        body: s.serverName?.isNotEmpty == true
                            ? s.serverName!
                            : (s.serverAddress ?? '—'),
                        sub: s.serverName?.isNotEmpty == true &&
                                s.serverAddress != null &&
                                s.serverAddress != s.serverName
                            ? s.serverAddress
                            : null,
                      )
                    else
                      _infoLine(
                        icon: Icons.dns_outlined,
                        title: '服务器',
                        body: '未连接',
                        mutedBody: true,
                      ),
                    const SizedBox(height: 6),
                    _infoLine(
                      icon: Icons.public_outlined,
                      title: '世界存档',
                      body: (s.worldName != null && s.worldName!.isNotEmpty)
                          ? s.worldName!
                          : (s.multiplayer ? '联机中' : '未进入'),
                      mutedBody: s.worldName == null || s.worldName!.isEmpty,
                    ),
                    Divider(
                      height: 16,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    Row(
                      children: [
                        Icon(Icons.videocam_outlined,
                            size: 16, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          '录制',
                          style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        if (recording)
                          Text(
                            _fmtElapsed(_recorder.elapsed),
                            style: const TextStyle(
                              color: Color(0xFFFF8A8A),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!recording) ...[
                      Row(
                        children: [
                          Expanded(
                            child: FilterChip(
                              selected: _systemAudio,
                              label: const Text('系统声',
                                  style: TextStyle(fontSize: 11)),
                              onSelected: (v) async {
                                setState(() => _systemAudio = v);
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setBool(
                                  AppConfig.keyRecordSystemAudio,
                                  v,
                                );
                              },
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: FilterChip(
                              selected: _mic,
                              label: const Text('麦克风',
                                  style: TextStyle(fontSize: 11)),
                              onSelected: (v) async {
                                setState(() => _mic = v);
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setBool(
                                  AppConfig.keyRecordMic,
                                  v,
                                );
                              },
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (recording)
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _stopRecord,
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('停止并保存'),
                        style: FilledButton.styleFrom(
                          foregroundColor: const Color(0xFFFF8A8A),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : _startWindowRecord,
                            icon: const Icon(Icons.desktop_windows_outlined,
                                size: 18),
                            label: const Text('点选窗口录制'),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed:
                                      _busy ? null : _startDesktopRecord,
                                  child: const Text('全桌面',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed:
                                      _busy ? null : _startRegionRecord,
                                  child: const Text('框选',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    if (_recStatus != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _recStatus!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: muted.withValues(alpha: 0.95),
                          fontSize: 10,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'F9 开始/停止 · 游戏 CPU · 保存到：${widget.recordSaveDir}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted.withValues(alpha: 0.75),
                        fontSize: 9,
                      ),
                    ),
                    if (_clickThrough) ...[
                      const SizedBox(height: 6),
                      Text(
                        '穿透中 · 游戏可点穿本窗；再点图钉恢复操作',
                        style: TextStyle(
                          color: muted.withValues(alpha: 0.85),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerBlock(GameHudSnapshot s) {
    final p = s.player;
    const muted = Color(0xFFB7C0CC);
    const fg = Color(0xFFF2F5FA);
    const accent = Color(0xFF7EB6FF);

    if (p == null || !p.hasCoords) {
      return _infoLine(
        icon: Icons.my_location_outlined,
        title: '人物坐标',
        body: s.multiplayer ? '联机需 HUD 桥接模组' : '进入世界后显示（存档同步）',
        mutedBody: true,
      );
    }

    final dim = PlayerHudState.prettyDimension(p.dimension);
    final gm = PlayerHudState.prettyGameMode(p.gameMode);
    final src = p.source == 'live' ? '实时' : '存档';
    final look = <String>[
      if (p.facing != null) p.facing!,
      if (p.yaw != null) '偏航 ${p.yaw!.toStringAsFixed(0)}°',
      if (p.pitch != null) '俯仰 ${p.pitch!.toStringAsFixed(0)}°',
    ].join(' · ');
    final extras = <String>[
      if (p.biome != null && p.biome!.isNotEmpty)
        p.biome!.replaceFirst('minecraft:', ''),
      if (gm != null) gm,
      src,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.my_location_outlined, size: 14, color: accent),
            const SizedBox(width: 6),
            const Text(
              '人物',
              style: TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              dim,
              style: const TextStyle(color: accent, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          p.coordsText,
          style: const TextStyle(
            color: fg,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '方块 ${p.blockCoordsText}',
          style: const TextStyle(
            color: muted,
            fontSize: 13,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (look.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            look,
            style: TextStyle(color: muted.withValues(alpha: 0.95), fontSize: 12),
          ),
        ],
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            extras,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted.withValues(alpha: 0.9), fontSize: 12),
          ),
        ],
        if (p.health != null || p.food != null || p.xpLevel != null) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (p.health != null)
                'HP ${p.health!.toStringAsFixed(0)}'
                    '${p.maxHealth != null ? "/${p.maxHealth!.toStringAsFixed(0)}" : ""}',
              if (p.food != null) '饱食 ${p.food}',
              if (p.xpLevel != null) 'Lv ${p.xpLevel}',
            ].join('   '),
            style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _metricRow({
    required String label,
    required String value,
    String unit = '',
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFB7C0CC), fontSize: 13),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: emphasize
                  ? const Color(0xFF9BE7A0)
                  : const Color(0xFFF2F5FA),
              fontWeight: FontWeight.w700,
              fontSize: emphasize ? 28 : 17,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              unit,
              style: const TextStyle(color: Color(0xFFB7C0CC), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoLine({
    required IconData icon,
    required String title,
    required String body,
    String? sub,
    bool mutedBody = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF7EB6FF)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Color(0xFFB7C0CC), fontSize: 12),
              ),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedBody
                      ? const Color(0xFF8A93A0)
                      : const Color(0xFFF2F5FA),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.25,
                ),
              ),
              if (sub != null && sub.isNotEmpty)
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF8A93A0), fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
