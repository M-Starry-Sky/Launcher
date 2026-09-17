import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/auth/auth_guard.dart';
import '../core/auth/auth_manager.dart';
import '../core/auth/token_store.dart';
import '../core/bedrock/bedrock_install.dart';
import '../core/config/app_config.dart';
import '../core/download/accelerated_downloader.dart';
import '../core/frp/frp_manager.dart';
import '../core/game/compat_multiplayer.dart';
import '../core/game/game_instance.dart';
import '../core/game/game_launcher.dart';
import '../core/game/java_runtime.dart';
import '../core/game/launch_loadout.dart';
import '../core/game/launch_service.dart';
import '../core/game/version_installer.dart';
import '../core/perf/java_env_adapter.dart';
import '../core/perf/recent_play_store.dart';
import '../models/pack.dart';
import '../models/room.dart';
import '../services/pack_service.dart';
import '../services/room_service.dart';
import 'app_theme.dart';
import 'compat_multiplayer_guard.dart';
import 'game_resources_nav.dart';
import 'widgets/app_select_field.dart';

enum _RoomTab { host, join }

enum _HostConnectMode { lan, frp, publicIp, platform }

_HostConnectMode _hostConnectModeFromId(String raw) => switch (raw) {
      'lan' => _HostConnectMode.lan,
      'public' => _HostConnectMode.publicIp,
      'platform' => _HostConnectMode.platform,
      _ => _HostConnectMode.frp,
    };

extension on _HostConnectMode {
  String get id => switch (this) {
        _HostConnectMode.lan => 'lan',
        _HostConnectMode.frp => 'frp',
        _HostConnectMode.publicIp => 'public',
        _HostConnectMode.platform => 'platform',
      };

  String get label => switch (this) {
        _HostConnectMode.lan => '局域网',
        _HostConnectMode.frp => 'OpenFRP/自配',
        _HostConnectMode.publicIp => '公网映射',
        _HostConnectMode.platform => '平台一键',
      };
}

/// 联机：一键内外穿透开房 / 加入房间 / 隧道与整合包同步。
class RoomPage extends StatefulWidget {
  const RoomPage({super.key});

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  _RoomTab _tab = _RoomTab.host;
  _HostConnectMode _hostMode = _HostConnectMode.frp;
  List<PackSummary>? _packs;
  String? _selectedPackId;
  bool _java = true;
  bool _compat = false;
  RoomJoinInfo? _joined;
  bool _isHost = false;
  bool _tunnelRunning = false;
  List<String> _lanAddresses = const [];
  final List<String> _log = [];
  bool _busy = false;
  /// 防止开房/加入自动进服与「启动游戏」并发，拉起两个客户端。
  bool _launchInFlight = false;
  final _joinCode = TextEditingController();
  final _publicHost = TextEditingController();
  int _navTicket = -1;
  bool _pendingJoinScheduled = false;

