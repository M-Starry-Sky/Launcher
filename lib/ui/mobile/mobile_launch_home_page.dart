import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_manager.dart';
import '../../core/bedrock/bedrock_install.dart';
import '../../core/config/app_config.dart';
import '../../core/game/game_instance.dart';
import '../../core/game/launch_loadout.dart';
import '../../core/game/launch_service.dart';
import '../../core/perf/game_session.dart';
import '../../core/perf/launcher_sleep.dart';
import '../../core/perf/perf_config.dart';
import '../about_dialogs.dart';
import '../app_theme.dart';
import '../glass/liquid_glass.dart';
import '../home_notice_host.dart';
import '../instances_page.dart';
import '../launch_feature_dialog.dart';
import '../recent_games_page.dart';
import '../recordings_page.dart';
import '../saves_page.dart';
import '../widgets/app_select_field.dart';
import '../widgets/home_banner_carousel.dart';
import '../widgets/launch_account_panel.dart';
import 'mobile_page_header.dart';

/// App 端启动首页：竖向信息流 + 底部固定开玩，不复用桌面双栏。
class MobileLaunchHomePage extends StatefulWidget {
  const MobileLaunchHomePage({
    super.key,
    this.onOpenCommunity,
  });

  final VoidCallback? onOpenCommunity;

  @override
  State<MobileLaunchHomePage> createState() => _MobileLaunchHomePageState();
}

class _MobileLaunchHomePageState extends State<MobileLaunchHomePage> {
  String _edition = 'java';
  bool _busy = false;
  final _logs = <String>[];
  final _pendingLogs = <String>[];
  Timer? _logFlush;
  BedrockInstallInfo? _bedrock;
  bool _bedrockChecking = false;

  @override
  void initState() {
    super.initState();
    _refreshBedrock();
  }

  @override
  void dispose() {
    _logFlush?.cancel();
    super.dispose();
  }

  Future<void> _refreshBedrock() async {
    setState(() => _bedrockChecking = true);
    final info = await BedrockInstall.detect();
    if (!mounted) return;
    setState(() {
      _bedrock = info;
      _bedrockChecking = false;
    });
  }

  void _log(String line) {
    _pendingLogs.add(line);
    _logFlush ??= Timer(const Duration(milliseconds: 120), _flushLogs);
  }

  void _flushLogs() {
    _logFlush = null;
    if (!mounted || _pendingLogs.isEmpty) return;
    setState(() {
      _logs.addAll(_pendingLogs);
      _pendingLogs.clear();
      if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
    });
  }

