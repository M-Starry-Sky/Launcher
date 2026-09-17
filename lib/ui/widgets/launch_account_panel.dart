import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/auth/auth_guard.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/game/game_instance.dart';
import '../../core/game/launch_loadout.dart';
import '../../models/pack.dart';
import '../../services/pack_service.dart';
import '../app_theme.dart';
import '../microsoft_login_dialog.dart';
import 'app_select_field.dart';

/// 启动页左侧：未就绪显示账号；就绪后显示模组/服务器/整合包/皮肤载入选项。
class LaunchAccountPanel extends StatefulWidget {
  const LaunchAccountPanel({super.key});

  @override
  State<LaunchAccountPanel> createState() => _LaunchAccountPanelState();
}

class _LaunchAccountPanelState extends State<LaunchAccountPanel> {
  late String _mode;
  final _offlineName = TextEditingController();
  bool _busy = false;
  List<PackSummary> _packs = const [];

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthManager>();
    _mode = auth.source == AuthSource.microsoft ? 'microsoft' : 'offline';
    _offlineName.text = (auth.source != AuthSource.microsoft
            ? auth.username
            : null) ??
        'Player';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPacks());
  }

  @override
  void dispose() {
    _offlineName.dispose();
    super.dispose();
  }

  Future<void> _loadPacks() async {
    try {
      final packs = await context.read<PackService>().list();
      if (mounted) setState(() => _packs = packs);
    } catch (_) {
      if (mounted) setState(() => _packs = const []);
    }
  }

  Future<void> _applyOffline() async {
    final name = _offlineName.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先输入离线玩家名')));
      return;
    }
    setState(() => _busy = true);
    try {
      final safe = AuthManager.sanitizeMinecraftUsername(name);
      await context.read<AuthManager>().loginOffline(name);
      if (mounted) {
        _offlineName.text = safe;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              safe == name
                  ? '已设置离线昵称：$safe'
                  : '昵称含非法字符，已改为：$safe（仅英文/数字/下划线，3–16 位）',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginMicrosoft() async {
    setState(() => _busy = true);
    try {
      await showMicrosoftLoginDialog(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthManager>();
    final global = context.watch<GlobalConfigProvider>();
    final msOk = global.microsoftLoginAvailable;
    if (auth.isLaunchReady) {
      return _LoadoutCard(
        packs: _packs,
        onRefreshPacks: _loadPacks,
        onSwitchAccount: () async {
          await auth.signOut();
          if (mounted) setState(() => _mode = 'offline');
        },
      );
    }
    // 后端未开微软时强制离线，避免空配置仍可点登录
    final mode = (!msOk && _mode == 'microsoft') ? 'offline' : _mode;
    return _AccountSetupCard(
      mode: mode,
      busy: _busy,
      microsoftAvailable: msOk,
      offlineName: _offlineName,
      onModeChanged: (m) {
        if (m == 'microsoft' && !msOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                  content: Text(
                    global.backendReachable
                        ? '后台已关闭微软登录'
                        : '后端连接失败，将使用内置 Xbox Live 公共客户端。请检查网络或开启本地配置。',
                  ),
            ),
          );
          return;
        }
        setState(() => _mode = m);
      },
      onApplyOffline: _applyOffline,
      onLoginMicrosoft: _loginMicrosoft,
    );
  }
}

class _ShellCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const _ShellCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _InnerBox extends StatelessWidget {
  final Widget child;
  const _InnerBox({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.28)),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _AccountSetupCard extends StatelessWidget {
  final String mode;
  final bool busy;
  final bool microsoftAvailable;
  final TextEditingController offlineName;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onApplyOffline;
  final VoidCallback onLoginMicrosoft;

  const _AccountSetupCard({
    required this.mode,
    required this.busy,
    required this.microsoftAvailable,
    required this.offlineName,
    required this.onModeChanged,
    required this.onApplyOffline,
    required this.onLoginMicrosoft,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthManager>();
    final isMs = mode == 'microsoft';

    return _ShellCard(
      title: '游戏账号',
      trailing: Text(
        auth.username ?? '未设置',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              ButtonSegment(
                value: 'microsoft',
                label: const Text('微软'),
                enabled: microsoftAvailable,
              ),
              const ButtonSegment(
                value: 'offline',
                label: Text('离线'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: busy ? null : (s) => onModeChanged(s.first),
          ),
          if (!microsoftAvailable) ...[
            const SizedBox(height: 8),
            Text(
              '微软登录未开放：后台未配置 Client ID，或后端连接失败。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: _InnerBox(
              child: isMs
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '登录微软正版账号后，将自动识别游戏皮肤模型：'
                          '细臂为爱丽克斯、宽臂为史蒂夫，并显示游戏昵称。'
                          '启动器内不提供性别切换。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: busy || !microsoftAvailable
                              ? null
                              : onLoginMicrosoft,
                          icon: const Icon(Icons.login),
                          label: const Text('登录 Minecraft 账号'),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: offlineName,
                          decoration: const InputDecoration(
                            labelText: '我的世界昵称',
                            helperText: '仅英文/数字/下划线，3–16 位（中文无法进单人世界）',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          enabled: !busy,
                          onSubmitted: (_) => onApplyOffline(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '离线模式无正版档案，默认史蒂夫头像。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          onPressed: busy ? null : onApplyOffline,
                          icon: const Icon(Icons.check),
                          label: const Text('应用离线昵称'),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadoutCard extends StatelessWidget {
  final List<PackSummary> packs;
  final VoidCallback onRefreshPacks;
  final VoidCallback onSwitchAccount;

  const _LoadoutCard({
    required this.packs,
    required this.onRefreshPacks,
    required this.onSwitchAccount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = context.watch<AuthManager>();
    final loadout = context.watch<LaunchLoadout>();
    final servers = loadout.savedServers();
    final skins = loadout.localSkins(
      directory: context.read<InstanceStore>().skinsDir(),
    );

    return _ShellCard(
      title: '启动载入',
      trailing: TextButton(
        onPressed: onSwitchAccount,
        child: Text(
          auth.username ?? '切换',
          style: theme.textTheme.labelMedium,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      SizedBox(
                        height: 56,
                        child: _SwitchRow(
                          title: '模组',
                          subtitle: '同步实例 mods',
                          value: loadout.includeMods,
                          onChanged: loadout.setIncludeMods,
                        ),
                      ),
                      SizedBox(
                        height: 56,
                        child: _SwitchRow(
                          title: '服务器',
                          subtitle: '启动后直连',
                          value: loadout.includeServer,
                          onChanged: loadout.setIncludeServer,
                        ),
                      ),
                      SizedBox(
                        height: 56,
                        child: _SwitchRow(
                          title: '存档',
                          subtitle: '启动后进入世界',
                          value: loadout.includeWorld,
                          onChanged: loadout.setIncludeWorld,
                        ),
                      ),
                      SizedBox(
                        height: 56,
                        child: _SwitchRow(
                          title: '整合包',
                          subtitle: packs.isEmpty ? '暂无整合包' : '下载到实例',
                          value: loadout.includePack,
                          onChanged: (v) async {
                            await loadout.setIncludePack(v);
                            if (v) onRefreshPacks();
                          },
                        ),
                      ),
                      SizedBox(
                        height: 56,
                        child: _SwitchRow(
                          title: '皮肤',
                          subtitle: '本地 skins',
                          value: loadout.includeSkin,
                          onChanged: loadout.setIncludeSkin,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.28),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (loadout.includeServer) ...[
                        AppSelectField<String>(
                          value: servers.any(
                                  (s) => s['address'] == loadout.serverAddress)
                              ? loadout.serverAddress
                              : null,
                          labelText: '选择服务器',
                          hintText: servers.isEmpty ? '暂无已存服务器' : '请选择',
                          options: [
                            for (final s in servers)
                              AppSelectOption(
                                value: s['address']!,
                                label: '${s['name']} (${s['address']})',
                              ),
                          ],
                          onChanged: loadout.setServerAddress,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (loadout.includeWorld) ...[
                        Builder(builder: (context) {
                          final store = context.read<InstanceStore>();
                          final inst = store.selected;
                          final worlds = loadout.localWorlds(
                            gameRoot: inst != null
                                ? store.instanceGameDir(inst)
                                : store.sharedGameRoot(),
                          );
                          return AppSelectField<String>(
                            value: worlds.contains(loadout.worldName)
                                ? loadout.worldName
                                : null,
                            labelText: '选择存档',
                            hintText: worlds.isEmpty ? '暂无存档' : '请选择',
                            options: [
                              for (final w in worlds)
                                AppSelectOption(value: w, label: w),
                            ],
                            onChanged: loadout.setWorldName,
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                      if (loadout.includePack) ...[
                        AppSelectField<String>(
                          value: packs.any((e) => e.packId == loadout.packId)
                              ? loadout.packId
                              : null,
                          labelText: '选择整合包',
                          hintText: packs.isEmpty ? '暂无整合包' : '请选择',
                          options: [
                            for (final pack in packs)
                              AppSelectOption(
                                value: pack.packId,
                                label: pack.name,
                              ),
                          ],
                          onChanged: loadout.setPackId,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (loadout.includeSkin) ...[
                        AppSelectField<String>(
                          value: skins.any((f) => f.path == loadout.skinPath)
                              ? loadout.skinPath
                              : null,
                          labelText: '选择皮肤',
                          hintText: skins.isEmpty ? '暂无皮肤' : '请选择',
                          options: [
                            for (final f in skins)
                              AppSelectOption(
                                value: f.path,
                                label: p.basename(f.path),
                              ),
                          ],
                          onChanged: loadout.setSkinPath,
                        ),
                      ],
                      if (!loadout.includeServer &&
                          !loadout.includeWorld &&
                          !loadout.includePack &&
                          !loadout.includeSkin)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '打开左侧开关后，在此选择对应资源',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
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

class _SwitchRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_SwitchRow> createState() => _SwitchRowState();
}

class _SwitchRowState extends State<_SwitchRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onChanged(!widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            color: _hover
                ? scheme.onSurface.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _SlimSwitch(
                value: widget.value,
                onChanged: (v) => widget.onChanged(v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 轻量轨道开关：悬停加亮、按下缩放，无 Material 大圆水波。
class _SlimSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SlimSwitch({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_SlimSwitch> createState() => _SlimSwitchState();
}

class _SlimSwitchState extends State<_SlimSwitch> {
  bool _hover = false;
  bool _pressed = false;

  static const double _w = 40;
  static const double _h = 22;
  static const double _thumb = 16;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = widget.value;
    final trackColor = on
        ? scheme.primary.withValues(alpha: _hover ? 1 : 0.88)
        : scheme.onSurface.withValues(alpha: _hover ? 0.28 : 0.18);

    return Semantics(
      checked: on,
      button: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _pressed = false;
        }),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () => widget.onChanged(!on),
          child: Padding(
            // 扩大点击热区
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: AnimatedScale(
              scale: _pressed ? 0.94 : 1,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _w,
                height: _h,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_h / 2),
                  color: trackColor,
                  boxShadow: _hover
                      ? [
                          BoxShadow(
                            color: (on ? scheme.primary : scheme.onSurface)
                                .withValues(alpha: 0.18),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment:
                      on ? Alignment.centerRight : Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? scheme.onPrimary : scheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: _pressed ? 1 : 3,
                          offset: Offset(0, _pressed ? 0.5 : 1),
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
    );
  }
}
