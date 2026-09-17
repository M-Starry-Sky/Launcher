import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/game/game_instance.dart';
import '../core/pack/local_pack_store.dart';
import '../models/pack.dart';
import '../services/pack_service.dart';
import 'dialog_guard.dart';
import 'pick_file_path.dart';
import 'widgets/modrinth_browser.dart';

/// 整合包管理：列表 / 创建（可带 Modrinth 模组）/ 分享码导入 / 清单编辑。
class PackPage extends StatefulWidget {
  const PackPage({super.key});

  @override
  State<PackPage> createState() => _PackPageState();
}

class _PackPageState extends State<PackPage> {
  List<PackSummary>? _packs;
  List<LocalPackInfo> _localPacks = const [];
  Set<String> _installedIds = {};
  bool _expandInstalled = true;
  bool _expandPending = true;
  String? _error;
  final _dialogGuard = DialogGuard();
  final _localStore = LocalPackStore();

  static const _prefsInstalledKey = 'pack_installed_ids';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _loadInstalledIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsInstalledKey) ?? const [];
    _installedIds = raw.toSet();
  }

  Future<void> _markInstalled(String id, {bool installed = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (installed) {
      _installedIds.add(id);
    } else {
      _installedIds.remove(id);
    }
    await prefs.setStringList(_prefsInstalledKey, _installedIds.toList());
    if (mounted) setState(() {});
  }

  Directory? _instanceModsDir() {
    final store = context.read<InstanceStore>();
    final inst = store.selected;
    if (inst == null) return null;
    return Directory(p.join(store.instanceDir(inst).path, 'mods'));
  }

  bool _localLooksInstalled(LocalPackInfo lp) {
    if (_installedIds.contains(lp.id)) return true;
    final modsDir = _instanceModsDir();
    if (modsDir == null || !modsDir.existsSync() || lp.modFiles.isEmpty) {
      return false;
    }
    final names = modsDir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path).toLowerCase())
        .toSet();
    var hit = 0;
    for (final m in lp.modFiles) {
      if (names.contains(m.toLowerCase())) hit++;
    }
    return hit > 0 && hit >= (lp.modFiles.length + 1) ~/ 2;
  }

  Future<void> _reload() async {
    try {
      await _loadInstalledIds();
      final local = await _localStore.list();
      List<PackSummary> remote = const [];
      try {
        remote = await context.read<PackService>().list();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _localPacks = local;
          _packs = remote;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _buildBody(context)),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('制作 / 导入'),
            onPressed: _dialogGuard.isLocked ? null : () => _showActions(context),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null && _packs == null && _localPacks.isEmpty) {
      return Center(child: Text('加载失败：$_error'));
    }
    final packs = _packs;
    if (packs == null && _localPacks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final remote = packs ?? const <PackSummary>[];
    if (remote.isEmpty && _localPacks.isEmpty) {
      return const Center(child: Text('暂无整合包，点击右下角「制作 / 导入」'));
    }

    final installedLocal =
        _localPacks.where(_localLooksInstalled).toList(growable: false);
    final pendingLocal = _localPacks
        .where((e) => !_localLooksInstalled(e))
        .toList(growable: false);
    final installedRemote = remote
        .where((e) => _installedIds.contains(e.packId))
        .toList(growable: false);
    final pendingRemote = remote
        .where((e) => !_installedIds.contains(e.packId))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: [
        ExpansionTile(
          initiallyExpanded: _expandInstalled,
          onExpansionChanged: (v) => setState(() => _expandInstalled = v),
          leading: Icon(Icons.check_circle_outline,
              color: Theme.of(context).colorScheme.primary),
          title: Text(
            '已安装（${installedLocal.length + installedRemote.length}）',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('已写入当前实例或已标记安装'),
          children: [
            if (installedLocal.isEmpty && installedRemote.isEmpty)
              const ListTile(dense: true, title: Text('暂无已安装整合包')),
            for (final lp in installedLocal) _localTile(lp, installed: true),
            for (final pack in installedRemote)
              _remoteTile(pack, installed: true),
          ],
        ),
        ExpansionTile(
          initiallyExpanded: _expandPending,
          onExpansionChanged: (v) => setState(() => _expandPending = v),
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(
            '未安装（${pendingLocal.length + pendingRemote.length}）',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('可安装到当前实例 / 导出 / 编辑'),
          children: [
            if (pendingLocal.isEmpty && pendingRemote.isEmpty)
              const ListTile(dense: true, title: Text('没有待安装整合包')),
            for (final lp in pendingLocal) _localTile(lp, installed: false),
            for (final pack in pendingRemote)
              _remoteTile(pack, installed: false),
          ],
        ),
      ],
    );
  }

  Widget _localTile(LocalPackInfo lp, {required bool installed}) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ListTile(
        leading: const Icon(Icons.folder_special_outlined),
        title: Text(lp.name),
        subtitle: Text(
          '${lp.gameType} · ${lp.gameVersion} · ${lp.loaderType}\n'
          '模组 ${lp.modFiles.length} 个 · 本地包',
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 0,
          children: [
            if (!installed)
              IconButton(
                tooltip: '安装到当前实例',
                icon: const Icon(Icons.download_done_outlined),
                onPressed: () => _installLocalToInstance(lp),
              ),
            if (installed)
              IconButton(
                tooltip: '标为未安装',
                icon: const Icon(Icons.remove_done),
                onPressed: () => _markInstalled(lp.id, installed: false),
              ),
            IconButton(
              tooltip: '导出 zip',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _exportLocal(lp),
            ),
          ],
        ),
        onTap: () => _showLocalDetail(lp),
      ),
    );
  }

  Widget _remoteTile(PackSummary pack, {required bool installed}) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text(pack.name),
        subtitle: Text(
          '${pack.gameType} · ${pack.gameVersion} · ${pack.loaderType}\n'
          '分享码: ${pack.shareCode}',
        ),
        isThreeLine: true,
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: installed ? '标为未安装' : '标为已安装',
              icon: Icon(installed ? Icons.remove_done : Icons.done_all),
              onPressed: () =>
                  _markInstalled(pack.packId, installed: !installed),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: _dialogGuard.isLocked ? null : () => _openDetail(context, pack),
      ),
    );
  }

  Future<void> _installLocalToInstance(LocalPackInfo lp) async {
    final modsDir = _instanceModsDir();
    if (modsDir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在启动页选择实例')),
      );
      return;
    }
    try {
      final n = await _localStore.installToModsDir(lp, modsDir);
      await _markInstalled(lp.id, installed: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已安装到实例（$n 个模组）')),
      );
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('安装失败: $e')),
        );
      }
    }
  }

  Future<void> _showLocalCreateDialog(BuildContext context) async {
    final nameCtrl = TextEditingController(text: '我的整合包');
    final versionCtrl = TextEditingController(text: '1.20.1');
    var gameType = 'java';
    var loaderType = 'fabric';
    final jars = <String>[];
    try {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setSt) => AlertDialog(
            title: const Text('制作本地整合包'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: versionCtrl,
                      decoration: const InputDecoration(
                        labelText: '游戏版本',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    _dialogDropdown(
                      label: '游戏类型',
                      value: gameType,
                      options: const [
                        ('java', 'Java 版'),
                        ('bedrock', '基岩版'),
                      ],
                      onChanged: (v) => setSt(() => gameType = v),
                    ),
                    _dialogDropdown(
                      label: '加载器',
                      value: loaderType,
                      options: const [
                        ('fabric', 'Fabric'),
                        ('forge', 'Forge'),
                        ('neoforge', 'NeoForge'),
                        ('none', '无'),
                      ],
                      onChanged: (v) => setSt(() => loaderType = v),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('模组 JAR（${jars.length}）'),
                    ),
                    ...jars.map(
                      (path) => ListTile(
                        dense: true,
                        title: Text(p.basename(path), maxLines: 1),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setSt(() => jars.remove(path)),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final paths = await pickFilePaths(
                          context,
                          title: '选择模组 JAR',
                          filter: 'JAR (*.jar)|*.jar|所有文件 (*.*)|*.*',
                        );
                        if (paths.isNotEmpty) {
                          setSt(() => jars.addAll(paths));
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('添加 JAR'),
                    ),
                  ],
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
                child: const Text('制作'),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      final info = await _localStore.create(
        name: nameCtrl.text,
        gameVersion: versionCtrl.text.trim(),
        gameType: gameType,
        loaderType: loaderType,
        jarPaths: jars,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已制作「${info.name}」，可导出 zip')),
      );
      await _reload();
    } finally {
      nameCtrl.dispose();
      versionCtrl.dispose();
    }
  }

  Future<void> _importLocalZip(BuildContext context) async {
    final path = await pickFilePath(
      context,
      title: '选择整合包 zip',
      filter: 'ZIP (*.zip)|*.zip|所有文件 (*.*)|*.*',
    );
    if (path == null || !mounted) return;
    try {
      final info = await _localStore.importZip(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入「${info.name}」')),
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  Future<void> _exportLocal(LocalPackInfo lp) async {
    final dest = await pickSaveFilePath(
      context,
      title: '导出整合包 zip',
      filter: 'ZIP (*.zip)|*.zip',
      defaultName: '${lp.name}.zip',
    );
    if (dest == null) return;
    final path = dest.toLowerCase().endsWith('.zip') ? dest : '$dest.zip';
    try {
      await _localStore.exportZip(lp, path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 $path')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _showLocalDetail(LocalPackInfo lp) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lp.name),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${lp.gameType} · ${lp.gameVersion} · ${lp.loaderType}'),
              const SizedBox(height: 8),
              Text('模组（${lp.modFiles.length}）'),
              ...lp.modFiles.map((f) => Text('· $f')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _exportLocal(lp);
            },
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('导出'),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    await _dialogGuard.run(() async {
      final action = await showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.create_outlined),
              title: const Text('制作整合包（本地）'),
              subtitle: const Text('选 JAR 做成可导出的本地包，不依赖后端'),
              onTap: () => Navigator.of(sheetContext).pop('local_create'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('创建云端整合包'),
              subtitle: const Text('可从 Modrinth 添加模组（需登录后端）'),
              onTap: () => Navigator.of(sheetContext).pop('create'),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('分享码导入'),
              onTap: () => Navigator.of(sheetContext).pop('import'),
            ),
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: const Text('导入本地 zip'),
              subtitle: const Text('导入此前导出的星穹整合包'),
              onTap: () => Navigator.of(sheetContext).pop('import_zip'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('本地文件上传云端'),
              subtitle: const Text('选择 JAR/ZIP，创建云端整合包并上传'),
              onTap: () => Navigator.of(sheetContext).pop('local'),
            ),
          ]),
        ),
      );
      if (!mounted || action == null) return null;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return null;
      switch (action) {
        case 'local_create':
          await _showLocalCreateDialog(context);
        case 'create':
          await _showCreateDialog(context, guarded: false);
        case 'import':
          await _showImportDialog(context, guarded: false);
        case 'import_zip':
          await _importLocalZip(context);
        case 'local':
          await _importLocalPack(context, guarded: false);
      }
      return null;
    });
    if (mounted) setState(() {});
  }

  Widget _dialogDropdown({
    required String label,
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InputDecorator(
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value:
                    options.any((e) => e.$1 == value) ? value : options.first.$1,
                items: [
                  for (final o in options)
                    DropdownMenuItem(value: o.$1, child: Text(o.$2)),
                ],
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importLocalPack(
    BuildContext context, {
    bool guarded = true,
  }) async {
    if (guarded) {
      await _dialogGuard.run(() async {
        await _importLocalPack(context, guarded: false);
        return null;
      });
      if (mounted) setState(() {});
      return;
    }
    final paths = await pickFilePaths(
      context,
      title: '选择本地整合包文件',
      filter:
          '模组/整合包 (*.jar;*.zip;*.mrpack)|*.jar;*.zip;*.mrpack|所有文件 (*.*)|*.*',
    );
    if (!mounted || paths.isEmpty) return;

    final nameCtrl = TextEditingController(
      text: p.basenameWithoutExtension(paths.first),
    );
    final versionCtrl = TextEditingController(text: '1.20.1');
    var loaderType = 'fabric';
    try {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('本地导入整合包'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '将上传 ${paths.length} 个本地文件并创建整合包（须为原创或已获授权内容）',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: versionCtrl,
                      decoration: const InputDecoration(
                        labelText: '游戏版本',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    _dialogDropdown(
                      label: '加载器',
                      value: loaderType,
                      options: const [
                        ('none', '无（原版）'),
                        ('fabric', 'Fabric'),
                        ('forge', 'Forge'),
                        ('neoforge', 'NeoForge'),
                      ],
                      onChanged: (v) => setDialogState(() => loaderType = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('导入'),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('正在上传本地文件并创建整合包…')),
      );
      try {
        final service = context.read<PackService>();
        final created = await service.create(
          name: nameCtrl.text.trim().isEmpty
              ? p.basenameWithoutExtension(paths.first)
              : nameCtrl.text.trim(),
          gameVersion: versionCtrl.text.trim().isEmpty
              ? '1.20.1'
              : versionCtrl.text.trim(),
          loaderType: loaderType,
          gameType: 'java',
        );
        final mods = <ManifestEntry>[];
        for (final path in paths) {
          final file = File(path);
          if (!await file.exists()) continue;
          final uploaded = await service.upload(
            await file.readAsBytes(),
            p.basename(path),
            license: 'original',
          );
          mods.add(ManifestEntry(
            type: 'custom',
            fileId: uploaded.fileId,
            filename: uploaded.filename,
            sha1: uploaded.sha1,
          ));
        }
        if (mods.isNotEmpty) {
          await service.updateManifest(
            created.packId,
            PackManifest(
              mods: mods,
              resourcePacks: const [],
              behaviorPacks: const [],
              configOverrides: const {},
            ),
          );
        }
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '已导入「${nameCtrl.text.trim()}」· 分享码 ${created.shareCode} · ${mods.length} 个文件',
            ),
          ),
        );
        _reload();
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('本地导入失败：$e')));
      }
    } finally {
      nameCtrl.dispose();
      versionCtrl.dispose();
    }
  }

  Future<void> _showCreateDialog(
    BuildContext context, {
    bool guarded = true,
  }) async {
    if (guarded) {
      await _dialogGuard.run(() async {
        await _showCreateDialog(context, guarded: false);
        return null;
      });
      if (mounted) setState(() {});
      return;
    }
    final nameCtrl = TextEditingController();
    final versionCtrl = TextEditingController(text: '1.20.1');
    final loaderVersionCtrl = TextEditingController();
    var loaderType = 'fabric';
    var gameType = 'java';
    final pendingMods = <ManifestEntry>[];

    try {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('创建整合包'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: versionCtrl,
                    decoration: const InputDecoration(
                      labelText: '游戏版本',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  _dialogDropdown(
                    label: '加载器',
                    value: loaderType,
                    options: const [
                      ('none', '无（原版）'),
                      ('fabric', 'Fabric'),
                      ('forge', 'Forge'),
                      ('neoforge', 'NeoForge'),
                    ],
                    onChanged: (v) => setDialogState(() => loaderType = v),
                  ),
                  if (loaderType != 'none') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: loaderVersionCtrl,
                      decoration: const InputDecoration(
                        labelText: '加载器版本',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  _dialogDropdown(
                    label: '游戏类型',
                    value: gameType,
                    options: const [
                      ('java', 'Java 版'),
                      ('bedrock', '基岩版'),
                    ],
                    onChanged: (v) => setDialogState(() => gameType = v),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Modrinth 模组（${pendingMods.length}）',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...pendingMods.map((e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.public, size: 18),
                        title:
                            Text(e.slug ?? e.filename ?? e.versionId ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              setDialogState(() => pendingMods.remove(e)),
                        ),
                      )),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.public, size: 18),
                      label: const Text('从 Modrinth 添加'),
                      onPressed: gameType != 'java'
                          ? null
                          : () async {
                              final pick = await showModrinthBrowser(
                                dialogContext,
                                gameVersion: versionCtrl.text.trim().isEmpty
                                    ? '1.20.1'
                                    : versionCtrl.text.trim(),
                                loader: loaderType == 'none'
                                    ? 'fabric'
                                    : loaderType,
                                projectType: 'mod',
                                title: '添加 Modrinth 模组',
                              );
                              if (pick == null) return;
                              setDialogState(() {
                                pendingMods.add(ManifestEntry(
                                  type: 'modrinth',
                                  slug: pick.hit.slug,
                                  versionId: pick.version.id,
                                  filename: pick.hit.title,
                                ));
                              });
                            },
                    ),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('创建'),
              ),
            ],
          ),
        ),
      );

      if (ok != true || !mounted) return;
      try {
        final result = await context.read<PackService>().create(
              name: nameCtrl.text.trim(),
              gameVersion: versionCtrl.text.trim(),
              loaderType: loaderType,
              loaderVersion: loaderVersionCtrl.text.trim().isEmpty
                  ? null
                  : loaderVersionCtrl.text.trim(),
              gameType: gameType,
              manifest: PackManifest(
                mods: List.of(pendingMods),
                resourcePacks: const [],
                behaviorPacks: const [],
                configOverrides: const {},
              ),
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '创建成功，分享码 ${result.shareCode}${pendingMods.isEmpty ? '' : ' · ${pendingMods.length} 个 Modrinth 模组'}')));
          _reload();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('创建失败：$e')));
        }
      }
    } finally {
      nameCtrl.dispose();
      versionCtrl.dispose();
      loaderVersionCtrl.dispose();
    }
  }

  Future<void> _showImportDialog(
    BuildContext context, {
    bool guarded = true,
  }) async {
    if (guarded) {
      await _dialogGuard.run(() async {
        await _showImportDialog(context, guarded: false);
        return null;
      });
      if (mounted) setState(() {});
      return;
    }
    final codeCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('分享码导入'),
          content: TextField(
            controller: codeCtrl,
            decoration: const InputDecoration(
              labelText: '分享码',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (ok != true || codeCtrl.text.trim().isEmpty || !mounted) return;
      try {
        final result = await context
            .read<PackService>()
            .importByShareCode(codeCtrl.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已导入整合包「${result.name}」')));
          _reload();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('导入失败：$e')));
        }
      }
    } finally {
      codeCtrl.dispose();
    }
  }

  Future<void> _openDetail(BuildContext context, PackSummary pack) async {
    await _dialogGuard.run(() async {
      try {
        final manifest =
            await context.read<PackService>().manifest(pack.packId);
        if (!mounted) return null;
        await showDialog<void>(
          context: context,
          useRootNavigator: true,
          builder: (dialogContext) => _PackDetailDialog(
            pack: pack,
            manifestResponse: manifest,
            onChanged: _reload,
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('获取清单失败：$e')));
        }
      }
      return null;
    });
    if (mounted) setState(() {});
  }
}

