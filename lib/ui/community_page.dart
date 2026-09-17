import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_manager.dart';
import '../core/auth/platform_utils.dart';
import '../core/network/api_client.dart';
import '../models/community_post.dart';
import '../services/community_service.dart';
import 'about_dialogs.dart';
import 'app_theme.dart';
import 'dialog_guard.dart';
import 'glass/liquid_glass.dart';

/// 社区：公告 / 心得 / 反馈 / 合规外链分享；内置版权拦截与举报。
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  String _category = 'all';
  List<CommunityPost> _posts = const [];
  CommunityGuidelines? _guidelines;
  bool _loading = true;
  String? _error;
  int _page = 0;
  int _total = 0;
  final _dialogGuard = DialogGuard();

  static const _tabs = <(String, String)>[
    ('all', '全部'),
    ('notice', '公告'),
    ('tip', '心得'),
    ('feedback', '反馈'),
    ('share_link', '合规分享'),
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  CommunityService get _svc => context.read<CommunityService>();

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final g = await _svc.guidelines();
      if (!mounted) return;
      setState(() => _guidelines = g);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    final auth = context.read<AuthManager>();
    if (auth.status != AuthStatus.loggedIn) {
      setState(() {
        _posts = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _svc.listPosts(category: _category, page: _page);
      if (!mounted) return;
      setState(() {
        _posts = res.items;
        _total = res.total;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _showCompose() async {
    if (_dialogGuard.isLocked) return;
    final auth = context.read<AuthManager>();
    if (auth.status != AuthStatus.loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发帖前请先登录账号')),
      );
      return;
    }
    await _dialogGuard.run(() async {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => const _ComposeDialog(),
      );
      if (ok == true && mounted) {
        _page = 0;
        await _reload();
      }
      return null;
    });
    if (mounted) setState(() {});
  }

  Future<void> _report(CommunityPost post) async {
    if (_dialogGuard.isLocked) return;
    await _dialogGuard.run(() async {
      final reason = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => SimpleDialog(
          title: const Text('举报该帖'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'copyright'),
              child: const Text('版权侵权'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'piracy'),
              child: const Text('盗版 / 破解传播'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'spam'),
              child: const Text('垃圾信息'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'other'),
              child: const Text('其他'),
            ),
          ],
        ),
      );
      if (reason == null || !mounted) return null;
      try {
        await _svc.reportPost(postId: post.postId, reason: reason);
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reason == 'copyright' || reason == 'piracy'
                  ? '已提交举报，相关帖子已暂时隐藏待审'
                  : '已提交举报，感谢维护社区秩序',
            ),
          ),
        );
        await _reload();
      } on ApiException catch (e) {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return null;
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthManager>();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '社区',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showGuidelinesSheet(),
                icon: const Icon(Icons.gavel_outlined, size: 18),
                label: const Text('公约'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _dialogGuard.isLocked ? null : _showCompose,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('发帖'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '交流心得与反馈；模组请只贴合规外链。禁止盗版、破解与未授权资源分发。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in _tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t.$2),
                      selected: _category == t.$1,
                      onSelected: (_) {
                        setState(() {
                          _category = t.$1;
                          _page = 0;
                        });
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildBody(auth, scheme)),
          if (_total > 20)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _page <= 0
                      ? null
                      : () {
                          setState(() => _page -= 1);
                          _reload();
                        },
                  child: const Text('上一页'),
                ),
                Text('${_page + 1}'),
                TextButton(
                  onPressed: (_page + 1) * 20 >= _total
                      ? null
                      : () {
                          setState(() => _page += 1);
                          _reload();
                        },
                  child: const Text('下一页'),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showCommunityContactDialog(context),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('联系 QQ 群主 / 反馈通道'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AuthManager auth, ColorScheme scheme) {
    if (auth.status != AuthStatus.loggedIn) {
      return Center(
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: scheme.primary),
              const SizedBox(height: 12),
              const Text('登录后可浏览社区帖子、发帖与举报侵权内容'),
              const SizedBox(height: 8),
              Text(
                '浏览公约无需登录；发帖须勾选版权承诺。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_posts.isEmpty) {
      return Center(
        child: Text(
          '暂无帖子',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      itemCount: _posts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final p = _posts[i];
        return Material(
          color: scheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            onTap: () => _showDetail(p),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (p.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.push_pin, size: 14, color: scheme.primary),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          p.categoryLabel,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: '举报',
                        onPressed: () => _report(p),
                        icon: const Icon(Icons.flag_outlined, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${p.authorName}${p.createdAt == null ? '' : ' · ${p.createdAt}'}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDetail(CommunityPost post) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(post.title),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${post.categoryLabel} · ${post.authorName}'),
                  const SizedBox(height: 12),
                  SelectableText(post.body, style: const TextStyle(height: 1.5)),
                  if (post.linkUrl != null && post.linkUrl!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () async {
                        final url = post.linkUrl!;
                        await openUrlInBrowser(url);
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(post.linkUrl!),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _report(post);
              },
              child: const Text('举报'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showGuidelinesSheet() async {
    final g = _guidelines;
    if (g == null) {
      try {
        final loaded = await _svc.guidelines();
        if (!mounted) return;
        setState(() => _guidelines = loaded);
      } catch (_) {}
    }
    if (!mounted) return;
    final guide = _guidelines;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(guide?.title ?? '社区公约'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in guide?.rules ?? const <String>[])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('· '),
                        Expanded(child: Text(r, style: const TextStyle(height: 1.45))),
                      ],
                    ),
                  ),
                if (guide != null && guide.allowedLinkHosts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '外链白名单：${guide.allowedLinkHosts.join('、')}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }
}

/// 发帖对话框：须勾选版权承诺。
class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog();

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  String _category = 'tip';
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _link = TextEditingController();
  bool _ack = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<CommunityService>().createPost(
            category: _category,
            title: _title.text.trim(),
            body: _body.text.trim(),
            linkUrl: _link.text.trim().isEmpty ? null : _link.text.trim(),
            licenseAck: _ack,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('发布帖子'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Text(
                  '分类',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    value: _category,
                    items: const [
                      DropdownMenuItem(value: 'tip', child: Text('心得')),
                      DropdownMenuItem(value: 'feedback', child: Text('反馈')),
                      DropdownMenuItem(
                          value: 'share_link', child: Text('合规外链分享')),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) {
                            if (v != null) setState(() => _category = v);
                          },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                enabled: !_busy,
                maxLength: 120,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              TextField(
                controller: _body,
                enabled: !_busy,
                maxLines: 6,
                maxLength: 8000,
                decoration: const InputDecoration(labelText: '正文'),
              ),
              if (_category == 'share_link')
                TextField(
                  controller: _link,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: '合规外链（Modrinth / CurseForge / GitHub…）',
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _ack,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _ack = v ?? false),
                title: const Text(
                  '我承诺：不传播盗版/破解，不上传未授权资源；外链内容已获授权或遵循开源许可',
                  style: TextStyle(fontSize: 13, height: 1.35),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发布'),
        ),
      ],
    );
  }
}
