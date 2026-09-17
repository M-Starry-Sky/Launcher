/// 远程全局配置（公开，无需登录）。
class GlobalConfig {
  final bool enableMicrosoftLogin;
  final bool enableCustomAuthLogin; // 自定义登录 = Ely.by
  final bool enableJavaRoom;
  final bool enableBedrockRoom;
  final bool enablePackAutoDistribute;
  final String? disclaimerVersion;
  final String msClientId;
  final String elybyClientId;
  final String elybyClientSecret;
  final int elybyRedirectPort;

  const GlobalConfig({
    required this.enableMicrosoftLogin,
    required this.enableCustomAuthLogin,
    required this.enableJavaRoom,
    required this.enableBedrockRoom,
    required this.enablePackAutoDistribute,
    this.disclaimerVersion,
    this.msClientId = '',
    this.elybyClientId = '',
    this.elybyClientSecret = '',
    this.elybyRedirectPort = 7788,
  });

  factory GlobalConfig.fromJson(Map<String, dynamic> json) {
    final msId = _asString(json['ms_client_id']) ?? '';
    final elyId = _asString(json['elyby_client_id']) ?? '';
    final msFlag = _asBool(json['enable_microsoft_login'], true);
    final elyFlag = _asBool(json['enable_custom_auth_login'], false);
    return GlobalConfig(
      // 未填 Azure GUID 时仍可用 Xbox Live 公共客户端
      enableMicrosoftLogin: msFlag,
      enableCustomAuthLogin: elyFlag && elyId.trim().isNotEmpty,
      enableJavaRoom: _asBool(json['enable_java_room'], true),
      enableBedrockRoom: _asBool(json['enable_bedrock_room'], false),
      enablePackAutoDistribute:
          _asBool(json['enable_pack_auto_distribute'], false),
      disclaimerVersion: _asString(json['disclaimer_version']),
      msClientId: msId,
      elybyClientId: elyId,
      elybyClientSecret: _asString(json['elyby_client_secret']) ?? '',
      elybyRedirectPort: _asInt(json['elyby_redirect_port'], 7788),
    );
  }

  /// 后端不可达：微软走内置 Live 公共客户端；Ely.by 仍关闭。
  static const GlobalConfig fallback = GlobalConfig(
    enableMicrosoftLogin: true,
    enableCustomAuthLogin: false,
    enableJavaRoom: true,
    enableBedrockRoom: false,
    enablePackAutoDistribute: false,
  );

  static bool _asBool(Object? value, bool defaultValue) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == '1' || v == 'yes') return true;
      if (v == 'false' || v == '0' || v == 'no') return false;
    }
    return defaultValue;
  }

  static String? _asString(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  static int _asInt(Object? value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? defaultValue;
    return defaultValue;
  }
}
