import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/auth/platform_utils.dart';
import '../core/dev/mod_dev_controller.dart';
import '../core/dev/perf_mod_source.dart';
import 'app_theme.dart';
import 'glass/liquid_glass.dart';
import 'open_local_directory.dart';
import 'pick_directory_path.dart';

/// 模组开发工作台：源码获取 + jar 同步 + 运行时遥控 API。
/// 作为实验室二级页时设 [embeddedInLab]。
class ModDevPage extends StatefulWidget {
  const ModDevPage({
    super.key,
    this.active = true,
    this.embeddedInLab = false,
  });

  final bool active;
  final bool embeddedInLab;

  @override
  State<ModDevPage> createState() => _ModDevPageState();
}

class _ModDevPageState extends State<ModDevPage> {
  late final TextEditingController _watchCtrl;
  bool _sourceBusy = false;
  String? _sourceStatus;
  String? _exportedSourcePath;

  static const _dependsSnippet =
      '"depends": { "xingqiong-perf": ">=0.4.0" }';

  static const _combatSnippet =
      'import com.xingqiong.hud.api.XingqiongPerfApi;\n'
      'import net.minecraft.entity.LivingEntity;\n'
      '\n'
      'XingqiongPerfApi.setDamageNumbersEnabled(true);\n'
      'XingqiongPerfApi.setEntityHealthBarsEnabled(true);\n'
      '\n'
      'XingqiongPerfApi.addDamageListener((LivingEntity e, Float delta) -> {\n'
      '    if (delta > 0) {\n'
      '        XingqiongPerfApi.spawnDamageNumber(e.getX(), e.getBodyY(1), e.getZ(), delta);\n'
      '    }\n'
      '});';

  static const _markerSnippet =
      'import com.xingqiong.hud.api.MarkerKind;\n'
      'import com.xingqiong.hud.api.XingqiongPerfApi;\n'
      '\n'
      'XingqiongPerfApi.addPlayerMarker(\n'
      '    null, "据点", MarkerKind.VILLAGE,\n'
      '    x, y, z, "minecraft:overworld"\n'
      ');';

