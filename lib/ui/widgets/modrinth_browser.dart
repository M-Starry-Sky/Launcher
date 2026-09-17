import 'package:flutter/material.dart';

import '../../services/pack_service.dart';

/// 从 Modrinth 公开库选一个项目版本。
class ModrinthPick {
  final ModrinthSearchHit hit;
  final ModrinthVersionInfo version;

  const ModrinthPick({required this.hit, required this.version});
}

/// 弹出 Modrinth 搜索 / 选版本对话框。
Future<ModrinthPick?> showModrinthBrowser(
  BuildContext context, {
  required String gameVersion,
  String loader = 'fabric',
  String projectType = 'mod',
  String title = '浏览 Modrinth',
}) {
  return showDialog<ModrinthPick>(
    context: context,
    builder: (ctx) => _ModrinthBrowserDialog(
      gameVersion: gameVersion,
      loader: loader,
      projectType: projectType,
      title: title,
    ),
  );
}

class _ModrinthBrowserDialog extends StatefulWidget {
  final String gameVersion;
  final String loader;
  final String projectType;
  final String title;

  const _ModrinthBrowserDialog({
    required this.gameVersion,
    required this.loader,
    required this.projectType,
    required this.title,
  });

  @override
  State<_ModrinthBrowserDialog> createState() => _ModrinthBrowserDialogState();
}

class _ModrinthBrowserDialogState extends State<_ModrinthBrowserDialog> {
  final _client = ModrinthClient();
  final _search = TextEditingController();
  List<ModrinthSearchHit> _hits = [];
  List<ModrinthVersionInfo> _versions = [];
  ModrinthSearchHit? _selected;
  ModrinthVersionInfo? _version;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    setState(() {
      _busy = true;
      _error = null;
      _selected = null;
      _version = null;
      _versions = [];
    });
    try {
      final hits = await _client.search(
        query: _search.text,
        projectType: widget.projectType,
        gameVersion: widget.gameVersion,
        loader: widget.loader,
      );
      if (!mounted) return;
      setState(() => _hits = hits);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectHit(ModrinthSearchHit hit) async {
    setState(() {
      _busy = true;
      _error = null;
      _selected = hit;
      _version = null;
      _versions = [];
    });
    try {
      final versions = await _client.listVersions(
        projectId: hit.projectId,
        gameVersion: widget.gameVersion,
        loader: widget.projectType == 'mod' ? widget.loader : null,
      );
      if (!mounted) return;
      setState(() {
        _versions = versions;
        _version = versions.isNotEmpty ? versions.first : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '游戏 ${widget.gameVersion}'
              '${widget.loader != 'none' && widget.projectType == 'mod' ? ' · ${widget.loader}' : ''}'
              ' · 数据来自 Modrinth 公开 API',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: '搜索名称，如 sodium / fabric-api',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _runSearch,
                  child: const Text('搜索'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error, fontSize: 12)),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: _busy && _hits.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _hits.isEmpty
                              ? Center(
                                  child: Text(
                                    '输入关键词搜索公开资源',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _hits.length,
                                  itemBuilder: (_, i) {
                                    final h = _hits[i];
                                    final sel =
                                        _selected?.projectId == h.projectId;
                                    return ListTile(
                                      selected: sel,
                                      dense: true,
                                      leading: h.iconUrl == null
                                          ? const Icon(Icons.extension)
                                          : ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Image.network(
                                                h.iconUrl!,
                                                width: 32,
                                                height: 32,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(
                                                        Icons.extension),
                                              ),
                                            ),
                                      title: Text(h.title),
                                      subtitle: Text(
                                        '${h.slug} · ${_fmtDownloads(h.downloads)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: _busy
                                          ? null
                                          : () => _selectHit(h),
                                    );
                                  },
                                ),
                        ),
                        const VerticalDivider(width: 12),
                        Expanded(
                          flex: 2,
                          child: _selected == null
                              ? Center(
                                  child: Text(
                                    '选择左侧项目',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _selected!.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Expanded(
                                      child: _versions.isEmpty
                                          ? Center(
                                              child: Text(
                                                _busy
                                                    ? '加载版本…'
                                                    : '无兼容版本',
                                                style: TextStyle(
                                                    color: scheme
                                                        .onSurfaceVariant),
                                              ),
                                            )
                                          : ListView.builder(
                                              itemCount: _versions.length,
                                              itemBuilder: (_, i) {
                                                final v = _versions[i];
                                                final sel =
                                                    _version?.id == v.id;
                                                return ListTile(
                                                  dense: true,
                                                  selected: sel,
                                                  title: Text(v.label),
                                                  subtitle: Text(
                                                    v.loaders.join(', '),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  trailing: sel
                                                      ? Icon(Icons.check_circle,
                                                          size: 18,
                                                          color:
                                                              scheme.primary)
                                                      : null,
                                                  onTap: _busy
                                                      ? null
                                                      : () => setState(
                                                            () => _version = v,
                                                          ),
                                                );
                                              },
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected == null || _version == null
              ? null
              : () => Navigator.pop(
                    context,
                    ModrinthPick(hit: _selected!, version: _version!),
                  ),
          child: const Text('选用'),
        ),
      ],
    );
  }

  String _fmtDownloads(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M 下载';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K 下载';
    return '$n 下载';
  }
}
