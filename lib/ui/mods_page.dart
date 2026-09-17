import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/game/game_instance.dart';
import '../core/perf/perf_config.dart';
import '../core/perf/perf_mods_installer.dart';
import '../core/perf/bedrock_render_presets.dart';
import '../core/bedrock/bedrock_install.dart';
import '../core/bedrock/bedrock_launcher.dart';
import '../services/pack_service.dart';
import 'open_local_directory.dart';
import 'dialog_guard.dart';
import 'pick_directory_path.dart';
import 'pick_file_path.dart';
import 'widgets/modrinth_browser.dart';

/// 本地模组列表 + Modrinth 公开资源搜索下载。
class ModsPage extends StatefulWidget {
  const ModsPage({super.key});

  @override
  State<ModsPage> createState() => _ModsPageState();
}

class _ModsPageState extends State<ModsPage> {
  List<File> _files = [];
  Directory? _viewDir;
  String? _boundInstanceId;
  bool _busy = false;
  String? _msg;
  final _dialogGuard = DialogGuard();
  final Set<String> _collapsedGroups = {};

  Directory _instanceModsDir(InstanceStore store, GameInstance inst) =>
      Directory(p.join(store.instanceDir(inst).path, 'mods'));

  String _groupOf(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('xingqiong') || lower.startsWith('xingqiong')) {
      return '星穹优化';
    }
    const perf = [
      'sodium',
      'lithium',
      'fabric-api',
      'cloth-config',
      'entityculling',
      'immediatelyfast',
      'ferrite',
      'modernfix',
      'krypton',
      'indium',
      'moreculling',
      'embeddium',
      'rubidium',
    ];
    for (final k in perf) {
      if (lower.contains(k)) return '性能加速';
    }
    // 按名称首段分组，便于折叠
    final base = filename.replaceAll(RegExp(r'\.jar$', caseSensitive: false), '');
    final token = base.split(RegExp(r'[-_]')).firstWhere(
          (e) => e.trim().isNotEmpty,
          orElse: () => '其他',
        );
    if (token.length <= 1) return '其他';
    return token;
  }

  Map<String, List<File>> _groupedFiles() {
    final map = <String, List<File>>{};
    for (final f in _files) {
      final g = _groupOf(p.basename(f.path));
      (map[g] ??= []).add(f);
    }
    final keys = map.keys.toList()
      ..sort((a, b) {
        int rank(String k) {
          if (k == '星穹优化') return 0;
          if (k == '性能加速') return 1;
          if (k == '其他') return 9;
          return 5;
        }
        final c = rank(a).compareTo(rank(b));
        if (c != 0) return c;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return {for (final k in keys) k: map[k]!};
  }

  Future<void> _exportModsZip() async {
    if (_files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可导出的模组')),
      );
      return;
    }
    final dest = await pickSaveFilePath(
      context,
      title: '导出模组 zip',
      filter: 'ZIP (*.zip)|*.zip',
      defaultName: 'mods_export.zip',
    );
    if (dest == null) return;
    final path = dest.toLowerCase().endsWith('.zip') ? dest : '$dest.zip';
    setState(() {
      _busy = true;
      _msg = '正在导出模组…';
    });
    try {
      final archive = Archive();
      for (final f in _files) {
        final bytes = await f.readAsBytes();
        final name = p.basename(f.path);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw StateError('打包失败');
      final out = File(path);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(encoded, flush: true);
      if (!mounted) return;
      setState(() => _msg = '已导出 ${p.basename(path)}（${_files.length} 个模组）');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 $path')),
      );
    } catch (e) {
      if (mounted) setState(() => _msg = '失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSingleMod(File f) async {
    final name = p.basename(f.path);
    final dest = await pickSaveFilePath(
      context,
      title: '导出模组',
      filter: 'JAR (*.jar)|*.jar|ZIP (*.zip)|*.zip',
      defaultName: name,
    );
    if (dest == null) return;
    try {
      await f.copy(dest.toLowerCase().endsWith('.jar') ||
              dest.toLowerCase().endsWith('.zip')
          ? dest
          : '$dest.jar');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 $name')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _refresh({Directory? dir}) async {
    final store = context.read<InstanceStore>();
    final inst = store.selected;
    final target = dir ??
        _viewDir ??
        (inst == null ? null : _instanceModsDir(store, inst));
    if (target == null) {
      if (!mounted) return;
      setState(() {
        _files = [];
        _viewDir = null;
      });
      return;
    }
    await target.create(recursive: true);
    if (!mounted) return;
    setState(() {
      _viewDir = target;
      _files = target
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.jar'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
    });
  }

  void _syncInstanceDir(InstanceStore store) {
    final inst = store.selected;
    final id = inst?.id;
    if (id == _boundInstanceId) return;
    _boundInstanceId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (inst == null) {
        setState(() {
          _files = [];
          _viewDir = null;
          _msg = null;
        });
        return;
      }
      _refresh(dir: _instanceModsDir(store, inst));
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncInstanceDir(context.read<InstanceStore>());
    });
  }

  Future<void> _openFolder() async {
    final dir = _viewDir;
    if (dir == null) return;
    final ok = await openLocalDirectory(dir.path);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开模组目录')),
      );
    }
  }

  String _loaderFor(GameInstance inst) {
    final t = inst.loaderType.trim().toLowerCase();
    if (t.isEmpty || t == 'none' || t == 'vanilla') return 'fabric';
    return t;
  }

  Future<void> _importLocal() async {
    if (_busy || _dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
    final store = context.read<InstanceStore>();
    final inst = store.selected;
    if (inst == null) {
      setState(() => _msg = '请先在启动页选择实例');
      return null;
    }
    final paths = await pickFilePaths(
      context,
      title: '选择本地模组 JAR',
      filter: '模组 JAR (*.jar)|*.jar|所有文件 (*.*)|*.*',
    );
    if (!mounted || paths.isEmpty) return null;

    final targetDir = _viewDir ?? _instanceModsDir(store, inst);
    await targetDir.create(recursive: true);
    setState(() {
      _busy = true;
      _msg = '正在导入 ${paths.length} 个模组…';
    });
    var ok = 0;
    try {
      for (final path in paths) {
        final src = File(path);
        if (!await src.exists()) continue;
        final name = p.basename(path);
        final dest = File(p.join(targetDir.path, name));
        await src.copy(dest.path);
        ok++;
      }
      if (!mounted) return null;
      setState(() => _msg = ok == 0 ? '未导入任何文件' : '已导入 $ok 个本地模组');
      await _refresh(dir: targetDir);
    } catch (e) {
      if (mounted) setState(() => _msg = '失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
    });
  }

  Future<void> _browseModrinth() async {
    if (_busy || _dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
    final store = context.read<InstanceStore>();
    final inst = store.selected;
    if (inst == null) {
      setState(() => _msg = '请先在启动页选择实例（用于匹配游戏版本）');
      return null;
    }

    final pick = await showModrinthBrowser(
      context,
      gameVersion: inst.gameVersion,
      loader: _loaderFor(inst),
      projectType: 'mod',
      title: '从 Modrinth 下载模组',
    );
    if (pick == null || !mounted) return null;

    final defaultDir = _viewDir ?? _instanceModsDir(store, inst);
    Directory targetDir = defaultDir;
    final useOther = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text('下载 ${pick.hit.title}'),
        content: Text(
          '将保存到实例模组目录：\n${defaultDir.path}\n\n'
          '版本：${pick.version.label}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('另选目录'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('下载到实例'),
          ),
        ],
      ),
    );
    if (!mounted) return null;
    if (useOther == null) return null;
    if (useOther == false) {
      final path = await pickDirectoryPath(context, title: '选择模组下载目录');
      if (!mounted) return null;
      if (path == null || path.isEmpty) {
        setState(() => _msg = '已取消：未选择下载目录');
        return null;
      }
      targetDir = Directory(p.normalize(path));
    }

    setState(() {
      _busy = true;
      _msg = '正在下载 ${pick.hit.slug}…';
    });
    try {
      final client = ModrinthClient();
      final file = await client.downloadVersion(
        versionId: pick.version.id,
        targetDir: targetDir,
      );
      if (!mounted) return null;
      setState(() => _msg = '已下载 ${file.uri.pathSegments.last}');
      await _refresh(dir: targetDir);
    } catch (e) {
      if (mounted) setState(() => _msg = '失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
    });
  }

  Future<void> _delete(File f) async {
    if (_busy || _dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模组'),
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
    if (ok != true) return null;
    await f.delete();
    if (!mounted) return null;
    await _refresh();
    return null;
    });
  }

  /// 星穹优化：模组资源里展示为「一个模组包」；Java 装一体化 jar，基岩写渲染预设。
  Widget _xingqiongPerfPackCard(
    BuildContext context,
    InstanceStore store,
    GameInstance? inst,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(Icons.speed, color: scheme.primary, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '星穹优化（一体化模组包）',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Java：帧率桥接 + 小地图自标 + API + 加速依赖；基岩：写入流畅渲染预设。两边都在此安装。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : () => _installXingqiongPerf(store, inst),
              child: const Text('安装'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _installXingqiongPerf(
    InstanceStore store,
    GameInstance? inst,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '正在安装星穹优化…';
    });
    try {
      var didSomething = false;

      // 基岩：写入渲染预设（与 Java 包同一入口）
      final bedrock = await BedrockInstall.detect();
      if (bedrock != null) {
        final settings = context.read<PerfConfig>().bedrock;
        if (!mounted) return;
        await BedrockLauncher(onLog: (l) {
          if (mounted) setState(() => _msg = l);
        }).applyRenderSettings(bedrock, settings);
        didSomething = true;
        if (mounted) {
          setState(() => _msg = '基岩：已写入「${settings.preset.label}」');
        }
      }

      // Java：装一体化 xingqiong-perf + 加速依赖
      if (inst != null) {
        var target = inst;
        if (target.loaderType == 'none') {
          if (mounted) {
            setState(() =>
                _msg = 'Java 原版需先挂 Fabric：请到「性能」页一键安装星穹优化');
          }
        } else {
          final modsDir = _instanceModsDir(store, target);
          final result = await PerfModsInstaller(
            onLog: (l) {
              if (mounted) setState(() => _msg = l);
            },
          ).install(
            gameVersion: target.gameVersion,
            loaderType: target.loaderType,
            modsDir: modsDir,
          );
          didSomething = true;
          if (mounted) {
            setState(() {
              _msg =
                  '星穹优化已装入实例 · 写入 ${result.ok} · 已有 ${result.skip} · 失败 ${result.fail}';
            });
            await _refresh(dir: modsDir);
          }
        }
      }

      if (!didSomething && mounted) {
        setState(() => _msg = '未检测到基岩版，且未选择 Fabric/Forge 实例');
      }
    } catch (e) {
      if (mounted) setState(() => _msg = '失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InstanceStore>();
    _syncInstanceDir(store);

    final inst = store.selected;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dirLabel = _viewDir?.path ?? '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inst == null
                          ? '请先在启动页选择实例，再管理或从 Modrinth 下载模组。'
                          : '当前实例「${inst.name}」· ${inst.gameVersion} · 对接 Modrinth 公开库',
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
                onPressed: _busy ? null : () => _refresh(),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '打开模组文件夹',
                onPressed: _busy || _viewDir == null ? null : _openFolder,
                icon: const Icon(Icons.folder_open),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: _busy || _files.isEmpty ? null : _exportModsZip,
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('导出'),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: _busy || inst == null ? null : _importLocal,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('本地导入'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _busy ? null : _browseModrinth,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.public, size: 18),
                label: Text(_busy ? '下载中' : 'Modrinth'),
              ),
            ],
          ),
          if (_msg != null) ...[
            const SizedBox(height: 8),
            Text(
              _msg!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _msg!.startsWith('失败') || _msg!.startsWith('已取消')
                    ? scheme.error
                    : scheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _xingqiongPerfPackCard(context, store, inst, theme, scheme),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
                color: scheme.surface.withValues(alpha: 0.28),
              ),
              child: _files.isEmpty
                  ? Center(
                      child: Text(
                        inst == null
                            ? '暂无模组'
                            : '尚无模组，可「本地导入」JAR 或从 Modrinth 下载',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : _buildFoldedModList(theme, scheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoldedModList(ThemeData theme, ColorScheme scheme) {
    final groups = _groupedFiles();
    return ListView(
      children: [
        for (final entry in groups.entries)
          ExpansionTile(
            initiallyExpanded: !_collapsedGroups.contains(entry.key),
            onExpansionChanged: (open) {
              setState(() {
                if (open) {
                  _collapsedGroups.remove(entry.key);
                } else {
                  _collapsedGroups.add(entry.key);
                }
              });
            },
            leading: Icon(
              entry.key == '星穹优化'
                  ? Icons.speed
                  : entry.key == '性能加速'
                      ? Icons.bolt_outlined
                      : Icons.extension_outlined,
              color: scheme.primary,
              size: 20,
            ),
            title: Text(
              '${entry.key}（${entry.value.length}）',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            children: [
              for (final f in entry.value) _modTile(f, scheme),
            ],
          ),
      ],
    );
  }

  Widget _modTile(File f, ColorScheme scheme) {
    final name = p.basename(f.path);
    final kb = f.lengthSync() / 1024;
    return ListTile(
      dense: true,
      leading: Icon(Icons.extension_outlined, color: scheme.primary, size: 20),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        kb >= 1024
            ? '${(kb / 1024).toStringAsFixed(1)} MB'
            : '${kb.toStringAsFixed(1)} KB',
      ),
      trailing: Wrap(
        children: [
          IconButton(
            tooltip: '导出',
            icon: const Icon(Icons.ios_share, size: 18),
            onPressed: _busy ? null : () => _exportSingleMod(f),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: _busy ? null : () => _delete(f),
          ),
        ],
      ),
    );
  }
}
