import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_guard.dart';
import '../core/auth/platform_utils.dart';
import '../core/config/app_config.dart';
import '../core/game/game_instance.dart';
import '../core/perf/screen_recorder.dart';
import '../core/update/app_updater.dart';
import '../core/update/app_version.dart';
import '../core/update/github_update_service.dart';
import 'app_background.dart';
import 'app_theme.dart';
import 'glass/glass_tokens.dart';
import 'glass/liquid_glass.dart';
import 'open_local_directory.dart';
import 'pick_directory_path.dart';
import 'pick_image_path.dart';
import 'widgets/app_select_field.dart';

/// 设置页：横排二级菜单；本地配置开关打开才显示授权编辑栏（无后端只读栏）。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

enum _SettingsSection { appearance, source, runtime, download, tunnel, update }

class _SettingsPageState extends State<SettingsPage> {
  _SettingsSection _section = _SettingsSection.appearance;
  /// 本地授权下拉：microsoft | elyby
  String _localAuthProvider = 'microsoft';

  late final TextEditingController _gameDir;
  late final TextEditingController _gameBody;
  late final TextEditingController _java;
  late final TextEditingController _memory;
  late final TextEditingController _frpc;
  late final TextEditingController _localPort;
  late final TextEditingController _frpServerAddr;
  late final TextEditingController _frpServerPort;
  late final TextEditingController _frpToken;
  late final TextEditingController _frpRemotePort;
  late final TextEditingController _frpUser;
  late final TextEditingController _frpTlsServerName;
  late final TextEditingController _frpProtocol;
  late final TextEditingController _localMs;
  late final TextEditingController _localElyId;
  late final TextEditingController _localElySecret;
  late final TextEditingController _localElyPort;
  late final TextEditingController _mirrors;
  late final TextEditingController _recordDir;
  late final TextEditingController _ffmpeg;

  bool _checkingUpdate = false;
  bool _applyingUpdate = false;
  bool _preparingFfmpeg = false;
  UpdateCheckResult? _updateResult;

  static const _menu = <(_SettingsSection, String)>[
    (_SettingsSection.appearance, '外观'),
    (_SettingsSection.source, '配置来源'),
    (_SettingsSection.runtime, '运行环境'),
    (_SettingsSection.download, '下载加速'),
    (_SettingsSection.tunnel, '联机隧道'),
    (_SettingsSection.update, '版本更新'),
  ];

  @override
  void initState() {
    super.initState();
    final c = context.read<AppConfig>();
    _gameDir = TextEditingController(text: c.gameDataDir);
    _gameBody = TextEditingController(text: c.gameBodyDir);
    _java = TextEditingController(text: c.javaPath == 'java' ? '' : c.javaPath);
    _memory = TextEditingController(text: c.maxMemoryMb.toString());
    _frpc = TextEditingController(text: c.frpcPath);
    _localPort = TextEditingController(text: c.localServerPort.toString());
    _frpServerAddr = TextEditingController(text: c.frpServerAddr);
    _frpServerPort = TextEditingController(text: c.frpServerPort.toString());
    _frpToken = TextEditingController(text: c.frpToken);
    _frpRemotePort = TextEditingController(
      text: c.frpRemotePort > 0 ? c.frpRemotePort.toString() : '',
    );
    _frpUser = TextEditingController(text: c.frpUser);
    _frpTlsServerName = TextEditingController(text: c.frpTlsServerName);
    _frpProtocol = TextEditingController(text: c.frpProtocol);
    _localMs = TextEditingController(text: c.localMsClientId);
    _localElyId = TextEditingController(text: c.localElybyClientId);
    _localElySecret = TextEditingController(text: c.localElybyClientSecret);
    _localElyPort =
        TextEditingController(text: c.localElybyRedirectPort.toString());
    _mirrors = TextEditingController(text: c.downloadMirrorBasesRaw);
    _recordDir = TextEditingController(text: c.recordSaveDir);
    _ffmpeg = TextEditingController(text: c.ffmpegPath);
  }

