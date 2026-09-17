/// 整合包模型（对应后端 pack_info + manifest 结构）。
class PackSummary {
  final String packId;
  final String name;
  final String gameType;
  final String gameVersion;
  final String loaderType;
  final String shareCode;

  const PackSummary({
    required this.packId,
    required this.name,
    required this.gameType,
    required this.gameVersion,
    required this.loaderType,
    required this.shareCode,
  });

  factory PackSummary.fromJson(Map<String, dynamic> json) => PackSummary(
        packId: json['pack_id'] as String,
        name: json['name'] as String,
        gameType: (json['game_type'] ?? 'java') as String,
        gameVersion: (json['game_version'] ?? '') as String,
        loaderType: (json['loader_type'] ?? 'none') as String,
        shareCode: (json['share_code'] ?? '') as String,
      );
}

/// manifest 中的一条内容（modrinth 官方源 / 自定义上传文件）。
class ManifestEntry {
  final String type; // modrinth / custom
  final String? slug;
  final String? versionId;
  final String? fileId;
  final String? filename;
  final String? sha1;
  final String? downloadUrl;

  const ManifestEntry({
    required this.type,
    this.slug,
    this.versionId,
    this.fileId,
    this.filename,
    this.sha1,
    this.downloadUrl,
  });

  factory ManifestEntry.fromJson(Map<String, dynamic> json) => ManifestEntry(
        type: (json['type'] ?? 'modrinth') as String,
        slug: json['slug'] as String?,
        versionId: json['version_id'] as String?,
        fileId: json['file_id'] as String?,
        filename: json['filename'] as String?,
        sha1: json['sha1'] as String?,
        downloadUrl: json['download_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        if (slug != null) 'slug': slug,
        if (versionId != null) 'version_id': versionId,
        if (fileId != null) 'file_id': fileId,
        if (filename != null) 'filename': filename,
        if (sha1 != null) 'sha1': sha1,
      };
}

/// 整合包 manifest：仅允许 用户原创 / 经授权可再分发的内容 走 custom 上传；
/// modrinth 条目由客户端从 Modrinth 官方 API 下载。
class PackManifest {
  final List<ManifestEntry> mods;
  final List<ManifestEntry> resourcePacks;
  final List<ManifestEntry> behaviorPacks;
  final Map<String, dynamic> configOverrides;

  const PackManifest({
    required this.mods,
    required this.resourcePacks,
    required this.behaviorPacks,
    required this.configOverrides,
  });

  factory PackManifest.fromJson(dynamic json) {
    final map = (json is Map<String, dynamic>) ? json : <String, dynamic>{};
    List<ManifestEntry> list(String key) => (map[key] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ManifestEntry.fromJson)
        .toList();
    return PackManifest(
      mods: list('mods'),
      resourcePacks: list('resource_packs'),
      behaviorPacks: list('behavior_packs'),
      configOverrides: (map['config_overrides'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'mods': mods.map((e) => e.toJson()).toList(),
        'resource_packs': resourcePacks.map((e) => e.toJson()).toList(),
        'behavior_packs': behaviorPacks.map((e) => e.toJson()).toList(),
        'config_overrides': configOverrides,
      };
}

/// 整合包清单完整返回。
class PackManifestResponse {
  final String packId;
  final String gameVersion;
  final String loaderType;
  final String loaderVersion;
  final String gameType;
  final PackManifest manifest;

  const PackManifestResponse({
    required this.packId,
    required this.gameVersion,
    required this.loaderType,
    required this.loaderVersion,
    required this.gameType,
    required this.manifest,
  });

  factory PackManifestResponse.fromJson(Map<String, dynamic> json) =>
      PackManifestResponse(
        packId: json['pack_id'] as String,
        gameVersion: (json['game_version'] ?? '') as String,
        loaderType: (json['loader_type'] ?? 'none') as String,
        loaderVersion: (json['loader_version'] ?? '') as String,
        gameType: (json['game_type'] ?? 'java') as String,
        manifest: PackManifest.fromJson(json['manifest']),
      );
}
