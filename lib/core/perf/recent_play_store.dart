import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// 最近启动 / 服务器 / 联机房间的本地履历。
class RecentPlayStore extends ChangeNotifier {
  static const prefsKey = 'recent_play_v1';
  static const _cap = 30;

  final AppConfig config;

  List<RecentLaunchEntry> _launches = const [];
  List<RecentServerEntry> _servers = const [];
  List<RecentRoomEntry> _rooms = const [];

  RecentPlayStore(this.config) {
    _load();
  }

  List<RecentLaunchEntry> get launches => _launches;
  List<RecentServerEntry> get servers => _servers;
  List<RecentRoomEntry> get rooms => _rooms;

  void _load() {
    final json = config.getJson(prefsKey);
    _launches = _list(json['launches'])
        .map(RecentLaunchEntry.fromJson)
        .whereType<RecentLaunchEntry>()
        .toList();
    _servers = _list(json['servers'])
        .map(RecentServerEntry.fromJson)
        .whereType<RecentServerEntry>()
        .toList();
    _rooms = _list(json['rooms'])
        .map(RecentRoomEntry.fromJson)
        .whereType<RecentRoomEntry>()
        .toList();
  }

  static List<Map<String, dynamic>> _list(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _persist() async {
    await config.setJson(prefsKey, {
      'launches': _launches.map((e) => e.toJson()).toList(),
      'servers': _servers.map((e) => e.toJson()).toList(),
      'rooms': _rooms.map((e) => e.toJson()).toList(),
    });
    notifyListeners();
  }

  Future<void> recordLaunch({
    required String instanceId,
    required String instanceName,
    required String gameVersion,
    String? serverName,
    String? serverAddress,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _launches = [
      RecentLaunchEntry(
        instanceId: instanceId,
        instanceName: instanceName,
        gameVersion: gameVersion,
        serverName: serverName,
        serverAddress: serverAddress,
        atMs: now,
      ),
      ..._launches,
    ].take(_cap).toList();

    final addr = serverAddress?.trim();
    if (addr != null && addr.isNotEmpty) {
      await recordServer(
        name: (serverName != null && serverName.trim().isNotEmpty)
            ? serverName.trim()
            : addr,
        address: addr,
        atMs: now,
      );
      return;
    }
    await _persist();
  }

  Future<void> recordServer({
    required String name,
    required String address,
    int? atMs,
  }) async {
    final now = atMs ?? DateTime.now().millisecondsSinceEpoch;
    final addr = address.trim();
    if (addr.isEmpty) return;
    final rest = _servers.where((e) => e.address != addr);
    _servers = [
      RecentServerEntry(
        name: name.trim().isEmpty ? addr : name.trim(),
        address: addr,
        atMs: now,
      ),
      ...rest,
    ].take(_cap).toList();
    await _persist();
  }

  Future<void> recordRoom({
    required String roomId,
    required String connectAddress,
    required String gameType,
    required String role,
    required bool localTunnel,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = connectAddress.trim().isNotEmpty
        ? connectAddress.trim()
        : roomId.trim();
    if (key.isEmpty) return;
    final rest = _rooms.where((e) {
      final k = e.connectAddress.trim().isNotEmpty
          ? e.connectAddress.trim()
          : e.roomId.trim();
      return k != key;
    });
    _rooms = [
      RecentRoomEntry(
        roomId: roomId,
        connectAddress: connectAddress,
        gameType: gameType,
        role: role,
        localTunnel: localTunnel,
        atMs: now,
      ),
      ...rest,
    ].take(_cap).toList();
    await _persist();
  }

  Future<void> clearAll() async {
    _launches = const [];
    _servers = const [];
    _rooms = const [];
    await _persist();
  }
}

class RecentLaunchEntry {
  final String instanceId;
  final String instanceName;
  final String gameVersion;
  final String? serverName;
  final String? serverAddress;
  final int atMs;

  const RecentLaunchEntry({
    required this.instanceId,
    required this.instanceName,
    required this.gameVersion,
    this.serverName,
    this.serverAddress,
    required this.atMs,
  });

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'instanceName': instanceName,
        'gameVersion': gameVersion,
        'serverName': serverName,
        'serverAddress': serverAddress,
        'atMs': atMs,
      };

  static RecentLaunchEntry? fromJson(Map<String, dynamic> json) {
    final id = '${json['instanceId'] ?? ''}';
    final name = '${json['instanceName'] ?? ''}';
    final at = (json['atMs'] as num?)?.toInt() ?? 0;
    if (name.isEmpty || at <= 0) return null;
    return RecentLaunchEntry(
      instanceId: id,
      instanceName: name,
      gameVersion: '${json['gameVersion'] ?? ''}',
      serverName: json['serverName'] as String?,
      serverAddress: json['serverAddress'] as String?,
      atMs: at,
    );
  }
}

class RecentServerEntry {
  final String name;
  final String address;
  final int atMs;

  const RecentServerEntry({
    required this.name,
    required this.address,
    required this.atMs,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'atMs': atMs,
      };

  static RecentServerEntry? fromJson(Map<String, dynamic> json) {
    final addr = '${json['address'] ?? ''}'.trim();
    final at = (json['atMs'] as num?)?.toInt() ?? 0;
    if (addr.isEmpty || at <= 0) return null;
    final name = '${json['name'] ?? ''}'.trim();
    return RecentServerEntry(
      name: name.isEmpty ? addr : name,
      address: addr,
      atMs: at,
    );
  }
}

class RecentRoomEntry {
  final String roomId;
  final String connectAddress;
  final String gameType;
  final String role;
  final bool localTunnel;
  final int atMs;

  const RecentRoomEntry({
    required this.roomId,
    required this.connectAddress,
    required this.gameType,
    required this.role,
    required this.localTunnel,
    required this.atMs,
  });

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'connectAddress': connectAddress,
        'gameType': gameType,
        'role': role,
        'localTunnel': localTunnel,
        'atMs': atMs,
      };

  static RecentRoomEntry? fromJson(Map<String, dynamic> json) {
    final at = (json['atMs'] as num?)?.toInt() ?? 0;
    final connect = '${json['connectAddress'] ?? ''}'.trim();
    final roomId = '${json['roomId'] ?? ''}'.trim();
    if (at <= 0 || (connect.isEmpty && roomId.isEmpty)) return null;
    return RecentRoomEntry(
      roomId: roomId,
      connectAddress: connect,
      gameType: '${json['gameType'] ?? 'java'}',
      role: '${json['role'] ?? 'join'}',
      localTunnel: json['localTunnel'] == true,
      atMs: at,
    );
  }
}
