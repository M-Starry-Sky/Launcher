import 'dart:convert';

import 'package:http/http.dart' as http;

import 'secure_endpoint.dart';

/// 远端访问异常。
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// HTTP 传输层：自动携带 Bearer，统一解析错误体。主机来自 [SecureEndpoint]。
class ApiClient {
  final String Function() baseUrl;
  final Future<String?> Function() tokenProvider;

  ApiClient({
    String Function()? baseUrl,
    required this.tokenProvider,
  }) : baseUrl = baseUrl ?? (() => SecureEndpoint.backendBaseUrl);

  Uri _uri(String path, [Map<String, String>? query]) {
    final baseStr = baseUrl();
    final base = baseStr.endsWith('/')
        ? baseStr.substring(0, baseStr.length - 1)
        : baseStr;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _handle(http.Response response) async {
    final body = utf8.decode(response.bodyBytes);
    Map<String, dynamic> json;
    try {
      json = body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('响应解析失败 (${response.statusCode})',
          statusCode: response.statusCode);
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }
    throw ApiException(
        (json['error'] as String?) ?? '请求失败 (${response.statusCode})',
        statusCode: response.statusCode);
  }

  Future<Map<String, String>> _headers() async {
    final token = await tokenProvider();
    return {
      'Content-Type': 'application/json; charset=utf-8',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> get(String path,
      [Map<String, String>? query]) async {
    final response =
        await http.get(_uri(path, query), headers: await _headers());
    return _handle(response);
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    final response = await http.post(_uri(path),
        headers: await _headers(),
        body: body == null ? null : jsonEncode(body));
    return _handle(response);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response =
        await http.delete(_uri(path), headers: await _headers());
    return _handle(response);
  }

  Future<Map<String, dynamic>> upload(
      String path, List<int> fileBytes, String filename,
      {Map<String, String>? fields}) async {
    final token = await tokenProvider();
    final request = http.MultipartRequest('POST', _uri(path))
      ..files.add(http.MultipartFile.fromBytes('file', fileBytes,
          filename: filename));
    fields?.forEach((key, value) {
      request.fields[key] = value;
    });
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _handle(response);
  }

  Future<Map<String, dynamic>> getPublic(String path) async {
    final response = await http.get(_uri(path));
    return _handle(response);
  }
}
