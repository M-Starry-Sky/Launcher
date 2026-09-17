import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'download_sources.dart';
import 'network_env.dart';
import 'peer_swarm.dart';

enum DownloadChannel { peer, multiSource, single, fallback }

class DownloadResult {
  final DownloadChannel channel;
  final Uri usedUri;
  const DownloadResult({required this.channel, required this.usedUri});
}

/// 全局限流闸门：桌面对齐 HMCL `max(CPU×2, 6)`；
/// 手机移动网过高并发易 429/重试，压到 4–8。
class _DownloadGate {
  static final _DownloadGate instance = _DownloadGate._();
  _DownloadGate._();

  static int get maxConcurrent {
    final n = Platform.numberOfProcessors;
    if (Platform.isAndroid || Platform.isIOS) {
      return n.clamp(4, 8);
    }
    return math.max(n * 2, 6).clamp(6, 32);
  }

  var _inflight = 0;
  final _waiters = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() fn) async {
    while (_inflight >= maxConcurrent) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _inflight++;
    try {
      return await fn();
    } finally {
      _inflight--;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }
}

/// 多源加速下载：镜像优先、官方快失败、全局限流、资产不走 Range。
class AcceleratedDownloader {
  static const _chunkSize = 2 * 1024 * 1024;
  static const _minChunkedBytes = 16 * 1024 * 1024;
  static const _smallFileBytes = 512 * 1024;
  static const _mirrorConnectTimeout = Duration(seconds: 15);
  static const _officialConnectTimeout = Duration(seconds: 4);
  static const _idleTimeout = Duration(seconds: 45);

  final AppConfig? config;
  final void Function(String message)? onLog;
  final PeerSwarm swarm;

  http.Client? _client;
  final Set<String> _badHosts = {};
  final Map<String, int> _hostFailStreak = {};
  final Set<String> _loggedSkipHosts = {};
  var _chunkFallbackLogged = false;
  var _rateLimitLogged = false;
  var _concurrencyLogged = false;

  String? versionId;

  AcceleratedDownloader({
    this.config,
    this.onLog,
    this.versionId,
    PeerSwarm? swarm,
  }) : swarm = swarm ?? peerSwarm;

  void _log(String m) => onLog?.call(m);

  bool get _accelEnabled => config?.downloadAccelEnabled ?? true;
  bool get _peerEnabled => config?.downloadPeerEnabled ?? true;

  List<String>? _rankedMirrors;
  Future<List<String>> _mirrorsAsync() async {
    if (_rankedMirrors != null) return _rankedMirrors!;
    final list = config?.downloadMirrorBases ?? const <String>[];
    _rankedMirrors = await NetworkEnv.instance.rankedMirrorBases(
      list,
      onLog: onLog,
    );
    return _rankedMirrors!;
  }

  http.Client get _http => _client ??= http.Client();

  void close() {
    _client?.close();
    _client = null;
  }

  static bool _isOfficialHost(String host) {
    final h = host.toLowerCase();
    // 海外源：preferMirrors 时排到 MCIM / BMCL 之后
    return h.endsWith('mojang.com') ||
        h.endsWith('minecraft.net') ||
        h.endsWith('fabricmc.net') ||
        h.endsWith('modrinth.com') ||
        h.endsWith('forgecdn.net') ||
        h.endsWith('curseforge.com') ||
        h.endsWith('minecraftforge.net') ||
        h.endsWith('neoforged.net');
  }

  static bool _isAssetOfficial(Uri uri) =>
      uri.host.toLowerCase() == 'resources.download.minecraft.net';

  static bool _isAssetLike(Uri uri) {
    if (_isAssetOfficial(uri)) return true;
    return uri.path.toLowerCase().contains('/assets/');
  }

  Duration _connectTimeoutFor(Uri uri) => _isOfficialHost(uri.host)
      ? _officialConnectTimeout
      : _mirrorConnectTimeout;

