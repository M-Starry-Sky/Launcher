import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_guard.dart';
import '../core/config/app_config.dart';
import 'app_theme.dart';
import 'boot_loading_page.dart';
import 'glass/liquid_glass.dart';
import 'settings_page.dart';

/// 本地告知修订号：后端未下发或未升版时，用此保证首次安装会弹出。
const String kLocalNoticeVersion = '2.3';

/// 首次安装 / 告知版本变更后弹出使用须知。
/// 版本号优先取后端 disclaimer_version；否则使用 [kLocalNoticeVersion]。
class DisclaimerGate extends StatelessWidget {
  final Widget child;

  const DisclaimerGate({super.key, required this.child});

  static String requiredVersion(GlobalConfigProvider global) {
    final remote = global.config.disclaimerVersion?.trim();
    // 文案已升到 2.3；后端仍为旧版时强制用本地修订号，确保会再弹一次
    if (remote == null ||
        remote.isEmpty ||
        remote == '1' ||
        remote.startsWith('1.') ||
        remote == '2.0' ||
        remote == '2.1' ||
        remote == '2.2') {
      return kLocalNoticeVersion;
    }
    return remote;
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = context.watch<AppConfig>();
    final globalConfig = context.watch<GlobalConfigProvider>();
    if (!appConfig.loaded || !globalConfig.loaded) {
      return const BootLoadingPage();
    }

    final required = requiredVersion(globalConfig);
    final accepted = appConfig.acceptedDisclaimerVersion == required;
    if (!accepted) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: _FirstInstallNotice(),
      );
    }
    return child;
  }
}

class _FirstInstallNotice extends StatelessWidget {
  const _FirstInstallNotice();

  static const _body = '''
【免责声明】

1. 星穹次元是第三方、非官方的 Minecraft 辅助启动与联机工具，与 Mojang / Microsoft / 官方 Realms /《我的世界》中国版（网易）均无任何关联。

2. 游戏本体仅通过官方公开渠道获取；本启动器不提供破解、盗版、离线冒充正版或任何绕过正版授权的能力。

3. 使用微软登录须具备合法微软账号与对应游戏授权。用户应自行遵守当地法律法规及游戏服务条款。

4. 联机功能依赖用户自建 / 自配 FRP 打洞。平台不提供 FRP 中继流量（含微软正版账号）；「一键内网穿透」仅启动本地 frpc。本软件不运营公共游戏服务器，不对用户联机内容与后果承担责任。

5. 「兼容联机」会关闭服务器正版登录校验，仅建议在私人好友房间使用。请勿用于公开招人、收费或规避正版授权；请遵守游戏服务条款，相关后果由使用者自行承担。

【资源来源说明】

6. 启动器内展示或引用的部分资源、开源组件与公开资料，来源于网络公开收集及开源社区；版权归原作者 / 原项目所有。

7. 本软件及相关资源不进行违规售卖，不提供任何非法牟利的资源交易渠道。请勿将本软件用于商业侵权、倒卖或其它违法用途。

【社区与用户内容】

8. 社区仅允许交流心得、问题反馈与合规外链分享；禁止发布、索要或传播破解、盗版、绕过正版验证及未授权资源文件。

9. 用户对本人发布内容的合法性负责；发现侵权可通过举报通道提交，平台有权隐藏或删除违规内容。

点击「我已阅读并同意」即表示您知悉并接受上述内容。''';

  @override
  Widget build(BuildContext context) {
    final appConfig = context.read<AppConfig>();
    final globalConfig = context.read<GlobalConfigProvider>();
    final version = DisclaimerGate.requiredVersion(globalConfig);
    final theme = Theme.of(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.78;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
          fillBoost: 0.14,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '使用告知',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'v$version',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '首次安装请仔细阅读以下说明',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.55),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Text(
                      _body,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  appConfig.set(AppConfig.keyAcceptedDisclaimer, version);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('我已阅读并同意'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 供设置页跳转使用（避免循环依赖简单转发）。
void openSettings(BuildContext context) {
  Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
}
