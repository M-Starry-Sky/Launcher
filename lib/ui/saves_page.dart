import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/auth/auth_manager.dart';
import '../core/config/app_config.dart';
import '../core/game/blank_world.dart';
import '../core/game/game_instance.dart';
import '../core/game/launch_loadout.dart';
import '../core/game/launch_service.dart';
import '../core/perf/launcher_sleep.dart';
import 'app_theme.dart';
import 'dialog_guard.dart';
import 'open_local_directory.dart';

class _SaveEntry {
  final String folderName;
  final Directory dir;
  final DateTime modified;
  final bool inUse;
  final int sizeBytes;

  const _SaveEntry({
    required this.folderName,
    required this.dir,
    required this.modified,
    required this.inUse,
    required this.sizeBytes,
  });
}

/// 当前实例下的世界存档管理（与共享本体隔离）。
class SavesPage extends StatefulWidget {
  const SavesPage({super.key});

  @override
  State<SavesPage> createState() => _SavesPageState();
}

class _SavesPageState extends State<SavesPage> {
  List<_SaveEntry> _items = const [];
  bool _loading = true;
  bool _entering = false;
  String? _error;
  String? _selected;
  final _dialogGuard = DialogGuard();

  Directory get _savesDir {
    final store = context.read<InstanceStore>();
    final inst = store.selected;
    final root = inst != null ? store.instanceGameDir(inst) : store.sharedGameRoot();
    return Directory(p.join(root.path, 'saves'));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saves = _savesDir;
      if (!await saves.exists()) {
        await saves.create(recursive: true);
      }
      final entries = <_SaveEntry>[];
      await for (final entity in saves.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final level = File(p.join(entity.path, 'level.dat'));
        if (!await level.exists()) continue;
        final lock = File(p.join(entity.path, 'session.lock'));
        final inUse = await lock.exists();
        DateTime modified;
        try {
          modified = await level.lastModified();
        } catch (_) {
          modified = DateTime.fromMillisecondsSinceEpoch(0);
        }
        entries.add(
          _SaveEntry(
            folderName: name,
            dir: entity,
            modified: modified,
            inUse: inUse,
            sizeBytes: await _dirSizeApprox(entity),
          ),
        );
      }
      entries.sort((a, b) => b.modified.compareTo(a.modified));
      if (!mounted) return;
      setState(() {
        _items = entries;
        _loading = false;
        if (_selected != null &&
            !entries.any((e) => e.folderName == _selected)) {
          _selected = entries.isEmpty ? null : entries.first.folderName;
        } else if (_selected == null && entries.isNotEmpty) {
          _selected = entries.first.folderName;
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

  /// 浅层估算体积，避免深扫卡死 UI。
  Future<int> _dirSizeApprox(Directory dir) async {
    var total = 0;
    try {
      await for (final e in dir.list(recursive: false, followLinks: false)) {
        if (e is File) {
          total += await e.length();
        } else if (e is Directory) {
          await for (final f
              in e.list(recursive: false, followLinks: false)) {
            if (f is File) {
              try {
                total += await f.length();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
    return total;
  }

  _SaveEntry? get _focused {
    final id = _selected;
    if (id == null) return null;
    for (final e in _items) {
      if (e.folderName == id) return e;
    }
    return null;
  }

  String _fmtTime(DateTime d) {
    if (d.millisecondsSinceEpoch <= 0) return '未知';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _openSavesRoot() async {
    final ok = await openLocalDirectory(_savesDir.path);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开存档目录')),
      );
    }
  }

  /// 标题固定在下拉框上方，避免 InputDecoration 浮动标签盖住选项。
  Widget _dialogLabeledDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              isDense: true,
              value: value,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createWorld() async {
    if (_dialogGuard.isLocked || _entering) return;
    await _dialogGuard.run(() async {
    final nameCtrl = TextEditingController(
      text: '新世界 ${DateTime.now().month}-${DateTime.now().day}',
    );
    final seedCtrl = TextEditingController();
    var gameType = 0; // 生存
    var difficulty = 2; // 普通
    var generator = WorldGeneratorType.normal;
    var hardcore = false;
    var allowCommands = true;
    var generateStructures = true;
    var bonusChest = false;
    var enterAfter = true;
    String? copyFrom;
    final templates = _items.map((e) => e.folderName).toList();

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final copying = copyFrom != null && copyFrom!.isNotEmpty;
          return AlertDialog(
            title: const Text('新建存档'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '存档名称',
                        border: OutlineInputBorder(),
                        helperText: '将创建在 saves 目录下',
                      ),
                    ),
                    if (templates.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _dialogLabeledDropdown<String?>(
                        label: '基于已有存档复制（可选）',
                        value: copyFrom,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('不复制 · 创建全新世界'),
                          ),
                          for (final t in templates)
                            DropdownMenuItem(value: t, child: Text(t)),
                        ],
                        onChanged: (v) => setDialogState(() => copyFrom = v),
                      ),
                    ],
                    if (!copying) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: seedCtrl,
                        decoration: const InputDecoration(
                          labelText: '地图种子',
                          border: OutlineInputBorder(),
                          helperText: '留空随机；可填数字或任意文字',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _dialogLabeledDropdown<WorldGeneratorType>(
                        label: '世界类型',
                        value: generator,
                        items: const [
                          DropdownMenuItem(
                            value: WorldGeneratorType.normal,
                            child: Text('默认'),
                          ),
                          DropdownMenuItem(
                            value: WorldGeneratorType.flat,
                            child: Text('超平坦'),
                          ),
                          DropdownMenuItem(
                            value: WorldGeneratorType.largeBiomes,
                            child: Text('大型生物群系'),
                          ),
                          DropdownMenuItem(
                            value: WorldGeneratorType.amplified,
                            child: Text('放大化'),
                          ),
                        ],
                        onChanged: (v) => setDialogState(
                          () => generator = v ?? WorldGeneratorType.normal,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _dialogLabeledDropdown<int>(
                        label: '游戏模式',
                        value: hardcore ? 0 : gameType,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('生存')),
                          DropdownMenuItem(value: 1, child: Text('创造')),
                          DropdownMenuItem(value: 2, child: Text('冒险')),
                          DropdownMenuItem(value: 3, child: Text('旁观')),
                        ],
                        onChanged: hardcore
                            ? null
                            : (v) =>
                                setDialogState(() => gameType = v ?? 0),
                      ),
                      const SizedBox(height: 12),
                      _dialogLabeledDropdown<int>(
                        label: '难度',
                        value: difficulty,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('和平')),
                          DropdownMenuItem(value: 1, child: Text('简单')),
                          DropdownMenuItem(value: 2, child: Text('普通')),
                          DropdownMenuItem(value: 3, child: Text('困难')),
                        ],
                        onChanged: hardcore
                            ? null
                            : (v) =>
                                setDialogState(() => difficulty = v ?? 2),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('极限模式'),
                        subtitle: const Text('硬核；死亡后无法再进该世界'),
                        value: hardcore,
                        onChanged: (v) => setDialogState(() {
                          hardcore = v;
                          if (v) {
                            gameType = 0;
                            difficulty = 3;
                          }
                        }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('允许作弊'),
                        value: allowCommands,
                        onChanged: (v) =>
                            setDialogState(() => allowCommands = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('生成建筑'),
                        subtitle: const Text('村庄、要塞等结构'),
                        value: generateStructures,
                        onChanged: (v) =>
                            setDialogState(() => generateStructures = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('奖励箱'),
                        value: bonusChest,
                        onChanged: (v) =>
                            setDialogState(() => bonusChest = v),
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('创建后立即进入'),
                      value: enterAfter,
                      onChanged: (v) =>
                          setDialogState(() => enterAfter = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
    final name = nameCtrl.text.trim();
    final seedText = seedCtrl.text;
    nameCtrl.dispose();
    seedCtrl.dispose();
    if (ok != true || !mounted) return null;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写存档名称')),
      );
      return null;
    }

    setState(() => _entering = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final Directory world;
      if (copyFrom != null && copyFrom!.isNotEmpty) {
        final src = Directory(p.join(_savesDir.path, copyFrom));
        world = await BlankWorldWriter.copyFrom(
          source: src,
          savesDir: _savesDir,
          folderName: name,
        );
      } else {
        world = await BlankWorldWriter.create(
          savesDir: _savesDir,
          folderName: name,
          gameType: gameType,
          difficulty: difficulty,
          hardcore: hardcore,
          seedText: seedText,
          generator: generator,
          allowCommands: allowCommands,
          generateStructures: generateStructures,
          bonusChest: bonusChest,
        );
      }
      final folder = p.basename(world.path);
      setState(() => _selected = folder);
      await _reload();
      messenger.showSnackBar(
        SnackBar(content: Text('已创建存档「$folder」')),
      );
      if (enterAfter && mounted) {
        final entry = _items.cast<_SaveEntry?>().firstWhere(
              (e) => e?.folderName == folder,
              orElse: () => null,
            );
        if (entry != null) {
          await _enterWorld(entry);
        } else {
          final store = context.read<InstanceStore>();
          final instance = store.selected;
          final auth = context.read<AuthManager>();
          if (instance != null && auth.isLaunchReady) {
            final loadout = context.read<LaunchLoadout>();
            final cfg = context.read<AppConfig>();
            await context.read<LaunchService>().installAndLaunch(
                  instance,
                  loadout: loadout,
                  singleplayerWorld: folder,
                  autoInstall: cfg.launchAutoInstall,
                );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('创建失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _entering = false);
    }
    return null;
    });
    if (mounted) setState(() {});
  }

  Future<void> _openWorld(_SaveEntry e) async {
    final ok = await openLocalDirectory(e.dir.path);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开存档文件夹')),
      );
    }
  }

  Future<void> _enterWorld(_SaveEntry e) async {
    final store = context.read<InstanceStore>();
    final instance = store.selected;
    if (instance == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在启动页选择实例')),
      );
      return;
    }
    final auth = context.read<AuthManager>();
    if (!auth.isLaunchReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录微软账号，或设置离线昵称')),
      );
      return;
    }
    setState(() => _entering = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final loadout = context.read<LaunchLoadout>();
      final cfg = context.read<AppConfig>();
      messenger.showSnackBar(
        SnackBar(content: Text('正在进入存档「${e.folderName}」…')),
      );
      await context.read<LaunchService>().installAndLaunch(
            instance,
            loadout: loadout,
            singleplayerWorld: e.folderName,
            autoInstall: cfg.launchAutoInstall,
          );
      if (cfg.launchMinimizeOnStart && mounted) {
        await context.read<LauncherSleepController>().enter();
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('已启动并进入「${e.folderName}」')),
        );
      }
    } catch (err) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('进入存档失败: $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _entering = false);
    }
  }

  Future<void> _rename(_SaveEntry e) async {
    if (_dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
    final ctrl = TextEditingController(text: e.folderName);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名存档'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            border: OutlineInputBorder(),
            helperText: '将重命名 saves 下的目录名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      ctrl.dispose();
      return null;
    }
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (name.isEmpty || name == e.folderName) return null;
    if (name.contains('/') ||
        name.contains('\\') ||
        name.contains(':') ||
        name == '.' ||
        name == '..') {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称含有非法字符')),
      );
      return null;
    }
    final target = Directory(p.join(_savesDir.path, name));
    if (await target.exists()) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已存在同名存档')),
      );
      return null;
    }
    try {
      await e.dir.rename(target.path);
      setState(() => _selected = name);
      await _reload();
    } catch (err) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重命名失败: $err')),
      );
    }
    return null;
    });
  }