  Future<void> ensurePeerRunning() async {
    if (!_accelEnabled || !_peerEnabled) return;
    // 移动端不启局域网 HTTP/UDP 互传
    if (Platform.isAndroid || Platform.isIOS) return;
    if (!swarm.running) {
      try {
        await swarm.start().timeout(const Duration(seconds: 3));
        _log('节点互传已就绪 (port=${swarm.httpPort})');
      } catch (e) {
        _log('节点互传跳过: $e');
      }
    }
  }

  Future<DownloadResult> downloadTo(
    Uri official,
    File target, {
    String? expectedSha1,
    int? expectedSize,
  }) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.part');
    await _safeDelete(tmp);

    if (!_concurrencyLogged) {
      _concurrencyLogged = true;
      final tip = (Platform.isAndroid || Platform.isIOS)
          ? '手机限流'
          : '对齐 HMCL';
      _log('下载并发 ${_DownloadGate.maxConcurrent}（$tip）');
    }

    if (!_accelEnabled) {
      await _singleDownload(official, tmp);
      await _finalize(tmp, target, expectedSha1);
      return DownloadResult(channel: DownloadChannel.single, usedUri: official);
    }

    final isSmall =
        expectedSize != null && expectedSize > 0 && expectedSize < _smallFileBytes;
    final isAsset = _isAssetLike(official);

    // 大文件才尝试 peer；资产海量小文件跳过
    if (!isSmall && !isAsset) {
      await ensurePeerRunning();
      if (_peerEnabled && expectedSha1 != null && expectedSha1.isNotEmpty) {
        for (final peerUri in swarm.peerUrlsFor(expectedSha1)) {
          try {
            await _singleDownload(peerUri, tmp);
            await _finalize(tmp, target, expectedSha1);
            swarm.registerFile(expectedSha1, target);
            return DownloadResult(
                channel: DownloadChannel.peer, usedUri: peerUri);
          } catch (_) {
            await _safeDelete(tmp);
          }
        }
      }
    }

    // 资产：国内官方极慢，加速开启时只走镜像。
    // 中国大陆（含手机）：库/本体也优先镜像，官方排最后，减少卡超时。
    final mirrorBases = await _mirrorsAsync();
    final mirrors = DownloadSources.candidates(
      official,
      mirrorBases: mirrorBases,
      versionId: versionId,
    ).where((u) {
      if (_isOfficialHost(u.host)) {
        if (isAsset) return false;
        // 手机 + 大陆：依赖/本体先不碰官方，避免每个文件卡 4s
        if ((Platform.isAndroid || Platform.isIOS) &&
            NetworkEnv.isChinaMainland &&
            NetworkEnv.instance.preferMirrors) {
          return false;
        }
        return !_badHosts.contains(u.host);
      }
      return !_badHosts.contains(u.host);
    }).toList();
    if (mirrors.isEmpty) {
      mirrors.add(official);
    } else if (NetworkEnv.instance.preferMirrors) {
      final officialOnes =
          mirrors.where((u) => _isOfficialHost(u.host)).toList();
      final mirrorOnes =
          mirrors.where((u) => !_isOfficialHost(u.host)).toList();
      mirrors
        ..clear()
        ..addAll(mirrorOnes)
        ..addAll(officialOnes);
    }
    // 手机大陆先前剔掉官方，避免逐文件卡超时；整轮镜像失败后再回落官方
    if ((Platform.isAndroid || Platform.isIOS) &&
        NetworkEnv.isChinaMainland &&
        !mirrors.any((u) => _isOfficialHost(u.host))) {
      mirrors.add(official);
    }

    final allowChunk = !isSmall &&
        !isAsset &&
        expectedSize != null &&
        expectedSize >= _minChunkedBytes;

