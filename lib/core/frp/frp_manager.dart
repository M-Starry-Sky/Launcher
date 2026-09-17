import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/room.dart';
import '../config/app_config.dart';
import 'frp_config_generator.dart';

/// frpc 进程管理：定位 frpc 可执行文件、写配置、启动与停止。
class FrpManager {
  final AppConfig config;
  final FrpConfigGenerator generator = FrpConfigGenerator();

  Process? _process;
  File? _configFile;

  FrpManager(this.config);

  bool get isRunning => _process != null;

  /// 本地联机隧道是否可用：中继地址 + Token 已配置。
  bool get hasLocalTunnelPrefer {
    final addr = config.frpServerAddr.trim();
    final token = config.frpToken.trim();
    return addr.isNotEmpty && token.isNotEmpty;
  }

  /// 缺配置时的提示文案（含远程端口）。
  String get localTunnelMissingHint {
    final miss = <String>[];
    if (config.frpServerAddr.trim().isEmpty) miss.add('FRP 中继地址');
    if (config.frpToken.trim().isEmpty) miss.add('FRP Token');
    if (config.frpRemotePort <= 0) miss.add('远程映射端口');
    if (miss.isEmpty) return '';
    return '请到「设置 → 联机隧道」填写：${miss.join('、')}';
  }

  String? get frpcExecutable {
    final configured = config.frpcPath.trim();
    if (configured.isNotEmpty) {
      final hit = _resolveExisting(configured);
      if (hit != null) return hit;
    }

    final exeName = Platform.isWindows ? 'frpc.exe' : 'frpc';
    final candidates = <String>[
      p.join(p.dirname(Platform.resolvedExecutable), 'frp', exeName),
      p.join(p.dirname(Platform.resolvedExecutable), exeName),
      p.join(Directory.current.path, 'frp', exeName),
      p.join(Directory.current.path, exeName),
      'frp/$exeName',
      exeName,
    ];
    for (final c in candidates) {
      final hit = _resolveExisting(c);
      if (hit != null) return hit;
    }
    return null;
  }

  String? _resolveExisting(String raw) {
    final path = raw.trim();
    if (path.isEmpty) return null;
    final file = File(path);
    if (file.existsSync()) return file.absolute.path;
    final beside = File(
      p.join(p.dirname(Platform.resolvedExecutable), path),
    );
    if (beside.existsSync()) return beside.absolute.path;
    return null;
  }

  Future<Process> start({
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
    void Function(String line)? onLog,
  }) async {
    if (isRunning) {
      throw const FrpException('已有隧道在运行，请先停止');
    }
    final exe = frpcExecutable;
    if (exe == null) {
      throw const FrpException(
        '未找到 frpc。请到「设置 → 联机隧道」填写 frpc 可执行文件路径',
      );
    }
    onLog?.call('使用 frpc：$exe');

    _configFile = await generator.writeToFile(
      configDir: '${Directory.systemTemp.path}/xingqiong-frp',
      roomTag: roomTag,
      serverAddr: serverAddr,
      serverPort: serverPort,
      token: token,
      localPort: localPort,
      remotePort: remotePort,
      user: user,
      tlsEnable: tlsEnable,
      tlsServerName: tlsServerName,
      useEncryption: useEncryption,
      useCompression: useCompression,
      protocol: protocol,
    );
    onLog?.call(
      '隧道配置：中继 $serverAddr:$serverPort · 本机 $localPort → 远程 $remotePort'
      '${tlsEnable ? ' · TLS' : ''}',
    );

    final process = await Process.start(exe, ['-c', _configFile!.path]);
    process.stdout
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      onLog?.call(line);
    });
    process.stderr
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      onLog?.call(line);
    });
    process.exitCode.then((code) {
      onLog?.call('frpc 已退出 (exit=$code)');
      _process = null;
    });
    _process = process;
    return process;
  }

  /// 用 [FrpConnection] 启动（平台下发或本地合成）。
  Future<Process> startFromConnection({
    required String roomTag,
    required FrpConnection frp,
    required int localPort,
    void Function(String line)? onLog,
  }) {
    return start(
      roomTag: roomTag,
      serverAddr: frp.host,
      serverPort: frp.controlPort,
      token: frp.token,
      localPort: localPort,
      remotePort: frp.remotePort,
      user: frp.user,
      tlsEnable: frp.tlsEnable,
      tlsServerName: frp.tlsServerName,
      useEncryption: frp.useEncryption,
      useCompression: frp.useCompression,
      protocol: frp.protocol,
      onLog: onLog,
    );
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    process?.kill();
    final file = _configFile;
    _configFile = null;
    if (file != null && file.existsSync()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}

class FrpException implements Exception {
  final String message;
  const FrpException(this.message);

  @override
  String toString() => message;
}
