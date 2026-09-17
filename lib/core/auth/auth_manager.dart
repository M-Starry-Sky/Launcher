import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'elyby_auth.dart';
import 'microsoft_game_auth.dart' hide ApiException;
import 'microsoft_oauth.dart';
import 'token_store.dart';

/// 临时屏蔽登录页：网络无法访问 Ely.by / 微软未配置时直接进主界面。
/// 恢复正式登录时改为 `false`。
const bool kBypassLoginPage = true;

enum AuthSource { microsoft, elyby, offline }

/// 角色性别：决定默认史蒂夫 / 爱丽克斯头像。
enum PlayerGender { male, female }

/// 登录状态。
enum AuthStatus { loading, loggedOut, loggedIn }

/// 统一认证入口：
/// - microsoft：微软设备码 + 正版链
/// - elyby：Ely.by OAuth2
/// - offline：本地离线玩家名（非正版联机）
class AuthManager extends ChangeNotifier {
  final AppConfig config;
  final TokenStore tokenStore;

  AuthStatus status = AuthStatus.loading;
  AuthSource? source;
  String? username;
  String? externalId;
  String? avatarUrl;
  /// 初次默认为男（史蒂夫）。
  PlayerGender gender = PlayerGender.male;

  static const steveAvatarAsset = 'assets/images/avatars/steve.png';
  static const alexAvatarAsset = 'assets/images/avatars/alex.png';

  MicrosoftOAuth? _microsoftOAuth;
  ElybyAuth? _elybyAuth;

  AuthManager({required this.config, required this.tokenStore}) {
    config.addListener(_onConfigChanged);
  }

  /// 侧栏展示用本地默认头像资源。
  String get defaultAvatarAsset =>
      gender == PlayerGender.female ? alexAvatarAsset : steveAvatarAsset;

  void _onConfigChanged() {
    _microsoftOAuth = null;
    _elybyAuth = null;
  }

  MicrosoftOAuth get microsoftOAuth =>
      _microsoftOAuth ??= MicrosoftOAuth.fromConfig(config.msClientId);

  ElybyAuth get elybyAuth => _elybyAuth ??= ElybyAuth(config);

  String? get currentAccessToken => _accessToken;

  String? _accessToken;

  /// 已可启动：微软已登录，或离线已设置昵称（loginOffline）。
  bool get isLaunchReady {
    if (status != AuthStatus.loggedIn) return false;
    if (source == AuthSource.microsoft) return true;
    if (source == AuthSource.offline) {
      final id = externalId ?? '';
      final name = username?.trim() ?? '';
      return id.startsWith('offline:') && name.isNotEmpty;
    }
    return false;
  }

  static AuthSource? parseSource(String? raw) {
    switch (raw) {
      case 'microsoft':
        return AuthSource.microsoft;
      case 'elyby':
        return AuthSource.elyby;
      case 'offline':
        return AuthSource.offline;
      default:
        return null;
    }
  }

  static PlayerGender parseGender(String? raw) {
    switch (raw) {
      case 'female':
      case 'f':
      case '女':
        return PlayerGender.female;
      default:
        return PlayerGender.male;
    }
  }

  static String genderKey(PlayerGender g) =>
      g == PlayerGender.female ? 'female' : 'male';

  static String sourceKey(AuthSource s) {
    switch (s) {
      case AuthSource.microsoft:
        return 'microsoft';
      case AuthSource.elyby:
        return 'elyby';
      case AuthSource.offline:
        return 'offline';
    }
  }