  @override
  void initState() {
    super.initState();
    _loadPacks();
    _refreshLan();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cfg = context.read<AppConfig>();
      final last = cfg.lastRoomJoin.trim();
      if (last.isNotEmpty && _joinCode.text.trim().isEmpty) {
        _joinCode.text = last;
      }
      _publicHost.text = cfg.roomPublicHost;
      setState(() {
        _compat = cfg.roomCompatMode;
        _hostMode = _hostConnectModeFromId(cfg.roomConnectMode);
        if (last.isNotEmpty) _tab = _RoomTab.join;
      });
      _applyPendingJoin();
    });
  }

  @override
  void dispose() {
    _joinCode.dispose();
    _publicHost.dispose();
    super.dispose();
  }

  void _applyPendingJoin() {
    if (!mounted) return;
    final pending = context.read<GameResourcesNav>().takePendingJoin();
    final code = pending.code?.trim();
    if (code == null || code.isEmpty) return;
    setState(() {
      _joinCode.text = code;
      _tab = _RoomTab.join;
    });
    // ignore: unawaited_futures
    context.read<AppConfig>().set(AppConfig.keyLastRoomJoin, code);
    if (pending.autoJoin &&
        !_pendingJoinScheduled &&
        !_busy &&
        !_launchInFlight) {
      _pendingJoinScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingJoinScheduled = false;
        if (mounted) _joinRoom();
      });
    }
  }

  Future<void> _loadPacks() async {
    try {
      final packs = await context.read<PackService>().list();
      if (!mounted) return;
        setState(() {
          _packs = packs;
        _selectedPackId ??= packs.isNotEmpty ? packs.first.packId : null;
        });
    } catch (e) {
      _appendLog('整合包列表加载失败: $e');
    }
  }

  Future<void> _refreshLan() async {
    final port = context.read<AppConfig>().localServerPort;
    final addrs = <String>['127.0.0.1:$port'];
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final a in iface.addresses) {
          if (!a.isLoopback) addrs.add('${a.address}:$port');
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _lanAddresses = addrs);
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() {
      _log.add(line);
      if (_log.length > 200) _log.removeAt(0);
    });
  }

  Future<void> _onCompatChanged(bool enabled) async {
    if (!enabled) {
      setState(() => _compat = false);
      await context.read<AppConfig>().setBool(AppConfig.keyRoomCompatMode, false);
      _appendLog('已关闭兼容联机');
      return;
    }
    final ok = await CompatMultiplayerGuard.confirmEnable(
      context,
      context.read<AppConfig>(),
    );
    if (!mounted) return;
    setState(() => _compat = ok);
    if (ok) {
      _appendLog('已开启兼容联机：请仅用于私人好友房间，并遵守游戏服务条款');
    }
  }

  /// 一键打洞前免责：平台不提供中继流量，用户自配 FRP。
  Future<bool> _confirmFrpDisclaimer() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('联机隧道免责说明'),
          content: SingleChildScrollView(
            child: Text(
              '1. 微软正版可用平台一键打洞，也可在「设置 → 联机隧道」自配，不强求。\n'
              '2. 离线账号必须自配 FRP，不能使用平台节点。\n'
              '3. 中继请使用自有或合法第三方（如 OpenFRP），费用与合规自负。\n'
              '4. 请仅用于私人好友联机，遵守当地法律与游戏服务条款。',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('我已了解，继续'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _oneClickHost() async {
    if (_busy || _launchInFlight) return;
    setState(() => _busy = true);
    try {
      await _refreshLan();
      final frpMgr = context.read<FrpManager>();
      if (frpMgr.isRunning) {
        await frpMgr.stop();
        _appendLog('已停止旧隧道');
      }

      final appConfig = context.read<AppConfig>();
      final gameType = _java ? 'java' : 'bedrock';
      final localPort = appConfig.localServerPort;
      final compat = _compat;
      await appConfig.setBool(AppConfig.keyRoomCompatMode, compat);
      await appConfig.set(AppConfig.keyRoomConnectMode, _hostMode.id);

      late RoomJoinInfo join;
      late FrpConnection frpConn;
      late final String roomTag;
      var needFrpc = false;

      final auth = context.read<AuthManager>();
      final isMicrosoft = auth.source == AuthSource.microsoft;

      switch (_hostMode) {
        case _HostConnectMode.lan:
          final addr = _lanAddresses.firstWhere(
            (a) => !a.startsWith('127.'),
            orElse: () => _lanAddresses.isNotEmpty
                ? _lanAddresses.first
                : '127.0.0.1:$localPort',
          );
          roomTag = 'lan${DateTime.now().millisecondsSinceEpoch % 100000000}';
          frpConn = const FrpConnection(
            node: 'lan',
            host: '',
            controlPort: 0,
            remotePort: 0,
            token: '',
          );
          join = RoomJoinInfo.localHost(
            roomId: roomTag,
            gameType: gameType,
            connectAddress: addr,
            packId: _selectedPackId,
            compatMode: compat,
            frp: frpConn,
          );
          _appendLog('局域网模式：好友（含 HMCL/PCL）填 $addr');

        case _HostConnectMode.publicIp:
          final host = _publicHost.text.trim();
          if (host.isEmpty) {
            throw StateError('请填写公网 IP / 域名（路由器已端口映射到本机 $localPort）');
          }
          await appConfig.set(AppConfig.keyRoomPublicHost, host);
          final addr = host.contains(':') ? host : '$host:$localPort';
          roomTag = 'pub${DateTime.now().millisecondsSinceEpoch % 100000000}';
          frpConn = const FrpConnection(
            node: 'public',
            host: '',
            controlPort: 0,
            remotePort: 0,
            token: '',
          );
          join = RoomJoinInfo.localHost(
            roomId: roomTag,
            gameType: gameType,
            connectAddress: addr,
            packId: _selectedPackId,
            compatMode: compat,
            frp: frpConn,
          );
          _appendLog('公网映射：分享 $addr 给任意启动器加入');

        case _HostConnectMode.frp:
          final accepted = await _confirmFrpDisclaimer();
          if (!accepted) {
            throw StateError('已取消：须先确认联机隧道免责说明');
          }
          if (!(frpMgr.hasLocalTunnelPrefer && appConfig.frpRemotePort > 0)) {
            final hint = frpMgr.localTunnelMissingHint;
            throw StateError(
              hint.isNotEmpty
                  ? '$hint\n也可改用「局域网」或「公网映射」。'
                  : '请到「设置 → 联机隧道」配置 OpenFRP / 自建 frp。',
            );
          }
          final serverAddr = appConfig.frpServerAddr.trim();
          final serverPort = appConfig.frpServerPort;
          final token = appConfig.frpToken.trim();
          final remotePort = appConfig.frpRemotePort;
          roomTag = 'local${DateTime.now().millisecondsSinceEpoch % 100000000}';
          final publicAddr = '$serverAddr:$remotePort';
          _appendLog('OpenFRP/自配：$serverAddr:$serverPort → 外网 $publicAddr');
          frpConn = FrpConnection(
            node: 'local',
            host: serverAddr,
            controlPort: serverPort,
            remotePort: remotePort,
            token: token,
            user: appConfig.frpUser.trim().isEmpty
                ? null
                : appConfig.frpUser.trim(),
            tlsEnable: appConfig.frpTlsEnable,
            tlsServerName: appConfig.frpTlsServerName.trim().isEmpty
                ? null
                : appConfig.frpTlsServerName.trim(),
            useEncryption: appConfig.frpUseEncryption,
            useCompression: appConfig.frpUseCompression,
            protocol: appConfig.frpProtocol,
          );
          join = RoomJoinInfo.localHost(
            roomId: roomTag,
            gameType: gameType,
            connectAddress: publicAddr,
            packId: _selectedPackId,
            compatMode: compat,
            frp: frpConn,
          );
          needFrpc = true;

        case _HostConnectMode.platform:
          final accepted = await _confirmFrpDisclaimer();
          if (!accepted) {
            throw StateError('已取消：须先确认联机隧道免责说明');
          }
          if (!isMicrosoft) {
            throw StateError(
              '平台一键仅支持微软正版。离线请用「OpenFRP/自配」「局域网」或「公网映射」。',
            );
          }
          _appendLog('微软正版：向平台申请一键打洞…');
          final room = await context.read<RoomService>().create(
                packId: _selectedPackId,
                gameType: gameType,
              );
          _appendLog(
              '后端房间 ${room.roomId} · 节点 ${room.frpNode} · 端口 ${room.frpPort}');
          join = await context.read<RoomService>().join(room.roomId);
          join = join.copyWith(compatMode: compat);
          frpConn = join.frp;
          roomTag = room.roomId.length >= 8
              ? room.roomId.substring(0, 8)
              : room.roomId;
          needFrpc = true;
      }

      if (compat) {
        _appendLog(CompatMultiplayer.hostHint(gameType));
        try {
          final root = context.read<InstanceStore>().sharedGameRoot();
          await CompatMultiplayer.patchServerProperties(
            root,
            gameType: gameType,
            port: localPort,
            onLog: _appendLog,
          );
          if (gameType == 'java') {
            final store = context.read<InstanceStore>();
            final inst = store.selected;
            final ver = inst?.gameVersion ?? '';
            final loader = inst?.loaderType ?? 'none';
            if (ver.isNotEmpty && inst != null) {
              final mods = Directory(
                p.join(store.instanceGameDir(inst).path, 'mods'),
              );
              await CompatMultiplayer.ensureJavaCompatMods(
                gameVersion: ver,
                loaderType: loader,
                modsDir: mods,
                onLog: _appendLog,
              );
            }
          }
        } catch (e) {
          _appendLog('兼容联机准备警告: $e');
        }
      }

      if (needFrpc) {
        _appendLog(
            '启动 frpc（本机 $localPort → 远程 ${frpConn.remotePort}）…');
        await frpMgr.startFromConnection(
          roomTag: roomTag,
          frp: frpConn,
          localPort: localPort,
          onLog: (line) {
            _appendLog(line);
            if (line.contains('frpc 已退出') && mounted) {
              setState(() => _tunnelRunning = false);
            }
          },
        );
        _appendLog('穿透就绪：本机 $localPort ↔ 外网 ${join.connectAddress}');
      } else {
        _appendLog('无需 frpc：分享地址 ${join.connectAddress}');
      }
      _appendLog('请确保游戏已对局域网开放 / 开服监听 $localPort');
      _appendLog('其他启动器（HMCL/PCL 等）多人游戏直接填：${join.connectAddress}');

      if (!mounted) return;
      setState(() {
        _joined = join;
        _isHost = true;
        _tunnelRunning = true;
        _tab = _RoomTab.host;
      });
      // ignore: unawaited_futures
      context.read<RecentPlayStore>().recordRoom(
            roomId: join.roomId,
            connectAddress: join.connectAddress,
            gameType: join.gameType,
            role: 'host',
            localTunnel: join.localTunnel,
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '开房就绪：${join.connectAddress}（可复制给其他启动器）',
          ),
        ),
      );
      await _launchGame(join);
    } catch (e) {
      _appendLog('开房失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开房失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinRoom() async {
    if (_busy || _launchInFlight) return;
    final code = _joinCode.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入外网地址或房间标识')),
      );
      return;
    }
    await context.read<AppConfig>().set(AppConfig.keyLastRoomJoin, code);
    setState(() => _busy = true);
    try {
      // host:port → 直连，不走后端
      final direct = _parseDirectAddress(code);
      if (direct != null) {
        final info = RoomJoinInfo.directJoin(
          connectAddress: direct,
          gameType: _java ? 'java' : 'bedrock',
          compatMode: _compat,
          packId: _selectedPackId,
        );
        if (!mounted) return;
        setState(() {
          _joined = info;
          _isHost = false;
        });
        // ignore: unawaited_futures
        context.read<RecentPlayStore>().recordRoom(
              roomId: info.roomId,
              connectAddress: info.connectAddress,
              gameType: info.gameType,
              role: 'join',
              localTunnel: info.localTunnel,
            );
        _appendLog('直连加入：$direct${_compat ? ' · 兼容联机' : ''}');
        if (info.packId != null && info.packId!.isNotEmpty) {
          await _syncPack(info);
        }
        await _launchGame(info);
        return;
      }

      final info = await context.read<RoomService>().join(code);
      if (!mounted) return;
      final joined = info.copyWith(
        compatMode: _compat,
        packId: (info.packId == null || info.packId!.isEmpty)
            ? _selectedPackId
            : info.packId,
      );
      setState(() {
        _joined = joined;
        _isHost = false;
      });
      // ignore: unawaited_futures
      context.read<RecentPlayStore>().recordRoom(
            roomId: joined.roomId,
            connectAddress: joined.connectAddress,
            gameType: joined.gameType,
            role: 'join',
            localTunnel: joined.localTunnel,
          );
      _appendLog(
        '已加入房间，外网地址 ${joined.connectAddress}'
        '${_compat ? ' · 兼容联机' : ''}'
        '${joined.packId != null ? ' · 整合包 ${joined.packId}' : ''}',
      );
      await context.read<AppConfig>().setBool(
            AppConfig.keyRoomCompatMode,
            _compat,
          );
      if (joined.packId != null && joined.packId!.isNotEmpty) {
        await _syncPack(joined);
      }
      await _launchGame(joined);
    } catch (e) {
      _appendLog('加入房间失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加入失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 识别 host:port（域名或 IP），否则视为后端房间码。
  static String? _parseDirectAddress(String raw) {
    final s = raw.trim();
    if (s.contains('://')) return null;
    final colon = s.lastIndexOf(':');
    if (colon <= 0 || colon >= s.length - 1) return null;
    final host = s.substring(0, colon).trim();
    final port = int.tryParse(s.substring(colon + 1).trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    // UUID 误伤：含多个连字符且无点 → 不当成地址
    if (!host.contains('.') && host.contains('-') && host.length > 20) {
      return null;
    }
    return '$host:$port';
  }

  Future<void> _stopTunnel({bool closeRoom = false}) async {
    setState(() => _busy = true);
    try {
      await context.read<FrpManager>().stop();
      _appendLog('隧道已停止');
      if (closeRoom && _joined != null && _isHost && !_joined!.localTunnel) {
        try {
          await context.read<RoomService>().close(_joined!.roomId);
          _appendLog('房间已关闭');
        } catch (e) {
          _appendLog('关闭房间失败: $e');
        }
      } else if (closeRoom && _joined?.localTunnel == true) {
        _appendLog('本地隧道已关闭');
      }
      if (mounted) {
        setState(() {
          _tunnelRunning = false;
          if (closeRoom) {
            _joined = null;
            _isHost = false;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String text, String tip) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip)));
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<GameResourcesNav>();
    if (nav.ticket != _navTicket) {
      final ticket = nav.ticket;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ticket == _navTicket) return;
        _navTicket = ticket;
        _applyPendingJoin();
      });
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final globalConfig = context.watch<GlobalConfigProvider>().config;
    final appConfig = context.watch<AppConfig>();
    final packs = _packs ?? const <PackSummary>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '开房可选局域网 / OpenFRP / 公网映射 / 平台一键；分享标准「主机:端口」即可与 HMCL、PCL 等互通。'
            '加入方粘贴同一地址即可。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ChoiceChip(
                label: const Text('开房'),
                selected: _tab == _RoomTab.host,
                onSelected: (_) => setState(() => _tab = _RoomTab.host),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('加入'),
                selected: _tab == _RoomTab.join,
                onSelected: (_) => setState(() => _tab = _RoomTab.join),
              ),
              const Spacer(),
              Text(
                '本机端口 ${appConfig.localServerPort}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: _Panel(
                    child: _tab == _RoomTab.host
                        ? _HostPane(
                            packs: packs,
                            selectedPackId: _selectedPackId,
                            java: _java,
                            compat: _compat,
                            busy: _busy,
                            hostMode: _hostMode,
                            publicHost: _publicHost,
                            enableJava: globalConfig.enableJavaRoom,
                            enableBedrock: globalConfig.enableBedrockRoom,
                            onPack: (v) =>
                                setState(() => _selectedPackId = v),
                            onJava: (v) => setState(() => _java = v),
                            onCompat: _onCompatChanged,
                            onHostMode: (m) {
                              setState(() => _hostMode = m);
                              // ignore: unawaited_futures
                              context
                                  .read<AppConfig>()
                                  .set(AppConfig.keyRoomConnectMode, m.id);
                            },
                            onOneClick: _oneClickHost,
                          )
                        : _JoinPane(
                            controller: _joinCode,
                            packs: packs,
                            selectedPackId: _selectedPackId,
                            busy: _busy,
                            java: _java,
                            compat: _compat,
                            onPack: (v) =>
                                setState(() => _selectedPackId = v),
                            onJava: (v) => setState(() => _java = v),
                            onCompat: _onCompatChanged,
                            onJoin: _joinRoom,
                            onCodeChanged: (v) {
                              // ignore: unawaited_futures
                              context
                                  .read<AppConfig>()
                                  .set(AppConfig.keyLastRoomJoin, v.trim());
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: _Panel(
                    child: _joined == null
                        ? Center(
                            child: Text(
                              '尚未开房或加入\n点左侧「一键内外穿透开房」开始',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : _RoomStatusPane(
                            info: _joined!,
                            isHost: _isHost,
                            frpRunning: _tunnelRunning,
                            lanAddresses: _lanAddresses,
                            localPort: appConfig.localServerPort,
                            busy: _busy,
                            onCopy: _copy,
                            onSync: () => _syncPack(_joined!),
                            onLaunch: () => _launchGame(_joined!),
                            onStopTunnel: () => _stopTunnel(),
                            onCloseRoom: () => _stopTunnel(closeRoom: true),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Panel(
            height: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('运行日志', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Expanded(
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Text(
                      _log.isEmpty ? '（暂无日志）' : _log.join('\n'),
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // —— 下方保留原同步 / 启动逻辑 ——

  Future<void> _syncPack(RoomJoinInfo info) async {
    if (info.packId == null) {
      _appendLog('该房间未绑定整合包');
      return;
    }
    setState(() => _busy = true);
    try {
      if (info.gameType == 'bedrock') {
        final install = await BedrockInstall.detect();
        if (install == null) {
          _appendLog('未检测到基岩版安装，无法同步资源包');
          return;
        }
        await context.read<LaunchService>().applyBedrockPack(
              info.packId!,
              install,
              _appendLog,
            );
        _appendLog('基岩整合包同步完成');
        return;
      }

      // 同步到当前实例 mods（启动直接读实例目录，不再写入共享）
      final store = context.read<InstanceStore>();
      final inst = store.selected;
      final instanceDir = inst != null
          ? store.instanceDir(inst)
          : store.sharedGameRoot();
      await instanceDir.create(recursive: true);

      late PackManifestResponse manifest;
      if (info.packId != null && info.packId!.isNotEmpty) {
        // 自选 / 直连绑定整合包：优先按 packId；房间码再尝试房间清单
        try {
          if (!info.localTunnel &&
              info.roomId.isNotEmpty &&
              !info.roomId.contains(':')) {
            manifest =
                await context.read<RoomService>().packManifest(info.roomId);
          } else {
            manifest =
                await context.read<PackService>().manifest(info.packId!);
          }
        } catch (_) {
          manifest =
              await context.read<PackService>().manifest(info.packId!);
        }
      } else {
        manifest =
            await context.read<RoomService>().packManifest(info.roomId);
      }
      final auth = context.read<AuthManager>();
      final token = auth.currentAccessToken ?? '';

      var ok = 0;
      var skip = 0;
      await for (final progress
          in _downloadManifestFiles(manifest, instanceDir, token)) {
        progress.downloaded ? ok++ : skip++;
        _appendLog(progress.message);
      }
      _appendLog('整合包同步完成（新增 $ok，已有 $skip）');
    } catch (e) {
      _appendLog('同步整合包失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Stream<_FileSync> _downloadManifestFiles(PackManifestResponse manifest,
      Directory instanceDir, String token) async* {
    final packService = context.read<PackService>();
    final accel = context.read<AppConfig>().downloadAccelEnabled;
    final modrinth = ModrinthClient(useMirrors: accel);
    final sections = {
      'mods': 'mods',
      'resource_packs': 'resourcepacks',
      'behavior_packs': 'behavior_packs',
    };
    for (final section in sections.entries) {
      for (final entry in _entriesOf(manifest.manifest, section.key)) {
        try {
          final (bytes, filename) =
              await _entryBytes(entry, packService, modrinth, token);
          final target = File('${instanceDir.path}/${section.value}/$filename');
          if (target.existsSync()) {
            yield _FileSync(false, '已存在 ${section.value}/$filename');
            continue;
          }
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes);
          yield _FileSync(true, '下载 ${section.value}/$filename');
        } catch (e) {
          yield _FileSync(false, '失败 ${entry.filename ?? entry.slug}: $e');
        }
      }
    }
  }

  List<ManifestEntry> _entriesOf(PackManifest manifest, String key) {
    switch (key) {
      case 'mods':
        return manifest.mods;
      case 'resource_packs':
        return manifest.resourcePacks;
      default:
        return manifest.behaviorPacks;
    }
  }

  Future<(List<int>, String)> _entryBytes(
      ManifestEntry entry,
      PackService packService,
      ModrinthClient modrinth,
      String token) async {
    final downloader = AcceleratedDownloader(
      config: context.read<AppConfig>(),
      onLog: _appendLog,
    );
    // 清单直链优先 → 前端直连 CDN/R2，不经 Worker 拉字节
    if (entry.downloadUrl != null && entry.downloadUrl!.isNotEmpty) {
      final name = entry.filename ??
          entry.downloadUrl!.split('/').last.split('?').first;
      final bytes = await downloader.downloadBytes(
        Uri.parse(entry.downloadUrl!),
        expectedSha1: entry.sha1,
      );
      return (bytes, name);
    }
    if (entry.type == 'modrinth' && entry.versionId != null) {
      final file = await modrinth.versionFile(entry.versionId!);
      final bytes = await downloader.downloadBytes(
        Uri.parse(file.url),
        expectedSha1: entry.sha1 ?? file.sha1,
      );
      return (bytes, file.filename);
    }
    if (entry.fileId != null) {
      final url = await packService.downloadUrl(entry.fileId!, token);
      final bytes = await downloader.downloadBytes(
        Uri.parse(url),
        expectedSha1: entry.sha1,
      );
      return (bytes, entry.filename ?? entry.fileId!);
    }
    throw StateError('清单条目缺少下载来源');
  }

  Future<void> _launchGame(RoomJoinInfo info) async {
    if (_launchInFlight) {
      _appendLog('已有启动进行中，已忽略重复启动');
      return;
    }
    _launchInFlight = true;
    setState(() => _busy = true);
    try {
      final compat = info.compatMode || _compat;
      if (info.gameType == 'bedrock') {
        if (compat) {
          _appendLog(CompatMultiplayer.hostHint('bedrock'));
        }
        await context.read<LaunchService>().launchBedrock(
              onLog: _appendLog,
            );
        _appendLog(
          '基岩已启动。请在游戏内多人游戏加入：${info.connectAddress}',
        );
        return;
      }

      final appConfig = context.read<AppConfig>();
      final store = context.read<InstanceStore>();
      final gameRoot = store.sharedGameRoot();
      await gameRoot.create(recursive: true);

      String gameVersion = '';
      try {
        if (info.packId != null) {
          final PackManifestResponse manifest;
          if (info.localTunnel) {
            manifest =
                await context.read<PackService>().manifest(info.packId!);
          } else {
            manifest =
                await context.read<RoomService>().packManifest(info.roomId);
          }
          gameVersion = manifest.gameVersion;
        }
      } catch (_) {}
      gameVersion = gameVersion.isNotEmpty
          ? gameVersion
          : (store.selected?.gameVersion ?? '');
      if (gameVersion.isEmpty) {
        _appendLog('无法确定游戏版本：请绑定整合包或先选择实例版本');
        return;
      }

      if (compat) {
        _appendLog(CompatMultiplayer.hostHint('java'));
        final loader = store.selected?.loaderType ?? 'fabric';
        final inst = store.selected;
        final modsDir = inst != null
            ? Directory(p.join(store.instanceGameDir(inst).path, 'mods'))
            : Directory(p.join(gameRoot.path, 'mods'));
        await CompatMultiplayer.ensureJavaCompatMods(
          gameVersion: gameVersion,
          loaderType: loader,
          modsDir: modsDir,
          onLog: _appendLog,
        );
      }

      final metaJava = await VersionInstaller.peekDeclaredJavaMajor(
        gameRoot,
        gameVersion,
      );
      final java = await JavaEnvAdapter(
        appConfig,
        context.read<JavaRuntime>(),
      ).ensureIsolatedForGame(
        gameVersion,
        onLog: _appendLog,
        javaMajorFromMeta: metaJava,
      );
      if (java.warning != null &&
          (java.warning!.contains('无法') || java.warning!.contains('不在允许'))) {
        throw StateError(java.warning!);
      }

      final installer =
          VersionInstaller(onProgress: _appendLog, config: appConfig);
      try {
        var warm = VersionInstaller.isWarmReady(
          gameDir: gameRoot,
          gameVersion: gameVersion,
          loaderType: 'none',
        );
        if (!warm) {
          await VersionInstaller.healAssetsStampIfPossible(
            gameRoot,
            gameVersion,
            onLog: _appendLog,
          );
          warm = VersionInstaller.isWarmReady(
            gameDir: gameRoot,
            gameVersion: gameVersion,
            loaderType: 'none',
          );
        }
        if (warm) {
          _appendLog('本地已就绪，跳过安装检查（快速启动）');
        } else {
          await installer.installVanilla(gameVersion, gameRoot);
        }
      } finally {
        installer.close();
      }

      final session = await context.read<TokenStore>().readGameSession();
      final auth = context.read<AuthManager>();
      final name = session['name'] ?? auth.username ?? 'Player';
      final uuid = session['uuid'] ?? '';
      final token =
          session['access_token'] ?? auth.currentAccessToken ?? '';

      // 兼容模式：无正版会话也可用离线身份进服
      if (!compat && (uuid.isEmpty)) {
        _appendLog('缺少游戏会话，请重新登录；或勾选「兼容联机」以离线身份进入');
        return;
      }

      final resolved =
          await installer.resolveVersionChain(gameVersion, gameRoot);
      final profile = CompatMultiplayer.resolveCompatProfile(
        username: name,
        uuid: uuid,
        accessToken: token,
        forceOfflineIdentity: compat &&
            (uuid.isEmpty || token.isEmpty || token == '0'),
      );
      if (compat) {
        _appendLog(
          '进服身份：${profile.username} · ${profile.userType}'
          '${profile.userType == 'legacy' ? '（离线）' : '（正版令牌，服需关正版校验）'}',
        );
      }

      final addr = CompatMultiplayer.parseAddress(
        _isHost
            ? '127.0.0.1:${appConfig.localServerPort}'
            : info.connectAddress,
      );
      if (!_isHost && addr == null) {
        _appendLog('无法解析进服地址，请确认房间外网地址');
        return;
      }

      // 房主：先进单人世界（可对局域网开放）；访客：直接加入外网地址
      String? joinHost;
      int? joinPort;
      String? worldName;
      if (_isHost) {
        final loadout = context.read<LaunchLoadout>();
        worldName = (loadout.includeWorld &&
                loadout.worldName != null &&
                loadout.worldName!.trim().isNotEmpty)
            ? loadout.worldName!.trim()
            : null;
        _appendLog(
          worldName == null
              ? '房主启动：进入游戏后请「对局域网开放」，端口 ${appConfig.localServerPort}'
              : '房主启动：进入存档「$worldName」，开放局域网时请用端口 ${appConfig.localServerPort}',
        );
      } else {
        joinHost = addr!.host;
        joinPort = addr.port;
      }

      final process = await context.read<GameLauncher>().launch(
            javaPath: java.path,
            gameDir: gameRoot,
            version: resolved,
            profile: profile,
            javaMajor: java.probe?.major,
            serverHost: joinHost,
            serverPort: joinPort,
            singleplayerWorld: worldName,
          );
      _appendLog(
        '游戏进程已启动 (pid=${process.pid})'
        '${joinHost != null ? ' · 自动进入 $joinHost:$joinPort' : ''}'
        '${worldName != null ? ' · 存档 $worldName' : ''}'
        '${_isHost ? '（房主）' : ''}',
      );
    } catch (e) {
      _appendLog('启动失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('启动失败: $e')));
      }
    } finally {
      _launchInFlight = false;
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final double? height;

  const _Panel({required this.child, this.height});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final box = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        color: scheme.surface.withValues(alpha: 0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: child,
      ),
    );
    // 无固定高度时铺满父级（Expanded），避免子 Column 按内容撑破后溢出
    if (height == null) {
      return SizedBox.expand(child: box);
    }
    return SizedBox(height: height, child: box);
  }
}

class _HostPane extends StatelessWidget {
  final List<PackSummary> packs;
  final String? selectedPackId;
  final bool java;
  final bool compat;
  final bool busy;
  final _HostConnectMode hostMode;
  final TextEditingController publicHost;
  final bool enableJava;
  final bool enableBedrock;
  final ValueChanged<String?> onPack;
  final ValueChanged<bool> onJava;
  final Future<void> Function(bool) onCompat;
  final ValueChanged<_HostConnectMode> onHostMode;
  final VoidCallback onOneClick;

  const _HostPane({
    required this.packs,
    required this.selectedPackId,
    required this.java,
    required this.compat,
    required this.busy,
    required this.hostMode,
    required this.publicHost,
    required this.enableJava,
    required this.enableBedrock,
    required this.onPack,
    required this.onJava,
    required this.onCompat,
    required this.onHostMode,
    required this.onOneClick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final btnLabel = switch (hostMode) {
      _HostConnectMode.lan => '局域网开房',
      _HostConnectMode.frp => 'OpenFRP / 自配开房',
      _HostConnectMode.publicIp => '公网映射开房',
      _HostConnectMode.platform => '平台一键开房',
    };
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text('房主开房', style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          '连接模式决定如何生成「主机:端口」。该地址可直接给 HMCL、PCL、官方启动器加入。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Text('连接模式', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final m in _HostConnectMode.values)
              ChoiceChip(
                label: Text(m.label),
                selected: hostMode == m,
                visualDensity: VisualDensity.compact,
                onSelected: busy ? null : (_) => onHostMode(m),
              ),
          ],
        ),
        if (hostMode == _HostConnectMode.publicIp) ...[
          const SizedBox(height: 8),
          TextField(
            controller: publicHost,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: '公网 IP / 域名',
              hintText: '例如 1.2.3.4 或 play.example.com',
              border: OutlineInputBorder(),
              isDense: true,
              helperText: '路由器需把外网端口转发到本机游戏端口',
            ),
          ),
        ],
        if (hostMode == _HostConnectMode.frp) ...[
          const SizedBox(height: 6),
          Text(
            '请先在「设置 → 联机隧道」填写 OpenFRP 节点 / Token / 远程端口（含 TLS、User 等）。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (hostMode == _HostConnectMode.platform) ...[
          const SizedBox(height: 6),
          Text(
            '仅微软正版可用；离线请改用局域网 / OpenFRP / 公网映射。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text('游戏类型', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Java 版'),
              selected: java,
              visualDensity: VisualDensity.compact,
              onSelected: enableJava ? (_) => onJava(true) : null,
            ),
            ChoiceChip(
              label: const Text('基岩版'),
              selected: !java,
              visualDensity: VisualDensity.compact,
              onSelected: enableBedrock ? (_) => onJava(false) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('兼容联机'),
          subtitle: Text(
            java
                ? '私人房间可用 · 关闭正版校验 · 方便离线号与其他启动器互通'
                : '私人房间可用 · 关闭校验试验 · 开启前会提示说明',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          value: compat,
          onChanged: busy ? null : (v) => onCompat(v),
        ),
        const SizedBox(height: 4),
        AppSelectField<String>(
          value: packs.any((e) => e.packId == selectedPackId)
              ? selectedPackId
              : '__none__',
          labelText: '整合包（可选）',
          hintText: packs.isEmpty ? '可不选，纯穿透开房' : '绑定后好友可自动同步',
          options: [
            const AppSelectOption(value: '__none__', label: '不使用整合包'),
            for (final e in packs)
              AppSelectOption(value: e.packId, label: e.name),
          ],
          onChanged: (v) => onPack(v == '__none__' ? null : v),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : onOneClick,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.rocket_launch_outlined),
          label: Text(busy ? '开房中…' : btnLabel),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(42),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          compat
              ? (java
                  ? '开启后：请在游戏里开服或对局域网开放；好友也勾选「兼容联机」再加入。请只用于私人好友房间。'
                  : '开启后：基岩跨版本能力有限，尽量和好友用同一版本。请只用于私人好友房间。')
              : '请先在游戏里「对局域网开放」或开服，端口与设置中的本机端口一致。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _JoinPane extends StatelessWidget {
  final TextEditingController controller;
  final List<PackSummary> packs;
  final String? selectedPackId;
  final bool busy;
  final bool java;
  final bool compat;
  final ValueChanged<String?> onPack;
  final ValueChanged<bool> onJava;
  final Future<void> Function(bool) onCompat;
  final VoidCallback onJoin;
  final ValueChanged<String>? onCodeChanged;

  const _JoinPane({
    required this.controller,
    required this.packs,
    required this.selectedPackId,
    required this.busy,
    required this.java,
    required this.compat,
    required this.onPack,
    required this.onJava,
    required this.onCompat,
    required this.onJoin,
    this.onCodeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text('加入房间', style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          '粘贴「主机:端口」（任意启动器开的房均可），或本平台房间码。可先选整合包再加入。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Text('游戏类型', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Java 版'),
              selected: java,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onJava(true),
            ),
            ChoiceChip(
              label: const Text('基岩版'),
              selected: !java,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onJava(false),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('兼容联机'),
          subtitle: Text(
            '私人房间可用 · 关闭正版校验 · 开启前会提示说明',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          value: compat,
          onChanged: busy ? null : (v) => onCompat(v),
        ),
        const SizedBox(height: 4),
        AppSelectField<String>(
          value: packs.any((e) => e.packId == selectedPackId)
              ? selectedPackId
              : '__none__',
          labelText: '整合包（可选）',
          hintText: packs.isEmpty ? '可不选；房主若绑定会以房间为准' : '加入前同步到本机',
          options: [
            const AppSelectOption(value: '__none__', label: '不使用整合包'),
            for (final e in packs)
              AppSelectOption(value: e.packId, label: e.name),
          ],
          onChanged:
              busy ? null : (v) => onPack(v == '__none__' ? null : v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '外网地址 / 房间标识',
            hintText: '例如 frp.example.com:7001',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: onCodeChanged,
          onSubmitted: (_) => onJoin(),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: busy ? null : onJoin,
          icon: const Icon(Icons.login),
          label: const Text('加入'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(42),
          ),
        ),
      ],
    );
  }
}

class _RoomStatusPane extends StatelessWidget {
  final RoomJoinInfo info;
  final bool isHost;
  final bool frpRunning;
  final List<String> lanAddresses;
  final int localPort;
  final bool busy;
  final Future<void> Function(String text, String tip) onCopy;
  final VoidCallback onSync;
  final VoidCallback onLaunch;
  final VoidCallback onStopTunnel;
  final VoidCallback onCloseRoom;

  const _RoomStatusPane({
    required this.info,
    required this.isHost,
    required this.frpRunning,
    required this.lanAddresses,
    required this.localPort,
    required this.busy,
    required this.onCopy,
    required this.onSync,
    required this.onLaunch,
    required this.onStopTunnel,
    required this.onCloseRoom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isHost ? '穿透已就绪' : '房间信息',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSm),
                        color: (frpRunning || !isHost)
                            ? scheme.primary.withValues(alpha: 0.2)
                            : scheme.error.withValues(alpha: 0.15),
                      ),
                      child: Text(
                        isHost
                            ? (frpRunning
                                ? (info.frp.node == 'lan'
                                    ? '局域网就绪'
                                    : info.frp.node == 'public'
                                        ? '公网映射就绪'
                                        : '隧道运行中')
                                : '未就绪')
                            : info.gameType,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: (frpRunning || !isHost)
                              ? scheme.primary
                              : scheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (info.compatMode) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSm),
                          color: scheme.tertiary.withValues(alpha: 0.2),
                        ),
                        child: Text(
                          '兼容联机',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.tertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                _AddrTile(
                  label: info.localTunnel ? '本地房间 / 直连' : '房间标识',
                  value: info.roomId,
                  onCopy: () => onCopy(info.roomId, '已复制'),
                ),
                const SizedBox(height: 8),
                _AddrTile(
                  label: '加入地址（HMCL / PCL / 本启动器通用）',
                  value: info.connectAddress.isEmpty
                      ? '—'
                      : info.connectAddress,
                  emphasize: true,
                  onCopy: info.connectAddress.isEmpty
                      ? null
                      : () => onCopy(
                            info.connectAddress,
                            '已复制加入地址，可发给其他启动器用户',
                          ),
                ),
                if (isHost) ...[
                  const SizedBox(height: 8),
                  Text(
                    '内网地址（局域网）',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final a in (lanAddresses.isEmpty
                      ? <String>['127.0.0.1:$localPort']
                      : lanAddresses))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              a,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: '复制',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => onCopy(a, '已复制内网地址'),
                            icon: const Icon(Icons.copy, size: 16),
                          ),
                        ],
                      ),
                    ),
                ] else
                  const SizedBox(height: 16),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (info.packId != null &&
                        (info.autoDistribute || info.localTunnel))
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : onSync,
                        icon: const Icon(Icons.sync, size: 18),
                        label: const Text('同步整合包'),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onLaunch,
                      icon: const Icon(
                        Icons.videogame_asset_outlined,
                        size: 18,
                      ),
                      label: const Text('启动游戏'),
                    ),
                    if (isHost) ...[
                      OutlinedButton.icon(
                        onPressed: busy ? null : onStopTunnel,
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('停止隧道'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : onCloseRoom,
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: scheme.error,
                        ),
                        label: Text(
                          '关闭房间',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddrTile extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  final VoidCallback? onCopy;

  const _AddrTile({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                  color: emphasize ? scheme.primary : null,
                ),
              ),
            ),
            if (onCopy != null)
              IconButton(
                tooltip: '复制',
                visualDensity: VisualDensity.compact,
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
              ),
          ],
        ),
      ],
    );
  }
}

class _FileSync {
  final bool downloaded;
  final String message;
  const _FileSync(this.downloaded, this.message);
}
