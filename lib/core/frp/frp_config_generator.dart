import 'dart:io';

/// 生成 frpc 配置（frp 0.52+ TOML；兼容 OpenFRP TLS / user / 加密）。
class FrpConfigGenerator {
  String generate({
    required String serverAddr,
    required int serverPort,
    required String token,
    required String proxyName,
    required int localPort,
    required int remotePort,
    String? user,
    bool tlsEnable = false,
    String? tlsServerName,
    bool useEncryption = false,
    bool useCompression = false,
    String protocol = 'tcp',
    String localIp = '127.0.0.1',
  }) {
    final buffer = StringBuffer()
      ..writeln("serverAddr = '$serverAddr'")
      ..writeln('serverPort = $serverPort');
    if (user != null && user.trim().isNotEmpty) {
      buffer.writeln("user = '${user.trim()}'");
    }
    buffer
      ..writeln()
      ..writeln('[auth]')
      ..writeln("method = 'token'")
      ..writeln("token = '$token'")
      ..writeln()
      ..writeln('[[proxies]]')
      ..writeln("name = '$proxyName'")
      ..writeln("type = 'tcp'")
      ..writeln("localIP = '$localIp'")
      ..writeln('localPort = $localPort')
      ..writeln('remotePort = $remotePort')
      ..writeln("autoTLS = 'false'");
    if (useEncryption || useCompression) {
      buffer
        ..writeln()
        ..writeln('[proxies.transport]');
      if (useCompression) buffer.writeln('useCompression = true');
      if (useEncryption) buffer.writeln('useEncryption = true');
    }
    buffer
      ..writeln()
      ..writeln('[transport]')
      ..writeln("protocol = '${protocol.trim().isEmpty ? 'tcp' : protocol.trim()}'");
    if (tlsEnable) {
      buffer
        ..writeln()
        ..writeln('[transport.tls]')
        ..writeln('enable = true')
        ..writeln('disableCustomTLSFirstByte = false');
      if (tlsServerName != null && tlsServerName.trim().isNotEmpty) {
        buffer.writeln("serverName = '${tlsServerName.trim()}'");
      }
    }
    return buffer.toString();
  }

  Future<File> writeToFile({
    required String configDir,
    required String roomTag,
    required String serverAddr,
    required int serverPort,
    required String token,
    required int localPort,
    required int remotePort,
    String? user,
    bool tlsEnable = false,
    String? tlsServerName,
    bool useEncryption = false,
    bool useCompression = false,
    String protocol = 'tcp',
    String localIp = '127.0.0.1',
  }) async {
    final dir = Directory(configDir);
    await dir.create(recursive: true);
    final file = File('${dir.path}/frpc-$roomTag.toml');
    final content = generate(
      serverAddr: serverAddr,
      serverPort: serverPort,
      token: token,
      proxyName: 'xingqiong-mc-$roomTag',
      localPort: localPort,
      remotePort: remotePort,
      user: user,
      tlsEnable: tlsEnable,
      tlsServerName: tlsServerName,
      useEncryption: useEncryption,
      useCompression: useCompression,
      protocol: protocol,
      localIp: localIp,
    );
    await file.writeAsString(content);
    return file;
  }
}
