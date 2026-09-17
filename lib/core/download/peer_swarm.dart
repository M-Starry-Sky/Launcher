import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// 轻量局域网节点：本机开 HTTP 块服务 + UDP 广播，按 SHA1 互传已缓存文件。
class PeerSwarm {
  static const _udpPort = 38472;
  static const _magic = 'xq-peer-v1';

  HttpServer? _http;
  RawDatagramSocket? _udp;
  Timer? _announceTimer;
  final Map<String, String> _hashToPath = {};
  final Map<String, Set<String>> _remote = {}; // sha1 → host:httpPort

  int? httpPort;
  bool get running => _http != null;

  Future<void> start() async {
    if (_http != null) return;
    _http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    httpPort = _http!.port;
    _http!.listen(_onHttp);

    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _udpPort);
    _udp!.broadcastEnabled = true;
    _udp!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = _udp!.receive();
      if (dg == null) return;
      _onUdp(dg);
    });

    _announceTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _broadcastAnnounce(),
    );
    _broadcastAnnounce();
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _udp?.close();
    _udp = null;
    await _http?.close(force: true);
    _http = null;
    httpPort = null;
  }

  void registerFile(String sha1, File file) {
    if (sha1.isEmpty || !file.existsSync()) return;
    _hashToPath[sha1.toLowerCase()] = file.path;
  }

  Future<void> registerAndHash(File file) async {
    if (!file.existsSync()) return;
    final digest = sha1.convert(await file.readAsBytes());
    registerFile(digest.toString(), file);
  }

  /// 返回已知拥有 [sha1] 的局域网节点文件 URL。
  List<Uri> peerUrlsFor(String sha1) {
    final key = sha1.toLowerCase();
    final hosts = _remote[key];
    if (hosts == null || hosts.isEmpty) return const [];
    return [
      for (final h in hosts) Uri.parse('http://$h/peer/$key'),
    ];
  }

  void _onHttp(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (!path.startsWith('/peer/')) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final hash = path.substring('/peer/'.length).toLowerCase();
      final filePath = _hashToPath[hash];
      if (filePath == null || !File(filePath).existsSync()) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final file = File(filePath);
      req.response.headers.contentType = ContentType.binary;
      req.response.contentLength = file.lengthSync();
      await req.response.addStream(file.openRead());
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  void _onUdp(Datagram dg) {
    try {
      final text = utf8.decode(dg.data);
      final map = jsonDecode(text) as Map<String, dynamic>;
      if (map['m'] != _magic) return;
      final port = map['p'] as int?;
      final hashes = (map['h'] as List?)?.whereType<String>() ?? const [];
      if (port == null) return;
      final host = '${dg.address.address}:$port';
      // 忽略自己
      if (httpPort != null &&
          dg.address == InternetAddress.loopbackIPv4 &&
          port == httpPort) {
        return;
      }
      for (final h in hashes) {
        (_remote[h.toLowerCase()] ??= {}).add(host);
      }
    } catch (_) {}
  }

  void _broadcastAnnounce() {
    final udp = _udp;
    final port = httpPort;
    if (udp == null || port == null) return;
    final hashes = _hashToPath.keys.take(64).toList();
    if (hashes.isEmpty) return;
    final payload = utf8.encode(jsonEncode({
      'm': _magic,
      'p': port,
      'h': hashes,
    }));
    try {
      udp.send(payload, InternetAddress('255.255.255.255'), _udpPort);
    } catch (_) {}
  }
}

/// 全局可选 peer 单例（由加速下载器持有）。
final PeerSwarm peerSwarm = PeerSwarm();