  /// 启动时恢复会话。
  Future<void> restore() async {
    status = AuthStatus.loading;
    notifyListeners();

    final profile = await tokenStore.readProfile();
    final stored = parseSource(profile['source']);

    if (kBypassLoginPage) {
      if (stored != null) {
        source = stored;
        externalId = profile['external_id'];
        username = profile['username'];
        avatarUrl = profile['avatar_url'];
        gender = parseGender(profile['gender']);
        if (stored == AuthSource.microsoft || stored == AuthSource.elyby) {
          final tokens =
              await tokenStore.readPlatformTokens(sourceKey(stored));
          _accessToken = tokens['access_token'];
        } else {
          _accessToken = null;
        }
      }
      username ??= '访客';
      externalId ??= 'dev-guest';
      source ??= AuthSource.offline;
      // 无档案时保持默认男（史蒂夫）
      if (profile['gender'] != null) {
        gender = parseGender(profile['gender']);
      }
      status = AuthStatus.loggedIn;
      notifyListeners();
      return;
    }

    if (stored == null) {
      status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }

    source = stored;
    externalId = profile['external_id'];
    username = profile['username'];
    avatarUrl = profile['avatar_url'];
    gender = parseGender(profile['gender']);

    if (stored == AuthSource.offline) {
      _accessToken = null;
      status = AuthStatus.loggedIn;
    } else {
      final tokens = await tokenStore.readPlatformTokens(sourceKey(stored));
      _accessToken = tokens['access_token'];
      status =
          _accessToken == null ? AuthStatus.loggedOut : AuthStatus.loggedIn;
    }
    notifyListeners();
  }

  /// 微软登录：Azure 设备码 或 Live 公共客户端授权码，再走 XBL 正版链。
  Future<void> loginMicrosoft({
    void Function(String userCode, String verificationUrl)? onCode,
    Future<String> Function(String authorizeUrl)? onLiveRedirect,
    void Function(String status)? onStatus,
  }) async {
    _microsoftOAuth = MicrosoftOAuth.fromConfig(config.msClientId);
    final oauth = microsoftOAuth;
    late final OAuthTokens tokens;

    if (oauth.isLive) {
      onStatus?.call('正在打开微软 / Xbox 登录页…');
      final authorizeUrl = oauth.buildLiveAuthorizeUrl();
      if (onLiveRedirect == null) {
        throw const ApiException('Live 登录需要在对话框中粘贴授权回调地址');
      }
      final pasted = await onLiveRedirect(authorizeUrl);
      onStatus?.call('正在换取令牌…');
      tokens = await oauth.exchangeLiveCode(pasted);
    } else {
      final start = await oauth.requestDeviceCode();
      onCode?.call(start.userCode, start.verificationUrl);
      tokens = await oauth.pollForToken(start, onStatus: onStatus);
    }

    onStatus?.call('正在校验正版与玩家档案…');
    final session = await MicrosoftGameAuth()
        .buildSession(tokens.accessToken)
        .timeout(const Duration(seconds: 60));

    _accessToken = tokens.accessToken;
    source = AuthSource.microsoft;
    externalId = tokens.subject ?? session.uuid;
    username = session.name;
    // 自动识别游戏账号皮肤模型，禁止用户在启动器内改性别
    gender =
        session.isAlexModel ? PlayerGender.female : PlayerGender.male;
    await tokenStore.savePlatformTokens(
      source: 'microsoft',
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      externalId: externalId,
      username: username,
      expiresAt: DateTime.now().add(Duration(seconds: tokens.expiresIn)),
    );
    await tokenStore.saveGameSession(
      accessToken: session.accessToken,
      uuid: session.uuid,
      name: session.name,
    );
    await tokenStore.saveProfile(
      source: 'microsoft',
      externalId: externalId!,
      username: username!,
      gender: genderKey(gender),
    );
    status = AuthStatus.loggedIn;
    notifyListeners();
  }

