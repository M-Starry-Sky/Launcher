import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/bedrock/bedrock_install.dart';
import '../core/bedrock/bedrock_launcher.dart';
import '../core/game/game_instance.dart';
import '../core/game/java_runtime.dart';
import '../core/game/version_catalog.dart';
import '../core/perf/bedrock_render_presets.dart';
import '../core/perf/cache_cleaner.dart';
import '../core/perf/crash_diagnoser.dart';
import '../core/perf/fps_presets.dart';
import '../core/perf/gc_presets.dart';
import '../core/perf/java_env_adapter.dart';
import '../core/perf/jvm_args_preview.dart';
import '../core/perf/jvm_templates.dart';
import '../core/perf/memory_allocator.dart';
import '../core/perf/mod_conflict_scanner.dart';
import '../core/perf/perf_config.dart';
import '../core/perf/perf_config_codec.dart';
import '../core/perf/perf_mods_installer.dart';
import '../core/perf/perf_profiles.dart';
import '../core/perf/portable_java_installer.dart';
import '../core/perf/soft_memory_trim.dart';
import '../core/perf/game_session.dart';
import '../core/perf/launcher_sleep.dart';
import 'app_theme.dart';
import 'glass/liquid_glass.dart';

enum _PerfSection { overview, fps, memory, javaEnv, maintain, bedrock }

/// 性能页：分区导航，默认一屏一事，高级项收进高级模式。
class PerfCenterPage extends StatefulWidget {
  const PerfCenterPage({super.key, this.active = true});

  final bool active;

  @override
  State<PerfCenterPage> createState() => _PerfCenterPageState();
}

class _PerfCenterPageState extends State<PerfCenterPage> {
  final _customJvm = TextEditingController();
  _PerfSection _section = _PerfSection.overview;
  bool _installingJava = false;
  bool _installingMods = false;
  String? _javaStatus;
  String? _modsStatus;
  String? _maintainStatus;
  List<ModConflict> _conflicts = const [];
  CrashDiagnosis? _diagnosis;
  Timer? _hwTimer;
  bool _bootstrapped = false;

  static const _javaMenu = <(_PerfSection, String)>[
    (_PerfSection.overview, '概览'),
    (_PerfSection.fps, '帧率'),
    (_PerfSection.memory, '内存'),
    (_PerfSection.javaEnv, 'Java'),
    (_PerfSection.maintain, '维护'),
  ];

  static const _bedrockMenu = <(_PerfSection, String)>[
    (_PerfSection.bedrock, '渲染'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncActive());
  }

  @override
  void didUpdateWidget(covariant PerfCenterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncActive();
  }

  void _syncActive() {
    if (!mounted) return;
    if (widget.active) {
      _startHwTimer();
    } else {
      _hwTimer?.cancel();
      _hwTimer = null;
    }
  }