  Future<void> _delete(_SaveEntry e) async {
    if (_dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('删除存档'),
        content: Text(
          e.inUse
              ? '「${e.folderName}」似乎正在被游戏占用。仍要删除吗？此操作不可恢复。'
              : '确定删除「${e.folderName}」？此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return null;
    try {
      await e.dir.delete(recursive: true);
      if (_selected == e.folderName) _selected = null;
      await _reload();
    } catch (err) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $err')),
      );
    }
    return null;
    });
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '目录：${_savesDir.path}',
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
                onPressed: _entering ? null : _createWorld,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建存档'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _openSavesRoot,
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '暂无存档',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _entering ? null : _createWorld,
                                  icon: const Icon(Icons.add),
                                  label: const Text('新建存档'),
                                ),
                              ],
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
                                    final selected =
                                        e.folderName == _selected;
                                    return Material(
                                      color: selected
                                          ? theme.colorScheme.primary
                                              .withValues(alpha: 0.12)
                                          : theme.colorScheme.surface
                                              .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusMd,
                                      ),
                                      child: ListTile(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            AppTheme.radiusMd,
                                          ),
                                        ),
                                        leading: Icon(
                                          e.inUse
                                              ? Icons.play_circle_outline
                                              : Icons.public_outlined,
                                          color: e.inUse
                                              ? theme.colorScheme.primary
                                              : null,
                                        ),
                                        title: Text(e.folderName),
                                        subtitle: Text(
                                          '${_fmtTime(e.modified)}'
                                          '${e.inUse ? ' · 使用中' : ''}',
                                        ),
                                        onTap: () => setState(
                                          () => _selected = e.folderName,
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

  Widget _detail(ThemeData theme, _SaveEntry e) {
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
            Text(
              e.folderName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _kv('最近修改', _fmtTime(e.modified)),
            _kv('体积（约）', _fmtSize(e.sizeBytes)),
            _kv('状态', e.inUse ? '可能正在使用' : '空闲'),
            const Spacer(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _entering ? null : () => _enterWorld(e),
                  icon: _entering
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow, size: 18),
                  label: Text(_entering ? '启动中' : '进入世界'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _openWorld(e),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('打开文件夹'),
                ),
                OutlinedButton.icon(
                  onPressed: e.inUse || _entering ? null : () => _rename(e),
                  icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                  label: const Text('重命名'),
                ),
                OutlinedButton.icon(
                  onPressed: _entering ? null : () => _delete(e),
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
          Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