  /// Ely.by 登录：浏览器授权码流程。
  Future<void> loginElyby({
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('正在打开浏览器等待 Ely.by 授权…');
    final session = await elybyAuth.login();

    _accessToken = session.accessToken;
    source = AuthSource.elyby;
    externalId = session.elyId;
    username = session.username;
    await tokenStore.savePlatformTokens(
      source: 'elyby',
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      externalId: session.elyId,
      username: session.username,
      expiresAt: DateTime.now().add(Duration(seconds: session.expiresIn)),
    );
    if (session.uuid.isNotEmpty) {
      await tokenStore.saveGameSession(
        accessToken: session.accessToken,
        uuid: session.uuid,
        name: session.username,
        refreshToken: session.refreshToken,
      );
    }
    await tokenStore.saveProfile(
      source: 'elyby',
      externalId: session.elyId,
      username: session.username,
      gender: genderKey(gender),
    );
    status = AuthStatus.loggedIn;
    notifyListeners();
  }

  /// 离线账号：仅本地玩家名 + 离线 UUID；无正版档案时默认史蒂夫。
  Future<void> loginOffline(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('玩家名不能为空');
    }
    final gameName = sanitizeMinecraftUsername(trimmed);
    if (gameName != trimmed) {
      // 启动用合法名；界面仍可提示已纠正
    }
    gender = PlayerGender.male;
    final uuid = offlineUuidFor(gameName);
    _accessToken = null;
    source = AuthSource.offline;
    externalId = 'offline:$gameName';
    username = gameName;
    avatarUrl = null;
    await tokenStore.clearPlatformTokens('microsoft');
    await tokenStore.clearPlatformTokens('elyby');
    await tokenStore.saveGameSession(
      accessToken: '0',
      uuid: uuid,
      name: gameName,
    );
    await tokenStore.saveProfile(
      source: 'offline',
      externalId: externalId!,
      username: gameName,
      gender: genderKey(gender),
    );
    status = AuthStatus.loggedIn;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (source == AuthSource.microsoft || source == AuthSource.elyby) {
      await tokenStore.clearPlatformTokens(sourceKey(source!));
    }
    await tokenStore.clearGameSession();
    await tokenStore.clearAll();
    _accessToken = null;
    source = null;
    username = null;
    externalId = null;
    avatarUrl = null;
    gender = PlayerGender.male;
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  /// 与启动器离线档案一致的 UUID 派生。
  static String offlineUuidFor(String name) {
    final bytes = utf8.encode('OfflinePlayer:$name');
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final b in bytes) {
      h1 = ((h1 ^ b) * 0x01000193) & 0xffffffff;
      h2 = ((h2 ^ b) * 0x811c9dc5) & 0xffffffff;
    }
    final a = h1.toRadixString(16).padLeft(8, '0');
    final b = (h2 & 0xffff).toRadixString(16).padLeft(4, '0');
    final c = ((h2 >> 16) & 0x0fff | 0x4000).toRadixString(16).padLeft(4, '0');
    final d = (0x8000 | (h1 & 0x3fff)).toRadixString(16).padLeft(4, '0');
    final e = ((h1 ^ h2) & 0xffffffff).toRadixString(16).padLeft(8, '0') +
        ((h1 + h2) & 0xffff).toRadixString(16).padLeft(4, '0');
    return '$a-$b-$c-$d-${e.substring(0, 12)}';
  }

  /// Java 版玩家名仅允许 3–16 位 `[A-Za-z0-9_]`。
  /// 中文等非法字符进单人服会报「无法连接服务器 / Invalid characters in username」。
  static String sanitizeMinecraftUsername(String raw) {
    final trimmed = raw.trim();
    final ascii = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    if (ascii.length >= 3 && ascii.length <= 16) return ascii;
    if (ascii.length > 16) return ascii.substring(0, 16);
    final hash = offlineUuidFor(trimmed).replaceAll('-', '');
    final suffix = hash.substring(0, 4);
    final base = ascii.isEmpty ? 'Player' : ascii;
    var out = '${base}_$suffix';
    if (out.length > 16) {
      final keep = 16 - 1 - suffix.length;
      out = '${base.substring(0, keep.clamp(1, base.length))}_$suffix';
    }
    if (out.length < 3) out = 'Player$suffix';
    return out.length > 16 ? out.substring(0, 16) : out;
  }

  static bool isValidMinecraftUsername(String name) =>
      RegExp(r'^[A-Za-z0-9_]{3,16}$').hasMatch(name);
}
