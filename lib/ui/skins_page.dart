import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/game/game_instance.dart';
import '../core/game/launch_loadout.dart';
import '../services/public_skin_client.dart';
import 'open_local_directory.dart';
import 'dialog_guard.dart';
import 'pick_image_path.dart';

/// 皮肤库：本地 PNG + 按玩家名拉取公开皮肤。
class SkinsPage extends StatefulWidget {
  const SkinsPage({super.key});

  @override
  State<SkinsPage> createState() => _SkinsPageState();
}

class _SkinsPageState extends State<SkinsPage> {
  List<File> _skins = [];
  bool _busy = false;
  final _dialogGuard = DialogGuard();

  Directory _skinsDir() => context.read<InstanceStore>().skinsDir();

  Future<void> _refresh() async {
    final dir = _skinsDir();
    await dir.create(recursive: true);
    if (!mounted) return;
    setState(() {
      _skins = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _importSkin() async {
    if (_busy || _dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
      final src = await pickImagePath(context);
      if (src == null || src.isEmpty || !mounted) return null;
      if (!src.toLowerCase().endsWith('.png')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择 PNG 皮肤文件')),
        );
        return null;
      }
      final file = File(src);
      if (!file.existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在')),
        );
        return null;
      }
      final dir = _skinsDir();
      await dir.create(recursive: true);
      final name = file.uri.pathSegments.last;
      final dest = File('${dir.path}${Platform.pathSeparator}$name');
      await file.copy(dest.path);
      await _refresh();
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $name')),
      );
      return null;
    });
    if (mounted) setState(() {});
  }

  Future<void> _fetchPublic() async {
    if (_busy || _dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('获取公开皮肤'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Minecraft 玩家名',
              hintText: '例如 Notch',
              border: OutlineInputBorder(),
              helperText: '来源：mc-heads / Crafatar 公开 CDN',
            ),
            onSubmitted: (_) => Navigator.pop(ctx, true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('下载'),
            ),
          ],
        ),
      );
      final name = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true || name.isEmpty || !mounted) return null;

      setState(() => _busy = true);
      try {
        final file = await PublicSkinClient().downloadByUsername(
          username: name,
          targetDir: _skinsDir(),
        );
        await _refresh();
        if (!mounted) return null;
        final loadout = context.read<LaunchLoadout>();
        await loadout.setSkinPath(file.path);
        await loadout.setIncludeSkin(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已获取并选用 ${file.uri.pathSegments.last}')),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('获取失败: $e')));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return null;
    });
    if (mounted) setState(() {});
  }

  Future<void> _openFolder() async {
    final ok = await openLocalDirectory(_skinsDir().path);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开皮肤目录')),
      );
    }
  }

  Future<void> _delete(File f) async {
    if (_busy || _dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('删除皮肤'),
          content: Text('确定删除「${f.uri.pathSegments.last}」？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除')),
          ],
        ),
      );
      if (ok != true || !mounted) return null;
      final loadout = context.read<LaunchLoadout>();
      if (loadout.skinPath == f.path) {
        await loadout.setSkinPath(null);
      }
      await f.delete();
      if (!mounted) return null;
      await _refresh();
      return null;
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final loadout = context.watch<LaunchLoadout>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dirLabel = context.watch<InstanceStore>().skinsDir().path;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本地 skins + 按玩家名拉取公开皮肤（mc-heads / Crafatar）。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '目录：$dirLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '打开皮肤文件夹',
                onPressed: _busy ? null : _openFolder,
                icon: const Icon(Icons.folder_open),
              ),
              FilledButton.tonalIcon(
                onPressed: (_busy || _dialogGuard.isLocked) ? null : _importSkin,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('导入'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed:
                    (_busy || _dialogGuard.isLocked) ? null : _fetchPublic,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.public, size: 18),
                label: Text(_busy ? '获取中' : '公开皮肤'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _skins.isEmpty
                ? const Center(
                    child: Text('暂无皮肤：导入 PNG，或点「公开皮肤」按玩家名下载'),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _skins.length,
                    itemBuilder: (context, i) {
                      final f = _skins[i];
                      final name = f.uri.pathSegments.last;
                      final selected = loadout.skinPath == f.path;
                      return Material(
                        color: selected
                            ? scheme.primaryContainer.withValues(alpha: 0.55)
                            : scheme.surface.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            await loadout.setSkinPath(f.path);
                            await loadout.setIncludeSkin(true);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('已选用 $name')),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      f,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.none,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.broken_image_outlined,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium,
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (selected)
                                      Icon(Icons.check_circle,
                                          size: 16, color: scheme.primary),
                                    IconButton(
                                      tooltip: '删除',
                                      visualDensity: VisualDensity.compact,
                                      onPressed:
                                          (_busy || _dialogGuard.isLocked)
                                              ? null
                                              : () => _delete(f),
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
