import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_guard.dart';
import '../core/auth/auth_manager.dart';
import 'app_theme.dart';
import 'microsoft_login_dialog.dart';

/// 账号中心：展示自动识别的头像与昵称（不可在启动器内改性别）。
class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthManager>();
    final global = context.watch<GlobalConfigProvider>();
    final msOk = global.microsoftLoginAvailable;
    final scheme = Theme.of(context).colorScheme;
    final modelLabel =
        auth.gender == PlayerGender.female ? '爱丽克斯（细臂）' : '史蒂夫（宽臂）';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('账号'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: Image.asset(
                      auth.defaultAvatarAsset,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.none,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.username ?? '未登录',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          auth.status == AuthStatus.loggedIn
                              ? (auth.source == AuthSource.microsoft
                                  ? '微软账号'
                                  : auth.source == AuthSource.offline
                                      ? '离线账号'
                                      : 'Ely.by')
                              : '未登录',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (auth.status == AuthStatus.loggedIn) ...[
                          const SizedBox(height: 6),
                          Text(
                            '自动识别：$modelLabel',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (auth.status == AuthStatus.loggedIn)
                    TextButton(
                      onPressed: () => auth.signOut(),
                      child: const Text('退出'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: msOk
                ? () => showMicrosoftLoginDialog(context)
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          global.backendReachable
                              ? '后台已关闭微软登录'
                              : '后端连接失败时仍可用内置 Xbox Live 公共客户端，请检查网络或到设置开启本地配置',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.login),
            label: Text(msOk ? '登录 / 切换账号' : '微软登录未开放'),
          ),
          const SizedBox(height: 16),
          Text(
            '头像由微软正版档案皮肤模型自动识别（CLASSIC→史蒂夫，SLIM→爱丽克斯）。'
            '启动器不提供性别设置或切换。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
