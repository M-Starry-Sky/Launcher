import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/pack.dart';
import '../core/network/api_client.dart';
import '../core/network/secure_endpoint.dart';
import '../core/download/download_sources.dart';

/// 整合包服务。
class PackService {
  final ApiClient api;

  PackService(this.api);

  Future<({String packId, String shareCode})> create({
    required String name,
    required String gameVersion,
    required String loaderType,
    String? loaderVersion,
    required String gameType,
    PackManifest? manifest,
  }) async {
    final json = await api.post(SecureRoutes.packCreate, body: {
      'name': name,
      'game_version': gameVersion,
      'loader_type': loaderType,
      if (loaderVersion != null) 'loader_version': loaderVersion,
      'game_type': gameType,
      'manifest': manifest?.toJson() ?? const PackManifest(
        mods: [],
        resourcePacks: [],
        behaviorPacks: [],
        configOverrides: {},
      ).toJson(),
    });
    return (
      packId: json['pack_id'] as String,
      shareCode: (json['share_code'] ?? '') as String,
    );
  }

  Future<List<PackSummary>> list() async {
    final json = await api.get(SecureRoutes.packList);
    final items = (json['items'] as List? ?? const []);
    return items
        .map((e) => PackSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<PackSummary> detail(String packId) async {
    final json = await api.get(SecureRoutes.packById(packId));
    return PackSummary.fromJson(json);
  }

  Future<bool> verify(String packId) async {
    final json =
        await api.post(SecureRoutes.packVerify, body: {'pack_id': packId});
    return json['allowed'] == true;
  }

  Future<({String packId, String name})> importByShareCode(
      String shareCode) async {
    final json = await api
        .post(SecureRoutes.packImport, body: {'share_code': shareCode});
    return (
      packId: json['pack_id'] as String,
      name: (json['name'] ?? '') as String,
    );
  }

  Future<PackManifestResponse> manifest(String packId) async {
    final json = await api.get(SecureRoutes.packManifest(packId));
    return PackManifestResponse.fromJson(json);
  }

  Future<void> updateManifest(String packId, PackManifest manifest) async {
    await api.post(SecureRoutes.packManifest(packId), body: {
      'manifest': manifest.toJson(),
    });
  }

  Future<({String fileId, String sha1, String filename})> upload(
      List<int> bytes, String filename,
      {String license = 'original'}) async {
    final json = await api.upload(SecureRoutes.packUpload, bytes, filename,
        fields: {'license': license});
    return (
      fileId: json['file_id'] as String,
      sha1: (json['sha1'] ?? '') as String,
      filename: (json['filename'] ?? filename) as String,
    );
  }

  /// 仅换取直链（302→R2/CDN），文件本体由客户端直连，不经 Worker 中转。
  Future<String> downloadUrl(String fileId, String accessToken) async {
    final response = await http.get(
      Uri.parse('${_base()}${SecureRoutes.packDownload(fileId)}'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode == 302 || response.statusCode == 301) {
      final loc = response.headers['location'] ?? '';
      if (loc.isEmpty) {
        throw ApiException('获取下载地址失败（空 Location）');
      }
      final uri = Uri.parse(loc);
      if (uri.hasScheme) return loc;
      return '${_base()}$loc';
    }
    throw ApiException('获取下载地址失败 (${response.statusCode})');
  }

  String _base() {
    final base = api.baseUrl();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }
}

/// Modrinth API 客户端：元数据与 CDN 由前端直连；加速开启时走 MCIM（对齐 HMCL）。
class ModrinthClient {
  static const String _baseUrl = 'https://api.modrinth.com/v2';
  static const String _userAgent = 'xingqiong-launcher/0.1.0 (contact: xingqiong)';

  /// 为 false 时只打官方（调试用）；默认 true 与启动器加速一致。
  final bool useMirrors;

  ModrinthClient({this.useMirrors = true});

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      };

  Future<http.Response> _get(Uri official) async {
    final ordered = useMirrors
        ? DownloadSources.candidates(official)
        : <Uri>[official];
    Object? last;
    for (final uri in ordered) {
      try {
        final response = await http.get(uri, headers: _headers);
        if (response.statusCode == 200) return response;
        last = 'HTTP ${response.statusCode}@$uri';
      } catch (e) {
        last = e;
      }
    }
    throw ApiException('Modrinth 请求失败 ($official): $last');
  }

  /// 公开搜索：模组 / 整合包 / 资源包等。
  Future<List<ModrinthSearchHit>> search({
    required String query,
    String projectType = 'mod',
    String? gameVersion,
    String? loader,
    int limit = 20,
    int offset = 0,
  }) async {
    final facets = <List<String>>[
      ['project_type:$projectType'],
    ];
    if (gameVersion != null && gameVersion.trim().isNotEmpty) {
      facets.add(['versions:${gameVersion.trim()}']);
    }
    if (loader != null &&
        loader.trim().isNotEmpty &&
        loader != 'none' &&
        projectType == 'mod') {
      facets.add(['categories:${loader.trim()}']);
    }
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'query': query.trim(),
      'limit': '$limit',
      'offset': '$offset',
      'index': 'relevance',
      'facets': jsonEncode(facets),
    });
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw ApiException('Modrinth 搜索失败 (${response.statusCode})');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    final hits = (json['hits'] as List? ?? const []);
    return hits
        .whereType<Map>()
        .map((e) => ModrinthSearchHit.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 列出项目兼容版本。
  Future<List<ModrinthVersionInfo>> listVersions({
    required String projectId,
    String? gameVersion,
    String? loader,
  }) async {
    final params = <String, String>{};
    if (gameVersion != null && gameVersion.trim().isNotEmpty) {
      params['game_versions'] = '["${gameVersion.trim()}"]';
    }
    if (loader != null &&
        loader.trim().isNotEmpty &&
        loader != 'none') {
      params['loaders'] = '["${loader.trim()}"]';
    }
    final uri = Uri.parse('$_baseUrl/project/$projectId/version')
        .replace(queryParameters: params.isEmpty ? null : params);
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw ApiException('Modrinth 项目版本查询失败 (${response.statusCode})');
    }
    final list = jsonDecode(utf8.decode(response.bodyBytes));
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => ModrinthVersionInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 按版本 id 获取版本文件信息。
  ///
  /// [preferGameVersion] 非空且存在多文件时，优先选文件名匹配该 MC 版本的 jar。
  Future<({String url, String filename, String? sha1})> versionFile(
    String versionId, {
    String? preferGameVersion,
  }) async {
    final picked = await versionFiles(
      versionId,
      preferGameVersion: preferGameVersion,
    );
    return (
      url: picked.first.url,
      filename: picked.first.filename,
      sha1: picked.first.sha1,
    );
  }

  /// 列出某版本应下载的文件（解析阶段，不落盘）。
  Future<List<ModrinthFileRef>> versionFiles(
    String versionId, {
    String? preferGameVersion,
    ModrinthFileSelect fileSelect = ModrinthFileSelect.singleBest,
  }) async {
    final response = await _get(Uri.parse('$_baseUrl/version/$versionId'));
    if (response.statusCode != 200) {
      throw ApiException('Modrinth 版本查询失败 (${response.statusCode})');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    final files = (json['files'] as List? ?? []).whereType<Map>().toList();
    if (files.isEmpty) {
      throw ApiException('Modrinth 版本无可用文件');
    }

    final gv = preferGameVersion?.trim() ?? '';
    final selected = switch (fileSelect) {
      ModrinthFileSelect.viaFabricForGame when gv.isNotEmpty =>
        _selectViaFabricFilesForGame(files, gv),
      ModrinthFileSelect.allMatching when gv.isNotEmpty && files.length > 1 =>
        _selectFilesForGameVersion(files, gv),
      ModrinthFileSelect.singleBest when gv.isNotEmpty && files.length > 1 =>
        [_pickBestFileForGameVersion(files, gv)],
      _ => [
          files.firstWhere(
            (f) => f['primary'] == true,
            orElse: () => files.first,
          ),
        ],
    };

    if (selected.isEmpty) {
      throw ApiException('未找到匹配 $preferGameVersion 的模组文件');
    }

    return selected.map(ModrinthFileRef.fromJsonFile).toList();
  }

  Future<Uint8List> download(String url) async {
    final official = Uri.parse(url);
    final ordered = useMirrors
        ? DownloadSources.candidates(official)
        : <Uri>[official];
    Object? last;
    for (final uri in ordered) {
      try {
        final response = await http.get(uri, headers: _headers);
        if (response.statusCode == 200) {
          return response.bodyBytes;
        }
        last = 'HTTP ${response.statusCode}';
      } catch (e) {
        last = e;
      }
    }
    throw ApiException('Modrinth 下载失败 ($url): $last');
  }

  /// 下载指定版本到目录。
  Future<File> downloadVersion({
    required String versionId,
    required Directory targetDir,
    String? preferGameVersion,
  }) async {
    final outs = await downloadVersionFiles(
      versionId: versionId,
      targetDir: targetDir,
      preferGameVersion: preferGameVersion,
    );
    return outs.first;
  }

  /// 下载版本内已解析的匹配文件。
  Future<List<File>> downloadVersionFiles({
    required String versionId,
    required Directory targetDir,
    String? preferGameVersion,
    ModrinthFileSelect fileSelect = ModrinthFileSelect.singleBest,
  }) async {
    final infos = await versionFiles(
      versionId,
      preferGameVersion: preferGameVersion,
      fileSelect: fileSelect,
    );
    return downloadResolvedFiles(files: infos, targetDir: targetDir);
  }

  /// 按已解析的文件列表落盘（下载前筛选完成后再调用）。
  Future<List<File>> downloadResolvedFiles({
    required List<ModrinthFileRef> files,
    required Directory targetDir,
  }) async {
    await targetDir.create(recursive: true);
    final outs = <File>[];
    for (final fileInfo in files) {
      final bytes = await download(fileInfo.url);
      final out = File('${targetDir.path}/${fileInfo.filename}');
      await out.writeAsBytes(bytes);
      outs.add(out);
    }
    return outs;
  }

  /// 精确匹配 [gameVersion]：只解析、不下载。无精确版本时返回 null。
  Future<({String versionNumber, List<ModrinthFileRef> files})?>
      resolveExactGameFiles({
    required String projectId,
    required String gameVersion,
    required String loader,
    ModrinthFileSelect fileSelect = ModrinthFileSelect.singleBest,
  }) async {
    final gv = gameVersion.trim();
    if (gv.isEmpty) return null;
    final versions = await listVersions(
      projectId: projectId,
      gameVersion: gv,
      loader: loader,
    );
    final exact =
        versions.where((v) => v.gameVersions.contains(gv)).toList();
    if (exact.isEmpty) return null;
    final chosen = exact.first;
    final files = await versionFiles(
      chosen.id,
      preferGameVersion: gv,
      fileSelect: fileSelect,
    );
    if (files.isEmpty) return null;
    return (versionNumber: chosen.versionNumber, files: files);
  }

  /// 按项目 slug/id + 游戏版本取最新兼容版本并下载到目录。
  /// 精确版本无文件时，按同加载器全部版本做邻近回退（适配更多 MC 版本）。
  Future<List<File>> downloadLatestForGame({
    required String projectId,
    required String gameVersion,
    required Directory targetDir,
    String loader = 'fabric',
    bool allowNearFallback = true,
    ModrinthFileSelect fileSelect = ModrinthFileSelect.singleBest,
  }) async {
    var versions = await listVersions(
      projectId: projectId,
      gameVersion: gameVersion,
      loader: loader,
    );
    if (versions.isEmpty && allowNearFallback) {
      final all = await listVersions(
        projectId: projectId,
        loader: loader,
      );
      versions = _rankVersionsNear(all, gameVersion);
      // 禁止跨系回退：1.x 必须同 minor；日历版本同 major
      versions = versions
          .where(
            (v) => v.gameVersions.any((g) => _nearCompatible(g, gameVersion)),
          )
          .toList();
    }
    if (versions.isEmpty) {
      throw ApiException('未找到兼容 $gameVersion 的版本');
    }
    final exact = versions
        .where((v) => v.gameVersions.contains(gameVersion.trim()))
        .toList();
    if (exact.isEmpty && !allowNearFallback) {
      throw ApiException('未找到精确匹配 $gameVersion 的版本');
    }
    final chosen = exact.isNotEmpty ? exact.first : versions.first;
    if (!chosen.gameVersions.any((g) => _nearCompatible(g, gameVersion)) &&
        !chosen.gameVersions.contains(gameVersion.trim())) {
      throw ApiException(
        '拒绝安装不适配 $gameVersion 的模组版本（${chosen.versionNumber}）',
      );
    }
    return downloadVersionFiles(
      versionId: chosen.id,
      targetDir: targetDir,
      preferGameVersion: gameVersion,
      fileSelect: fileSelect,
    );
  }

  /// MC 版本在 jar 文件名中的常见标记（ViaFabric `mc1201` 等）。
  static List<String> mcFilenameTags(String gameVersion) {
    final p = _parseMcVersion(gameVersion);
    if (p == null) return [gameVersion.toLowerCase()];
    final (maj, min, pat) = p;
    final tags = <String>{
      gameVersion.toLowerCase(),
      '$maj.$min.$pat',
      '$maj.$min',
      'mc$maj$min$pat',
      '${maj}_${min}_$pat',
      '${maj}_$min',
    };
    if (pat == 0) {
      tags.add('mc$maj$min');
    }
    return tags.map((e) => e.toLowerCase()).toList();
  }

  static Map _pickBestFileForGameVersion(List<Map> files, String gameVersion) {
    final tags = mcFilenameTags(gameVersion);
    Map? best;
    var bestScore = -1;
    for (final f in files) {
      final name = '${f['filename'] ?? ''}'.toLowerCase();
      if (!name.endsWith('.jar')) continue;
      var score = 0;
      for (final t in tags) {
        if (name.contains(t)) score += 10;
      }
      if (RegExp(r'mc\d{3,5}').hasMatch(name) && score == 0) {
        score = -100;
      }
      if (f['primary'] == true) score += 1;
      if (score > bestScore) {
        bestScore = score;
        best = f;
      }
    }
    if (best != null && bestScore >= 0) return best;
    return files.firstWhere(
      (f) => f['primary'] == true,
      orElse: () => files.first,
    );
  }

  /// ViaFabric：仅公共 jar + 当前 MC 的 mc* jar；其它版本 / cotton 等不进列表。
  static List<Map> _selectViaFabricFilesForGame(
    List<Map> files,
    String gameVersion,
  ) {
    final tags = mcFilenameTags(gameVersion);
    final out = <Map>[];
    for (final f in files) {
      final name = '${f['filename'] ?? ''}'.toLowerCase();
      if (!name.endsWith('.jar')) continue;
      if (name.contains('cotton')) continue;
      if (name.contains('viafabricplus')) continue;
      if (!name.contains('viafabric')) continue;

      final mc = RegExp(r'mc(\d{3,5})').firstMatch(name);
      if (mc != null) {
        if (tags.any(name.contains)) out.add(f);
        continue;
      }
      // 公共主包：viafabric-0.4.x.jar（无 mc 段）
      out.add(f);
    }
    if (out.isEmpty) {
      throw ApiException('ViaFabric 无匹配 $gameVersion 的文件');
    }
    return out;
  }

  /// 多文件：当前版本专用 jar + 不含 mcXXXX 的公共 jar；排除其它 MC 变体。
  static List<Map> _selectFilesForGameVersion(
    List<Map> files,
    String gameVersion,
  ) {
    final tags = mcFilenameTags(gameVersion);
    final out = <Map>[];
    for (final f in files) {
      final name = '${f['filename'] ?? ''}'.toLowerCase();
      if (!name.endsWith('.jar')) continue;
      if (name.contains('cotton')) continue;
      final hasMcTag = RegExp(r'mc\d{3,5}').hasMatch(name);
      if (hasMcTag) {
        if (tags.any(name.contains)) out.add(f);
        continue;
      }
      out.add(f);
    }
    if (out.isEmpty) {
      return [_pickBestFileForGameVersion(files, gameVersion)];
    }
    return out;
  }

  /// 在同加载器版本池中，按与目标 MC 版本的邻近度排序（最近优先）。
  static List<ModrinthVersionInfo> _rankVersionsNear(
    List<ModrinthVersionInfo> all,
    String targetGame,
  ) {
    final target = _parseMcVersion(targetGame);
    if (all.isEmpty) return const [];
    final scored = <({ModrinthVersionInfo v, int dist})>[];
    for (final v in all) {
      var best = 1 << 30;
      for (final gv in v.gameVersions) {
        final p = _parseMcVersion(gv);
        if (p == null || target == null) {
          if (gv == targetGame) best = 0;
          continue;
        }
        final d = (p.$1 - target.$1).abs() * 10000 +
            (p.$2 - target.$2).abs() * 100 +
            (p.$3 - target.$3).abs();
        if (d < best) best = d;
      }
      if (best < (1 << 30)) scored.add((v: v, dist: best));
    }
    scored.sort((a, b) => a.dist.compareTo(b.dist));
    return scored.map((e) => e.v).toList();
  }

  static (int, int, int)? _parseMcVersion(String raw) {
    final m = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(raw.trim());
    if (m == null) return null;
    return (
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.tryParse(m.group(3) ?? '0') ?? 0,
    );
  }

  /// 邻近回退兼容：传统 1.x 必须同 minor（1.20.x 互邻，1.16 不接 1.20）；
  /// 日历版（26.x）同 major 即可。
  static bool _nearCompatible(String candidate, String target) {
    if (candidate.trim() == target.trim()) return true;
    final pa = _parseMcVersion(candidate);
    final pb = _parseMcVersion(target);
    if (pa == null || pb == null) return false;
    if (pa.$1 != pb.$1) return false;
    if (pa.$1 == 1) return pa.$2 == pb.$2;
    return true;
  }
}

class ModrinthSearchHit {
  final String projectId;
  final String slug;
  final String title;
  final String description;
  final String? iconUrl;
  final String projectType;
  final int downloads;
  final List<String> categories;

  const ModrinthSearchHit({
    required this.projectId,
    required this.slug,
    required this.title,
    required this.description,
    required this.iconUrl,
    required this.projectType,
    required this.downloads,
    required this.categories,
  });

  factory ModrinthSearchHit.fromJson(Map<String, dynamic> json) =>
      ModrinthSearchHit(
        projectId: (json['project_id'] ?? '') as String,
        slug: (json['slug'] ?? '') as String,
        title: (json['title'] ?? json['slug'] ?? '') as String,
        description: (json['description'] ?? '') as String,
        iconUrl: json['icon_url'] as String?,
        projectType: (json['project_type'] ?? 'mod') as String,
        downloads: (json['downloads'] as num?)?.toInt() ?? 0,
        categories: (json['categories'] as List? ?? const [])
            .map((e) => '$e')
            .toList(),
      );
}

class ModrinthVersionInfo {
  final String id;
  final String name;
  final String versionNumber;
  final List<String> gameVersions;
  final List<String> loaders;

  const ModrinthVersionInfo({
    required this.id,
    required this.name,
    required this.versionNumber,
    required this.gameVersions,
    required this.loaders,
  });

  factory ModrinthVersionInfo.fromJson(Map<String, dynamic> json) =>
      ModrinthVersionInfo(
        id: json['id'] as String,
        name: (json['name'] ?? '') as String,
        versionNumber: (json['version_number'] ?? '') as String,
        gameVersions: (json['game_versions'] as List? ?? const [])
            .map((e) => '$e')
            .toList(),
        loaders: (json['loaders'] as List? ?? const [])
            .map((e) => '$e')
            .toList(),
      );

  String get label =>
      versionNumber.isNotEmpty ? versionNumber : (name.isNotEmpty ? name : id);
}

/// Modrinth 版本文件（解析结果，尚未下载）。
class ModrinthFileRef {
  final String url;
  final String filename;
  final String? sha1;

  const ModrinthFileRef({
    required this.url,
    required this.filename,
    this.sha1,
  });

  factory ModrinthFileRef.fromJsonFile(Map file) {
    final hashes = (file['hashes'] as Map?) ?? {};
    return ModrinthFileRef(
      url: file['url'] as String,
      filename: file['filename'] as String,
      sha1: hashes['sha1']?.toString(),
    );
  }
}

/// 多文件版本在下载前的筛选策略。
enum ModrinthFileSelect {
  /// 只选一个最匹配当前 MC 的 jar（ViaFabricPlus 等）。
  singleBest,

  /// 当前 MC 相关的全部匹配文件（通用多文件）。
  allMatching,

  /// ViaFabric：仅公共主包 + 当前 MC 的 mc* jar。
  viaFabricForGame,
}

