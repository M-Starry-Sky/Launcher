import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_version.dart';

/// 从 GitHub 拉取版本清单 / Releases，做本地版本校验。
class GithubUpdateService {
  /// 优先 [version.json]，失败再试 Releases API。
  Future<UpdateCheckResult> check() async {
    try {
      final fromManifest = await _fromManifest();
      if (fromManifest != null) return fromManifest;
    } catch (_) {}

    try {
      final fromRelease = await _fromLatestRelease();
      if (fromRelease != null) return fromRelease;
    } catch (_) {}

    return UpdateCheckResult.unavailable(
      '无法从 GitHub 获取版本信息，请稍后重试',
    );
  }

  Future<UpdateCheckResult?> _fromManifest() async {
    final res = await http
        .get(
          Uri.parse(AppVersion.versionManifestUrl),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'XingqiongLauncher/${AppVersion.version}',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final remote = (json['version'] as String?)?.trim() ?? '';
    if (remote.isEmpty) return null;
    final notes = (json['notes'] as String?)?.trim() ?? '';
    final download = (json['download_url'] as String?)?.trim();
    final page = (json['release_url'] as String?)?.trim();
    return _compare(
      remote: remote,
      notes: notes,
      downloadUrl: (download != null && download.isNotEmpty)
          ? download
          : AppVersion.releasesPageUrl,
      releasePageUrl: (page != null && page.isNotEmpty)
          ? page
          : AppVersion.releasesPageUrl,
      source: 'version.json',
    );
  }

  Future<UpdateCheckResult?> _fromLatestRelease() async {
    final res = await http
        .get(
          Uri.parse(AppVersion.releasesApiUrl),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'XingqiongLauncher/${AppVersion.version}',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode == 404) {
      return UpdateCheckResult.upToDate(source: 'releases(empty)');
    }
    if (res.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final remote = tag.startsWith('v') ? tag.substring(1) : tag;
    if (remote.isEmpty) return null;
    final notes = (json['body'] as String?)?.trim() ?? '';
    final htmlUrl = (json['html_url'] as String?)?.trim();
    String? assetUrl;
    final assets = json['assets'];
    if (assets is List && assets.isNotEmpty) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = (a['name'] as String?)?.toLowerCase() ?? '';
        final url = (a['browser_download_url'] as String?)?.trim();
        if (url == null || url.isEmpty) continue;
        if (name.endsWith('.exe') ||
            name.endsWith('.zip') ||
            name.endsWith('.msix')) {
          assetUrl = url;
          break;
        }
        assetUrl ??= url;
      }
    }
    return _compare(
      remote: remote,
      notes: notes,
      downloadUrl: assetUrl ?? htmlUrl ?? AppVersion.releasesPageUrl,
      releasePageUrl: htmlUrl ?? AppVersion.releasesPageUrl,
      source: 'releases',
    );
  }

  UpdateCheckResult _compare({
    required String remote,
    required String notes,
    required String downloadUrl,
    required String releasePageUrl,
    required String source,
  }) {
    final local = AppVersion.version;
    final cmp = compareSemver(local, remote);
    if (cmp < 0) {
      return UpdateCheckResult.updateAvailable(
        localVersion: local,
        remoteVersion: remote,
        notes: notes,
        downloadUrl: downloadUrl,
        releasePageUrl: releasePageUrl,
        source: source,
      );
    }
    return UpdateCheckResult.upToDate(
      localVersion: local,
      remoteVersion: remote,
      source: source,
    );
  }

  /// 返回负：a < b；0：相等；正：a > b。非法段按 0。
  static int compareSemver(String a, String b) {
    List<int> parts(String v) {
      final core = v.trim().split(RegExp(r'[-+]')).first;
      return core
          .split('.')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

enum UpdateStatus { upToDate, updateAvailable, unavailable }

class UpdateCheckResult {
  final UpdateStatus status;
  final String localVersion;
  final String? remoteVersion;
  final String notes;
  final String? downloadUrl;
  final String? releasePageUrl;
  final String? message;
  final String source;

  const UpdateCheckResult._({
    required this.status,
    required this.localVersion,
    this.remoteVersion,
    this.notes = '',
    this.downloadUrl,
    this.releasePageUrl,
    this.message,
    this.source = '',
  });

  factory UpdateCheckResult.upToDate({
    String localVersion = AppVersion.version,
    String? remoteVersion,
    String source = '',
  }) =>
      UpdateCheckResult._(
        status: UpdateStatus.upToDate,
        localVersion: localVersion,
        remoteVersion: remoteVersion ?? localVersion,
        source: source,
      );

  factory UpdateCheckResult.updateAvailable({
    required String localVersion,
    required String remoteVersion,
    required String notes,
    required String downloadUrl,
    required String releasePageUrl,
    String source = '',
  }) =>
      UpdateCheckResult._(
        status: UpdateStatus.updateAvailable,
        localVersion: localVersion,
        remoteVersion: remoteVersion,
        notes: notes,
        downloadUrl: downloadUrl,
        releasePageUrl: releasePageUrl,
        source: source,
      );

  factory UpdateCheckResult.unavailable(String message) => UpdateCheckResult._(
        status: UpdateStatus.unavailable,
        localVersion: AppVersion.version,
        message: message,
      );

  bool get hasUpdate => status == UpdateStatus.updateAvailable;
}
