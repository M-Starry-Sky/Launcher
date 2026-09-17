import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'game_instance.dart';

/// 启动前可选项：模组 / 服务器 / 整合包 / 皮肤（由开始按钮载入）。
class LaunchLoadout extends ChangeNotifier {
  static const keyIncludeMods = 'loadout_include_mods';
  static const keyIncludeServer = 'loadout_include_server';
  static const keyIncludePack = 'loadout_include_pack';
  static const keyIncludeSkin = 'loadout_include_skin';
  static const keyIncludeWorld = 'loadout_include_world';
  static const keyServerAddress = 'loadout_server_address';
  static const keyPackId = 'loadout_pack_id';
  static const keySkinPath = 'loadout_skin_path';
  static const keyWorldName = 'loadout_world_name';
  static const serversKey = 'saved_servers_v1';

  final AppConfig config;

  bool includeMods = true;
  bool includeServer = false;
  bool includePack = false;
  bool includeSkin = false;
  bool includeWorld = false;
  String? serverAddress;
  String? packId;
  String? skinPath;
  String? worldName;

  LaunchLoadout(this.config) {
    _load();
  }

  void _load() {
    includeMods = config.getBoolOr(keyIncludeMods, true);
    includeServer = config.getBoolOr(keyIncludeServer, false);
    includePack = config.getBoolOr(keyIncludePack, false);
    includeSkin = config.getBoolOr(keyIncludeSkin, false);
    includeWorld = config.getBoolOr(keyIncludeWorld, false);
    final s = config.getStringOr(keyServerAddress, '');
    serverAddress = s.isEmpty ? null : s;
    final p = config.getStringOr(keyPackId, '');
    packId = p.isEmpty ? null : p;
    final sk = config.getStringOr(keySkinPath, '');
    skinPath = sk.isEmpty ? null : sk;
    final w = config.getStringOr(keyWorldName, '');
    worldName = w.isEmpty ? null : w;
  }

  /// 实例 saves 下的世界文件夹名（传入 [instanceGameDir]，勿传共享本体）。
  List<String> localWorlds({Directory? gameRoot}) {
    // 调用方应传入当前实例目录；未传时回退到配置中的本体路径（兼容旧调用）。
    final root = gameRoot ??
        () {
          final body = config.gameBodyDir.trim();
          if (body.isNotEmpty) return Directory(body);
          final data = config.gameDataDir.trim().isNotEmpty
              ? config.gameDataDir.trim()
              : InstanceStore.defaultDataRootHint();
          return Directory('$data${Platform.pathSeparator}game');
        }();
    final saves = Directory('${root.path}${Platform.pathSeparator}saves');
    if (!saves.existsSync()) return const [];
    final names = <String>[];
    for (final e in saves.listSync(followLinks: false)) {
      if (e is! Directory) continue;
      final parts = e.path
          .split(RegExp(r'[\\/]'))
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;
      final folder = parts.last;
      if (folder.startsWith('.')) continue;
      final level = File('${e.path}${Platform.pathSeparator}level.dat');
      if (!level.existsSync()) continue;
      names.add(folder);
    }
    names.sort();
    return names;
  }

  List<Map<String, String>> savedServers() {
    final raw = config.getJson(serversKey);
    return (raw['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => {
              'name': '${e['name'] ?? ''}',
              'address': '${e['address'] ?? ''}',
            })
        .where((e) => (e['address'] ?? '').isNotEmpty)
        .toList();
  }

  List<File> localSkins({Directory? directory}) {
    final dir = directory ??
        Directory(
          '${(config.gameDataDir.trim().isNotEmpty ? config.gameDataDir.trim() : InstanceStore.defaultDataRootHint())}${Platform.pathSeparator}skins',
        );
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final n = f.path.toLowerCase();
          return n.endsWith('.png');
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  Future<void> setIncludeMods(bool v) async {
    includeMods = v;
    await config.setBool(keyIncludeMods, v);
    notifyListeners();
  }

  Future<void> setIncludeServer(bool v) async {
    includeServer = v;
    await config.setBool(keyIncludeServer, v);
    notifyListeners();
  }

  Future<void> setIncludePack(bool v) async {
    includePack = v;
    await config.setBool(keyIncludePack, v);
    notifyListeners();
  }

  Future<void> setIncludeSkin(bool v) async {
    includeSkin = v;
    await config.setBool(keyIncludeSkin, v);
    notifyListeners();
  }

  Future<void> setIncludeWorld(bool v) async {
    includeWorld = v;
    await config.setBool(keyIncludeWorld, v);
    notifyListeners();
  }

  Future<void> setServerAddress(String? v) async {
    serverAddress = (v == null || v.isEmpty) ? null : v;
    await config.set(keyServerAddress, serverAddress ?? '');
    notifyListeners();
  }

  Future<void> setPackId(String? v) async {
    packId = (v == null || v.isEmpty) ? null : v;
    await config.set(keyPackId, packId ?? '');
    notifyListeners();
  }

  Future<void> setSkinPath(String? v) async {
    skinPath = (v == null || v.isEmpty) ? null : v;
    await config.set(keySkinPath, skinPath ?? '');
    notifyListeners();
  }

  Future<void> setWorldName(String? v) async {
    worldName = (v == null || v.isEmpty) ? null : v;
    await config.set(keyWorldName, worldName ?? '');
    notifyListeners();
  }

  /// 开始按钮文案（随整合包 / 服务器开关变化）。
  String launchButtonLabel({required bool isJava, required bool busy}) {
    if (busy) return '安装 / 启动中…';
    if (!isJava) return busy ? '启动中…' : '启动基岩版';
    final pack = includePack && (packId != null && packId!.isNotEmpty);
    final server =
        includeServer && (serverAddress != null && serverAddress!.isNotEmpty);
    final world =
        includeWorld && (worldName != null && worldName!.isNotEmpty);
    if (pack && server) return '启动整合包并加入服务器';
    if (pack && world) return '启动整合包并进入存档';
    if (pack) return '启动整合包';
    if (server) return '加入服务器并启动';
    if (world) return '进入存档并启动';
    return '启动游戏';
  }

  /// 解析 host:port
  static ({String host, int port})? parseServer(String? address) {
    if (address == null) return null;
    final raw = address.trim();
    if (raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length == 1) {
      return (host: parts[0], port: 25565);
    }
    final port = int.tryParse(parts.last) ?? 25565;
    final host = parts.sublist(0, parts.length - 1).join(':');
    if (host.isEmpty) return null;
    return (host: host, port: port);
  }
}
