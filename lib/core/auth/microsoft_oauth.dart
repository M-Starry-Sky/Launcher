import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'platform_utils.dart';

/// 微软登录协议：Azure AD 设备码，或 Xbox Live 公共客户端（login.live.com）。
enum MicrosoftAuthKind {
  /// Entra GUID + `login.microsoftonline.com` 设备码。
  azureDeviceCode,

  /// Xbox Live 公共客户端（如 `00000000402b5328`）+ 浏览器授权码。
  liveXbox,
}

/// 微软官方 OAuth：两套体系并存。
/// - Azure：consumers 租户设备码，`XboxLive.signin`
/// - Live：Minecraft / Xbox 公共 Client ID，浏览器授权后粘贴带 `code=` 的回调地址
class MicrosoftOAuth {
  /// Minecraft Java / Xbox Live 文档中的公共客户端 ID（无 secret）。
  static const String livePublicClientId = '00000000402b5328';

  static const String liveAuthorizeUrl =
      'https://login.live.com/oauth20_authorize.srf';
  static const String liveTokenUrl = 'https://login.live.com/oauth20_token.srf';
  static const String liveRedirectUri =
      'https://login.live.com/oauth20_desktop.srf';
  static const String liveScope = 'service::user.auth.xboxlive.com::MBI_SSL';

  static const String _tenant = 'consumers';
  static const String _deviceCodeUrl =
      'https://login.microsoftonline.com/$_tenant/oauth2/v2.0/devicecode';
  static const String _azureTokenUrl =
      'https://login.microsoftonline.com/$_tenant/oauth2/v2.0/token';

  /// XboxLive.signin：获取 XBL 链所需；offline_access：获取 refresh_token。
  static const String azureScopes = 'XboxLive.signin offline_access';

  /// 兼容旧引用。
  static const String scopes = azureScopes;

  final String clientId;
  final MicrosoftAuthKind kind;

  MicrosoftOAuth({
    required this.clientId,
    MicrosoftAuthKind? kind,
  }) : kind = kind ?? detectKind(clientId);

  factory MicrosoftOAuth.fromConfig(String rawClientId) {
    final id = resolveClientId(rawClientId);
    return MicrosoftOAuth(clientId: id, kind: detectKind(id));
  }

  /// 空配置时使用 Xbox Live 公共客户端，避免必须自建 Azure 应用。
  static String resolveClientId(String raw) {
    final t = raw.trim();
    return t.isEmpty ? livePublicClientId : t;
  }

  static MicrosoftAuthKind detectKind(String clientId) {
    final id = clientId.trim();
    if (_azureGuid.hasMatch(id) || _azureGuidCompact.hasMatch(id)) {
      return MicrosoftAuthKind.azureDeviceCode;
    }
    return MicrosoftAuthKind.liveXbox;
  }

  static final _azureGuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _azureGuidCompact = RegExp(r'^[0-9a-fA-F]{32}$');

  bool get isLive => kind == MicrosoftAuthKind.liveXbox;

