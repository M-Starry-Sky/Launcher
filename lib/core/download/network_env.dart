import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'download_sources.dart';

/// 探测结果：延迟越低越好；不可达为 null。
class SourceProbe {
  final String id;
  final Uri uri;
  final int? latencyMs;
  final String? error;

  const SourceProbe({
    required this.id,
    required this.uri,
    this.latencyMs,
    this.error,
  });

  bool get ok => latencyMs != null;
}

/// 自动检查网络环境，按延迟排序下载源（会话级缓存）。
class NetworkEnv {
  NetworkEnv._();
  static final NetworkEnv instance = NetworkEnv._();

  static const _cacheTtl = Duration(minutes: 15);
  static const _probeTimeout = Duration(seconds: 4);

  DateTime? _probedAt;
  bool? _preferMirrors;
  List<SourceProbe> _lastProbes = const [];
  String? _bestJavaMirrorBase;

  bool get preferMirrors => _preferMirrors ?? true;
  List<SourceProbe> get lastProbes => List.unmodifiable(_lastProbes);
  String? get bestJavaMirrorBase => _bestJavaMirrorBase;

  bool get _cacheFresh =>
      _probedAt != null &&
      DateTime.now().difference(_probedAt!) < _cacheTtl;

  /// 强制重新探测。
  Future<void> refresh({void Function(String line)? onLog}) async {
    _probedAt = null;
    await ensureProbed(onLog: onLog);
  }

  /// 是否中国大陆环境（对齐 HMCL `LocaleUtils.IS_CHINA_MAINLAND`）。
  /// 手机 / PC 共用。
  static bool get isChinaMainland {
    final loc = ui.PlatformDispatcher.instance.locale;
    if (loc.countryCode?.toUpperCase() == 'CN') return true;
    if (loc.languageCode.toLowerCase() != 'zh') return false;
    final script = loc.scriptCode?.toLowerCase();
    if (script == 'hant') return false;
    return true;
  }

  /// 探测国内镜像 vs 官方：决定游戏资源是否优先镜像。
  Future<void> ensureProbed({void Function(String line)? onLog}) async {
    if (_cacheFresh) return;
    onLog?.call('正在检测网络环境与下载源…');

    final client = http.Client();
    try {
      final targets = <(String id, Uri uri)>[
        (
          'bmclapi2',
          Uri.parse('https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json'),
        ),
        (
          'bmclapi',
          Uri.parse('https://bmclapi.bangbang93.com/mc/game/version_manifest_v2.json'),
        ),
        (
          'mojang',
          Uri.parse(
            'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json',
          ),
        ),
        (
          'tuna-adoptium',
          Uri.parse('https://mirrors.tuna.tsinghua.edu.cn/Adoptium/'),
        ),
        (
          'bfsu-adoptium',
          Uri.parse('https://mirrors.bfsu.edu.cn/Adoptium/'),
        ),
        (
          'adoptium-api',
          Uri.parse('https://api.adoptium.net/v3/info/available_releases'),
        ),
      ];

      final probes = await Future.wait(
        targets.map((t) => _probeOne(client, t.$1, t.$2)),
      );
      probes.sort((a, b) {
        if (a.ok != b.ok) return a.ok ? -1 : 1;
        return (a.latencyMs ?? 1 << 30).compareTo(b.latencyMs ?? 1 << 30);
      });
      _lastProbes = probes;
      _probedAt = DateTime.now();

      final bmcl = _bestOf(probes, const ['bmclapi2', 'bmclapi']);
      final mojang = _bestOf(probes, const ['mojang']);

      // 对齐 HMCL：中国大陆（含手机）默认第三方镜像优先，官方仅回落。
      if (isChinaMainland) {
        _preferMirrors = bmcl != null || mojang == null;
      } else if (bmcl != null && mojang != null) {
        _preferMirrors = bmcl.latencyMs! <= mojang.latencyMs! + 80;
      } else {
        _preferMirrors = bmcl != null || mojang == null;
      }

      final javaMirror = _bestOf(probes, const ['tuna-adoptium', 'bfsu-adoptium']);
      if (javaMirror?.id == 'tuna-adoptium') {
        _bestJavaMirrorBase = 'https://mirrors.tuna.tsinghua.edu.cn/Adoptium';
      } else if (javaMirror?.id == 'bfsu-adoptium') {
        _bestJavaMirrorBase = 'https://mirrors.bfsu.edu.cn/Adoptium';
      } else {
        _bestJavaMirrorBase = null;
      }

      final mode = preferMirrors
          ? (isChinaMainland
              ? '第三方镜像优先（BMCLAPI / 对齐 HMCL）'
              : '国内镜像优先')
          : '官方源可达，镜像与官方并行';
      final parts = probes
          .where((e) => e.ok)
          .take(4)
          .map((e) => '${e.id} ${e.latencyMs}ms')
          .join(' · ');
      onLog?.call('网络检测完成：$mode${parts.isEmpty ? '' : '（$parts）'}');
    } finally {
      client.close();
    }
  }

