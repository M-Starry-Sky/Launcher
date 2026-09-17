import 'dart:convert';
import 'dart:io';

/// 用系统默认浏览器打开链接。
Future<void> openUrlInBrowser(String url) async {
  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', url], runInShell: false);
  } else if (Platform.isMacOS) {
    await Process.run('open', [url]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [url]);
  } else if (Platform.isAndroid) {
    final r = await Process.run('am', [
      'start',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      url,
    ]);
    if (r.exitCode != 0) {
      throw StateError('无法打开链接（请手动访问）: $url');
    }
  } else if (Platform.isIOS) {
    await Process.run('open', [url]);
  } else {
    throw UnsupportedError('当前平台不支持自动打开浏览器: ${Platform.operatingSystem}');
  }
}

/// 解析 JWT 的 payload（不验签，仅用于读取 sub 等声明）。
Map<String, dynamic> parseJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length < 2) {
    throw const FormatException('不是有效的 JWT');
  }
  String normalized = base64Url.normalize(parts[1]);
  final payload = utf8.decode(base64Url.decode(normalized));
  return jsonDecode(payload) as Map<String, dynamic>;
}
