import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/network/api_client.dart';

/// 公开皮肤源：按玩家名从公开 CDN / Mojang 拉取 PNG。
class PublicSkinClient {
  static const _userAgent = 'xingqiong-launcher/0.1.0';

  /// 按玩家名下载皮肤到目录，返回保存文件。
  Future<File> downloadByUsername({
    required String username,
    required Directory targetDir,
  }) async {
    final name = username.trim();
    if (name.isEmpty) {
      throw ApiException('请输入玩家名');
    }
    if (!RegExp(r'^[A-Za-z0-9_]{1,16}$').hasMatch(name)) {
      throw ApiException('玩家名格式无效');
    }

    final bytes = await _fetchPng(name);
    await targetDir.create(recursive: true);
    final out = File('${targetDir.path}${Platform.pathSeparator}$name.png');
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  Future<Uint8List> _fetchPng(String name) async {
    final primary = await _tryGet(
      Uri.parse('https://mc-heads.net/skin/${Uri.encodeComponent(name)}'),
    );
    if (primary != null) return primary;

    final uuid = await _mojangUuid(name);
    if (uuid != null) {
      final viaCrafatar = await _tryGet(
        Uri.parse('https://crafatar.com/skins/$uuid?default=MHF_Steve'),
      );
      if (viaCrafatar != null) return viaCrafatar;
    }

    throw ApiException('未找到玩家「$name」的公开皮肤');
  }

  Future<String?> _mojangUuid(String name) async {
    final response = await http.get(
      Uri.parse(
          'https://api.mojang.com/users/profiles/minecraft/${Uri.encodeComponent(name)}'),
      headers: {'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) return null;
    try {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final id = (json['id'] as String?) ?? '';
      if (id.length != 32) return id.isEmpty ? null : id;
      return '${id.substring(0, 8)}-${id.substring(8, 12)}-'
          '${id.substring(12, 16)}-${id.substring(16, 20)}-${id.substring(20)}';
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _tryGet(Uri uri) async {
    try {
      final response = await http.get(uri, headers: {'User-Agent': _userAgent});
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      if (bytes.length < 8 ||
          bytes[0] != 0x89 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x4E ||
          bytes[3] != 0x47) {
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