  /// 按探测结果重排游戏镜像 base（快的在前）。
  Future<List<String>> rankedMirrorBases(
    List<String> configured, {
    void Function(String line)? onLog,
  }) async {
    await ensureProbed(onLog: onLog);
    final bases = configured.isEmpty
        ? List<String>.from(DownloadSources.defaultMirrorBases)
        : List<String>.from(configured);

    int score(String base) {
      final host = Uri.tryParse(base)?.host.toLowerCase() ?? base.toLowerCase();
      for (final p in _lastProbes) {
        if (!p.ok) continue;
        if (host.contains(p.id) || p.uri.host.toLowerCase().contains(host)) {
          return p.latencyMs!;
        }
        // bmclapi2 ↔ id
        if (host.contains('bmclapi2') && p.id == 'bmclapi2') return p.latencyMs!;
        if (host.contains('bmclapi') &&
            !host.contains('bmclapi2') &&
            p.id == 'bmclapi') {
          return p.latencyMs!;
        }
      }
      return preferMirrors ? 5000 : 3000;
    }

    bases.sort((a, b) => score(a).compareTo(score(b)));
    if (!preferMirrors) {
      // 官方较好时仍保留镜像，但不刻意打乱已排好的快镜像
    }
    return bases;
  }

  /// Java 包候选：国内 Adoptium 目录镜像 + 官方 API（按网络环境排序）。
  Future<List<Uri>> rankedJavaBinaryUris({
    required int major,
    required String os,
    required String arch,
    required String imageType, // jdk | jre
    void Function(String line)? onLog,
  }) async {
    await ensureProbed(onLog: onLog);
    final client = http.Client();
    try {
      final mirrorBases = <String>[
        if (_bestJavaMirrorBase != null) _bestJavaMirrorBase!,
        'https://mirrors.tuna.tsinghua.edu.cn/Adoptium',
        'https://mirrors.bfsu.edu.cn/Adoptium',
      ];
      // 去重保序
      final seenBase = <String>{};
      final uniqueBases = <String>[];
      for (final b in mirrorBases) {
        if (seenBase.add(b)) uniqueBases.add(b);
      }

      final out = <Uri>[];
      final seen = <String>{};

      void add(Uri u) {
        if (seen.add(u.toString())) out.add(u);
      }

      // 并行解析目录里最新 zip/tar.gz
      final resolved = await Future.wait(
        uniqueBases.map((base) async {
          try {
            return await _resolveMirrorPackage(
              client,
              base: base,
              major: major,
              os: os,
              arch: arch,
              imageType: imageType,
            );
          } catch (_) {
            return null;
          }
        }),
      );
      for (final u in resolved) {
        if (u != null) add(u);
      }

      // 官方 API（GitHub release，国内常慢，放后面；若镜像全挂则靠它）
      add(Uri.parse(
        'https://api.adoptium.net/v3/binary/latest/$major/ga/'
        '$os/$arch/$imageType/hotspot/normal/eclipse?project=jdk',
      ));

      // 若探测显示官方 API 很快、镜像都很慢，把官方提前
      final api = _bestOf(_lastProbes, const ['adoptium-api']);
      final tuna = _bestOf(_lastProbes, const ['tuna-adoptium', 'bfsu-adoptium']);
      if (api != null &&
          (tuna == null || api.latencyMs! + 120 < tuna.latencyMs!)) {
        final official = out.removeLast();
        out.insert(0, official);
        onLog?.call('Java 源：官方 Adoptium 延迟更优，优先官方');
      } else if (out.length > 1) {
        onLog?.call('Java 源：优先国内镜像（清华/北外），官方回落');
      }
      return out;
    } finally {
      client.close();
    }
  }

  Future<Uri?> _resolveMirrorPackage(
    http.Client client, {
    required String base,
    required int major,
    required String os,
    required String arch,
    required String imageType,
  }) async {
    final dir = Uri.parse(
      '${base.replaceAll(RegExp(r'/$'), '')}/$major/$imageType/$arch/$os/',
    );
        final res = await client
            .get(dir, headers: _headers)
            .timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 400) return null;
    final body = res.body;
    final re = RegExp(
      imageType == 'jre'
          ? r'OpenJDK[\w.\-]*jre[\w.\-]*\.(?:zip|tar\.gz)'
          : r'OpenJDK[\w.\-]*jdk[\w.\-]*\.(?:zip|tar\.gz)',
      caseSensitive: false,
    );
    final matches = re.allMatches(body).map((m) => m.group(0)!).toSet().toList();
    if (matches.isEmpty) return null;
    matches.sort(); // 版本号字符串大致递增，取最后一个较新
    final file = matches.last;
    return dir.resolve(file);
  }

  Future<SourceProbe> _probeOne(http.Client client, String id, Uri uri) async {
    final sw = Stopwatch()..start();
    try {
      final req = http.Request('GET', uri);
      req.headers.addAll(_headers);
      final streamed =
          await client.send(req).timeout(_probeTimeout);
      // 读一点 body 证明链路可用
      await streamed.stream.first.timeout(_probeTimeout);
      sw.stop();
      if (streamed.statusCode < 200 || streamed.statusCode >= 400) {
        return SourceProbe(
          id: id,
          uri: uri,
          error: 'HTTP ${streamed.statusCode}',
        );
      }
      return SourceProbe(id: id, uri: uri, latencyMs: sw.elapsedMilliseconds);
    } on TimeoutException {
      return SourceProbe(id: id, uri: uri, error: 'timeout');
    } on SocketException catch (e) {
      return SourceProbe(id: id, uri: uri, error: e.message);
    } catch (e) {
      return SourceProbe(id: id, uri: uri, error: '$e');
    }
  }

  SourceProbe? _bestOf(List<SourceProbe> probes, List<String> ids) {
    SourceProbe? best;
    for (final p in probes) {
      if (!p.ok || !ids.contains(p.id)) continue;
      if (best == null || p.latencyMs! < best.latencyMs!) best = p;
    }
    return best;
  }

  static Map<String, String> get _headers => {
        'User-Agent': DownloadSources.userAgent,
        'Accept': '*/*',
      };
}
