import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/game/launch_loadout.dart';
import 'dialog_guard.dart';

/// 服务器列表（启动器侧收藏；写入游戏 servers.dat 后续增强）。
class ServersPage extends StatefulWidget {
  const ServersPage({super.key});

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  static const _key = LaunchLoadout.serversKey;
  List<Map<String, String>> _servers = [];
  bool _loading = true;
  final _dialogGuard = DialogGuard();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    if (!mounted) return;
    try {
      final raw = context.read<AppConfig>().getJson(_key);
      final items = (raw['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => {
                'name': '${e['name'] ?? ''}'.trim(),
                'address': '${e['address'] ?? ''}'.trim(),
              })
          .where((e) => (e['address'] ?? '').isNotEmpty)
          .toList();
      setState(() {
        _servers = items;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _toast('读取服务器列表失败: $e');
    }
  }

  Future<void> _save() async {
    final items = _servers
        .map((e) => <String, dynamic>{
              'name': e['name'] ?? '',
              'address': e['address'] ?? '',
            })
        .toList();
    await context.read<AppConfig>().setJson(_key, <String, dynamic>{
      'items': items,
    });
    // 通知启动选项里的服务器下拉刷新
    context.read<LaunchLoadout>().notifyListeners();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _add() async {
    if (_dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
    final result = await showDialog<({String name, String address})>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => const _AddServerDialog(),
    );
    if (result == null || !mounted) return null;

    final name = result.name.trim().isEmpty ? '服务器' : result.name.trim();
    final address = result.address.trim();
    if (address.isEmpty) {
      _toast('请填写服务器地址');
      return null;
    }
    if (_servers.any((e) => (e['address'] ?? '') == address)) {
      _toast('该地址已在列表中');
      return null;
    }

    try {
      setState(() {
        _servers = [
          ..._servers,
          {'name': name, 'address': address},
        ];
      });
      await _save();
      _toast('已添加 $name');
    } catch (e) {
      _toast('添加失败: $e');
      _load();
    }
    return null;
    });
    if (mounted) setState(() {});
  }

  Future<void> _removeAt(int i) async {
    if (i < 0 || i >= _servers.length) return;
    final removed = _servers[i];
    try {
      setState(() {
        _servers = [..._servers]..removeAt(i);
      });
      await _save();
      _toast('已删除 ${removed['name'] ?? removed['address'] ?? ''}');
    } catch (e) {
      _toast('删除失败: $e');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '收藏常用服务器地址。进游戏后可在多人游戏中手动加入，或在启动页勾选「带服务器启动」。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: (_loading || _dialogGuard.isLocked) ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _servers.isEmpty
                      ? const Center(child: Text('暂无服务器，点右上角添加'))
                      : ListView.separated(
                          itemCount: _servers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final s = _servers[i];
                            return ListTile(
                              leading: const Icon(Icons.dns_outlined),
                              title: Text(s['name'] ?? ''),
                              subtitle: Text(s['address'] ?? ''),
                              trailing: IconButton(
                                tooltip: '删除',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeAt(i),
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
}

class _AddServerDialog extends StatefulWidget {
  const _AddServerDialog();

  @override
  State<_AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<_AddServerDialog> {
  final _name = TextEditingController();
  final _addr = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _addr.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      (
        name: _name.text.trim(),
        address: _addr.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加服务器'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如 生存服',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addr,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: '地址',
                  hintText: 'play.example.com:25565',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return '请填写地址';
                  if (t.contains(' ')) return '地址不能包含空格';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('添加'),
        ),
      ],
    );
  }
}
