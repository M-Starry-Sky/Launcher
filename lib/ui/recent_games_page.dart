import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/auth/auth_manager.dart';
import '../core/config/app_config.dart';
import '../core/game/game_instance.dart';
import '../core/game/launch_loadout.dart';
import '../core/game/launch_service.dart';
import '../core/perf/launcher_sleep.dart';
import '../core/perf/recent_play_store.dart';
import 'app_theme.dart';
import 'dialog_guard.dart';
import 'game_resources_nav.dart';
import 'open_local_directory.dart';

/// 最近游戏：点击即可进入对应服务器 / 房间 / 存档 / 实例。
class RecentGamesPage extends StatefulWidget {
  const RecentGamesPage({super.key});

  @override
  State<RecentGamesPage> createState() => _RecentGamesPageState();
}

class _RecentGamesPageState extends State<RecentGamesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<_WorldBrief> _worlds = const [];
  bool _worldsLoading = true;
  bool _launching = false;
  final _dialogGuard = DialogGuard();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWorlds());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadWorlds() async {
    setState(() => _worldsLoading = true);
    try {
      final root = context.read<InstanceStore>().sharedGameRoot();
      final saves = Directory(p.join(root.path, 'saves'));
      final out = <_WorldBrief>[];
      if (await saves.exists()) {
        await for (final e in saves.list(followLinks: false)) {
          if (e is! Directory) continue;
          final name = p.basename(e.path);
          if (name.startsWith('.')) continue;
          final level = File(p.join(e.path, 'level.dat'));
          if (!await level.exists()) continue;
          DateTime modified;
          try {
            modified = await level.lastModified();
          } catch (_) {
            modified = DateTime.fromMillisecondsSinceEpoch(0);
          }
          final lock = File(p.join(e.path, 'session.lock'));
          out.add(
            _WorldBrief(
              name: name,
              path: e.path,
              modified: modified,
              inUse: await lock.exists(),
            ),
          );
        }
      }
      out.sort((a, b) => b.modified.compareTo(a.modified));
      if (!mounted) return;
      setState(() {
        _worlds = out.take(30).toList();
        _worldsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _worlds = const [];
        _worldsLoading = false;
      });
    }
  }

  String _fmtMs(int ms) {
    if (ms <= 0) return '未知';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtDt(DateTime d) {
    if (d.millisecondsSinceEpoch <= 0) return '未知';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  Future<GameInstance?> _resolveInstance(String? instanceId) async {
    final store = context.read<InstanceStore>();
    if (instanceId != null && instanceId.isNotEmpty) {
      final hit = store.items.where((e) => e.id == instanceId);
      if (hit.isNotEmpty) {
        await store.select(instanceId);
        return hit.first;
      }
    }
    final selected = store.selected;
    if (selected != null) return selected;
    if (store.items.isNotEmpty) {
      await store.select(store.items.first.id);
      return store.selected;
    }
    return null;
  }

  Future<void> _launch({
    required String tip,
    String? instanceId,
    String? serverAddress,
    String? worldName,
  }) async {
    if (_launching) return;
    final auth = context.read<AuthManager>();
    if (!auth.isLaunchReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录微软账号，或设置离线昵称')),
      );
      return;
    }
    final instance = await _resolveInstance(instanceId);
    if (instance == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建或选择实例')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _launching = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(tip)));
    try {
      final loadout = context.read<LaunchLoadout>();
      final cfg = context.read<AppConfig>();
      if (serverAddress != null && serverAddress.trim().isNotEmpty) {
        await loadout.setIncludeServer(true);
        await loadout.setServerAddress(serverAddress.trim());
        await loadout.setIncludeWorld(false);
      } else if (worldName != null && worldName.trim().isNotEmpty) {
        await loadout.setIncludeWorld(true);
        await loadout.setWorldName(worldName.trim());
        await loadout.setIncludeServer(false);
      }
      await context.read<LaunchService>().installAndLaunch(
            instance,
            loadout: loadout,
            singleplayerWorld: (serverAddress == null || serverAddress.isEmpty)
                ? worldName?.trim()
                : null,
            autoInstall: cfg.launchAutoInstall,
          );
      if (cfg.launchMinimizeOnStart && mounted) {
        await context.read<LauncherSleepController>().enter();
      }
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('游戏已启动')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('启动失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = context.watch<RecentPlayStore>();
    final store = context.watch<InstanceStore>();
    final instances = [...store.items]
      ..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
    final played = instances.where((e) => e.lastPlayedMs > 0).take(20).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: const [
                    Tab(text: '最近启动'),
                    Tab(text: '服务器'),
                    Tab(text: '联机房间'),
                    Tab(text: '世界存档'),
                  ],
                ),
              ),
              if (_launching)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              TextButton(
                onPressed: (_launching || _dialogGuard.isLocked)
                    ? null
                    : () async {
                        await _dialogGuard.run(() async {
                          final ok = await showDialog<bool>(
                            context: context,
                            useRootNavigator: true,
                            builder: (ctx) => AlertDialog(
                              title: const Text('清空履历'),
                              content: const Text(
                                '仅清除启动/服务器/房间记录，不影响实际存档。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('清空'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) await recent.clearAll();
                          return null;
                        });
                        if (mounted) setState(() {});
                      },
                child: const Text('清空履历'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '点击条目即可进入对应游戏 / 服务器 / 房间 / 存档',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _launchTab(theme, recent, played),
                _serverTab(theme, recent),
                _roomTab(theme, recent),
                _worldTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String msg) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _launchTab(
    ThemeData theme,
    RecentPlayStore recent,
    List<GameInstance> played,
  ) {
    if (recent.launches.isEmpty && played.isEmpty) {
      return _empty('暂无启动记录\n启动一次游戏后会出现在这里');
    }
    return ListView(
      children: [
        if (recent.launches.isNotEmpty) ...[
          _section('启动履历 · 点击进入'),
          ...recent.launches.map((e) {
            final sub = <String>[
              if (e.gameVersion.isNotEmpty) e.gameVersion,
              _fmtMs(e.atMs),
              if (e.serverAddress != null && e.serverAddress!.isNotEmpty)
                e.serverName?.isNotEmpty == true
                    ? '${e.serverName} (${e.serverAddress})'
                    : e.serverAddress!,
            ].join(' · ');
            return _tile(
              icon: Icons.play_circle_outline,
              title: e.instanceName,
              subtitle: sub,
              onTap: _launching
                  ? null
                  : () => _launch(
                        tip: e.serverAddress?.isNotEmpty == true
                            ? '正在加入 ${e.serverAddress}…'
                            : '正在启动「${e.instanceName}」…',
                        instanceId: e.instanceId,
                        serverAddress: e.serverAddress,
                      ),
            );
          }),
        ],
        if (played.isNotEmpty) ...[
          _section('实例 · 点击启动'),
          ...played.map((e) {
            final loader = e.loaderType == 'fabric'
                ? (e.loaderVersion.isEmpty
                    ? 'Fabric'
                    : 'Fabric ${e.loaderVersion}')
                : '原版';
            return _tile(
              icon: Icons.folder_copy_outlined,
              title: e.name,
              subtitle: '${e.gameVersion} · $loader · ${_fmtMs(e.lastPlayedMs)}',
              onTap: _launching
                  ? null
                  : () => _launch(
                        tip: '正在启动「${e.name}」…',
                        instanceId: e.id,
                      ),
            );
          }),
        ],
      ],
    );
  }

  Widget _serverTab(ThemeData theme, RecentPlayStore recent) {
    if (recent.servers.isEmpty) {
      return _empty('暂无最近服务器\n带服务器启动或直连后会出现在这里');
    }
    return ListView(
      children: recent.servers.map((e) {
        return _tile(
          icon: Icons.dns_outlined,
          title: e.name,
          subtitle: '${e.address} · ${_fmtMs(e.atMs)} · 点击加入',
          trailing: IconButton(
            tooltip: '复制地址',
            onPressed: () => _copy(e.address),
            icon: const Icon(Icons.copy, size: 18),
          ),
          onTap: _launching
              ? null
              : () => _launch(
                    tip: '正在加入 ${e.address}…',
                    serverAddress: e.address,
                  ),
        );
      }).toList(),
    );
  }

  Widget _roomTab(ThemeData theme, RecentPlayStore recent) {
    if (recent.rooms.isEmpty) {
      return _empty('暂无联机房间记录\n开房或加入房间后会出现在这里');
    }
    return ListView(
      children: recent.rooms.map((e) {
        final role = e.role == 'host' ? '房主' : '加入';
        final kind = e.localTunnel ? '本地隧道' : '中继房间';
        final addr = e.connectAddress.isNotEmpty ? e.connectAddress : e.roomId;
        return _tile(
          icon: Icons.lan_outlined,
          title: addr,
          subtitle:
              '$role · $kind · ${e.gameType} · ${_fmtMs(e.atMs)} · 点击再次加入'
              '${e.roomId.isNotEmpty && e.roomId != addr ? ' · id ${e.roomId}' : ''}',
          trailing: IconButton(
            tooltip: '复制地址',
            onPressed: () => _copy(addr),
            icon: const Icon(Icons.copy, size: 18),
          ),
          onTap: _launching
              ? null
              : () async {
                  final cfg = context.read<AppConfig>();
                  await cfg.set(AppConfig.keyLastRoomJoin, addr);
                  if (!mounted) return;
                  context.read<GameResourcesNav>().openJoinRoom(
                        addr,
                        autoJoin: true,
                      );
                },
        );
      }).toList(),
    );
  }

  Widget _worldTab(ThemeData theme) {
    if (_worldsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_worlds.isEmpty) {
      return _empty('暂无世界存档\n进入游戏创建世界后会出现在这里');
    }
    return RefreshIndicator(
      onRefresh: _loadWorlds,
      child: ListView(
        children: [
          _section('按最近修改 · 点击进入世界'),
          ..._worlds.map((e) {
            return _tile(
              icon: e.inUse
                  ? Icons.play_circle_outline
                  : Icons.public_outlined,
              title: e.name,
              subtitle: '${_fmtDt(e.modified)}${e.inUse ? ' · 使用中' : ''}',
              trailing: IconButton(
                tooltip: '打开文件夹',
                onPressed: () => openLocalDirectory(e.path),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
              ),
              onTap: _launching
                  ? null
                  : () => _launch(
                        tip: '正在进入存档「${e.name}」…',
                        worldName: e.name,
                      ),
            );
          }),
        ],
      ),
    );
  }

  Widget _section(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          leading: Icon(icon),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: trailing ??
              (onTap == null
                  ? null
                  : Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _WorldBrief {
  final String name;
  final String path;
  final DateTime modified;
  final bool inUse;

  const _WorldBrief({
    required this.name,
    required this.path,
    required this.modified,
    required this.inUse,
  });
}
