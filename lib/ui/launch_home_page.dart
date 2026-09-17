import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_manager.dart';
import '../core/bedrock/bedrock_install.dart';
import '../core/config/app_config.dart';
import '../core/game/game_instance.dart';
import '../core/game/launch_loadout.dart';
import '../core/game/launch_service.dart';
import '../core/game/mobile_launch_limits.dart';
import '../core/perf/game_session.dart';
import '../core/perf/launcher_sleep.dart';
import '../core/perf/perf_config.dart';
import 'app_theme.dart';
import 'glass/liquid_glass.dart';
import 'instances_page.dart';
import 'launch_feature_dialog.dart';
import 'recent_games_page.dart';
import 'recordings_page.dart';
import 'saves_page.dart';
import 'widgets/app_select_field.dart';
import 'widgets/home_banner_carousel.dart';
import 'widgets/launch_account_panel.dart';
import 'home_notice_host.dart';

/// 启动页：左侧轮播 + 账号；右侧日志 + 启动区。
/// 顶栏：实例 / 存档 / 最近游戏 / 录像；版本下载在侧栏「游戏资源」。
class LaunchHomePage extends StatefulWidget {
  const LaunchHomePage({super.key});

  @override
  State<LaunchHomePage> createState() => _LaunchHomePageState();
}

class _LaunchHomePageState extends State<LaunchHomePage> {
  /// java | bedrock
  String _edition = 'java';
  bool _busy = false;
  final _logs = <String>[];
  final _logScroll = ScrollController();
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
    _logScroll.dispose();
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
    void scrollToEnd() {
      if (!mounted || !_logScroll.hasClients) return;
      final max = _logScroll.position.maxScrollExtent;
      if (max <= 0) return;
      _logScroll.jumpTo(max);
    }

