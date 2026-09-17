import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/game/game_instance.dart';
import '../core/game/java_runtime.dart';
import '../core/game/mobile_launch_limits.dart';
import '../core/game/version_catalog.dart';
import '../core/game/version_installer.dart';
import '../core/perf/java_env_adapter.dart';
import '../core/platform/app_permissions.dart';
import 'app_theme.dart';
import 'dialog_guard.dart';
import 'open_local_directory.dart';
import 'pick_directory_path.dart';
import 'widgets/app_select_field.dart';

/// 版本库：已安装 / 未安装 双栏，对接 Mojang 清单与本地下载。
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key, this.embeddedInResources = false});

  final bool embeddedInResources;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

enum _VersionTab { installed, available }

class _DownloadPageState extends State<DownloadPage> {
  VersionCatalog? _catalog;
  final _search = TextEditingController();
  List<RemoteGameVersion> _versions = [];
  List<LocalGameVersion> _local = [];
  List<String> _fabricLoaders = [];
  bool _loading = true;
  bool _releaseOnly = true;
  String? _error;
  String? _gameId;
  String _loader = 'none';
  String? _fabricLoader;
  bool _busy = false;
  _VersionTab _tab = _VersionTab.installed;
  final _dialogGuard = DialogGuard();

  Map<String, LocalGameVersion> get _localById => {
        for (final e in _local) e.id: e,
      };

  Map<String, RemoteGameVersion> get _remoteById => {
        for (final e in _versions) e.id: e,
      };

  String get _query => _search.text.trim().toLowerCase();

  /// 已安装（含仅本地存在、或不完整）。
  List<LocalGameVersion> get _installed {
    final q = _query;
    final list = _local.where((e) {
      if (q.isEmpty) return true;
      final remote = _remoteById[e.id];
      return e.id.toLowerCase().contains(q) ||
          e.statusLabel.contains(q) ||
          (remote?.type.toLowerCase().contains(q) ?? false);
    }).toList();
    return list;
  }