  @override
  void initState() {
    super.initState();
    final c = context.read<ModDevController>();
    _watchCtrl = TextEditingController(text: c.watchDir);
    final local = PerfModSource.resolveLocalSource();
    if (local != null) _exportedSourcePath = local.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ModDevController>().startPolling();
    });
  }

  @override
  void didUpdateWidget(covariant ModDevPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final c = context.read<ModDevController>();
    if (widget.active && !oldWidget.active) {
      c.startPolling();
    } else if (!widget.active && oldWidget.active) {
      c.stopPolling();
    }
  }

  @override
  void dispose() {
    _watchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickWatchDir() async {
    final path =
        await pickDirectoryPath(context, title: '选择模组输出目录（如 build/libs）');
    if (path == null || !mounted) return;
    _watchCtrl.text = path;
    await context.read<ModDevController>().setWatchDir(path);
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制「$label」')),
    );
  }

  Future<void> _downloadSource({bool forceNetwork = false}) async {
    setState(() {
      _sourceBusy = true;
      _sourceStatus = forceNetwork ? '正在从 GitHub 下载…' : '正在获取源码…';
    });
    try {
      final dir = await PerfModSource.obtainSource(
        preferLocalCopy: !forceNetwork,
        onLog: (m) {
          if (mounted) setState(() => _sourceStatus = m);
        },
      );
      if (!mounted) return;
      setState(() {
        _exportedSourcePath = dir.path;
        _sourceStatus = '已就绪：${dir.path}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('源码已保存到 ${dir.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sourceStatus = '失败：$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取源码失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _sourceBusy = false);
    }
  }

  Future<void> _openSourceFolder() async {
    final path = _exportedSourcePath ?? PerfModSource.resolveLocalSource()?.path;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先下载源码')),
      );
      return;
    }
    final ok = await openLocalDirectory(path);
    if (!mounted) return;
    if (!ok) {
      // 手机上文件管理器常打不开：复制路径并提示
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制路径（可手动打开文件管理）：$path')),
      );
    }
  }

  Future<void> _openGithub() async {
    try {
      await openUrlInBrowser(PerfModSource.githubTreeUrl);
    } catch (e) {
      await Clipboard.setData(
        ClipboardData(text: PerfModSource.githubTreeUrl),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 GitHub 链接（$e）')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.watch<ModDevController>();
    final inst = c.currentInstance;
    final previewReady = c.channelOnline;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final pad = compact
        ? const EdgeInsets.fromLTRB(12, 12, 12, 24)
        : const EdgeInsets.fromLTRB(20, 16, 20, 28);

    return ListView(
      padding: pad,
      children: [
        if (!widget.embeddedInLab) ...[
          Text(
            '模组开发工作台',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          '获取星穹优化源码做二次开发，或监视本地 jar 同步到实例并用命令通道遥控 API。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),

        // ── 源码 ──
        _card(
          title: '星穹优化源码',
          subtitle:
              '许可证 ${PerfModSource.license} · 开放二次开发与深度优化 · $modHint',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                PerfModSource.apiDocHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              if (_exportedSourcePath != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(
                    _exportedSourcePath!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const ['monospace'],
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _sourceBusy ? null : () => _downloadSource(),
                    icon: _sourceBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download, size: 18),
                    label: Text(_sourceBusy ? '获取中…' : '下载源码到本机'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _sourceBusy
                        ? null
                        : () => _downloadSource(forceNetwork: true),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('强制从 GitHub 拉取'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openSourceFolder,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('打开源码目录'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openGithub,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('GitHub 查看'),
                  ),
                ],
              ),
              if (_sourceStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  _sourceStatus!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '构建：进入源码目录执行 build_and_copy.ps1（或 gradlew build），'
                '产物 jar 可用下方「同步」拷进实例 mods。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // ── 环境 ──
        _card(
          title: '环境',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statusRow(
                '实例',
                inst == null
                    ? '未选择'
                    : '${inst.name} · ${inst.gameVersion} ${inst.loaderType}',
              ),
              _statusRow(
                '目标版本',
                c.isFabric1201 ? 'Fabric 1.20.1 可用' : '星穹核心目前针对 Fabric 1.20.1',
                warn: !c.isFabric1201,
              ),
              _statusRow(
                '核心 jar',
                c.coreJarInstalled ? '已在实例 mods' : '未安装',
                warn: !c.coreJarInstalled,
              ),
              _statusRow(
                '开发通道',
                c.channelOnline
                    ? '在线 · FPS ${c.hudFps ?? '…'}'
                    : '离线（进世界后才会上线）',
                warn: !c.channelOnline,
              ),
              if (c.lastAckMessage != null)
                _statusRow(
                  '回执',
                  '#${c.lastAckSeq} ${c.lastAckOk == true ? 'OK' : 'FAIL'} · ${c.lastAckMessage}',
                ),
              if (c.statusMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  c.statusMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () => c.ensureCoreInstalled(),
                  child: const Text('确保星穹核心已安装'),
                ),
              ),
            ],
          ),
        ),

        // ── 同步 ──
        _card(
          title: 'Jar 同步',
          subtitle: '监视 build/libs，变更后拷到当前实例 mods/',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _watchCtrl,
                decoration: InputDecoration(
                  labelText: '监视目录',
                  hintText: r'例如 …\xingqiong-perf-src\build\libs',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: '选择目录',
                    onPressed: _pickWatchDir,
                    icon: const Icon(Icons.folder_open),
                  ),
                ),
                onSubmitted: (v) => c.setWatchDir(v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('自动同步'),
                value: c.autoSync,
                onChanged: (v) => c.setAutoSync(v),
              ),
              _statusRow(
                '最近同步',
                c.lastSyncedJar == null
                    ? '无'
                    : '${c.lastSyncedJar} · ${_fmtTime(c.lastSyncedAt)}',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: c.watching
                        ? () => c.stopWatch()
                        : () async {
                            await c.setWatchDir(_watchCtrl.text);
                            await c.startWatch();
                          },
                    child: Text(c.watching ? '停止监视' : '开始监视'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await c.setWatchDir(_watchCtrl.text);
                      await c.syncNewestJar();
                    },
                    child: const Text('立即同步'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      final dir = c.instanceModsDir();
                      if (dir == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请先选择实例')),
                        );
                        return;
                      }
                      openLocalDirectory(dir.path);
                    },
                    child: const Text('打开 mods'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 预览 ──
        _card(
          title: '实时预览',
          subtitle: previewReady
              ? null
              : '先启动带星穹优化的 Fabric 1.20.1 实例并进入世界',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('伤害跳字'),
                value: c.hudDamageNumbers ?? true,
                onChanged: previewReady ? (v) => c.setDamageNumbers(v) : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('生物血条'),
                value: c.hudHealthBars ?? true,
                onChanged: previewReady ? (v) => c.setHealthBars(v) : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('小地图'),
                value: c.hudMinimap ?? true,
                onChanged: previewReady ? (v) => c.setMinimap(v) : null,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: previewReady ? () => c.spawnTestDamage() : null,
                    child: const Text('测试跳字'),
                  ),
                  OutlinedButton(
                    onPressed: previewReady ? () => c.addTestMarker() : null,
                    child: const Text('测试标记'),
                  ),
                  OutlinedButton(
                    onPressed: previewReady ? () => c.clearMarkers() : null,
                    child: const Text('清空标记'),
                  ),
                  OutlinedButton(
                    onPressed: previewReady ? () => c.ping() : null,
                    child: const Text('Ping'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── API（可折叠）──
        _card(
          title: 'API 速查',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copy('depends', _dependsSnippet),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('depends'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy('战斗示例', _combatSnippet),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('战斗示例'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy('标记示例', _markerSnippet),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('标记示例'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '查看代码片段',
                  style: theme.textTheme.titleSmall,
                ),
                children: const [
                  _CodeBlock(title: 'depends', code: _dependsSnippet),
                  SizedBox(height: 8),
                  _CodeBlock(title: '战斗示例', code: _combatSnippet),
                  SizedBox(height: 8),
                  _CodeBlock(title: '标记示例', code: _markerSnippet),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const modHint = '模组 ID：xingqiong-perf';

  Widget _card({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return LiquidGlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _statusRow(String k, String v, {bool warn = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              k,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: warn ? scheme.error : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtTime(DateTime? t) {
    if (t == null) return '';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _CodeBlock extends StatelessWidget {
  final String title;
  final String code;

  const _CodeBlock({required this.title, required this.code});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: SelectableText(
            code,
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12,
              height: 1.35,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
