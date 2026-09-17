import 'dart:convert';

import 'package:http/http.dart' as http;

/// 微软正版链（全部为官方接口，仅用于验证账号与游戏拥有状态）：
/// MSA token → Xbox Live user_token → XSTS token → Minecraft services 登录
/// → 查询正版拥有状态（entitlements）→ 获取玩家档案（profile）。
class MicrosoftGameAuth {
  static const String _userAuthUrl =
      'https://user.auth.xboxlive.com/user/authenticate';
  static const String _xstsUrl =
      'https://xsts.auth.xboxlive.com/xsts/authorize';
  static const String _mcLoginUrl =
      'https://api.minecraftservices.com/authentication/login_with_xbox';
  static const String _entitlementsUrl =
      'https://api.minecraftservices.com/entitlements/mcstore';
  static const String _profileUrl =
      'https://api.minecraftservices.com/minecraft/profile';

  /// Azure JWT 要加 `d=`；Live MBI 票往往已是 `t=` / 非 JWT，原样提交。
  static String rpsTicketForXbox(String msaAccessToken) {
    final t = msaAccessToken.trim();
    if (t.startsWith('d=') || t.startsWith('t=')) return t;
    if (t.startsWith('ey')) return 'd=$t';
    return t;
  }

  /// XBL → XSTS → MC 会话；未拥有游戏时抛出 [NotEntitledException]。
  Future<GameSession> buildSession(String msaAccessToken) async {
    // 1. Xbox Live user_token
    final ticket = rpsTicketForXbox(msaAccessToken);
    Map<String, dynamic> userToken;
    try {
      userToken = await _postJson(_userAuthUrl, {
        'Properties': {
          'AuthMethod': 'RPS',
          'SiteName': 'user.auth.xboxlive.com',
          'RpsTicket': ticket,
        },
        'RelyingParty': 'http://auth.xboxlive.com',
        'TokenType': 'JWT',
      });
    } on ApiException {
      // 前缀不对时换另一种再试一次
      final alt = ticket.startsWith('d=')
          ? ticket.substring(2)
          : (msaAccessToken.startsWith('d=')
              ? msaAccessToken
              : 'd=$msaAccessToken');
      if (alt == ticket) rethrow;
      userToken = await _postJson(_userAuthUrl, {
        'Properties': {
          'AuthMethod': 'RPS',
          'SiteName': 'user.auth.xboxlive.com',
          'RpsTicket': alt,
        },
        'RelyingParty': 'http://auth.xboxlive.com',
        'TokenType': 'JWT',
      });
    }
    final xblToken = userToken['Token'] as String;

    // 2. XSTS：必须用 Minecraft 服务 RP，不能用 http://xboxlive.com
    final xstsJson = await _postJson(_xstsUrl, {
      'Properties': {
        'SandboxId': 'RETAIL',
        'UserTokens': [xblToken],
      },
      'RelyingParty': 'rp://api.minecraftservices.com/',
      'TokenType': 'JWT',
    });
    final xstsToken = xstsJson['Token'] as String;
    final uhs = ((xstsJson['DisplayClaims'] as Map)['xui'] as List)
        .first['uhs'] as String;

    // 3. Minecraft services 登录
    final mcJson = await _postJson(_mcLoginUrl, {
      'identityToken': 'XBL3.0 x=$uhs;$xstsToken',
    });
    final mcAccessToken = mcJson['access_token'] as String;

    // 4. 正版校验：优先 entitlements；格式变更时以 profile 能否取到为准
    var ownedByStore = false;
    try {
      final entitlements = await _getJson(_entitlementsUrl, mcAccessToken);
      final items = (entitlements['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => (e['name'] ?? '').toString().toLowerCase())
          .toSet();
      ownedByStore = items.any((n) =>
          n.contains('product_minecraft') ||
          n.contains('game_minecraft') ||
          n == 'minecraft');
    } catch (_) {
      // entitlements 接口变更时忽略，改用 profile
    }

    // 5. 玩家档案（含皮肤模型：CLASSIC=史蒂夫 / SLIM=爱丽克斯）
    Map<String, dynamic> profile;
    try {
      profile = await _getJson(_profileUrl, mcAccessToken);
    } on ApiException {
      if (!ownedByStore) {
        throw const NotEntitledException();
      }
      rethrow;
    }

    return GameSession(
      accessToken: mcAccessToken,
      uuid: profile['id'] as String,
      name: profile['name'] as String,
      skinVariant: _activeSkinVariant(profile),
    );
  }
  /// 从官方 profile 读取当前皮肤模型。
  static String _activeSkinVariant(Map<String, dynamic> profile) {
    final skins = profile['skins'];
    if (skins is! List) return 'CLASSIC';
    for (final item in skins) {
      if (item is! Map) continue;
      final state = '${item['state'] ?? ''}'.toUpperCase();
      if (state != 'ACTIVE') continue;
      final variant = '${item['variant'] ?? item['model'] ?? 'CLASSIC'}'
          .toUpperCase();
      if (variant == 'SLIM' || variant == 'ALEX') return 'SLIM';
      return 'CLASSIC';
    }
    return 'CLASSIC';
  }

  Future<Map<String, dynamic>> _postJson(String url, Object body) async {
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 401) {
      final bodyJson = _tryDecode(response);
      final xerr = bodyJson?['XErr']?.toString();
      if (xerr == '2148916233') {
        throw const ApiException('该微软账号没有 Xbox 档案，请先在 Xbox 平台创建');
      } else if (xerr == '2148916238') {
        throw const ApiException('账号为未成年人，需在家长账号中授权后重试');
      }
      throw const ApiException('Xbox 认证失败（401）');
    }
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException('$url 请求失败 (${response.statusCode})');
    }
    return _tryDecode(response) ?? {};
  }

  Future<Map<String, dynamic>> _getJson(String url, String bearer) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $bearer', 'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw ApiException('$url 请求失败 (${response.statusCode})');
    }
    return _tryDecode(response) ?? {};
  }

  Map<String, dynamic>? _tryDecode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

class GameSession {
  final String accessToken;
  final String uuid;
  final String name;
  /// CLASSIC（史蒂夫宽臂）/ SLIM（爱丽克斯细臂）
  final String skinVariant;

  const GameSession({
    required this.accessToken,
    required this.uuid,
    required this.name,
    this.skinVariant = 'CLASSIC',
  });

  bool get isAlexModel =>
      skinVariant.toUpperCase() == 'SLIM' ||
      skinVariant.toUpperCase() == 'ALEX';
}

class NotEntitledException implements Exception {
  const NotEntitledException();

  @override
  String toString() => '该微软账号未拥有 Minecraft（正版权益校验未通过）';
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}