/// 整合包详情：清单查看 + 真正写入 Modrinth / 自定义文件。
class _PackDetailDialog extends StatefulWidget {
  final PackSummary pack;
  final PackManifestResponse manifestResponse;
  final VoidCallback onChanged;

  const _PackDetailDialog({
    required this.pack,
    required this.manifestResponse,
    required this.onChanged,
  });

  @override
  State<_PackDetailDialog> createState() => _PackDetailDialogState();
}

class _PackDetailDialogState extends State<_PackDetailDialog> {
  late PackManifest _manifest;
  bool _busy = false;
  final _dialogGuard = DialogGuard();

  @override
  void initState() {
    super.initState();
    _manifest = widget.manifestResponse.manifest;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.pack.name),
      content: SizedBox(
        width: 480,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${widget.pack.gameType} · ${widget.pack.gameVersion} · ${widget.pack.loaderType}${widget.pack.loaderType != 'none' ? ' ${widget.manifestResponse.loaderVersion}' : ''}'),
            const SizedBox(height: 8),
            Text('分享码: ${widget.pack.shareCode}'),
            Text(
              '模组从 Modrinth 公开源解析；自定义文件走平台上传。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Mods（${_manifest.mods.length}）'),
                    ..._manifest.mods.map(_entryTile),
                    _sectionTitle(
                        '资源包（${_manifest.resourcePacks.length}）'),
                    ..._manifest.resourcePacks.map(_entryTile),
                    _sectionTitle(
                        '行为包（${_manifest.behaviorPacks.length}）'),
                    ..._manifest.behaviorPacks.map(_entryTile),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.ios_share, size: 18),
          label: const Text('导出清单'),
          onPressed: (_busy || _dialogGuard.isLocked) ? null : _exportManifest,
        ),
        TextButton.icon(
          icon: const Icon(Icons.public, size: 18),
          label: const Text('添加 Modrinth Mod'),
          onPressed: (_busy || _dialogGuard.isLocked) ? null : _addModrinthMod,
        ),
        TextButton.icon(
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('上传自定义文件'),
          onPressed: (_busy || _dialogGuard.isLocked) ? null : _uploadCustomFile,
        ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭')),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _entryTile(ManifestEntry entry) {
    final name = entry.filename ?? entry.slug ?? entry.fileId ?? '(未知)';
    return ListTile(
      dense: true,
      leading: Icon(
          entry.type == 'modrinth' ? Icons.public : Icons.upload_file),
      title: Text(name),
      subtitle: Text(entry.type == 'modrinth'
          ? 'Modrinth · ${entry.versionId ?? ''}'
          : '自定义上传 · SHA1 已记录'),
    );
  }

  Future<void> _exportManifest() async {
    final safeName = widget.pack.name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final dest = await pickSaveFilePath(
      context,
      title: '导出整合包清单',
      filter: 'JSON (*.json)|*.json|所有文件 (*.*)|*.*',
      defaultName: '${safeName.isEmpty ? widget.pack.packId : safeName}_manifest.json',
    );
    if (dest == null) return;
    final path = dest.toLowerCase().endsWith('.json') ? dest : '$dest.json';
    try {
      final payload = <String, dynamic>{
        'pack_id': widget.pack.packId,
        'name': widget.pack.name,
        'game_type': widget.pack.gameType,
        'game_version': widget.pack.gameVersion,
        'loader_type': widget.pack.loaderType,
        'loader_version': widget.manifestResponse.loaderVersion,
        'share_code': widget.pack.shareCode,
        'manifest': _manifest.toJson(),
      };
      final out = File(path);
      await out.parent.create(recursive: true);
      await out.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 $path')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _addModrinthMod() async {
    await _dialogGuard.run(() async {
      final pick = await showModrinthBrowser(
        context,
        gameVersion: widget.pack.gameVersion,
        loader: widget.pack.loaderType == 'none'
            ? 'fabric'
            : widget.pack.loaderType,
        projectType: 'mod',
        title: '添加 Modrinth 模组',
      );
      if (pick == null || !mounted) return null;
      setState(() => _busy = true);
      try {
        final next = PackManifest(
          mods: [
            ..._manifest.mods,
            ManifestEntry(
              type: 'modrinth',
              slug: pick.hit.slug,
              versionId: pick.version.id,
              filename: pick.hit.title,
            ),
          ],
          resourcePacks: _manifest.resourcePacks,
          behaviorPacks: _manifest.behaviorPacks,
          configOverrides: _manifest.configOverrides,
        );
        await context.read<PackService>().updateManifest(
              widget.pack.packId,
              next,
            );
        if (!mounted) return null;
        setState(() => _manifest = next);
        widget.onChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 ${pick.hit.title}')),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('添加失败：$e')));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return null;
    });
    if (mounted) setState(() {});
  }

  Future<void> _uploadCustomFile() async {
    await _dialogGuard.run(() async {
    var license = 'original';
    String? pickedPath;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('上传自定义文件'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(
                  pickedPath == null
                      ? '选择本地文件'
                      : p.basename(pickedPath!),
                ),
                onPressed: () async {
                  final path = await pickFilePath(
                    context,
                    title: '选择要上传的文件',
                    filter:
                        '模组/资源 (*.jar;*.zip)|*.jar;*.zip|所有文件 (*.*)|*.*',
                  );
                  if (path != null) {
                    setDialogState(() => pickedPath = path);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            const Text('仅允许上传原创内容或经授权可再分发的内容',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 6),
                      child: Text(
                        '授权声明',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          isDense: true,
                          value: license,
                          items: const [
                            DropdownMenuItem(
                                value: 'original', child: Text('原创')),
                            DropdownMenuItem(
                                value: 'authorized', child: Text('已获授权')),
                          ],
                          onChanged: (v) => setDialogState(
                              () => license = v ?? 'original'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消')),
            FilledButton(
                onPressed: pickedPath == null
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                child: const Text('上传并加入清单'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || pickedPath == null) return null;
    final file = File(pickedPath!);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文件不存在')));
      }
      return null;
    }
    setState(() => _busy = true);
    try {
      final result = await context.read<PackService>().upload(
            file.readAsBytesSync(),
            file.uri.pathSegments.last,
            license: license,
          );
      final next = PackManifest(
        mods: [
          ..._manifest.mods,
          ManifestEntry(
            type: 'custom',
            fileId: result.fileId,
            filename: result.filename,
            sha1: result.sha1,
          ),
        ],
        resourcePacks: _manifest.resourcePacks,
        behaviorPacks: _manifest.behaviorPacks,
        configOverrides: _manifest.configOverrides,
      );
      await context.read<PackService>().updateManifest(
            widget.pack.packId,
            next,
          );
      if (!mounted) return null;
      setState(() => _manifest = next);
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已上传并加入清单 ${result.filename}')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('上传失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
    });
    if (mounted) setState(() {});
  }
}
