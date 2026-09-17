import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/global_config.dart';
import '../../ui/boot_loading_page.dart';
import '../config/app_config.dart';
import 'auth_manager.dart';

/// 启动守卫：配置与会话恢复完成后进入主界面（不再跳转独立登录页）。
class AuthGuard extends StatelessWidget {
  final Widget Function(BuildContext context) onReady;

  const AuthGuard({
    super.key,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthManager>();
    final appConfig = context.watch<AppConfig>();

    if (auth.status == AuthStatus.loading || !appConfig.loaded) {
      return const BootLoadingPage();
    }
    return onReady(context);
  }
}

/// 全局配置提供者（远程公开配置）。
class GlobalConfigProvider extends ChangeNotifier {
  final AppConfig appConfig;
  final Future<Map<String, dynamic>> Function() fetchConfig;

  GlobalConfigProvider({required this.appConfig, required this.fetchConfig});

  bool loaded = false;
  bool backendReachable = false;
  String? backendError;
  GlobalConfig _config = GlobalConfig.fallback;

  GlobalConfig get config => _config;

  /// 微软登录是否可用：后台未关即可（空 Client ID 走 Xbox Live 公共客户端）。
  bool get microsoftLoginAvailable {
    if (appConfig.useLocalConfig) return true;
    if (!backendReachable) return true;
    return _config.enableMicrosoftLogin;
  }

  Future<void> refresh() async {
    try {
      final json = await fetchConfig();
      _config = GlobalConfig.fromJson(json);
      // 管理端保存的 OAuth 凭据写入本地；空字符串会清掉旧缓存
      await appConfig.applyRemoteAuth(
        msClientId: _config.msClientId,
        elybyClientId: _config.elybyClientId,
        elybyClientSecret: _config.elybyClientSecret,
        elybyRedirectPort: _config.elybyRedirectPort,
      );
      backendReachable = true;
      backendError = null;
    } catch (e) {
      backendReachable = false;
      backendError = e.toString();
      _config = GlobalConfig.fallback;
      // 非本地配置时清掉远程 OAuth 缓存，避免连不上新后台仍用旧 Client ID
      if (!appConfig.useLocalConfig) {
        await appConfig.applyRemoteAuth(
          msClientId: '',
          elybyClientId: '',
          elybyClientSecret: '',
          elybyRedirectPort: 7788,
        );
      }
    }
    loaded = true;
    notifyListeners();
  }
}