  @override
  void dispose() {
    for (final c in [
      _gameDir,
      _gameBody,
      _java,
      _memory,
      _frpc,
      _localPort,
      _frpServerAddr,
      _frpServerPort,
      _frpToken,
      _frpRemotePort,
      _frpUser,
      _frpTlsServerName,
      _frpProtocol,
      _localMs,
      _localElyId,
      _localElySecret,
      _localElyPort,
      _mirrors,
      _recordDir,
      _ffmpeg,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final config = context.read<AppConfig>();
    await config.set(AppConfig.keyGameDataDir, _gameDir.text.trim());
    await config.set(AppConfig.keyGameBodyDir, _gameBody.text.trim());
    final java = _java.text.trim();
    await config.set(AppConfig.keyJavaPath, java.isEmpty ? 'java' : java);
    final mem = int.tryParse(_memory.text.trim());
    if (mem != null) await config.set(AppConfig.keyMaxMemoryMb, mem);
    await config.set(AppConfig.keyFrpcPath, _frpc.text.trim());
    final port = int.tryParse(_localPort.text.trim());
    if (port != null) await config.set(AppConfig.keyLocalServerPort, port);
    await config.set(AppConfig.keyFrpServerAddr, _frpServerAddr.text.trim());
    final frpPort = int.tryParse(_frpServerPort.text.trim());
    if (frpPort != null) await config.set(AppConfig.keyFrpServerPort, frpPort);
    await config.set(AppConfig.keyFrpToken, _frpToken.text.trim());
    final remote = int.tryParse(_frpRemotePort.text.trim());
    await config.set(AppConfig.keyFrpRemotePort, remote ?? 0);
    await config.set(AppConfig.keyFrpUser, _frpUser.text.trim());
    await config.set(AppConfig.keyFrpTlsServerName, _frpTlsServerName.text.trim());
    final proto = _frpProtocol.text.trim().isEmpty ? 'tcp' : _frpProtocol.text.trim();
    await config.set(AppConfig.keyFrpProtocol, proto);
    await config.set(AppConfig.keyDownloadMirrors, _mirrors.text.trim());
    await config.set(AppConfig.keyRecordSaveDir, _recordDir.text.trim());
    await config.set(AppConfig.keyFfmpegPath, _ffmpeg.text.trim());

    if (config.useLocalConfig) {
      await config.set(AppConfig.keyMsClientId, _localMs.text.trim());
      await config.set(AppConfig.keyElybyClientId, _localElyId.text.trim());
      await config.set(AppConfig.keyElybyClientSecret, _localElySecret.text);
      final elyPort = int.tryParse(_localElyPort.text.trim());
      if (elyPort != null) {
        await config.set(AppConfig.keyElybyRedirectPort, elyPort);
      }
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置已保存')));
    }
  }

  Future<void> _refreshRemote() async {
    await context.read<GlobalConfigProvider>().refresh();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已从后端拉取配置')));
      setState(() {});
    }
  }

  Future<void> _pickGameDir() async {
    final path = await pickDirectoryPath(context, title: '选择数据根目录');
    if (path == null || !mounted) return;
    setState(() => _gameDir.text = path);
  }

  Future<void> _pickGameBodyDir() async {
    final path = await pickDirectoryPath(context, title: '选择游戏本体下载目录');
    if (path == null || !mounted) return;
    setState(() => _gameBody.text = path);
  }

  Future<void> _openGameDir() async {
    final store = context.read<InstanceStore>();
    final root = _gameDir.text.trim().isNotEmpty
        ? _gameDir.text.trim()
        : store.dataRootPath();
    final ok = await openLocalDirectory(root);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开数据根目录')),
      );
    }
  }

  Future<void> _openGameBodyDir() async {
    final store = context.read<InstanceStore>();
    final body = _gameBody.text.trim().isNotEmpty
        ? _gameBody.text.trim()
        : store.sharedGameRoot().path;
    final ok = await openLocalDirectory(body);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开游戏本体目录')),
      );
    }
  }

  void _resetGameDir() {
    setState(() => _gameDir.text = '');
  }

  void _resetGameBodyDir() {
    setState(() => _gameBody.text = '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text('设置', style: theme.textTheme.headlineSmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in _menu) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(item.$2),
                      selected: _section == item.$1,
                      onSelected: (_) => setState(() => _section = item.$1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: _section == _SettingsSection.appearance
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: _buildAppearancePane(),
                )
              : _section == _SettingsSection.runtime
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: _buildRuntimePane(),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      children: [
                        ..._buildSectionBody(),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('保存设置'),
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  List<Widget> _buildSectionBody() {
    switch (_section) {
      case _SettingsSection.appearance:
        return const [];
      case _SettingsSection.source:
        return _sourceBody();
      case _SettingsSection.runtime:
        return const [];
      case _SettingsSection.download:
        return _downloadBody();
      case _SettingsSection.tunnel:
        final config = context.watch<AppConfig>();
        return [
          _card('联机隧道（OpenFRP / 自建 frp）', [
            Text(
              '填好后，开房可选「OpenFRP/自配」。好友用「中继:远程端口」即可加入，'
              'HMCL、PCL 等第三方启动器同样粘贴该地址。'
              '微软正版也可不填，改用「平台一键」。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            Text('1. 客户端', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _field('frpc 可执行文件路径', _frpc, hint: '例如 C:\\frp\\frpc.exe'),
            _field('房主本机游戏端口', _localPort, number: true, hint: '默认 25565'),
            const SizedBox(height: 14),
            Text('2. 中继服务器', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _field('中继地址 host', _frpServerAddr, hint: 'OpenFRP 节点域名'),
            _field('控制端口', _frpServerPort, number: true, hint: '常为 7000'),
            _field('Token', _frpToken, hint: '与面板 / frps auth.token 一致'),
            _field('User（OpenFRP 访问密钥）', _frpUser, hint: '可空；OpenFRP 常需填写'),
            const SizedBox(height: 14),
            Text('3. 端口映射', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _field(
              '远程映射端口',
              _frpRemotePort,
              number: true,
              hint: '好友用 中继地址:此端口 加入',
            ),
            const SizedBox(height: 14),
            Text('4. 传输（对齐 OpenFRP）', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _field('协议', _frpProtocol, hint: 'tcp / kcp / quic / websocket'),
            _field('TLS ServerName', _frpTlsServerName, hint: '开启 TLS 时可填'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用 TLS'),
              value: config.frpTlsEnable,
              onChanged: (v) => config.setBool(AppConfig.keyFrpTlsEnable, v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('传输加密 useEncryption'),
              value: config.frpUseEncryption,
              onChanged: (v) =>
                  config.setBool(AppConfig.keyFrpUseEncryption, v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('传输压缩 useCompression'),
              value: config.frpUseCompression,
              onChanged: (v) =>
                  config.setBool(AppConfig.keyFrpUseCompression, v),
            ),
          ]),
        ];
      case _SettingsSection.update:
        return _updateBody();
    }
  }

  List<Widget> _updateBody() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = _updateResult;
    String statusText = '尚未检查';
    if (_checkingUpdate) {
      statusText = '正在从 GitHub 校验…';
    } else if (r != null) {
      switch (r.status) {
        case UpdateStatus.upToDate:
          statusText = '已是最新（${r.remoteVersion ?? AppVersion.version}）';
        case UpdateStatus.updateAvailable:
          statusText =
              '发现新版本 ${r.remoteVersion}（当前 ${r.localVersion}）';
        case UpdateStatus.unavailable:
          statusText = r.message ?? '检查失败';
      }
    }
    return [
      _card('版本校验（GitHub）', [
        Text(
          '本地 ${AppVersion.version} · 源 ${AppVersion.githubOwner}/${AppVersion.githubRepo}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Text(statusText, style: theme.textTheme.bodyMedium),
        if (r != null &&
            r.hasUpdate &&
            r.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            r.notes.trim(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          '启动时会自动检查并拉取更新；也可在此手动检查 / 立即安装。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: (_checkingUpdate || _applyingUpdate)
                  ? null
                  : _checkGithubUpdate,
              icon: _checkingUpdate
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt),
              label: Text(_checkingUpdate ? '检查中…' : '检查更新'),
            ),
            if (r != null && r.hasUpdate) ...[
              FilledButton.tonalIcon(
                onPressed: _applyingUpdate ? null : () => _applyUpdate(r),
                icon: _applyingUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(_applyingUpdate ? '更新中…' : '立即更新'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final url = r.downloadUrl ?? r.releasePageUrl;
                  if (url == null || url.isEmpty) return;
                  await openUrlInBrowser(url);
                },
                icon: const Icon(Icons.open_in_browser),
                label: const Text('打开下载页'),
              ),
            ],
            TextButton(
              onPressed: () => openUrlInBrowser(AppVersion.githubRepoUrl),
              child: const Text('打开仓库'),
            ),
          ],
        ),
      ]),
    ];
  }

  Future<void> _checkGithubUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _updateResult = null;
    });
    try {
      final result = await GithubUpdateService().check();
      if (!mounted) return;
      setState(() {
        _updateResult = result;
        _checkingUpdate = false;
      });
      final tip = switch (result.status) {
        UpdateStatus.upToDate => '当前已是最新版本',
        UpdateStatus.updateAvailable =>
          '发现新版本 ${result.remoteVersion}',
        UpdateStatus.unavailable => result.message ?? '检查失败',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip)));
      if (result.hasUpdate) {
        await _applyUpdate(result);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingUpdate = false;
        _updateResult = UpdateCheckResult.unavailable('$e');
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('检查失败: $e')));
    }
  }

  Future<void> _applyUpdate(UpdateCheckResult result) async {
    if (_applyingUpdate || !result.hasUpdate) return;
    setState(() => _applyingUpdate = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppUpdater(
        onLog: (line) {
          if (!mounted) return;
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(content: Text(line), duration: const Duration(seconds: 4)),
          );
        },
      ).downloadAndApply(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _applyingUpdate = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('自动更新失败: $e'),
          action: SnackBarAction(
            label: '打开下载',
            onPressed: () {
              final url = result.downloadUrl ?? result.releasePageUrl;
              if (url == null || url.isEmpty) return;
              openUrlInBrowser(url);
            },
          ),
        ),
      );
    }
  }

  Future<void> _prepareFfmpegEnv() async {
    if (_preparingFfmpeg) return;
    setState(() => _preparingFfmpeg = true);
    final messenger = ScaffoldMessenger.of(context);
    final config = context.read<AppConfig>();
    try {
      final path = await ScreenRecorder.ensureFfmpeg(
        configured:
            _ffmpeg.text.trim().isEmpty ? null : _ffmpeg.text.trim(),
        onLog: (line) {
          if (!mounted) return;
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(content: Text(line), duration: const Duration(seconds: 4)),
          );
        },
      );
      if (!mounted) return;
      if (path != 'ffmpeg' && _ffmpeg.text.trim().isEmpty) {
        setState(() => _ffmpeg.text = path);
        await config.set(AppConfig.keyFfmpegPath, path);
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('录制环境就绪: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('准备录制环境失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _preparingFfmpeg = false);
    }
  }

  /* ---------- helpers below (appearance / runtime / etc.) ---------- */

  Widget _buildRuntimePane() {
    final store = context.watch<InstanceStore>();
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dataHint = InstanceStore.defaultDataRootHint();
    final dataEffective = _gameDir.text.trim().isNotEmpty
        ? _gameDir.text.trim()
        : store.dataRootPath();
    final bodyHint = store.defaultGameBodyHint();
    final bodyEffective = _gameBody.text.trim().isNotEmpty
        ? _gameBody.text.trim()
        : bodyHint;
    final wide = MediaQuery.sizeOf(context).width >= 980;

    final directories = _card(
      '目录',
      [
        Text(
          '数据根存放实例与皮肤；本体目录存放版本、库与资产（可单独放到大容量盘）。'
          '建议纯英文路径。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        _pathSettingBlock(
          title: '数据根目录',
          subtitle: 'instances / skins',
          controller: _gameDir,
          hintText: '留空则使用默认：$dataHint',
          effectivePath: dataEffective,
          onBrowse: _pickGameDir,
          onOpen: _openGameDir,
          onReset: _resetGameDir,
        ),
        const SizedBox(height: 16),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        _pathSettingBlock(
          title: '游戏本体下载目录',
          subtitle: 'versions / libraries / assets / natives',
          controller: _gameBody,
          hintText: '留空则使用：$bodyHint',
          effectivePath: bodyEffective,
          onBrowse: _pickGameBodyDir,
          onOpen: _openGameBodyDir,
          onReset: _resetGameBodyDir,
          emphasize: true,
        ),
      ],
    );

    final javaCard = _card(
      'Java 与内存',
      [
        _field(
          'Java 路径',
          _java,
          hint: '留空则按游戏版本使用隔离绿色 JDK',
        ),
        _field('堆内存 (MB)', _memory, number: true, hint: 'Xms 与 Xmx 相同'),
        Text(
          'GC / 基岩渲染 / 一键适配请到侧栏「性能」页。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final launchCard = _card(
      '启动行为',
      [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启动完成后最小化并休眠'),
          subtitle: const Text(
            '游戏起来后收起启动器，关闭玻璃特效、降优先级并收缩内存，少抢游戏资源；游戏退出后自动唤醒',
          ),
          value: config.launchMinimizeOnStart,
          onChanged: (v) => config.setBool(
            AppConfig.keyLaunchMinimizeOnStart,
            v,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('游戏悬浮窗（帧率 / 服务器 / 世界）'),
          subtitle: const Text(
            '置顶半透明；默认可点按钮，图钉可切换穿透',
          ),
          value: config.gameHudOverlay,
          onChanged: (v) => config.setBool(
            AppConfig.keyGameHudOverlay,
            v,
          ),
        ),
      ],
    );

    final recordCard = _card(
      '视频录制',
      [
        Text(
          '悬浮窗一键录游戏窗口，可带系统声/麦克风；F9 开始或停止。'
          '未检测到 FFmpeg 时会自动下载绿色运行时。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        _pathSettingBlock(
          title: '录像保存目录',
          subtitle: '留空则用「视频/XingqiongRecordings」',
          controller: _recordDir,
          hintText: '例如 D:\\Videos\\Xingqiong',
          effectivePath: _recordDir.text.trim().isNotEmpty
              ? _recordDir.text.trim()
              : '（默认系统视频目录）',
          onBrowse: () async {
            final path = await pickDirectoryPath(context, title: '选择录像保存目录');
            if (path != null) setState(() => _recordDir.text = path);
          },
          onOpen: () async {
            final path = _recordDir.text.trim();
            if (path.isEmpty) return;
            await openLocalDirectory(path);
          },
          onReset: () => setState(() => _recordDir.clear()),
        ),
        const SizedBox(height: 12),
        _field(
          'FFmpeg 路径',
          _ffmpeg,
          hint: '留空则自动探测 / 下载绿色 FFmpeg',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _preparingFfmpeg ? null : _prepareFfmpegEnv,
            icon: _preparingFfmpeg
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.movie_creation_outlined),
            label: Text(_preparingFfmpeg ? '准备中…' : '准备录制环境'),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('录制系统声音'),
          subtitle: const Text('默认开启；不可用时自动降级为无声画面'),
          value: config.recordSystemAudio,
          onChanged: (v) => config.setBool(AppConfig.keyRecordSystemAudio, v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('录制麦克风'),
          subtitle: const Text('旁白讲解用，默认关闭'),
          value: config.recordMic,
          onChanged: (v) => config.setBool(AppConfig.keyRecordMic, v),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('录制帧率'),
          subtitle: Text('当前 ${config.recordFps} FPS'),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 30, label: Text('30')),
              ButtonSegment(value: 60, label: Text('60')),
            ],
            selected: {config.recordFps >= 60 ? 60 : 30},
            onSelectionChanged: (s) =>
                config.set(AppConfig.keyRecordFps, s.first),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('运行环境', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '分开配置数据根与游戏本体下载位置，避免把大体积版本文件塞进系统盘。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: ListView(
                        children: [directories],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: ListView(
                        children: [
                          javaCard,
                          launchCard,
                          recordCard,
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              onPressed: _save,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('保存设置'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView(
                  children: [
                    directories,
                    javaCard,
                    launchCard,
                    recordCard,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('保存设置'),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _pathSettingBlock({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hintText,
    required String effectivePath,
    required VoidCallback onBrowse,
    required VoidCallback onOpen,
    required VoidCallback onReset,
    bool emphasize = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              emphasize ? Icons.download_outlined : Icons.folder_outlined,
              size: 18,
              color: emphasize ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: emphasize ? scheme.primary : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onBrowse,
              child: const Text('浏览'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '当前生效',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          effectivePath,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('打开目录'),
            ),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('恢复默认'),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _downloadBody() {
    final config = context.watch<AppConfig>();
    return [
      _card(
        '加速通道',
        [
          _sectionLabel('选项'),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用下载加速'),
            subtitle: const Text(
              '对齐 HMCL：本体走 BMCLAPI 第三方镜像，模组走 MCIM；'
              '中国大陆（手机/PC）默认镜像优先，官方仅回落',
            ),
            value: config.downloadAccelEnabled,
            onChanged: (v) => config.setBool(AppConfig.keyDownloadAccel, v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('局域网节点互传'),
            subtitle: const Text(
              '同网段按 SHA1 互传缓存（桌面默认开；手机默认关）',
            ),
            value: config.downloadPeerEnabled,
            onChanged: config.downloadAccelEnabled
                ? (v) => config.setBool(AppConfig.keyDownloadPeer, v)
                : null,
          ),
        ],
      ),
      _card(
        '镜像列表',
        [
          Text(
            '逗号分隔镜像根地址；留空使用内置 BMCLAPI（bmclapi2 / bmclapi）。'
            '与 HMCL、PCL 同一套第三方下载源；手机与 PC 共用。'
            '模组另走 MCIM（mod.mcimirror.top）。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          _field(
            '镜像 Base URL',
            _mirrors,
            hint: 'https://bmclapi2.bangbang93.com, …',
          ),
        ],
      ),
    ];
  }

  Widget _buildAppearancePane() {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = AppTheme.parseThemeMode(config.themeModeRaw);
    final glass = GlassModeX.parse(config.glassModeRaw);
    final bg = config.backgroundImagePath;
    final locale = Localizations.localeOf(context);
    final localeLabel = _systemLocaleLabel(locale);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: LiquidGlassCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: ListView(
              children: [
                Text('显示与材质', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '左侧调选项，右侧即时预览背景效果。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel('主题模式'),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('跟随系统'),
                      icon: Icon(Icons.brightness_auto, size: 16),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('浅色'),
                      icon: Icon(Icons.light_mode_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('深色'),
                      icon: Icon(Icons.dark_mode_outlined, size: 16),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) async {
                    await config.set(
                      AppConfig.keyThemeMode,
                      AppTheme.themeModeKey(s.first),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _sectionLabel('软件语言'),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.translate_rounded,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '跟随系统',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '当前系统：$localeLabel',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.lock_outline,
                          size: 16, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel('液态玻璃'),
                const SizedBox(height: 4),
                Text(
                  '透射模糊与虹彩描边；低配可选「纯净」。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in GlassMode.values)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: glass == m,
                        onSelected: (_) async {
                          await config.set(
                            AppConfig.keyGlassMode,
                            m.storageKey,
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  glass.hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 7,
          child: LiquidGlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('背景预览', style: theme.textTheme.titleMedium),
                    ),
                    Text(
                      bg.isEmpty ? '内置默认' : '自定义',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (bg.isNotEmpty)
                          Image.file(
                            File(bg),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: const Center(child: Text('预览失败')),
                            ),
                          )
                        else
                          const Image(
                            image: AssetImage(kDefaultBackgroundAsset),
                            fit: BoxFit.cover,
                          ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: LiquidGlass(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                              child: Text(
                                '预览当前玻璃材质 · ${glass.label}',
                                style: theme.textTheme.labelLarge,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (bg.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    bg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => _pickBackground(config),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('上传背景图'),
                    ),
                    const SizedBox(width: 8),
                    if (bg.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await config.set(
                            AppConfig.keyBackgroundImagePath,
                            '',
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已恢复默认背景')),
                            );
                          }
                        },
                        icon: const Icon(Icons.hide_image_outlined),
                        label: const Text('恢复默认'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  String _systemLocaleLabel(Locale locale) {
    switch (locale.languageCode) {
      case 'zh':
        if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') {
          return '中文（繁体）';
        }
        return '中文（简体）';
      case 'en':
        return 'English';
      default:
        final tag = locale.toLanguageTag();
        return tag.isEmpty ? locale.languageCode : tag;
    }
  }

  Future<void> _pickBackground(AppConfig config) async {
    final path = await pickImagePath(context);
    if (path == null || !mounted) return;
    try {
      await AppBackground.savePickedImage(config, path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('背景图已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置失败: $e')),
        );
      }
    }
  }

  List<Widget> _sourceBody() {
    final config = context.watch<AppConfig>();
    final useLocal = config.useLocalConfig;

    return [
      _card(
        '使用方式',
        [
          _sectionLabel('配置来源'),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('使用本地配置'),
            subtitle: Text(
              useLocal
                  ? '已开启：使用下方本地授权字段'
                  : '已关闭：登录直接使用远程配置，不显示本地字段',
            ),
            value: useLocal,
            onChanged: (v) async {
              await config.setBool(AppConfig.keyUseLocalAuthOverride, v);
              if (v == false) await _refreshRemote();
            },
          ),
        ],
      ),
      if (useLocal)
        _card(
          '本地授权',
          [
            _sectionLabel('授权平台'),
            const SizedBox(height: 6),
            AppSelectField<String>(
              value: _localAuthProvider,
              options: const [
                AppSelectOption(value: 'microsoft', label: '微软'),
                AppSelectOption(value: 'elyby', label: 'Ely.by'),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _localAuthProvider = v);
              },
            ),
            const SizedBox(height: 12),
            if (_localAuthProvider == 'microsoft') ...[
              _field('微软 Client ID', _localMs),
              const SizedBox(height: 6),
              Text(
                '可留空或填 Xbox 公共 ID 00000000402b5328（浏览器授权）。'
                '填 Azure 应用 GUID 则走设备码。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_localAuthProvider == 'elyby') ...[
              _field('Ely.by Client ID', _localElyId),
              _field('Ely.by Client Secret', _localElySecret, obscure: true),
              _field('Ely.by 回调端口', _localElyPort, number: true),
            ],
          ],
        ),
    ];
  }

  Widget _card(String title, List<Widget> children) {
    return LiquidGlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  /// 标题在输入框上方（不用浮动 label）。
  Widget _field(
    String label,
    TextEditingController c, {
    bool obscure = false,
    bool number = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(label),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            obscureText: obscure,
            keyboardType: number ? TextInputType.number : null,
            inputFormatters:
                number ? [FilteringTextInputFormatter.digitsOnly] : null,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}
