import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/update/app_version.dart';
import 'app_theme.dart';
import 'glass/liquid_glass.dart';

const String kAuthorName = '星夜幻梦';
const String kAuthorQq = '2569966922';

Future<void> showAppAboutDialog(BuildContext context) {
  return _showInfoSheet(
    context: context,
    title: '关于',
    icon: Icons.info_outline_rounded,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: Image(
            image: AssetImage('assets/images/logo.png'),
            width: 72,
            height: 72,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          AppVersion.displayName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'v${AppVersion.version}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        _InfoTile(label: '作者', value: kAuthorName),
        const SizedBox(height: 8),
        _InfoTile(
          label: '联系方式',
          value: 'QQ：$kAuthorQq',
          trailing: IconButton(
            tooltip: '复制 QQ',
            onPressed: () => _copyQq(context),
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '第三方非官方 Minecraft 辅助启动工具。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    ),
  );
}

Future<void> showCommunityContactDialog(BuildContext context) {
  return _showInfoSheet(
    context: context,
    title: '社区联系',
    icon: Icons.chat_bubble_outline,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '也可通过 QQ 联系作者反馈问题。站内社区请使用侧栏「社区」发帖与举报。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 16),
        _InfoTile(
          label: '社区联系 QQ',
          value: kAuthorQq,
          trailing: IconButton(
            tooltip: '复制 QQ',
            onPressed: () => _copyQq(context),
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => _copyQq(context),
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: const Text('复制 QQ 号'),
        ),
      ],
    ),
  );
}

/// 兼容旧调用名。
Future<void> showCommunityDialog(BuildContext context) =>
    showCommunityContactDialog(context);

Future<void> _copyQq(BuildContext context) async {
  await Clipboard.setData(const ClipboardData(text: kAuthorQq));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('已复制 QQ：$kAuthorQq')),
  );
}

Future<void> _showInfoSheet({
  required BuildContext context,
  required String title,
  required IconData icon,
  required Widget child,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: LiquidGlass(
            borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
            fillBoost: 0.14,
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, color: Theme.of(ctx).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoTile({
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
