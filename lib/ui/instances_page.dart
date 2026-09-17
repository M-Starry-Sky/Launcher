import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/game/game_instance.dart';
import 'app_theme.dart';
import 'dialog_guard.dart';
import 'open_local_directory.dart';
import 'widgets/app_select_field.dart';

/// 实例管理：左侧列表 + 右侧详情（选用 / 编辑 / 打开目录 / 删除）。
class InstancesPage extends StatefulWidget {
  const InstancesPage({super.key});

  @override
  State<InstancesPage> createState() => _InstancesPageState();
}

class _InstancesPageState extends State<InstancesPage> {
  /// 详情面板聚焦项；为空则跟当前选用实例。
  String? _focusId;
  final _dialogGuard = DialogGuard();

  GameInstance? _focused(InstanceStore store) {
    final id = _focusId ?? store.selectedId;
    if (id == null) return store.selected;
    for (final e in store.items) {
      if (e.id == id) return e;
    }
    return store.selected;
  }

  String _loaderLabel(GameInstance e) {
    if (e.loaderType == 'fabric' && e.loaderVersion.isNotEmpty) {
      return 'Fabric ${e.loaderVersion}';
    }
    if (e.loaderType == 'fabric') return 'Fabric';
    return '原版';
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '尚未游玩';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  int _modCount(InstanceStore store, GameInstance e) {
    final dir = Directory(
        '${store.instanceDir(e).path}${Platform.pathSeparator}mods');
    if (!dir.existsSync()) return 0;
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jar'))
        .length;
  }

  Future<void> _openDir(InstanceStore store, GameInstance e) async {
    final ok = await openLocalDirectory(store.instanceDir(e).path);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开实例目录')),
      );
    }
  }

  Future<void> _create() async {
    if (_dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
      final result = await _showInstanceEditor(
        title: '新建实例',
        confirmLabel: '创建',
        initialName: '新实例',
        initialVersion: '1.20.1',
        initialLoader: 'none',
        initialLoaderVersion: '',
      );
      if (result == null || !mounted) return null;
      final created = await context.read<InstanceStore>().create(
            name: result.name,
            gameVersion: result.version,
            loaderType: result.loader,
            loaderVersion:
                result.loader == 'fabric' ? result.loaderVersion : '',
          );
      setState(() => _focusId = created.id);
      return null;
    });
    if (mounted) setState(() {});
  }

  Future<void> _edit(GameInstance e) async {
    if (_dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
      final result = await _showInstanceEditor(
        title: '编辑实例',
        confirmLabel: '保存',
        initialName: e.name,
        initialVersion: e.gameVersion,
        initialLoader: e.loaderType == 'fabric' ? 'fabric' : 'none',
        initialLoaderVersion: e.loaderVersion,
      );
      if (result == null || !mounted) return null;
      await context.read<InstanceStore>().update(
            e.copyWith(
              name: result.name,
              gameVersion: result.version,
              loaderType: result.loader,
              loaderVersion:
                  result.loader == 'fabric' ? result.loaderVersion : '',
            ),
          );
      return null;
    });
    if (mounted) setState(() {});
  }

  Future<({String name, String version, String loader, String loaderVersion})?>
      _showInstanceEditor({
    required String title,
    required String confirmLabel,
    required String initialName,
    required String initialVersion,
    required String initialLoader,
    required String initialLoaderVersion,
  }) async {
    final name = TextEditingController(text: initialName);
    final ver = TextEditingController(text: initialVersion);
    final loaderVer = TextEditingController(text: initialLoaderVersion);
    var loader = initialLoader;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ver,
                      decoration: const InputDecoration(
                        labelText: '游戏版本',
                        hintText: '例如 1.20.1',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppSelectField<String>(
                      value: loader,
                      labelText: '加载器',
                      options: const [
                        AppSelectOption(value: 'none', label: '原版'),
                        AppSelectOption(value: 'fabric', label: 'Fabric'),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => loader = v);
                      },
                    ),
                    if (loader == 'fabric') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: loaderVer,
                        decoration: const InputDecoration(
                          labelText: 'Fabric Loader 版本',
                          hintText: '可稍后在下载页安装',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        );
      },
    );

    final out = ok == true
        ? (
            name: name.text.trim().isEmpty ? '新实例' : name.text.trim(),
            version: ver.text.trim().isEmpty ? '1.20.1' : ver.text.trim(),
            loader: loader,
            loaderVersion: loaderVer.text.trim(),
          )
        : null;
    name.dispose();
    ver.dispose();
    loaderVer.dispose();
    return out;
  }

  Future<void> _delete(InstanceStore store, GameInstance e) async {
    if (_dialogGuard.isLocked) return;
    if (store.items.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个实例')),
      );
      return;
    }
    await _dialogGuard.run(() async {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('删除实例'),
          content: Text(
            '确定删除「${e.name}」？\n'
            '将同时删除磁盘目录：\n${store.instanceDir(e).path}',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return null;
      try {
        await store.remove(e.id, deleteFiles: true);
        if (_focusId == e.id) {
          setState(() => _focusId = store.selectedId);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除实例「${e.name}」及本地目录')),
          );
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$err')));
        }
      }
      return null;
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InstanceStore>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final focus = _focused(store);
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '每个实例独立版本与模组目录。点选可设为启动目标。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                '共 ${store.items.length} 个',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _dialogGuard.isLocked ? null : _create,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                      SizedBox(
                        width: 300,
                        child: _InstanceList(
                          store: store,
                          focusId: focus?.id,
                          loaderLabel: _loaderLabel,
                          onFocus: (id) => setState(() => _focusId = id),
                          onSelect: (id) async {
                            await store.select(id);
                            setState(() => _focusId = id);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: focus == null
                            ? _EmptyDetail(scheme: scheme)
                            : _InstanceDetail(
                                store: store,
                                instance: focus,
                                loaderLabel: _loaderLabel(focus),
                                lastPlayed: _formatTime(focus.lastPlayedMs),
                                modCount: _modCount(store, focus),
                                isLaunchTarget: focus.id == store.selectedId,
                                onUse: () => store.select(focus.id),
                                onEdit: () => _edit(focus),
                                onOpen: () => _openDir(store, focus),
                                onDelete: () => _delete(store, focus),
                                onCopyPath: () async {
                                  final path = store.instanceDir(focus).path;
                                  await Clipboard.setData(
                                      ClipboardData(text: path));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('已复制实例路径')),
                                    );
                                  }
                                },
                              ),
                      ),
                    ],
                  )
                : focus == null
                    ? _EmptyDetail(scheme: scheme)
                    : Column(
                        children: [
                          SizedBox(
                            height: 180,
                            child: _InstanceList(
                              store: store,
                              focusId: focus.id,
                              loaderLabel: _loaderLabel,
                              onFocus: (id) => setState(() => _focusId = id),
                              onSelect: (id) async {
                                await store.select(id);
                                setState(() => _focusId = id);
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _InstanceDetail(
                              store: store,
                              instance: focus,
                              loaderLabel: _loaderLabel(focus),
                              lastPlayed: _formatTime(focus.lastPlayedMs),
                              modCount: _modCount(store, focus),
                              isLaunchTarget: focus.id == store.selectedId,
                              onUse: () => store.select(focus.id),
                              onEdit: () => _edit(focus),
                              onOpen: () => _openDir(store, focus),
                              onDelete: () => _delete(store, focus),
                              onCopyPath: () async {
                                final path = store.instanceDir(focus).path;
                                await Clipboard.setData(
                                    ClipboardData(text: path));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('已复制实例路径')),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  final ColorScheme scheme;

  const _EmptyDetail({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        color: scheme.surface.withValues(alpha: 0.22),
      ),
      child: Center(
        child: Text(
          '还没有实例',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _InstanceList extends StatelessWidget {
  final InstanceStore store;
  final String? focusId;
  final String Function(GameInstance) loaderLabel;
  final ValueChanged<String> onFocus;
  final ValueChanged<String> onSelect;

  const _InstanceList({
    required this.store,
    required this.focusId,
    required this.loaderLabel,
    required this.onFocus,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        color: scheme.surface.withValues(alpha: 0.22),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: store.items.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 12,
          endIndent: 12,
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
        itemBuilder: (_, i) {
          final e = store.items[i];
          final focused = e.id == focusId;
          final launch = e.id == store.selectedId;
          return Material(
            color: focused
                ? scheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            child: InkWell(
              onTap: () => onFocus(e.id),
              onDoubleTap: () => onSelect(e.id),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSm),
                        color: launch
                            ? scheme.primary.withValues(alpha: 0.28)
                            : scheme.surfaceContainerHighest
                                .withValues(alpha: 0.55),
                      ),
                      child: Icon(
                        launch
                            ? Icons.play_arrow_rounded
                            : Icons.folder_outlined,
                        color: launch
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${e.gameVersion} · ${loaderLabel(e)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (launch)
                      Icon(Icons.check_circle,
                          size: 18, color: scheme.primary),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InstanceDetail extends StatelessWidget {
  final InstanceStore store;
  final GameInstance instance;
  final String loaderLabel;
  final String lastPlayed;
  final int modCount;
  final bool isLaunchTarget;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onCopyPath;

  const _InstanceDetail({
    required this.store,
    required this.instance,
    required this.loaderLabel,
    required this.lastPlayed,
    required this.modCount,
    required this.isLaunchTarget,
    required this.onUse,
    required this.onEdit,
    required this.onOpen,
    required this.onDelete,
    required this.onCopyPath,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = store.instanceDir(instance).path;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        color: scheme.surface.withValues(alpha: 0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    color: scheme.primary.withValues(alpha: 0.2),
                  ),
                  child: Icon(
                    Icons.sports_esports_outlined,
                    color: scheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instance.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MetaChip(
                            icon: Icons.tag,
                            label: instance.gameVersion,
                          ),
                          _MetaChip(
                            icon: Icons.extension_outlined,
                            label: loaderLabel,
                          ),
                          _MetaChip(
                            icon: Icons.inventory_2_outlined,
                            label: '$modCount 个模组',
                          ),
                          if (isLaunchTarget)
                            const _MetaChip(
                              icon: Icons.check_circle_outline,
                              label: '当前启动',
                              emphasis: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _InfoRow(label: '上次游玩', value: lastPlayed),
            const SizedBox(height: 8),
            _InfoRow(
              label: '创建时间',
              value: instance.createdAtMs <= 0
                  ? '—'
                  : () {
                      final d = DateTime.fromMillisecondsSinceEpoch(
                          instance.createdAtMs);
                      String two(int n) => n.toString().padLeft(2, '0');
                      return '${d.year}-${two(d.month)}-${two(d.day)}';
                    }(),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: '目录',
              value: path,
              trailing: IconButton(
                tooltip: '复制路径',
                visualDensity: VisualDensity.compact,
                onPressed: onCopyPath,
                icon: const Icon(Icons.copy_outlined, size: 18),
              ),
            ),
            const Spacer(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isLaunchTarget ? null : onUse,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(isLaunchTarget ? '已设为启动' : '设为启动'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('打开目录'),
                ),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: scheme.error),
                  label: Text('删除',
                      style: TextStyle(color: scheme.error)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '提示：双击左侧列表也可直接设为启动目标。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasis;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        color: emphasis
            ? scheme.primary.withValues(alpha: 0.22)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(
          color: emphasis
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: emphasis ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: emphasis ? scheme.primary : scheme.onSurface,
                  fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
