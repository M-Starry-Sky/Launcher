import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../download/download_sources.dart';
import '../download/network_env.dart';
import 'version_installer.dart';

/// 远程版本目录：镜像优先拉取 Mojang 清单（对齐 HMCL），Fabric Loader 走官方/镜像。
class VersionCatalog {
  static const String _ua = VersionInstaller.userAgent;

  final AppConfig? config;

  VersionCatalog({this.config});

  List<String> get _mirrorBases {
    final list = config?.downloadMirrorBases ?? const <String>[];
    if (list.isEmpty) return DownloadSources.defaultMirrorBases;
    return list;
  }

  Future<List<RemoteGameVersion>> listGameVersions({
    bool releaseOnly = false,
  }) async {
    await NetworkEnv.instance.ensureProbed();
    final uris = DownloadSources.versionManifestCandidates(
      mirrorBases: _mirrorBases,
    );
    if (NetworkEnv.instance.preferMirrors && uris.length > 1) {
      final ordered = [
        ...uris.where((u) => !_isOfficial(u.host)),
        ...uris.where((u) => _isOfficial(u.host)),
      ];
      uris
        ..clear()
        ..addAll(ordered);
    }

    Object? last;
    for (final uri in uris) {
      try {
        final res = await http
            .get(uri, headers: {'User-Agent': _ua})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) {
          last = 'HTTP ${res.statusCode} @ ${uri.host}';
          continue;
        }
        final json =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final list = (json['versions'] as List? ?? [])
            .whereType<Map>()
            .map((v) => RemoteGameVersion(
                  id: v['id'] as String? ?? '',
                  type: v['type'] as String? ?? 'release',
                  releaseTime: v['releaseTime'] as String? ?? '',
                  url: v['url'] as String? ?? '',
                ))
            .where((v) => v.id.isNotEmpty)
            .toList();
        if (releaseOnly) {
          return list.where((v) => v.type == 'release').toList();
        }
        return list;
      } catch (e) {
        last = e;
      }
    }
    throw StateError('获取版本清单失败（已尝试镜像与官方）: $last');
  }

  static bool _isOfficial(String host) {
    final h = host.toLowerCase();
    return h.endsWith('mojang.com') || h.endsWith('minecraft.net');
  }

  Future<List<String>> listFabricLoaders(String gameVersion) async {
    await NetworkEnv.instance.ensureProbed();
    final official = Uri.parse(
      'https://meta.fabricmc.net/v2/versions/loader/$gameVersion',
    );
    final uris = DownloadSources.candidates(
      official,
      mirrorBases: _mirrorBases,
    );
    if (NetworkEnv.instance.preferMirrors && uris.length > 1) {
      final ordered = [
        ...uris.where((u) => !_isOfficial(u.host)),
        ...uris.where((u) => _isOfficial(u.host)),
      ];
      uris
        ..clear()
        ..addAll(ordered);
    }

    Object? last;
    for (final uri in uris) {
      try {
        final res = await http
            .get(uri, headers: {'User-Agent': _ua})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) {
          last = 'HTTP ${res.statusCode}';
          continue;
        }
        final list = jsonDecode(utf8.decode(res.bodyBytes));
        if (list is! List) return [];
        final versions = <String>[];
        for (final item in list) {
          if (item is! Map) continue;
          final loader = item['loader'];
          if (loader is Map && loader['version'] is String) {
            versions.add(loader['version'] as String);
          }
        }
        return versions;
      } catch (e) {
        last = e;
      }
    }
    throw StateError('获取 Fabric Loader 失败: $last');
  }
}

class RemoteGameVersion {
  final String id;
  final String type;
  final String releaseTime;
  final String url;

  const RemoteGameVersion({
    required this.id,
    required this.type,
    required this.releaseTime,
    required this.url,
  });
}
