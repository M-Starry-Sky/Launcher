import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../services/home_notice_service.dart';

/// 启动页进入后拉取未读运营通知并弹窗（每条本机只弹一次）。
class HomeNoticeHost extends StatefulWidget {
  final Widget child;

  const HomeNoticeHost({super.key, required this.child});

  @override
  State<HomeNoticeHost> createState() => _HomeNoticeHostState();
}

class _HomeNoticeHostState extends State<HomeNoticeHost> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final cfg = context.read<AppConfig>();
      final svc = context.read<HomeNoticeService>();
      final list = await svc.list();
      if (!mounted || list.isEmpty) return;

      final dismissed = cfg.dismissedHomeNoticeIds;
      for (final n in list) {
        if (dismissed.contains(n.id)) continue;
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(n.title),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: SelectableText(n.body),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        await cfg.dismissHomeNotice(n.id);
      }
    } on ApiException {
      // 后端未就绪时静默跳过，不挡启动页
    } catch (_) {
      // ignore
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
