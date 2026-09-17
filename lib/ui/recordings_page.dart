import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/perf/launcher_recording_controller.dart';
import '../core/perf/record_paths.dart';
import '../core/perf/screen_recorder.dart';
import 'app_theme.dart';
import 'dialog_guard.dart';
import 'open_local_directory.dart';
import 'pick_record_window.dart';
import 'record_region_picker.dart';

class _RecordingItem {
  final File file;
  final String name;
  final DateTime modified;
  final int sizeBytes;

  const _RecordingItem({
    required this.file,
    required this.name,
    required this.modified,
    required this.sizeBytes,
  });
}

/// 启动器内录像：点选桌面窗口 / 全桌面 / 框选范围，并浏览已保存 mp4。
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  String _dir = '';
  List<_RecordingItem> _items = const [];
  bool _loading = true;
  String? _selected;
  String? _error;
  final _dialogGuard = DialogGuard();

  bool _systemAudio = true;
  bool _mic = false;
  int _fps = 30;
  LauncherRecordingController? _recCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _recCtrl = context.read<LauncherRecordingController>();
      _recCtrl!.addListener(_onRecChanged);
      await _loadRecPrefs();
      await _reload();
    });
  }

  @override
  void dispose() {
    _recCtrl?.removeListener(_onRecChanged);
    super.dispose();
  }

  void _onRecChanged() {
    if (mounted) setState(() {});
  }

  LauncherRecordingController get _rec =>
      _recCtrl ?? context.read<LauncherRecordingController>();

  Future<void> _loadRecPrefs() async {
    final c = context.read<AppConfig>();
    setState(() {
      _systemAudio = c.recordSystemAudio;
      _mic = c.recordMic;
      _fps = c.recordFps >= 60 ? 60 : 30;
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = context.read<AppConfig>();
      final dirPath = await resolveRecordSaveDir(config.recordSaveDir);
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final items = <_RecordingItem>[];
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final lower = e.path.toLowerCase();
        if (!lower.endsWith('.mp4')) continue;
        final name = p.basename(e.path);
        DateTime modified;
        try {
          modified = await e.lastModified();
        } catch (_) {
          modified = DateTime.fromMillisecondsSinceEpoch(0);
        }
        int size = 0;
        try {
          size = await e.length();
        } catch (_) {}
        items.add(
          _RecordingItem(
            file: e,
            name: name,
            modified: modified,
            sizeBytes: size,
          ),
        );
      }
      items.sort((a, b) => b.modified.compareTo(a.modified));
      if (!mounted) return;
      setState(() {
        _dir = dirPath;
        _items = items;
        _loading = false;
        if (_selected != null &&
            !items.any((e) => e.file.path == _selected)) {
          _selected = items.isEmpty ? null : items.first.file.path;
        } else if (_selected == null && items.isNotEmpty) {
          _selected = items.first.file.path;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  _RecordingItem? get _focused {
    final id = _selected;
    if (id == null) return null;
    for (final e in _items) {
      if (e.file.path == id) return e;
    }
    return null;
  }

  String _fmtTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _fmtElapsed(Duration? d) {
    if (d == null) return '00:00';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  Future<void> _play(_RecordingItem e) async {
    final ok = await openLocalFile(e.file.path);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开录像')),
      );
    }
  }

  Future<void> _reveal(_RecordingItem e) async {
    await openLocalDirectory(p.dirname(e.file.path));
  }

  Future<void> _delete(_RecordingItem e) async {
    if (_dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('删除录像'),
          content: Text('确定删除「${e.name}」？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await e.file.delete();
      } catch (err) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $err')),
        );
        return;
      }
    });
    if (mounted) await _reload();
  }

  Future<void> _begin(RecordTarget target, String tip) async {
    final rec = _rec;
    if (rec.busy || rec.isRecording) return;
    try {
      final label = switch (target) {
        RecordWindowTarget(:final title) => '窗口 · $title',
        RecordDesktopTarget() => '全桌面',
        RecordRegionTarget() => '框选范围',
      };
      await rec.start(
        target: target,
        label: label,
        systemAudio: _systemAudio,
        microphone: _mic,
        fps: _fps,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开始录制，右上角会出现红色录制悬浮窗')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法开始录制: $e')),
      );
    }
  }

  Future<void> _stop() async {
    await _rec.stop();
    if (mounted) await _reload();
  }

  Future<void> _recordWindow() async {
    final w = await pickCapturableWindow(context, preferGame: true);
    if (w == null || !mounted) return;
    await _begin(
      RecordWindowTarget(title: w.title, pid: w.pid),
      '正在录制窗口「${w.title}」…',
    );
  }

  Future<void> _recordDesktop() async {
    await _begin(const RecordDesktopTarget(), '正在录制全桌面…');
  }

  Future<void> _recordRegion() async {
    final rec = _rec;
    if (rec.busy || rec.isRecording) return;
    try {
      final region = await pickRecordRegion(
        context,
        restoreMinimumSize: const Size(960, 600),
      );
      if (!mounted) return;
      if (region == null) return;
      await _begin(
        RecordRegionTarget(
          x: region['x']!,
          y: region['y']!,
          width: region['width']!,
          height: region['height']!,
        ),
        '正在录制所选范围…',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('框选失败: $e')),
      );
    }
  }

  Widget _controls(ThemeData theme) {
    final rec = context.watch<LauncherRecordingController>();
    final recording = rec.isRecording;
    final busy = rec.busy;
    final recStatus = rec.status;
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  recording ? Icons.fiber_manual_record : Icons.videocam_outlined,
                  color: recording ? const Color(0xFFFF6B6B) : scheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  recording
                      ? '录制中 ${_fmtElapsed(rec.elapsed)}'
                      : '启动器录制',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (recording)
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : _stop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('停止'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              recording
                  ? '屏幕右上角有红色录制悬浮窗，可随时停止；关掉本弹窗也不会中断。'
                  : '点选桌面软件窗口，或录全桌面；也可框选局部。音轨与「设置 → 视频录制」同步。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (!recording) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('系统声'),
                    selected: _systemAudio,
                    onSelected: (v) async {
                      setState(() => _systemAudio = v);
                      await context
                          .read<AppConfig>()
                          .setBool(AppConfig.keyRecordSystemAudio, v);
                    },
                  ),
                  FilterChip(
                    label: const Text('麦克风'),
                    selected: _mic,
                    onSelected: (v) async {
                      setState(() => _mic = v);
                      await context
                          .read<AppConfig>()
                          .setBool(AppConfig.keyRecordMic, v);
                    },
                  ),
                  ...[30, 60].map(
                    (f) => ChoiceChip(
                      label: Text('$f FPS'),
                      selected: _fps == f,
                      onSelected: (_) async {
                        setState(() => _fps = f);
                        await context
                            .read<AppConfig>()
                            .set(AppConfig.keyRecordFps, f);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : _recordWindow,
                    icon: const Icon(Icons.desktop_windows_outlined, size: 18),
                    label: const Text('点选窗口'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : _recordDesktop,
                    icon: const Icon(Icons.desktop_mac_outlined, size: 18),
                    label: const Text('录全桌面'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _recordRegion,
                    icon: const Icon(Icons.crop_free, size: 18),
                    label: const Text('框选范围'),
                  ),
                ],
              ),
            ],
            if (recStatus != null) ...[
              const SizedBox(height: 8),
              Text(
                recStatus,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = _focused;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _controls(theme),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _dir.isEmpty ? '录像目录加载中…' : '目录：$_dir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    _dir.isEmpty ? null : () => openLocalDirectory(_dir),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('打开目录'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? Center(
                            child: Text(
                              '暂无录像\n上方可「点选窗口 / 录全桌面 / 框选」\n游戏 HUD 里同样可用',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 5,
                                child: ListView.separated(
                                  itemCount: _items.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (ctx, i) {
                                    final e = _items[i];
                                    final selected = e.file.path == _selected;
                                    return Material(
                                      color: selected
                                          ? theme.colorScheme.primary
                                              .withValues(alpha: 0.12)
                                          : theme.colorScheme.surface
                                              .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusMd,
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radiusMd,
                                        ),
                                        onTap: () => setState(
                                          () => _selected = e.file.path,
                                        ),
                                        onDoubleTap: () => _play(e),
                                        child: ListTile(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusMd,
                                            ),
                                          ),
                                          leading: const Icon(
                                            Icons.videocam_outlined,
                                          ),
                                          title: Text(
                                            e.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            '${_fmtTime(e.modified)} · ${_fmtSize(e.sizeBytes)}',
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 4,
                                child: focused == null
                                    ? const SizedBox.shrink()
                                    : _detail(theme, focused),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _detail(ThemeData theme, _RecordingItem e) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF101418),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  onTap: () => _play(e),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_circle_fill,
                        size: 56,
                        color: Color(0xFF7EB6FF),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '用系统播放器打开',
                        style: TextStyle(color: Color(0xFFB7C0CC)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              e.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _kv('录制时间', _fmtTime(e.modified)),
            _kv('文件大小', _fmtSize(e.sizeBytes)),
            _kv('路径', e.file.path),
            const Spacer(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _play(e),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('播放'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _reveal(e),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('打开位置'),
                ),
                OutlinedButton.icon(
                  onPressed: _dialogGuard.isLocked ? null : () => _delete(e),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    '删除',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
