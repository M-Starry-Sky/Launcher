import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_manager.dart';
import '../core/auth/microsoft_oauth.dart';
import '../core/auth/platform_utils.dart';

/// 弹出微软登录对话框（Azure 设备码 或 Live 粘贴回调）。
Future<void> showMicrosoftLoginDialog(BuildContext context) async {
  final auth = context.read<AuthManager>();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _MicrosoftLoginDialog(auth: auth),
  );
}

class _MicrosoftLoginDialog extends StatefulWidget {
  final AuthManager auth;

  const _MicrosoftLoginDialog({required this.auth});

  @override
  State<_MicrosoftLoginDialog> createState() => _MicrosoftLoginDialogState();
}

class _MicrosoftLoginDialogState extends State<_MicrosoftLoginDialog> {
  String? userCode;
  String? verificationUrl;
  String? liveAuthorizeUrl;
  String status = '正在准备微软登录…';
  String? error;
  final _paste = TextEditingController();
  Completer<String>? _liveWait;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    final pending = _liveWait;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('已取消登录'));
    }
    _paste.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      await widget.auth.loginMicrosoft(
        onCode: (code, url) {
          if (!mounted) return;
          setState(() {
            userCode = code;
            verificationUrl = url;
            status = '请在浏览器完成授权';
          });
        },
        onLiveRedirect: (url) async {
          if (!mounted) {
            throw StateError('已取消登录');
          }
          final wait = Completer<String>();
          _liveWait = wait;
          setState(() {
            liveAuthorizeUrl = url;
            status = '请在浏览器登录微软账号，完成后把地址栏网址粘贴到下方';
          });
          await openUrlInBrowser(url);
          return wait.future;
        },
        onStatus: (s) {
          if (mounted) setState(() => status = s);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
        });
      }
    }
  }

  void _submitLivePaste() {
    final wait = _liveWait;
    if (wait == null || wait.isCompleted) return;
    final text = _paste.text.trim();
    try {
      MicrosoftOAuth.extractAuthCode(text);
    } catch (e) {
      setState(() => error = e.toString());
      return;
    }
    setState(() => error = null);
    wait.complete(text);
  }

  @override
  Widget build(BuildContext context) {
    final live = liveAuthorizeUrl != null;
    return AlertDialog(
      title: const Text('微软账号登录'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            if (userCode != null) ...[
              Text('访问下方链接并输入代码：',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              SelectableText(verificationUrl ?? ''),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(userCode ?? '',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(letterSpacing: 2)),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('打开浏览器'),
                onPressed: verificationUrl == null
                    ? null
                    : () => openUrlInBrowser(verificationUrl!),
              ),
            ],
            if (live) ...[
              Text(
                '已打开 Xbox Live 公共客户端登录页。登录成功后地址会变成 '
                'login.live.com/oauth20_desktop.srf?code=… ，把整段网址粘贴到这里。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _paste,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '粘贴完整回调网址或 code=',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitLivePaste(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _submitLivePaste,
                    child: const Text('继续'),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('重新打开浏览器'),
                    onPressed: () => openUrlInBrowser(liveAuthorizeUrl!),
                  ),
                ],
              ),
            ],
            if (error == null || live || userCode != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(status)),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
