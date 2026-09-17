import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_manager.dart';
import '../accounts_page.dart';
import '../app_theme.dart';
import '../glass/liquid_glass.dart';

/// App 端页顶：品牌条 + 可选账号入口，不复用桌面侧栏样式。
class MobilePageHeader extends StatelessWidget {
  const MobilePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showAccount = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = context.watch<AuthManager>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showAccount) ...[
            InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AccountsPage(),
                ),
              ),
              child: LiquidGlass(
                allowBackdrop: false,
                fillBoost: 0.06,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Image.asset(
                    auth.defaultAvatarAsset,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person,
                      size: 22,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