  /// 未安装：官方清单中本地尚无目录的版本。
  List<RemoteGameVersion> get _available {
    final q = _query;
    final installedIds = _localById.keys.toSet();
    return _versions.where((v) {
      if (installedIds.contains(v.id)) return false;
      if (q.isEmpty) return true;
      return v.id.toLowerCase().contains(q) ||
          v.type.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refreshLocal() {
    if (!mounted) return;
    try {
      final store = context.read<InstanceStore>();
      final list = VersionInstaller.listLocalVersions(store.sharedGameRoot());
      setState(() => _local = list);
    } catch (_) {
      setState(() => _local = []);
    }
  }

  void _ensureSelection() {
    if (_tab == _VersionTab.installed) {
      final list = _installed;
      if (list.isEmpty) {
        _gameId = null;
        return;
      }
      if (_gameId == null || !list.any((e) => e.id == _gameId)) {
        _gameId = list.first.id;
      }
    } else {
      final list = _available;
      if (list.isEmpty) {
        _gameId = null;
        return;
      }
      if (_gameId == null || !list.any((e) => e.id == _gameId)) {
        _gameId = list.first.id;
      }
    }
  }

  Future<void> _changeBodyDir() async {
    final path = await pickDirectoryPath(context, title: '选择游戏本体下载目录');
    if (path == null || !mounted) return;
    final cfg = context.read<AppConfig>();
    await cfg.set(AppConfig.keyGameBodyDir, path);
    if (!mounted) return;
    setState(() {});
    _refreshLocal();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('本体目录已改为：$path')),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _catalog ??= VersionCatalog(config: context.read<AppConfig>());
      final list = await _catalog!.listGameVersions(releaseOnly: _releaseOnly);
      if (!mounted) return;
      _refreshLocal();
      setState(() {
        _versions = list;
        if (_local.isNotEmpty) {
          _tab = _VersionTab.installed;
        } else {
          _tab = _VersionTab.available;
        }
        _ensureSelection();
        _loading = false;
      });
      if (_gameId != null) await _loadFabric(_gameId!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _selectVersion(String id) async {
    setState(() => _gameId = id);
    await _loadFabric(id);
  }

  Future<void> _switchTab(_VersionTab tab) async {
    setState(() {
      _tab = tab;
      _ensureSelection();
    });
    if (_gameId != null) await _loadFabric(_gameId!);
  }

  Future<void> _loadFabric(String game) async {
    try {
      _catalog ??= VersionCatalog(config: context.read<AppConfig>());
      final loaders = await _catalog!.listFabricLoaders(game);
      if (!mounted) return;
      setState(() {
        _fabricLoaders = loaders;
        _fabricLoader = loaders.isNotEmpty ? loaders.first : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fabricLoaders = [];
        _fabricLoader = null;
      });
    }
  }

  Future<void> _deleteLocal(String versionId) async {
    if (_busy || _dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
      final store = context.read<InstanceStore>();
      final root = store.sharedGameRoot();
      final target = Directory('${root.path}/versions/$versionId');
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('彻底删除已安装版本'),
          content: Text(
            '将从磁盘删除：\n${target.path}\n'
            '以及同版本的 Fabric 配置目录（若有）。\n\n'
            '删除后必须重新下载才能启动；请先关闭正在运行的游戏。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('彻底删除'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return null;
      setState(() => _busy = true);
      try {
        await VersionInstaller.deleteLocalVersion(root, versionId);
        if (target.existsSync()) {
          throw StateError('删除后目录仍存在，可能被占用');
        }
        if (!mounted) return null;
        _refreshLocal();
        setState(() {
          _tab = _VersionTab.available;
          _ensureSelection();
        });
        if (_gameId != null) await _loadFabric(_gameId!);
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已从磁盘删除 $versionId；下次启动将强制重新下载'),
            action: SnackBarAction(
              label: '打开目录',
              onPressed: () => openLocalDirectory('${root.path}/versions'),
            ),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败（未完成）: $e')),
          );
          _refreshLocal();
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return null;
    });
    if (mounted) setState(() {});
  }

  /// 下载/重装游戏本体到 sharedGameRoot（versions / libraries / assets）。
  Future<bool> _downloadGameBody({
    required String versionId,
    bool force = false,
  }) async {
    final store = context.read<InstanceStore>();
    final cfg = context.read<AppConfig>();
    final root = store.sharedGameRoot();
    final logs = <String>[];
    final logNotifier = ValueNotifier<List<String>>(const []);

    void pushLog(String line) {
      logs.add(line);
      if (logs.length > 120) logs.removeAt(0);
      logNotifier.value = List<String>.from(logs);
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(force ? '重新下载 $versionId' : '下载本体 $versionId'),
          content: SizedBox(
            width: 440,
            height: 260,
            child: ValueListenableBuilder<List<String>>(
              valueListenable: logNotifier,
              builder: (_, lines, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 10),
                  Text(
                    '目录：${root.path}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(ctx)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          lines.isEmpty ? '准备中…' : lines.join('\n'),
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final installer = VersionInstaller(onProgress: pushLog, config: cfg);
    try {
      final permitted = await AppPermissions.ensureForDownload(
        context: context,
        onLog: pushLog,
      );
      if (!permitted) {
        pushLog('权限未就绪，已取消下载');
        return false;
      }
      pushLog('数据目录：${root.path}');
      pushLog(force ? '强制清空版本目录后重新下载…' : '开始下载原版本体…');
      // 先下游戏本体；Java 失败不得阻断本体下载（此前会导致“游戏下不下来”）
      await installer.installVanilla(versionId, root, force: force);
      // Fabric 仅在已选 loader 时附加；缺 loader 不阻断原版下载
      if (_loader == 'fabric') {
        final fl = _fabricLoader;
        if (fl != null && fl.isNotEmpty) {
          pushLog('安装 Fabric $fl…');
          await installer.installFabric(versionId, fl, root);
        } else {
          pushLog('未选择 Fabric Loader，仅下载原版本体');
        }
      }
      await VersionInstaller.clearReinstallStamp(root, versionId);
      pushLog('完成：${root.path}${Platform.pathSeparator}versions${Platform.pathSeparator}$versionId');

      try {
        if (MobileLaunchLimits.isMobile) {
          pushLog(MobileLaunchLimits.javaSkipDesktopJdk);
        } else {
          pushLog('准备隔离 Java（失败不影响已下好的本体）…');
          if (!mounted) return true;
          final metaJava = await VersionInstaller.peekDeclaredJavaMajor(
            root,
            versionId,
          );
          await JavaEnvAdapter(cfg, context.read<JavaRuntime>())
              .ensureIsolatedForGame(
            versionId,
            onLog: pushLog,
            javaMajorFromMeta: metaJava,
          );
        }
      } catch (e) {
        pushLog('隔离 Java 未完成: $e（可稍后在性能中心安装）');
      }
      return true;
    } catch (e) {
      pushLog('失败: $e');
      rethrow;
    } finally {
      installer.close();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        logNotifier.dispose();
      });
    }
  }

  Future<void> _downloadSelected({bool force = false}) async {
    if (_gameId == null || _busy || _dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
      if (force) {
        final ok = await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: const Text('重新下载本体'),
            content: Text(
              '将删除 $_gameId 的本地版本目录并重新下载客户端 / 依赖 / 资产。\n'
              '目录：${context.read<InstanceStore>().sharedGameRoot().path}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('重新下载'),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return null;
      }
      setState(() => _busy = true);
      try {
        final okDl = await _downloadGameBody(
          versionId: _gameId!,
          force: force,
        );
        if (!mounted) return null;
        if (!okDl) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('下载已取消（权限未就绪）')),
          );
          return null;
        }
        _refreshLocal();
        setState(() {
          _tab = _VersionTab.installed;
          _ensureSelection();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              force ? '已重新下载 $_gameId' : '本体已下载：$_gameId',
            ),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载失败: $e')),
          );
          _refreshLocal();
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return null;
    });
    if (mounted) setState(() {});
  }

  Future<void> _installAsInstance() async {
    if (_gameId == null || _busy || _dialogGuard.isLocked) return;
    if (_loader == 'fabric' &&
        (_fabricLoader == null || _fabricLoader!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择 Fabric Loader，或改用原版')),
      );
      return;
    }
    await _dialogGuard.run(() async {
      final nameCtrl = TextEditingController(text: _gameId);
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('创建实例'),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: '实例名称',
              border: OutlineInputBorder(),
              helperText: '若本机无完整本体，将先下载再创建',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('创建'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) {
        nameCtrl.dispose();
        return null;
      }
      setState(() => _busy = true);
      try {
        final instances = context.read<InstanceStore>();
        final local = _localById[_gameId!];
        final needDownload = local == null || !local.looksComplete;
        if (needDownload) {
          await _downloadGameBody(versionId: _gameId!, force: false);
        }
        if (!mounted) return null;
        await instances.create(
          name: nameCtrl.text,
          gameVersion: _gameId!,
          loaderType: _loader,
          loaderVersion: _loader == 'fabric' ? (_fabricLoader ?? '') : '',
        );
        if (!mounted) return null;
        _refreshLocal();
        setState(() {
          _tab = _VersionTab.installed;
          _ensureSelection();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              needDownload ? '实例已创建，本体已下载' : '实例已创建',
            ),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('失败: $e')));
          _refreshLocal();
        }
      } finally {
        nameCtrl.dispose();
        if (mounted) setState(() => _busy = false);
      }
      return null;
    });
    if (mounted) setState(() {});
  }

  Future<void> _applyToSelected() async {
    final store = context.read<InstanceStore>();
    final cur = store.selected;
    if (cur == null || _gameId == null) return;
    setState(() => _busy = true);
    try {
      final local = _localById[_gameId!];
      if (local == null || !local.looksComplete) {
        await _downloadGameBody(versionId: _gameId!);
      }
      if (!mounted) return;
      await store.update(cur.copyWith(
        gameVersion: _gameId!,
        loaderType: _loader,
        loaderVersion: _loader == 'fabric' ? (_fabricLoader ?? '') : '',
      ));
      if (mounted) {
        _refreshLocal();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已应用到当前实例（缺本体时已下载）')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('应用失败: $e')));
        _refreshLocal();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = context.watch<InstanceStore>();
    final bodyPath = store.sharedGameRoot().path;
    final localMap = _localById;
    final selectedLocal = _gameId == null ? null : localMap[_gameId!];
    final selected = () {
      if (_gameId == null) return null;
      final remote = _remoteById[_gameId!];
      if (remote != null) return remote;
      return RemoteGameVersion(
        id: _gameId!,
        type: selectedLocal?.looksComplete == true ? 'installed' : 'incomplete',
        releaseTime: selectedLocal?.statusLabel ?? '本地',
        url: '',
      );
    }();
    final installed = _installed;
    final available = _available;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final compact = !wide;

    final listPane = _tab == _VersionTab.installed
        ? _InstalledList(
            items: installed,
            remoteById: _remoteById,
            selectedId: _gameId,
            busy: _busy || _dialogGuard.isLocked,
            onSelect: _selectVersion,
            onDelete: _deleteLocal,
          )
        : _AvailableList(
            versions: available,
            selectedId: _gameId,
            onSelect: _selectVersion,
          );

    final panel = _InstallPanel(
      version: selected,
      local: selectedLocal,
      installed: selectedLocal != null,
      loader: _loader,
      fabricLoader: _fabricLoader,
      fabricLoaders: _fabricLoaders,
      busy: _busy || _dialogGuard.isLocked,
      instanceName: store.selected?.name,
      onLoader: (v) => setState(() => _loader = v ?? 'none'),
      onFabric: (v) => setState(() => _fabricLoader = v),
      // 不完整：补下（不清空）；已完整：禁用「下载」，只用「重新下载」
      onDownload: selectedLocal?.looksComplete == true
          ? null
          : () => _downloadSelected(force: false),
      onRedownload: selectedLocal == null
          ? null
          : () => _downloadSelected(force: true),
      onCreate: _installAsInstance,
      onApply: _applyToSelected,
      onDeleteLocal: selectedLocal == null
          ? null
          : () => _deleteLocal(selectedLocal.id),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 10 : 16, 12, compact ? 10 : 16, 16),
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
                    if (!widget.embeddedInResources)
                      Text('版本库', style: theme.textTheme.headlineSmall),
                    Text(
                      '点「下载本体」写入 jar / 库 / 资产；完整安装后可「重新下载」。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => openLocalDirectory(bodyPath),
                            child: Text(
                              '本体目录：$bodyPath',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _changeBodyDir,
                          child: const Text('更改目录'),
                        ),
                        IconButton(
                          tooltip: '打开本体目录',
                          onPressed: () => openLocalDirectory(bodyPath),
                          icon: const Icon(Icons.folder_open, size: 18),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              FilterChip(
                label: const Text('仅正式版'),
                selected: _releaseOnly,
                onSelected: _loading
                    ? null
                    : (v) {
                        setState(() => _releaseOnly = v);
                        _reload();
                      },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading
                    ? null
                    : () {
                        _refreshLocal();
                        _reload();
                      },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<_VersionTab>(
            segments: [
              ButtonSegment(
                value: _VersionTab.installed,
                icon: const Icon(Icons.download_done, size: 18),
                label: Text('已安装（${installed.length}）'),
              ),
              ButtonSegment(
                value: _VersionTab.available,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: Text('未安装（${available.length}）'),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: _loading
                ? null
                : (s) {
                    if (s.isEmpty) return;
                    _switchTab(s.first);
                  },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: _tab == _VersionTab.installed
                  ? '搜索已安装版本'
                  : '搜索未安装版本，例如 1.20.1',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) {
              setState(_ensureSelection);
            },
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _reload,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: listPane),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: panel),
                      ],
                    )
                  : Column(
                      children: [
                        SizedBox(height: 220, child: listPane),
                        const SizedBox(height: 12),
                        Expanded(child: panel),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _InstalledList extends StatelessWidget {
  final List<LocalGameVersion> items;
  final Map<String, RemoteGameVersion> remoteById;
  final String? selectedId;
  final bool busy;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

  const _InstalledList({
    required this.items,
    required this.remoteById,
    required this.selectedId,
    required this.busy,
    required this.onSelect,
    required this.onDelete,
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
      child: items.isEmpty
          ? Center(
              child: Text(
                '暂无已安装版本\n切换到「未安装」下载本体，或创建实例时自动下载',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 12,
                endIndent: 12,
                color: scheme.outlineVariant.withValues(alpha: 0.3),
              ),
              itemBuilder: (_, i) {
                final e = items[i];
                final remote = remoteById[e.id];
                final selected = e.id == selectedId;
                final ok = e.looksComplete;
                return Material(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.16)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelect(e.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            ok
                                ? Icons.check_circle_outline
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: ok ? scheme.primary : scheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.id,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  [
                                    e.statusLabel,
                                    if (remote != null) remote.type,
                                    '${(e.jarBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                                    'natives ${e.nativeLibCount}',
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '删除',
                            visualDensity: VisualDensity.compact,
                            onPressed: busy ? null : () => onDelete(e.id),
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
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

class _AvailableList extends StatelessWidget {
  final List<RemoteGameVersion> versions;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _AvailableList({
    required this.versions,
    required this.selectedId,
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
      child: versions.isEmpty
          ? Center(
              child: Text(
                '无匹配的未安装版本',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.separated(
              itemCount: versions.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 12,
                endIndent: 12,
                color: scheme.outlineVariant.withValues(alpha: 0.3),
              ),
              itemBuilder: (_, i) {
                final v = versions[i];
                final selected = v.id == selectedId;
                return Material(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.16)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelect(v.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            v.type == 'release'
                                ? Icons.cloud_outlined
                                : Icons.science_outlined,
                            size: 18,
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v.id,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${v.type} · ${v.releaseTime}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
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

class _InstallPanel extends StatelessWidget {
  final RemoteGameVersion? version;
  final LocalGameVersion? local;
  final bool installed;
  final String loader;
  final String? fabricLoader;
  final List<String> fabricLoaders;
  final bool busy;
  final String? instanceName;
  final ValueChanged<String?> onLoader;
  final ValueChanged<String?> onFabric;
  final VoidCallback? onDownload;
  final VoidCallback? onRedownload;
  final VoidCallback onCreate;
  final VoidCallback onApply;
  final VoidCallback? onDeleteLocal;

  const _InstallPanel({
    required this.version,
    required this.local,
    required this.installed,
    required this.loader,
    required this.fabricLoader,
    required this.fabricLoaders,
    required this.busy,
    required this.instanceName,
    required this.onLoader,
    required this.onFabric,
    required this.onDownload,
    required this.onRedownload,
    required this.onCreate,
    required this.onApply,
    required this.onDeleteLocal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final complete = local?.looksComplete == true;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        color: scheme.surface.withValues(alpha: 0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                installed ? '已安装版本' : '未安装版本',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                installed
                    ? (complete
                        ? '本体已就绪。可应用到实例，或重新下载。'
                        : '本地不完整，请点「下载本体」强制重下。')
                    : '下载本体后会出现在「已安装」列表。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                version?.id ?? '未选择版本',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (version != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${version!.type} · ${version!.releaseTime}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (local != null) ...[
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: (complete
                            ? scheme.primaryContainer
                            : scheme.errorContainer)
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Text(
                      '${local!.statusLabel}'
                      ' · jar ${(local!.jarBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                      ' · natives ${local!.nativeLibCount}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              AppSelectField<String>(
                value: loader,
                labelText: '加载器',
                options: const [
                  AppSelectOption(value: 'none', label: '原版'),
                  AppSelectOption(value: 'fabric', label: 'Fabric'),
                  AppSelectOption(
                      value: 'forge',
                      label: 'Forge（即将支持）',
                      enabled: false),
                  AppSelectOption(
                      value: 'neoforge',
                      label: 'NeoForge（即将支持）',
                      enabled: false),
                ],
                onChanged: onLoader,
              ),
              if (loader == 'fabric') ...[
                const SizedBox(height: 12),
                AppSelectField<String>(
                  value: fabricLoader,
                  labelText: 'Fabric Loader',
                  options: [
                    for (final e in fabricLoaders)
                      AppSelectOption(value: e, label: e),
                  ],
                  onChanged: onFabric,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                instanceName == null
                    ? '当前无选中实例'
                    : '当前实例：$instanceName',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (onDownload != null)
                FilledButton.icon(
                  onPressed: busy || version == null ? null : onDownload,
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('下载本体'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              if (onRedownload != null) ...[
                if (onDownload != null) const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: busy ? null : onRedownload,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新下载'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy || version == null || instanceName == null
                    ? null
                    : onApply,
                icon: const Icon(Icons.playlist_add_check, size: 18),
                label: const Text('应用到当前实例'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy || version == null ? null : onCreate,
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text('创建新实例'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
              if (onDeleteLocal != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: busy ? null : onDeleteLocal,
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: scheme.error),
                  label: Text(
                    '彻底删除',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
