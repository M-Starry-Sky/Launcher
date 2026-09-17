import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/game/game_instance.dart';
import '../core/import/drop_import_service.dart';

/// 任意界面均可拖入：自动识别模组 / 资源包 / 光影 / 存档 / 皮肤 / 整合包并归入对应目录。
class GlobalDropImportScope extends StatefulWidget {
  final Widget child;

  const GlobalDropImportScope({super.key, required this.child});

  @override
  State<GlobalDropImportScope> createState() => _GlobalDropImportScopeState();
}

class _GlobalDropImportScopeState extends State<GlobalDropImportScope> {
  bool _dragging = false;
  bool _busy = false;

  bool get _enabled =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _handle(List<String> paths) async {
    if (_busy || paths.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _dragging = false;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('正在识别并导入…'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final store = context.read<InstanceStore>();
      final result = await DropImportService(store).importPaths(paths);
      if (!mounted) return;
      messenger?.hideCurrentSnackBar();
      final detail = result.items
          .map((e) => e.message)
          .where((m) => m.isNotEmpty)
          .take(4)
          .join('\n');
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            detail.isEmpty ? result.summary() : '${result.summary()}\n$detail',
          ),
          duration: Duration(seconds: result.failCount > 0 ? 8 : 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;

    return DropTarget(
      onDragEntered: (_) {
        if (!_busy) setState(() => _dragging = true);
      },
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        final paths = <String>[];
        for (final f in detail.files) {
          final path = f.path;
          if (path.isEmpty) continue;
          // 忽略仅路径无效的条目
          if (!FileSystemEntity.isFileSync(path) &&
              !FileSystemEntity.isDirectorySync(path)) {
            continue;
          }
          paths.add(path);
        }
        _handle(paths);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_dragging || _busy)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _dragging || _busy ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: 8,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 22,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _busy
                                      ? Icons.hourglass_top_rounded
                                      : Icons.file_download_outlined,
                                  size: 40,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _busy ? '正在自动归类保存…' : '松开以自动识别并导入',
                                  style: Theme.of(context).textTheme.titleMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '模组 · 资源包 · 光影 · 存档 · 皮肤 · 整合包\n'
                                  '将放入当前实例对应目录（皮肤进全局 skins）',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        height: 1.4,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
