import 'dart:async';
import 'package:http/http.dart' as http;

Future<void> main() async {
  const ua = 'xingqiong-launcher/0.1.0';
  final urls = <String>[
    'https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json',
    'https://bmclapi2.bangbang93.com/version/1.20.1/client',
    'https://bmclapi2.bangbang93.com/assets/bd/bdf48ef6b5d0d23bbb02e17d04865216179f510a',
    'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json',
  ];
  final client = http.Client();
  try {
    for (final u in urls) {
      final sw = Stopwatch()..start();
      try {
        final req = http.Request('GET', Uri.parse(u))
          ..headers['User-Agent'] = ua
          ..followRedirects = true;
        final res = await client.send(req).timeout(const Duration(seconds: 20));
        var n = 0;
        await for (final c in res.stream.take(3)) {
          n += c.length;
        }
        sw.stop();
        print('OK ${res.statusCode} ${sw.elapsedMilliseconds}ms got=$n $u');
      } catch (e) {
        sw.stop();
        print('FAIL ${sw.elapsedMilliseconds}ms $u :: $e');
      }
    }
  } finally {
    client.close();
  }
}