  /// Live 授权页（系统浏览器打开）。
  String buildLiveAuthorizeUrl() {
    return Uri.parse(liveAuthorizeUrl).replace(queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'scope': liveScope,
      'redirect_uri': liveRedirectUri,
      'display': 'touch',
    }).toString();
  }

  /// 从用户粘贴的回调地址 / 裸 code 取出授权码。
  static String extractAuthCode(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      throw const ApiException('请粘贴登录完成后的完整网址（含 code=）');
    }
    if (!s.contains('://') && !s.contains('=')) {
      return s;
    }
    final uri = Uri.tryParse(s);
    if (uri != null) {
      final q = uri.queryParameters['code'];
      if (q != null && q.isNotEmpty) return q;
      if (uri.fragment.isNotEmpty) {
        final f = Uri.splitQueryString(uri.fragment);
        final fc = f['code'];
        if (fc != null && fc.isNotEmpty) return fc;
      }
    }
    final m = RegExp(r'[?&#]code=([^&\s#]+)').firstMatch(s);
    if (m != null) {
      return Uri.decodeComponent(m.group(1)!);
    }
    throw const ApiException('粘贴内容里没有 code=，请复制地址栏完整网址');
  }

  /// 第一步：请求设备码（仅 Azure）。
  Future<DeviceCodeStart> requestDeviceCode() async {
    if (kind != MicrosoftAuthKind.azureDeviceCode) {
      throw const ApiException('当前 Client ID 走 Live 授权，不使用设备码');
    }
    final response = await http.post(
      Uri.parse(_deviceCodeUrl),
      body: {'client_id': clientId, 'scope': azureScopes},
    );
    final json = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorText(json, '请求设备码失败'));
    }
    return DeviceCodeStart._(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUrl: (json['verification_uri'] as String?) ??
          (json['verification_url'] as String),
      intervalSeconds: (json['interval'] as num?)?.toInt() ?? 5,
      expiresInSeconds: (json['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  /// 第二步：轮询令牌端点，直至用户完成授权或超时。
  Future<OAuthTokens> pollForToken(DeviceCodeStart start,
      {void Function(String status)? onStatus}) async {
    final deadline =
        DateTime.now().add(Duration(seconds: start.expiresInSeconds));
    var interval = start.intervalSeconds;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: interval));
      final response = await http.post(Uri.parse(_azureTokenUrl), body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'client_id': clientId,
        'device_code': start.deviceCode,
      });
      final json = _decode(response);
      if (response.statusCode == 200) {
        return _tokensFromJson(json);
      }
      final error = json['error'] as String?;
      if (error == 'authorization_pending') {
        onStatus?.call('等待用户完成授权…');
        continue;
      } else if (error == 'slow_down') {
        interval += 5;
        continue;
      }
      throw ApiException(_errorText(json, '授权失败'));
    }
    throw const ApiException('授权超时，请重试');
  }

  /// Live：用授权码换令牌。
  Future<OAuthTokens> exchangeLiveCode(String pasted) async {
    final code = extractAuthCode(pasted);
    final response = await http.post(
      Uri.parse(liveTokenUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'client_id': clientId,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': liveRedirectUri,
      },
    );
    final json = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorText(json, 'Live 换票失败'));
    }
    return _tokensFromJson(json);
  }

  /// 刷新令牌（按当前 kind 走对应端点）。
  Future<OAuthTokens> refresh(String refreshToken) async {
    if (kind == MicrosoftAuthKind.liveXbox) {
      final response = await http.post(
        Uri.parse(liveTokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': clientId,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
          'redirect_uri': liveRedirectUri,
        },
      );
      final json = _decode(response);
      if (response.statusCode != 200) {
        throw ApiException(_errorText(json, '刷新令牌失败'));
      }
      return _tokensFromJson(json);
    }

    final response = await http.post(Uri.parse(_azureTokenUrl), body: {
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': refreshToken,
      'scope': azureScopes,
    });
    final json = _decode(response);
    if (response.statusCode != 200) {
      throw ApiException(_errorText(json, '刷新令牌失败'));
    }
    return _tokensFromJson(json);
  }

  OAuthTokens _tokensFromJson(Map<String, dynamic> json) {
    return OAuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('微软认证服务响应异常 (${response.statusCode})');
    }
  }

  String _errorText(Map<String, dynamic> json, String fallback) {
    final desc = json['error_description'] as String?;
    final error = json['error'] as String?;
    return desc ?? error ?? fallback;
  }
}

class DeviceCodeStart {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int intervalSeconds;
  final int expiresInSeconds;

  DeviceCodeStart._({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.intervalSeconds,
    required this.expiresInSeconds,
  });
}

class OAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final int expiresIn;

  OAuthTokens(
      {required this.accessToken, this.refreshToken, required this.expiresIn});

  /// 从 id_token（如果有）读取 sub 作为平台用户 ID。
  String? get subject {
    try {
      final claims = parseJwtPayload(accessToken);
      return claims['sub']?.toString();
    } catch (_) {
      return null;
    }
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}
