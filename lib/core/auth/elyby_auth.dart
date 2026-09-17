import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'platform_utils.dart';

/// Ely.by OAuth2（授权码流程 + 本地 loopback 回调）：
/// 1. 本地起 HTTP 服务监听回调 → 2. 系统浏览器打开授权页
/// 3. 回调收到 code → 4. 与 account.ely.by/api/oauth2/v1/token 交换令牌
/// 5. 调用 api/account/v1/info 获取用户信息。
/// 端点依据官方文档：https://docs.ely.by/en/oauth.html
class ElybyAuth {
  static const String authorizeUrl = 'https://account.ely.by/oauth2/v1';
  static const String tokenUrl = 'https://account.ely.by/api/oauth2/v1/token';
  static const String userInfoUrl =
      'https://account.ely.by/api/account/v1/info';
  static const String scopes = 'account_info offline_access';

  final AppConfig config;

  ElybyAuth(this.config);

  Future<ElybySession> login() async {
    final clientId = config.elybyClientId;
    final clientSecret = config.elybyClientSecret;
    if (clientId.isEmpty || clientSecret.isEmpty) {
      throw const AuthFlowException('请先在设置中填写 Ely.by ClientId / ClientSecret');
    }

    final state = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final redirectPort = config.elybyRedirectPort;
    final redirectUri = 'http://127.0.0.1:$redirectPort/callback';

    // 1. 本地回调服务器
    final server = await HttpServer.bind('127.0.0.1', redirectPort);
    String? code;
    String? error;
    try {
      final completer = Completer<AuthorizationResult>();
      server.listen((request) async {
        final result = AuthorizationResult.fromUri(request.uri);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.html;
        request.response.write(
            '<html><body style="font-family:sans-serif;text-align:center;padding-top:4em">'
            '<h2>星穹次元启动器</h2><p>${result.error == null ? "登录成功，请返回启动器" : "登录失败: ${result.error}"}</p>'
            '</body></html>');
        await request.response.close();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      });

      // 2. 打开浏览器授权页
      final uri = Uri.parse(authorizeUrl).replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scopes,
        'state': state,
      });
      await openUrlInBrowser(uri.toString());

      // 3. 等待回调
      final result = await completer.future.timeout(const Duration(minutes: 5));
      if (result.error != null) {
        throw AuthFlowException('Ely.by 授权失败: ${result.error}');
      }
      if (result.state != state) {
        throw const AuthFlowException('state 校验失败，请重试');
      }
      code = result.code;
      error = code == null ? '未收到授权码' : null;
      if (error != null) {
        throw AuthFlowException(error);
      }
    } finally {
      await server.close(force: true);
    }

    // 4. 交换令牌
    final tokenResponse = await http.post(Uri.parse(tokenUrl), body: {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'client_secret': clientSecret,
    });
    final tokenJson = _decode(tokenResponse);
    if (tokenResponse.statusCode != 200) {
      throw AuthFlowException(
          '令牌交换失败: ${tokenJson['error_description'] ?? tokenJson['error'] ?? tokenResponse.statusCode}');
    }

    // 5. 获取用户信息
    final infoResponse = await http.get(
      Uri.parse(userInfoUrl),
      headers: {'Authorization': 'Bearer ${tokenJson['access_token']}'},
    );
    final infoJson = _decode(infoResponse);
    if (infoResponse.statusCode != 200) {
      throw const AuthFlowException('获取 Ely.by 用户信息失败');
    }

    return ElybySession(
      accessToken: tokenJson['access_token'] as String,
      refreshToken: tokenJson['refresh_token'] as String?,
      expiresIn: (tokenJson['expires_in'] as num?)?.toInt() ?? 86400,
      elyId: (infoJson['id'] as num).toString(),
      uuid: (infoJson['uuid'] as String?) ?? '',
      username: (infoJson['username'] as String?) ?? '',
    );
  }

  /// 用 refresh_token 换新 access_token。
  Future<ElybySession> refresh(String refreshToken) async {
    final response = await http.post(Uri.parse(tokenUrl), body: {
      'grant_type': 'refresh_token',
      'client_id': config.elybyClientId,
      'client_secret': config.elybyClientSecret,
      'scope': scopes,
      'refresh_token': refreshToken,
    });
    final json = _decode(response);
    if (response.statusCode != 200) {
      throw AuthFlowException(
          '刷新令牌失败: ${json['error_description'] ?? json['error'] ?? response.statusCode}');
    }
    return ElybySession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String? ?? refreshToken,
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 86400,
      elyId: '',
      uuid: '',
      username: '',
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

class AuthorizationResult {
  final String? code;
  final String? state;
  final String? error;

  const AuthorizationResult({this.code, this.state, this.error});

  factory AuthorizationResult.fromUri(Uri uri) {
    return AuthorizationResult(
      code: uri.queryParameters['code'],
      state: uri.queryParameters['state'],
      error: uri.queryParameters['error'] ?? uri.queryParameters['error_message'],
    );
  }
}

class ElybySession {
  final String accessToken;
  final String? refreshToken;
  final int expiresIn;
  final String elyId;
  final String uuid;
  final String username;

  const ElybySession({
    required this.accessToken,
    this.refreshToken,
    required this.expiresIn,
    required this.elyId,
    required this.uuid,
    required this.username,
  });
}

class AuthFlowException implements Exception {
  final String message;
  const AuthFlowException(this.message);

  @override
  String toString() => message;
}
