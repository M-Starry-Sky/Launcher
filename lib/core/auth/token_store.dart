import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// token 安全存储：所有令牌只放系统安全存储，绝不落普通文件。
class TokenStore {
  static const String _keyMicrosoftTokens = 'tokens_microsoft';
  static const String _keyElybyTokens = 'tokens_elyby';
  static const String _keyGameSession = 'game_session';
  static const String _keyProfile = 'profile';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<Map<String, String?>> _readJson(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded.map((k, v) => MapEntry(k, v?.toString()));
    }
    return {};
  }

  Future<void> _writeJson(String key, Map<String, String?> value) async {
    await _storage.write(key: key, value: jsonEncode(value));
  }

  // ---- 平台登录令牌（microsoft / elyby） ----

  Future<void> savePlatformTokens({
    required String source,
    required String accessToken,
    String? refreshToken,
    String? externalId,
    String? username,
    DateTime? expiresAt,
  }) async {
    final key = source == 'microsoft' ? _keyMicrosoftTokens : _keyElybyTokens;
    await _writeJson(key, {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'external_id': externalId,
      'username': username,
      'expires_at': expiresAt?.millisecondsSinceEpoch.toString(),
    });
  }

  Future<Map<String, String?>> readPlatformTokens(String source) async {
    final key = source == 'microsoft' ? _keyMicrosoftTokens : _keyElybyTokens;
    return _readJson(key);
  }

  Future<void> clearPlatformTokens(String source) async {
    final key = source == 'microsoft' ? _keyMicrosoftTokens : _keyElybyTokens;
    await _storage.delete(key: key);
  }

  // ---- 游戏会话（微软正版链 / ely.by 档案） ----

  Future<void> saveGameSession({
    required String accessToken,
    required String uuid,
    required String name,
    String? refreshToken,
  }) async {
    await _writeJson(_keyGameSession, {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'uuid': uuid,
      'name': name,
    });
  }

  Future<Map<String, String?>> readGameSession() => _readJson(_keyGameSession);

  Future<void> clearGameSession() => _storage.delete(key: _keyGameSession);

  // ---- 当前登录资料（用于 UI 展示） ----

  Future<void> saveProfile({
    required String source,
    required String externalId,
    required String username,
    String? avatarUrl,
    String? gender,
  }) async {
    await _writeJson(_keyProfile, {
      'source': source,
      'external_id': externalId,
      'username': username,
      'avatar_url': avatarUrl,
      'gender': gender ?? 'male',
    });
  }

  Future<Map<String, String?>> readProfile() => _readJson(_keyProfile);

  Future<void> clearAll() async {
    await _storage.delete(key: _keyMicrosoftTokens);
    await _storage.delete(key: _keyElybyTokens);
    await _storage.delete(key: _keyGameSession);
    await _storage.delete(key: _keyProfile);
  }
}