    // 等 ListView 完成布局后再滚；必要时再补一帧（SelectableText 高度稍后才稳定）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToEnd();
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollToEnd());
    });
  }

  Future<void> _play() async {
    if (_busy) return;
    if (_edition == 'bedrock') {
      await _playBedrock();
      return;
    }
    if (Platform.isIOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'iOS 暂未接入 Java 版。Android 请用内嵌虚拟键启动。',
          ),
        ),
      );
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
      // 游戏进程已起来：最小化休眠不挡出窗口（PowerShell 降优先级放到后台）
      if (cfg.launchMinimizeOnStart) {
        // ignore: unawaited_futures
        context.read<LauncherSleepController>().enter(onLog: _log);
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
      // 确保性能页最新配置可用
      context.read<PerfConfig>();
      await context.read<LaunchService>().launchBedrock(
            onLog: _log,
            loadout: loadout,
          );
      await _refreshBedrock();
      final cfg = context.read<AppConfig>();
      if (cfg.launchMinimizeOnStart) {
        // ignore: unawaited_futures
        context.read<LauncherSleepController>().enter(onLog: _log);
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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InstanceStore>();
    final loadout = context.watch<LaunchLoadout>();
    final session = context.watch<GameSession>();
    final instance = store.selected;
    final theme = Theme.of(context);
    final isJava = _edition == 'java';
    final compact = MediaQuery.sizeOf(context).width < 720;
    final pad = compact
        ? const EdgeInsets.fromLTRB(12, 10, 12, 12)
        : const EdgeInsets.fromLTRB(28, 20, 28, 24);

    return HomeNoticeHost(
      child: Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerBar(theme, compact: compact),
            if (session.isRunning || session.lastExitCode != null) ...[
              const SizedBox(height: 8),
              LiquidGlass(
                allowBackdrop: false,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                fillBoost: 0.03,
                child: Text(
                  session.isRunning
                      ? '游戏运行中 · ${session.lastInstanceName ?? ""} · pid=${session.pid}'
                      : '上次退出 code=${session.lastExitCode}'
                          '${session.lastDiagnosis != null && session.lastDiagnosis!.findings.isNotEmpty ? " · ${session.lastDiagnosis!.findings.first.title}" : ""}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: compact
                  ? _compactBody(
                      theme: theme,
                      store: store,
                      loadout: loadout,
                      instance: instance,
                      isJava: isJava,
                    )
                  : _wideBody(
                      theme: theme,
                      store: store,
                      loadout: loadout,
                      instance: instance,
                      isJava: isJava,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerBar(ThemeData theme, {required bool compact}) {
    if (compact) {
      return Row(
        children: [
          Expanded(
            child: Text('启动', style: theme.textTheme.titleLarge),
          ),
          IconButton(
            tooltip: '实例',
            onPressed: () => openLaunchFeatureDialog(
              context: context,
              title: '实例',
              child: const InstancesPage(),
            ),
            icon: const Icon(Icons.folder_copy_outlined),
          ),
          IconButton(
            tooltip: '存档',
            onPressed: () => openLaunchFeatureDialog(
              context: context,
              title: '存档管理',
              child: const SavesPage(),
            ),
            icon: const Icon(Icons.public_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) {
              switch (v) {
                case 'recent':
                  openLaunchFeatureDialog(
                    context: context,
                    title: '最近游戏',
                    child: const RecentGamesPage(),
                  );
                case 'record':
                  openLaunchFeatureDialog(
                    context: context,
                    title: '录像',
                    child: const RecordingsPage(),
                  );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'recent', child: Text('最近游戏')),
              PopupMenuItem(value: 'record', child: Text('录像')),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text('启动', style: theme.textTheme.headlineSmall),
        ),
        _toolbarBtn(
          icon: Icons.folder_copy_outlined,
          label: '实例',
          onPressed: () => openLaunchFeatureDialog(
            context: context,
            title: '实例',
            child: const InstancesPage(),
          ),
        ),
        _toolbarBtn(
          icon: Icons.public_outlined,
          label: '存档管理',
          onPressed: () => openLaunchFeatureDialog(
            context: context,
            title: '存档管理',
            child: const SavesPage(),
          ),
        ),
        _toolbarBtn(
          icon: Icons.history,
          label: '最近游戏',
          onPressed: () => openLaunchFeatureDialog(
            context: context,
            title: '最近游戏',
            child: const RecentGamesPage(),
          ),
        ),
        _toolbarBtn(
          icon: Icons.videocam_outlined,
          label: '录像',
          onPressed: () => openLaunchFeatureDialog(
            context: context,
            title: '录像',
            child: const RecordingsPage(),
          ),
        ),
      ],
    );
  }

  Widget _compactBody({
    required ThemeData theme,
    required InstanceStore store,
    required LaunchLoadout loadout,
    required GameInstance? instance,
    required bool isJava,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiquidGlass(
          allowBackdrop: false,
          borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
          fillBoost: 0.05,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: _launchControls(
            theme: theme,
            store: store,
            loadout: loadout,
            instance: instance,
            isJava: isJava,
            scrollable: false,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 3,
          child: LiquidGlass(
            allowBackdrop: false,
            borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
            fillBoost: 0.04,
            child: const LaunchAccountPanel(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 132,
          child: _logPanel(theme),
        ),
      ],
    );
  }

  Widget _wideBody({
    required ThemeData theme,
    required InstanceStore store,
    required LaunchLoadout loadout,
    required GameInstance? instance,
    required bool isJava,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 1,
                child: LiquidGlass(
                  allowBackdrop: false,
                  borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
                  fillBoost: 0.02,
                  child: const HomeBannerCarousel(),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                flex: 2,
                child: LiquidGlass(
                  allowBackdrop: false,
                  borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
                  fillBoost: 0.04,
                  child: const LaunchAccountPanel(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: _logPanel(theme)),
              const SizedBox(height: 10),
              Expanded(
                flex: 3,
                child: LiquidGlass(
                  allowBackdrop: false,
                  borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
                  fillBoost: 0.05,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: _launchControls(
                    theme: theme,
                    store: store,
                    loadout: loadout,
                    instance: instance,
                    isJava: isJava,
                    scrollable: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logPanel(ThemeData theme) {
    return LiquidGlass(
      allowBackdrop: false,
      borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
      fillBoost: 0.04,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              '启动日志',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          Expanded(
            child: Container(
              color: const Color(0xCC0F1419),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: ListView.builder(
                controller: _logScroll,
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
  }

  Widget _launchControls({
    required ThemeData theme,
    required InstanceStore store,
    required LaunchLoadout loadout,
    required GameInstance? instance,
    required bool isJava,
    required bool scrollable,
  }) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _editionBtn(
                label: 'Java 版',
                icon: Icons.desktop_windows_outlined,
                selected: isJava,
                onTap: _busy
                    ? null
                    : () {
                        if (Platform.isIOS) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'iOS 暂未接入 Java 版运行时',
                              ),
                            ),
                          );
                          return;
                        }
                        setState(() => _edition = 'java');
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _editionBtn(
                label: '基岩版',
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
        const SizedBox(height: 8),
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
          _bedrockStatusCard(theme),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _play,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  loadout.includeServer &&
                          (loadout.serverAddress?.isNotEmpty ?? false)
                      ? Icons.login_rounded
                      : Icons.play_arrow_rounded,
                ),
          label: Text(
            loadout.launchButtonLabel(isJava: isJava, busy: _busy),
            overflow: TextOverflow.ellipsis,
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            textStyle: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
    if (!scrollable) return SingleChildScrollView(child: body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: SingleChildScrollView(child: body)),
      ],
    );
  }

  Widget _toolbarBtn({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool emphasized = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fg = emphasized ? scheme.onPrimaryContainer : scheme.onSurface;
    final iconColor = emphasized ? scheme.primary : scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: LiquidGlass(
              allowBackdrop: false,
        interactive: true,
        onTap: onPressed,
        fillBoost: emphasized ? 0.14 : 0.06,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
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

  Widget _bedrockStatusCard(ThemeData theme) {
    final scheme = theme.colorScheme;
    final info = _bedrock;
    final subtitle = _bedrockChecking
        ? '正在检测本机安装…'
        : info == null
            ? (MobileLaunchLimits.isMobile
                ? '未检测到已安装的 Minecraft 基岩版（请先安装官方客户端）'
                : '未检测到微软商店基岩版（不提供版本体下载）')
            : '${info.label}'
                '${info.displayVersion != null ? ' · ${info.displayVersion}' : ''}'
                '\n${MobileLaunchLimits.isMobile ? '将唤起已安装的基岩版客户端' : '将写入 options.txt 并协议启动'}';
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

  Widget _editionBtn({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
