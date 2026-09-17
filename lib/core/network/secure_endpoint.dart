import 'payload_cipher.dart';

/// 密封的后端入口与路由表。明文不入库；可用 --dart-define=BACKEND_BASE_URL= 覆盖主机。
class SecureEndpoint {
  SecureEndpoint._();

  static const String _sealedHost =
      'MkjlkmSOQiexmEwdNfJhuz0R/YNi2g5grIMPGCX4ZbA0WL+Hb9cEfKCfRRUp+GK0KFn/zGDbH2Osg1FUIP54';

  static final String _compiledOverride = const String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: '',
  );

  static String get backendBaseUrl {
    final override = _compiledOverride.trim();
    if (override.isNotEmpty) return override;
    return PayloadCipher.unveil(_sealedHost);
  }
}

/// 密封的业务路由（相对路径）。
class SecureRoutes {
  SecureRoutes._();

  static String get config =>
      PayloadCipher.unveil('dV3hizjXAmavmEU=');

  static String get homeBanners =>
      PayloadCipher.unveil('dV3hizjcAmWs3kAbKvVrpyk=');

  static String get homeNotices =>
      PayloadCipher.unveil('dV3hizjcAmWs3kwVMPJtsCk=');

  static String get packCreate =>
      PayloadCipher.unveil('dV3hizjEDGui3kEIIfp6sA==');

  static String get packList =>
      PayloadCipher.unveil('dV3hizjEDGui3k4TN+8=');

  static String get packVerify =>
      PayloadCipher.unveil('dV3hizjEDGui3lQfNvJorA==');

  static String get packImport =>
      PayloadCipher.unveil('dV3hizjEDGui3ksXNPR8oQ==');

  static String get packUpload =>
      PayloadCipher.unveil('dV3hizjEDGui3lcKKPRvsQ==');

  static String get _packPrefix =>
      PayloadCipher.unveil('dV3hizjEDGui3g==');

  static String get _packDownloadPrefix =>
      PayloadCipher.unveil('dV3hizjEDGui3kYVM/ViujtYvg==');

  static String get roomCreate =>
      PayloadCipher.unveil('dV3hizjGAmek3kEIIfp6sA==');

  static String get _roomJoinPrefix =>
      PayloadCipher.unveil('dV3hizjGAmek3kgVLfUh');

  static String get roomClose =>
      PayloadCipher.unveil('dV3hizjGAmek3kEWK+hr');

  static String get _roomPrefix =>
      PayloadCipher.unveil('dV3hizjGAmek3g==');

  static String get communityGuidelines =>
      PayloadCipher.unveil('dV3hizjXAmWkhEwTMOIhsi9V9Yd73QNtug==');

  static String get communityPosts =>
      PayloadCipher.unveil('dV3hizjXAmWkhEwTMOIhpTVP5ZE=');

  static String packById(String packId) => '$_packPrefix$packId';

  static String packManifest(String packId) =>
      '${packById(packId)}/manifest';

  static String packDownload(String fileId) =>
      '$_packDownloadPrefix$fileId';

  static String roomJoin(String code) => '$_roomJoinPrefix$code';

  static String roomPackManifest(String roomId) =>
      '$_roomPrefix$roomId/pack-manifest';

  static String communityPost(String postId) =>
      '$communityPosts/$postId';

  static String communityReport(String postId) =>
      '${communityPost(postId)}/report';
}