  Future<void> _startHwTimer() async {
    if (!mounted || !widget.active) return;
    if (!_bootstrapped) {
      _bootstrapped = true;
      final perf = context.read<PerfConfig>();
      _customJvm.text = perf.customJvmArgs;
      if (perf.hardware == null) await perf.refreshHardware();
      await _probeJava();
    }
    _hwTimer?.cancel();
    if (!mounted || !widget.active) return;
    if (context.read<LauncherSleepController>().isAsleep) return;
    _hwTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !widget.active) return;
      if (context.read<LauncherSleepController>().isAsleep) return;
      context.read<PerfConfig>().refreshHardware();
    });
  }

  @override
  void dispose() {
    _hwTimer?.cancel();
    _customJvm.dispose();
    super.dispose();
  }

  Future<void> _probeJava() async {
    final config = context.read<AppConfig>();
    final runtime = context.read<JavaRuntime>();
    try {
      final path = await runtime.findJava();
      final probe = await JavaEnvAdapter(config, runtime).probe(path);
      if (!mounted) return;
      setState(() {
        if (probe == null) {
          _javaStatus = '已找到 Java，但无法解析版本';
        } else {
          _javaStatus =
              '${probe.is64Bit ? '64 位' : '32 位'} · Java ${probe.major ?? '?'} · $path';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _javaStatus = '未找到 Java：$e');
    }
  }

  Future<void> _smartAdapt() async {
    final perf = context.read<PerfConfig>();
    final runtime = context.read<JavaRuntime>();
    int? major;
    try {
      final path = await runtime.findJava();
      major = await runtime.detectVersion(path);
    } catch (_) {}
    await perf.smartAdapt(javaMajor: major);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已适配：${perf.fps.preset.label} · ${perf.heapMb}M · ${perf.gcPreset.label}',
        ),
      ),
    );
  }

  Future<void> _installPerfMods() async {
    final store = context.read<InstanceStore>();
    final selected = store.selected;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择游戏实例')),
      );
      return;
    }
    var inst = selected;
    setState(() {
      _installingMods = true;
      _modsStatus = inst.loaderType == 'none'
          ? '原版实例：先挂载 Fabric，再装星穹优化…'
          : '正在安装星穹优化模组…';
    });
    try {
      if (inst.loaderType == 'none') {
        final loaders = await VersionCatalog(config: context.read<AppConfig>())
            .listFabricLoaders(inst.gameVersion);
        if (loaders.isEmpty) {
          throw StateError('未找到适用于 ${inst.gameVersion} 的 Fabric Loader');
        }
        inst = inst.copyWith(
          loaderType: 'fabric',
          loaderVersion: loaders.first,
        );
        await store.update(inst);
        if (mounted) {
          setState(() => _modsStatus = '已挂载 Fabric ${loaders.first}，安装星穹优化…');
        }
      }
      final modsDir = Directory('${store.instanceDir(inst).path}/mods');
      final result = await PerfModsInstaller(
        onLog: (l) {
          if (mounted) setState(() => _modsStatus = l);
        },
      ).install(
        gameVersion: inst.gameVersion,
        loaderType: inst.loaderType,
        modsDir: modsDir,
      );
      if (!mounted) return;
      setState(() {
        _modsStatus =
            '完成（${inst.gameVersion}）：成功 ${result.ok} · 跳过 ${result.skip} · 失败 ${result.fail}'
            '${PerfModsInstaller.supportsCoreHud(inst.gameVersion) ? '' : ' · 核心需MC≥1.20'}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_modsStatus!)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _modsStatus = '安装失败: $e');
    } finally {
      if (mounted) setState(() => _installingMods = false);
    }
  }

  Future<void> _installJava(int major) async {
    setState(() => _installingJava = true);
    try {
      final installer = PortableJavaInstaller();
      final path = await installer.ensure(major);
      await context.read<AppConfig>().set(AppConfig.keyJavaPath, path);
      await _probeJava();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Java $major 绿色包已就绪')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('安装失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _installingJava = false);
    }
  }

  void _onEditionChanged(PerfConfig perf, bool toJava) {
    perf.setEditionTab(toJava ? 'java' : 'bedrock');
    setState(() {
      _section = toJava ? _PerfSection.overview : _PerfSection.bedrock;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perf = context.watch<PerfConfig>();
    final isJava = perf.editionTab != 'bedrock';
    final menu = isJava ? _javaMenu : _bedrockMenu;
    final compact = MediaQuery.sizeOf(context).width < 720;
    if (!isJava && _section != _PerfSection.bedrock) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _section = _PerfSection.bedrock);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 24,
            compact ? 10 : 16,
            compact ? 14 : 24,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '性能',
                  style: compact
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.headlineSmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: perf.probing ? null : _smartAdapt,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(compact ? '适配' : '智能适配'),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 10 : 16, 10, compact ? 10 : 16, 0),
          child: Row(
            children: [
              Flexible(
                child: SegmentedButton<bool>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: true, label: Text('Java')),
                    ButtonSegment(value: false, label: Text('基岩')),
                  ],
                  selected: {isJava},
                  onSelectionChanged: (s) => _onEditionChanged(perf, s.first),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('高级'),
                selected: perf.advancedMode,
                visualDensity: VisualDensity.compact,
                onSelected: (v) => perf.setAdvancedMode(v),
              ),
            ],
          ),
        ),
        if (isJava)
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 10 : 16, 10, compact ? 10 : 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in menu)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item.$2),
                        selected: _section == item.$1,
                        onSelected: (_) =>
                            setState(() => _section = item.$1),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 20,
              14,
              compact ? 12 : 20,
              24,
            ),
            children: _body(perf, isJava),
          ),
        ),
      ],
    );
  }

  List<Widget> _body(PerfConfig perf, bool isJava) {
    if (!isJava) return _bedrockBody(perf);
    return switch (_section) {
      _PerfSection.overview => _overviewBody(perf),
      _PerfSection.fps => _fpsBody(perf),
      _PerfSection.memory => _memoryBody(perf),
      _PerfSection.javaEnv => _javaEnvBody(perf),
      _PerfSection.maintain => _maintainBody(perf),
      _PerfSection.bedrock => _bedrockBody(perf),
    };
  }

  // ─── 概览 ───────────────────────────────────────────

  List<Widget> _overviewBody(PerfConfig perf) {
    final hw = perf.hardware;
    final mem = perf.memoryRecommendation;
    final scheme = Theme.of(context).colorScheme;

    return [
      _card(
        '本机',
        [
          Row(
            children: [
              Expanded(
                child: Text(
                  hw == null
                      ? '尚未检测…'
                      : '${hw.totalMemoryMb} MB · ${hw.cpuLogicalCores} 核 · '
                          '${hw.likelySsd ? 'SSD' : 'HDD'} · '
                          '占用 ${(hw.memoryUsageRatio * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: '重新检测',
                visualDensity: VisualDensity.compact,
                onPressed:
                    perf.probing ? null : () => perf.refreshHardware(),
                icon: perf.probing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          if (hw != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: hw.memoryUsageRatio.clamp(0.0, 1.0),
                minHeight: 6,
              ),
            ),
          ],
          if (mem != null) ...[
            const SizedBox(height: 8),
            Text(
              '${mem.label} · 推荐堆 ${mem.recommendedMb}M',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('启动器性能模式'),
            subtitle: const Text('关闭玻璃动效，降低占用'),
            value: perf.launcherPerfMode,
            onChanged: (v) => perf.setLauncherPerfMode(v),
          ),
        ],
      ),
      _card(
        '场景档',
        [
          Text(
            '一键套用帧率 / 内存 / GC；细调请到对应分区。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in PerfProfileId.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: perf.activeProfile == p,
                  onSelected: (_) async {
                    await perf.applyProfile(p);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已套用「${p.label}」')),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
      _card(
        '当前生效',
        [
          _kv('帧率档', perf.fps.preset.label),
          _kv('堆内存', '${perf.heapMb}M'),
          _kv('GC', perf.gcPreset.label),
          _kv('JVM 模板', perf.jvmTemplate.label),
          Consumer<GameSession>(
            builder: (context, session, _) {
              if (!session.isRunning && session.lastExitCode == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  session.isRunning
                      ? '游戏运行中 · pid=${session.pid}'
                      : '上次退出 · code=${session.lastExitCode}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              );
            },
          ),
        ],
      ),
    ];
  }

  // ─── 帧率 ───────────────────────────────────────────

  List<Widget> _fpsBody(PerfConfig perf) {
    final fps = perf.fps;
    final scheme = Theme.of(context).colorScheme;
    return [
      _card(
        '帧率预设',
        [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in FpsPreset.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: fps.preset == p,
                  onSelected: (_) => perf.applyFpsPreset(p),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fps.preset.subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Text('视距 ${fps.renderDistance}'),
          Slider(
            value: fps.renderDistance.toDouble().clamp(2, 32),
            min: 2,
            max: 32,
            divisions: 30,
            label: '${fps.renderDistance}',
            onChanged: (v) =>
                perf.setFps(fps.copyWith(renderDistance: v.round())),
          ),
          Text('帧率上限 ${fps.maxFps >= 260 ? '无上限' : '${fps.maxFps}'}'),
          Slider(
            value: fps.maxFps.toDouble().clamp(30, 260),
            min: 30,
            max: 260,
            divisions: 46,
            label: fps.maxFps >= 260 ? '无上限' : '${fps.maxFps}',
            onChanged: (v) => perf.setFps(fps.copyWith(maxFps: v.round())),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('关闭垂直同步'),
            value: !fps.vsync,
            onChanged: (v) => perf.setFps(fps.copyWith(vsync: !v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('启动时写入 options.txt'),
            value: fps.applyOnLaunch,
            onChanged: (v) => perf.setFps(fps.copyWith(applyOnLaunch: v)),
          ),
        ],
      ),
      _card(
        '星穹优化',
        [
          Text(
            '一体化模组：帧率 / 小地图 / API，并补齐渲染加速依赖。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('启动时自动安装'),
            value: fps.autoInstallPerfMods,
            onChanged: (v) =>
                perf.setFps(fps.copyWith(autoInstallPerfMods: v)),
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: _installingMods ? null : _installPerfMods,
            icon: _installingMods
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download, size: 18),
            label: Text(_installingMods ? '安装中…' : '立即安装'),
          ),
          if (_modsStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              _modsStatus!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      if (perf.advancedMode)
        _card(
          '高级帧率',
          [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('激进 JVM 帧率旗标'),
              value: fps.aggressiveJvmFps,
              onChanged: (v) =>
                  perf.setFps(fps.copyWith(aggressiveJvmFps: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('进程高优先级'),
              value: fps.boostProcessPriority,
              onChanged: (v) =>
                  perf.setFps(fps.copyWith(boostProcessPriority: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('精美画面'),
              value: fps.fancyGraphics,
              onChanged: (v) =>
                  perf.setFps(fps.copyWith(fancyGraphics: v, fabulous: false)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('实体阴影'),
              value: fps.entityShadows,
              onChanged: (v) =>
                  perf.setFps(fps.copyWith(entityShadows: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('环境光遮蔽'),
              value: fps.ambientOcclusion,
              onChanged: (v) =>
                  perf.setFps(fps.copyWith(ambientOcclusion: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('全屏'),
              value: fps.fullscreen,
              onChanged: (v) => perf.setFps(fps.copyWith(fullscreen: v)),
            ),
          ],
        ),
    ];
  }

  // ─── 内存 ───────────────────────────────────────────

  List<Widget> _memoryBody(PerfConfig perf) {
    final mem = perf.memoryRecommendation ??
        const MemoryRecommendation(
          tier: MemoryTier.mid8g,
          recommendedMb: 2048,
          maxSafeMb: 3072,
          minMb: 1024,
          label: '中端',
          hint: '',
        );
    final heap = perf.heapMb.toDouble();
    final maxSlider = mem.maxSafeMb.toDouble();
    final minSlider = mem.minMb.toDouble();
    final scheme = Theme.of(context).colorScheme;

    return [
      _card(
        '堆内存',
        [
          Text(
            'Xms = Xmx = ${perf.heapMb}M'
            '${mem.hint.isEmpty ? '' : ' · ${mem.hint}'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          Slider(
            value: heap.clamp(minSlider, maxSlider),
            min: minSlider,
            max: maxSlider,
            divisions: ((maxSlider - minSlider) / 256).round().clamp(1, 48),
            label: '${perf.heapMb}M',
            onChanged: mem.tier == MemoryTier.low4g
                ? null
                : (v) => perf.setHeapMb(v.round()),
          ),
          Row(
            children: [
              Text(
                '推荐 ${mem.recommendedMb}M · 上限 ${mem.maxSafeMb}M',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              const Text('自动'),
              const SizedBox(width: 6),
              Switch(
                value: perf.autoMemory,
                onChanged: (v) => perf.setAutoMemory(v),
              ),
            ],
          ),
        ],
      ),
      _card(
        'GC',
        [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in GcPreset.values)
                      ChoiceChip(
                        label: Text(g.label),
                        selected: perf.gcPreset == g,
                        onSelected: (_) => perf.setGcPreset(g),
                      ),
                  ],
                ),
              ),
              const Text('自动'),
              const SizedBox(width: 6),
              Switch(
                value: perf.autoGc,
                onChanged: (v) => perf.setAutoGc(v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            perf.gcPreset.subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      _card(
        'JVM 模板',
        [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in JvmTemplate.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: perf.jvmTemplate == t,
                  onSelected: (_) => perf.setJvmTemplate(t),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            perf.jvmTemplate.hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('大型整合包元空间扩容'),
            value: perf.largeModpack,
            onChanged: (v) => perf.setLargeModpack(v),
          ),
          if (perf.advancedMode) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customJvm,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '自定义 JVM 参数',
                hintText: '空格分隔，启动时追加',
                isDense: true,
              ),
              onChanged: (v) => perf.setCustomJvmArgs(v),
            ),
            const SizedBox(height: 10),
            Text('即将生效', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(
              JvmArgsPreview.build(perf),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'Consolas',
                    fontFamilyFallback: const ['Courier New', 'monospace'],
                  ),
            ),
          ],
        ],
      ),
    ];
  }

  // ─── Java 环境 ───────────────────────────────────────

  List<Widget> _javaEnvBody(PerfConfig perf) {
    return [
      _card(
        '运行时',
        [
          Text(_javaStatus ?? '检测中…'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _installingJava ? null : () => _installJava(21),
                child: const Text('Java 21'),
              ),
              FilledButton.tonal(
                onPressed: _installingJava ? null : () => _installJava(17),
                child: const Text('Java 17'),
              ),
              if (perf.advancedMode)
                FilledButton.tonal(
                  onPressed: _installingJava ? null : () => _installJava(8),
                  child: const Text('Java 8'),
                ),
              OutlinedButton(
                onPressed: _probeJava,
                child: const Text('重新探测'),
              ),
            ],
          ),
          if (_installingJava) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(
              '正在下载绿色包（Adoptium Temurin）…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('启动时自动修复 Java'),
            subtitle: const Text('按游戏版本安装隔离 Temurin'),
            value: perf.autoFixJava,
            onChanged: (v) => perf.setAutoFixJava(v),
          ),
        ],
      ),
    ];
  }

  // ─── 维护 ───────────────────────────────────────────

  List<Widget> _maintainBody(PerfConfig perf) {
    final scheme = Theme.of(context).colorScheme;
    return [
      _card(
        '启动前',
        [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('弱冲突自动修复'),
            value: perf.autoFixSoftConflict,
            onChanged: (v) => perf.setAutoFixSoftConflict(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('强冲突阻止启动'),
            value: perf.blockOnModConflict,
            onChanged: (v) => perf.setBlockOnModConflict(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('清理日志 / 崩溃缓存'),
            value: perf.cleanCacheOnLaunch,
            onChanged: (v) => perf.setCleanCacheOnLaunch(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('收缩启动器工作集'),
            value: perf.trimLauncherOnLaunch,
            onChanged: (v) => perf.setTrimLauncherOnLaunch(v),
          ),
        ],
      ),
      _card(
        '工具',
        [
          _toolTile(
            Icons.delete_outline,
            '清理 Java 缓存',
            _cleanCacheNow,
          ),
          _toolTile(
            Icons.cleaning_services_outlined,
            '清理基岩临时缓存',
            _cleanBedrockCache,
          ),
          _toolTile(
            Icons.memory_outlined,
            '收缩启动器内存',
            () async {
              await SoftMemoryTrim.trimLauncher(
                onLog: (m) => setState(() => _maintainStatus = m),
              );
            },
          ),
          _toolTile(
            Icons.rule_folder_outlined,
            '扫描模组冲突',
            _scanConflicts,
          ),
          _toolTile(
            Icons.build_circle_outlined,
            '自动修复弱冲突',
            _autoFixSoftConflicts,
          ),
          _toolTile(
            Icons.bug_report_outlined,
            '分析最近崩溃',
            _diagnoseCrash,
          ),
          if (perf.advancedMode) ...[
            _toolTile(
              Icons.copy_outlined,
              '导出配置到剪贴板',
              () async {
                final json = PerfConfigCodec.exportJson(perf);
                await Clipboard.setData(ClipboardData(text: json));
                if (!mounted) return;
                setState(() => _maintainStatus = '性能配置已复制到剪贴板');
              },
            ),
            _toolTile(
              Icons.paste_outlined,
              '从剪贴板导入',
              () => _importPerfDialog(perf),
            ),
          ],
          if (_maintainStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              _maintainStatus!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (_conflicts.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final c in _conflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_conflictTag(c.severity)} ${c.title}\n${c.detail}\n→ ${c.suggestion}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          if (_diagnosis != null) ...[
            const SizedBox(height: 8),
            if (_diagnosis!.sourcePath != null)
              Text(
                '来源: ${_diagnosis!.sourcePath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            for (final f in _diagnosis!.findings)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${f.title}\n${f.detail}'
                  '${f.action != null ? '\n建议: ${f.action}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    ];
  }

  String _conflictTag(ConflictSeverity s) => switch (s) {
        ConflictSeverity.block => '[阻止]',
        ConflictSeverity.soft => '[可修]',
        ConflictSeverity.warn => '[警告]',
      };

  Widget _toolTile(IconData icon, String title, FutureOr<void> Function() onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => onTap(),
    );
  }

  // ─── 基岩 ───────────────────────────────────────────

  List<Widget> _bedrockBody(PerfConfig perf) {
    final b = perf.bedrock;
    final scheme = Theme.of(context).colorScheme;
    return [
      _card(
        '渲染预设',
        [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in BedrockRenderPreset.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: b.preset == p,
                  onSelected: (_) => perf.applyBedrockPreset(p),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            b.preset.subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          Text('渲染距离 ${b.renderDistance}'),
          Slider(
            value: b.renderDistance.toDouble().clamp(4, 32),
            min: 4,
            max: 32,
            divisions: 28,
            label: '${b.renderDistance}',
            onChanged: (v) =>
                perf.setBedrock(b.copyWith(renderDistance: v.round())),
          ),
          Text('帧率上限 ${b.maxFramerate == 0 ? '不限制' : b.maxFramerate}'),
          Slider(
            value: b.maxFramerate == 0 ? 260 : b.maxFramerate.toDouble(),
            min: 30,
            max: 260,
            divisions: 46,
            label: b.maxFramerate == 0 ? '不限制' : '${b.maxFramerate}',
            onChanged: (v) {
              final n = v.round();
              perf.setBedrock(b.copyWith(maxFramerate: n >= 260 ? 0 : n));
            },
          ),
        ],
      ),
      _card(
        '画面',
        [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('精美天空'),
            value: b.fancySkies,
            onChanged: (v) => perf.setBedrock(b.copyWith(fancySkies: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('精美画面'),
            value: b.fancyGraphics,
            onChanged: (v) => perf.setBedrock(b.copyWith(fancyGraphics: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('平滑光照'),
            value: b.smoothLighting,
            onChanged: (v) =>
                perf.setBedrock(b.copyWith(smoothLighting: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('垂直同步'),
            value: b.vsync,
            onChanged: (v) => perf.setBedrock(b.copyWith(vsync: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('全屏'),
            value: b.fullscreen,
            onChanged: (v) => perf.setBedrock(b.copyWith(fullscreen: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('多线程渲染'),
            value: b.multithreadedRenderer,
            onChanged: (v) =>
                perf.setBedrock(b.copyWith(multithreadedRenderer: v)),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _applyBedrockOptions(perf),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('写入 options.txt'),
          ),
        ],
      ),
    ];
  }

  // ─── 动作 ───────────────────────────────────────────

  Future<void> _cleanCacheNow() async {
    final store = context.read<InstanceStore>();
    final gameDir = store.sharedGameRoot();
    final report = await CacheCleaner.cleanGameDir(gameDir);
    final inst = store.selected;
    CacheCleanReport? instReport;
    if (inst != null) {
      instReport = await CacheCleaner.cleanInstance(store.instanceDir(inst));
    }
    if (!mounted) return;
    final totalFiles =
        report.filesDeleted + (instReport?.filesDeleted ?? 0);
    final totalMb =
        ((report.bytesFreed + (instReport?.bytesFreed ?? 0)) / (1024 * 1024))
            .toStringAsFixed(1);
    setState(() {
      _maintainStatus = totalFiles == 0
          ? '没有可清理的垃圾文件'
          : '已删除 $totalFiles 个文件，约释放 $totalMb MB';
    });
  }

  Future<void> _cleanBedrockCache() async {
    final report = await CacheCleaner.cleanBedrockTemps();
    if (!mounted) return;
    setState(() => _maintainStatus = '基岩: ${report.summary}');
  }

  Future<void> _scanConflicts() async {
    final store = context.read<InstanceStore>();
    final inst = store.selected;
    if (inst == null) {
      setState(() {
        _conflicts = [];
        _maintainStatus = '请先选择实例';
      });
      return;
    }
    final list = ModConflictScanner.scan(
      Directory('${store.instanceGameDir(inst).path}/mods'),
    );
    if (!mounted) return;
    setState(() {
      _conflicts = list;
      _maintainStatus = list.isEmpty ? '未发现已知互斥模组' : '发现 ${list.length} 项';
    });
  }

  Future<void> _autoFixSoftConflicts() async {
    final store = context.read<InstanceStore>();
    final inst = store.selected;
    if (inst == null) {
      setState(() => _maintainStatus = '请先选择实例');
      return;
    }
    final mods = Directory('${store.instanceGameDir(inst).path}/mods');
    final removed = ModConflictScanner.autoResolve(
      [mods],
      loaderType: inst.loaderType,
    );
    final list = ModConflictScanner.scan(mods);
    if (!mounted) return;
    setState(() {
      _conflicts = list;
      _maintainStatus = removed.isEmpty
          ? (list.isEmpty ? '无需修复' : '未能自动修复，仍剩 ${list.length} 项')
          : '已删除 ${removed.length} 个 jar：${removed.join(', ')}';
    });
  }

  Future<void> _diagnoseCrash() async {
    final store = context.read<InstanceStore>();
    final inst = store.selected;
    final root = inst != null
        ? store.instanceGameDir(inst)
        : store.sharedGameRoot();
    final d = await CrashDiagnoser.analyze(root);
    if (!mounted) return;
    setState(() {
      _diagnosis = d;
      _maintainStatus = '崩溃分析完成';
    });
  }

  Future<void> _importPerfDialog(PerfConfig perf) async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final initial = clip?.text?.trim() ?? '';
    if (!mounted) return;
    final controller = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入性能配置'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '粘贴含 xingqiong_perf 标记的 JSON',
              border: OutlineInputBorder(),
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
            child: const Text('导入'),
          ),
        ],
      ),
    );
    final raw = controller.text;
    controller.dispose();
    if (ok != true || !mounted) return;
    try {
      final changes = await PerfConfigCodec.importJson(perf, raw);
      if (!mounted) return;
      setState(() => _maintainStatus = changes.join('；'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入：${changes.join('；')}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
    }
  }

  Future<void> _applyBedrockOptions(PerfConfig perf) async {
    try {
      final install = await BedrockInstall.detect();
      if (install == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未检测到本机基岩版安装')),
        );
        return;
      }
      await BedrockLauncher().applyRenderSettings(install, perf.bedrock);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已写入 ${install.optionsFile.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写入失败: $e')),
      );
    }
  }

  // ─── 小组件 ─────────────────────────────────────────

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
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 88,
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