  Future<void> _play() async {
    if (_busy) return;
    if (_edition == 'bedrock') {
      await _playBedrock();
      return;
    }
    final store = context.read<InstanceStore>();
    final instance = store.selected;
    if (instance == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先选择版本 / 实例')));
      return;
    }
    final auth = context.read<AuthManager>();
    if (!auth.isLaunchReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录微软账号，或设置离线昵称')),
      );
      return;
    }
    setState(() {
      _busy = true;
      _logs.clear();
    });
    try {
      final loadout = context.read<LaunchLoadout>();
      final cfg = context.read<AppConfig>();
      final accel = cfg.downloadAccelEnabled;
      _log('开始启动…');
      _log('数据根: ${context.read<InstanceStore>().dataRootPath()}');
      _log('游戏本体: ${context.read<InstanceStore>().sharedGameRoot().path}');
      final authName = auth.username;
      if (authName != null &&
          auth.source == AuthSource.offline &&
          !AuthManager.isValidMinecraftUsername(authName)) {
        final safe = AuthManager.sanitizeMinecraftUsername(authName);
        _log('离线昵称「$authName」非法，启动将使用「$safe」');
        await auth.loginOffline(safe);
      }
      _log(accel ? '下载加速已开启（多源 / 节点互传）' : '下载加速已关闭，使用单源');
      await context.read<LaunchService>().installAndLaunch(
            instance,
            onLog: _log,
            loadout: loadout,
            autoInstall: cfg.launchAutoInstall,
          );
      if (Platform.isAndroid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '已打开内嵌 Java 版（含虚拟按键）；首次需下载手机 OpenJDK',
              ),
            ),
          );
        }
        return;
      }
      if (cfg.launchMinimizeOnStart) {
        await context.read<LauncherSleepController>().enter(onLog: _log);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('游戏已启动，启动器已休眠')));
      }
    } catch (e) {
      _log('失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('启动失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playBedrock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _logs.clear();
    });
    try {
      final loadout = context.read<LaunchLoadout>();
      context.read<PerfConfig>();
      await context.read<LaunchService>().launchBedrock(
            onLog: _log,
            loadout: loadout,
          );
      await _refreshBedrock();
      final cfg = context.read<AppConfig>();
      if (cfg.launchMinimizeOnStart) {
        await context.read<LauncherSleepController>().enter(onLog: _log);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已请求启动基岩版，启动器已休眠')),
        );
      }
    } catch (e) {
      _log('失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('基岩启动失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openFeature(String title, Widget child) {
    openLaunchFeatureDialog(context: context, title: title, child: child);
  }

  void _showLogsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return LiquidGlass(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              fillBoost: 0.08,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Text(
                          '启动日志',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                  ),
                  Expanded(
                    child: Container(
                      color: const Color(0xCC0F1419),
                      child: ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                        itemCount: _logs.isEmpty ? 1 : _logs.length,
                        itemBuilder: (_, i) {
                          if (_logs.isEmpty) {
                            return const Text(
                              '等待启动…',
                              style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 13,
                                height: 1.45,
                                color: Color(0xFF6B7280),
                              ),
                            );
                          }
                          final line = _logs[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: SelectableText(
                              line,
                              style: TextStyle(
                                fontFamily: 'Consolas',
                                fontSize: 13,
                                height: 1.45,
                                color: _logLineColor(line),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InstanceStore>();
    final loadout = context.watch<LaunchLoadout>();
    final session = context.watch<GameSession>();
    final auth = context.watch<AuthManager>();
    final instance = store.selected;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isJava = _edition == 'java';
    final playLabel = loadout.launchButtonLabel(isJava: isJava, busy: _busy);

    return HomeNoticeHost(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MobilePageHeader(
            title: '星穹次元',
            subtitle: auth.username?.trim().isNotEmpty == true
                ? auth.username
                : '未登录 · 点头像管理账号',
            showAccount: true,
            actions: [
              IconButton(
                tooltip: '社区',
                onPressed: widget.onOpenCommunity,
                icon: const Icon(Icons.groups_outlined),
              ),
              IconButton(
                tooltip: '关于',
                onPressed: () => showAppAboutDialog(context),
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                SizedBox(
                  height: 148,
                  child: LiquidGlass(
                    allowBackdrop: false,
                    borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
                    fillBoost: 0.02,
                    clip: true,
                    child: const HomeBannerCarousel(),
                  ),
                ),
                if (session.isRunning || session.lastExitCode != null) ...[
                  const SizedBox(height: 10),
                  LiquidGlass(
                    allowBackdrop: false,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    fillBoost: 0.04,
                    child: Row(
                      children: [
                        Icon(
                          session.isRunning
                              ? Icons.sports_esports_rounded
                              : Icons.history_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            session.isRunning
                                ? '游戏运行中 · ${session.lastInstanceName ?? ""}'
                                : '上次退出 code=${session.lastExitCode}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                LiquidGlass(
                  allowBackdrop: false,
                  borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
                  fillBoost: 0.05,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _EditionChip(
                              label: 'Java',
                              icon: Icons.desktop_windows_outlined,
                              selected: isJava,
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _edition = 'java'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _EditionChip(
                              label: '基岩',
                              icon: Icons.phone_android_outlined,
                              selected: !isJava,
                              onTap: _busy
                                  ? null
                                  : () {
                                      setState(() => _edition = 'bedrock');
                                      _refreshBedrock();
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isJava)
                        AppSelectField<String>(
                          value: instance?.id,
                          labelText: '选择版本 / 实例',
                          options: [
                            for (final e in store.items)
                              AppSelectOption(
                                value: e.id,
                                label:
                                    '${e.name} · ${e.gameVersion}${e.loaderType == 'fabric' ? ' Fabric' : ''}',
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (id) {
                                  if (id != null) store.select(id);
                                },
                        )
                      else
                        _bedrockCard(theme),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 280,
                  child: LiquidGlass(
                    allowBackdrop: false,
                    borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
                    fillBoost: 0.04,
                    child: const LaunchAccountPanel(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '快捷入口',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.35,
                  children: [
                    _QuickTile(
                      icon: Icons.folder_copy_outlined,
                      label: '实例',
                      onTap: () =>
                          _openFeature('实例', const InstancesPage()),
                    ),
                    _QuickTile(
                      icon: Icons.public_outlined,
                      label: '存档',
                      onTap: () =>
                          _openFeature('存档管理', const SavesPage()),
                    ),
                    _QuickTile(
                      icon: Icons.history_rounded,
                      label: '最近游戏',
                      onTap: () =>
                          _openFeature('最近游戏', const RecentGamesPage()),
                    ),
                    _QuickTile(
                      icon: Icons.videocam_outlined,
                      label: '录像',
                      onTap: () =>
                          _openFeature('录像', const RecordingsPage()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  onTap: _showLogsSheet,
                  child: LiquidGlass(
                    allowBackdrop: false,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    fillBoost: 0.04,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.terminal_rounded,
                            size: 18, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _logs.isEmpty
                                ? '启动日志 · 等待启动'
                                : '启动日志 · ${_logs.length} 行',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: FilledButton(
              onPressed: _busy ? null : _play,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _busy
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(playLabel),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          loadout.includeServer &&
                                  (loadout.serverAddress?.isNotEmpty ?? false)
                              ? Icons.login_rounded
                              : Icons.play_arrow_rounded,
                          size: 26,
                        ),
                        const SizedBox(width: 6),
                        Text(playLabel),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bedrockCard(ThemeData theme) {
    final scheme = theme.colorScheme;
    final info = _bedrock;
    final subtitle = _bedrockChecking
        ? '正在检测本机安装…'
        : info == null
            ? '未检测到微软商店基岩版（不提供版本体下载）'
            : '${info.label}'
                '${info.displayVersion != null ? ' · ${info.displayVersion}' : ''}'
                '\n将写入 options.txt 并协议启动';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        color: scheme.surface.withValues(alpha: 0.35),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              info == null
                  ? Icons.warning_amber_outlined
                  : Icons.check_circle_outline,
              size: 18,
              color: info == null ? scheme.error : scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
          IconButton(
            tooltip: '重新检测',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _busy ? null : _refreshBedrock,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      ),
    );
  }

  static Color _logLineColor(String line) {
    final lower = line.toLowerCase();
    if (line.contains('失败') ||
        line.contains('错误') ||
        lower.contains('error') ||
        lower.contains('exception') ||
        lower.contains('fail')) {
      return const Color(0xFFFF6B6B);
    }
    if (line.contains('完成') ||
        line.contains('已启动') ||
        lower.contains('success') ||
        lower.contains('done')) {
      return const Color(0xFF4ADE80);
    }
    if (line.contains('跳过') ||
        line.contains('警告') ||
        line.contains('不存在') ||
        lower.contains('warn')) {
      return const Color(0xFFFBBF24);
    }
    if (line.contains('下载') ||
        line.contains('安装') ||
        line.contains('同步') ||
        line.contains('获取') ||
        line.contains('解压') ||
        line.contains('资产') ||
        line.contains('载入')) {
      return const Color(0xFF60A5FA);
    }
    if (line.contains('启动命令') ||
        line.contains('使用 Java') ||
        line.contains('将直连') ||
        line.contains('皮肤')) {
      return const Color(0xFFC084FC);
    }
    return const Color(0xFFD1D5DB);
  }
}

class _EditionChip extends StatelessWidget {
  const _EditionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LiquidGlass(
      allowBackdrop: false,
      interactive: true,
      onTap: onTap,
      fillBoost: 0.05,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