    if (allowChunk) {
      try {
        _log('多源分片 ${(expectedSize / (1024 * 1024)).toStringAsFixed(1)} MB…');
        await _chunkedDownload(mirrors, tmp, expectedSize);
        await _finalize(tmp, target, expectedSha1);
        if (expectedSha1 != null) swarm.registerFile(expectedSha1, target);
        return DownloadResult(
          channel: DownloadChannel.multiSource,
          usedUri: mirrors.first,
        );
      } catch (e) {
        if (!_chunkFallbackLogged) {
          _chunkFallbackLogged = true;
          _log('分片失败，改为整文件下载');
        }
        await _safeDelete(tmp);
      }
    }

    Object? lastError;
    for (final uri in mirrors) {
      try {
        await _singleDownload(uri, tmp);
        await _finalize(tmp, target, expectedSha1);
        _hostFailStreak[uri.host] = 0;
        if (expectedSha1 != null) swarm.registerFile(expectedSha1, target);
        final isOfficial = uri.host == official.host;
        return DownloadResult(
          channel: isOfficial
              ? DownloadChannel.fallback
              : DownloadChannel.multiSource,
          usedUri: uri,
        );
      } catch (e) {
        lastError = e;
        _noteHostResult(uri.host, e);
        await _safeDelete(tmp);
      }
    }
    throw StateError('下载失败 ($official): $lastError');
  }

  void _noteHostResult(String host, Object e) {
    if (_isOfficialHost(host)) return;

    final s = e.toString();
    // 4xx：换 URL，不拉黑整站
    if (RegExp(r'→\s*4\d\d').hasMatch(s) && !s.contains('429')) {
      return;
    }
    // 429：等待重试，不拉黑
    if (s.contains('限流') || s.contains('429')) return;

    final transport = s.contains('Timeout') ||
        s.contains('SocketException') ||
        s.contains('Failed host') ||
        s.contains('Connection') ||
        s.contains('Handshake') ||
        RegExp(r'→\s*5\d\d').hasMatch(s);
    if (!transport) return;
    if (_badHosts.contains(host)) return;

    final n = (_hostFailStreak[host] ?? 0) + 1;
    _hostFailStreak[host] = n;
    // 镜像更耐打：连续 8 次传输失败才跳过
    if (n >= 8) {
      _badHosts.add(host);
      if (_loggedSkipHosts.add(host)) {
        _log('镜像暂时跳过 $host（约 45 秒后恢复）');
      }
      Future<void>.delayed(const Duration(seconds: 45), () {
        _badHosts.remove(host);
        _hostFailStreak[host] = 0;
        _loggedSkipHosts.remove(host);
      });
    }
  }

  Future<void> _safeDelete(File f) async {
    if (!f.existsSync()) return;
    try {
      await f.delete();
    } catch (_) {}
  }

  Future<Uint8List> downloadBytes(
    Uri official, {
    String? expectedSha1,
  }) async {
    final tmpDir = await Directory.systemTemp.createTemp('xq_dl_');
    final tmp = File('${tmpDir.path}/blob');
    try {
      await downloadTo(official, tmp, expectedSha1: expectedSha1);
      return Uint8List.fromList(await tmp.readAsBytes());
    } finally {
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _finalize(File tmp, File target, String? expectedSha1) async {
    if (expectedSha1 != null && expectedSha1.isNotEmpty) {
      final digest = await sha1.bind(tmp.openRead()).first;
      if (digest.toString().toLowerCase() != expectedSha1.toLowerCase()) {
        await tmp.delete();
        throw StateError('SHA1 不匹配: expect=$expectedSha1 got=$digest');
      }
    }
    // Windows 上 jar/dll 常被游戏或杀软占用：删改名失败时改为复制覆盖。
    Object? last;
    for (var i = 0; i < 6; i++) {
      try {
        if (target.existsSync()) {
          try {
            await target.delete();
          } catch (e) {
            last = e;
          }
        }
        if (!target.existsSync()) {
          await tmp.rename(target.path);
          return;
        }
        // 目标仍在（删除失败）：直接覆盖写入
        await tmp.copy(target.path);
        await _safeDelete(tmp);
        return;
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(milliseconds: 120 * (i + 1)));
      }
    }
    throw StateError(
      '无法写入 ${target.path}（文件可能被游戏/Java 占用，请先完全退出后重试）: $last',
    );
  }

  Future<void> _chunkedDownload(
    List<Uri> sources,
    File tmp,
    int totalSize,
  ) async {
    final chunkCount = (totalSize / _chunkSize).ceil();
    final parts = <File>[];
    // 对齐国内启动器常见多连接；过大易触发镜像 429
    const maxParallel = 4;
    try {
      for (var batchStart = 0;
          batchStart < chunkCount;
          batchStart += maxParallel) {
        final batchEnd = (batchStart + maxParallel).clamp(0, chunkCount);
        final futures = <Future<void>>[];
        for (var i = batchStart; i < batchEnd; i++) {
          final start = i * _chunkSize;
          final end = (start + _chunkSize - 1).clamp(0, totalSize - 1);
          final part = File('${tmp.path}.c$i');
          parts.add(part);
          futures.add(_downloadRange(sources[i % sources.length], part, start, end));
        }
        await Future.wait(futures);
      }

      final sink = tmp.openWrite();
      try {
        for (final p in parts) {
          await for (final chunk in p.openRead()) {
            sink.add(chunk);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (tmp.lengthSync() != totalSize) {
        throw StateError('分片合并大小不符 ${tmp.lengthSync()} != $totalSize');
      }
    } finally {
      for (final p in parts) {
        await _safeDelete(p);
      }
    }
  }

  Future<void> _downloadRange(
    Uri uri,
    File part,
    int start,
    int end,
  ) async {
    await _withRetries(() async {
      await _DownloadGate.instance.run(() async {
        final req = http.Request('GET', uri)
          ..headers['User-Agent'] = DownloadSources.userAgent
          ..headers['Range'] = 'bytes=$start-$end'
          ..followRedirects = true;
        final res =
            await _http.send(req).timeout(_connectTimeoutFor(uri));
        if (res.statusCode == 429 || res.statusCode == 503) {
          throw _RateLimited(res.statusCode);
        }
        if (res.statusCode != 206 && res.statusCode != 200) {
          throw StateError('Range 失败 ($uri → ${res.statusCode})');
        }
        await _writeBody(res.stream, part);
      });
    });
  }

  Future<void> _singleDownload(Uri uri, File target) async {
    await _withRetries(() async {
      await _DownloadGate.instance.run(() async {
        final req = http.Request('GET', uri)
          ..headers['User-Agent'] = DownloadSources.userAgent
          ..followRedirects = true;
        final res =
            await _http.send(req).timeout(_connectTimeoutFor(uri));
        if (res.statusCode == 429 || res.statusCode == 503) {
          throw _RateLimited(res.statusCode);
        }
        if (res.statusCode != 200 && res.statusCode != 206) {
          throw StateError('下载失败 ($uri → ${res.statusCode})');
        }
        await _writeBody(res.stream, target);
      });
    });
  }

  Future<void> _writeBody(http.ByteStream stream, File target) async {
    final sink = target.openWrite();
    try {
      await for (final chunk in stream.timeout(_idleTimeout)) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      try {
        await sink.close();
      } catch (_) {}
    }
  }

  Future<void> _withRetries(Future<void> Function() run) async {
    const maxAttempts = 5;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await run();
        return;
      } on _RateLimited catch (e) {
        if (attempt == maxAttempts - 1) {
          throw StateError('下载限流 (→ ${e.code})');
        }
        // 指数退避；不再假设 BMCL 固定 60s 短窗
        final secs = [1, 2, 4, 8][attempt.clamp(0, 3)];
        if (!_rateLimitLogged) {
          _rateLimitLogged = true;
          _log('镜像限流，自动降速重试…');
        }
        await Future<void>.delayed(Duration(seconds: secs));
      } on TimeoutException {
        if (attempt == maxAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      } on SocketException {
        if (attempt == maxAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }
}

class _RateLimited implements Exception {
  final int code;
  _RateLimited(this.code);
}
