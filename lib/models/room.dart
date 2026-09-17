/// 联机房间连接信息（本地隧道合成，或远程加入结果）。
class RoomJoinInfo {
  final String roomId;
  final String gameType;
  final String connectAddress; // 好友直连地址 host:port
  final FrpConnection frp;
  final String? packId;
  final bool autoDistribute;
  final String? expireAt;
  /// true = 本机 frpc 隧道，不走后端房间 API
  final bool localTunnel;
  /// 兼容联机：关正版校验 / 跨版本辅助
  final bool compatMode;

  const RoomJoinInfo({
    required this.roomId,
    required this.gameType,
    required this.connectAddress,
    required this.frp,
    this.packId,
    required this.autoDistribute,
    this.expireAt,
    this.localTunnel = false,
    this.compatMode = false,
  });

  factory RoomJoinInfo.fromJson(Map<String, dynamic> json) => RoomJoinInfo(
        roomId: json['room_id'] as String,
        gameType: (json['game_type'] ?? 'java') as String,
        connectAddress: (json['connect_address'] ?? '') as String,
        frp: FrpConnection.fromJson(
            (json['frp'] as Map<String, dynamic>?) ?? {}),
        packId: json['pack_id'] as String?,
        autoDistribute: json['auto_distribute'] == true,
        expireAt: json['expire_at'] as String?,
        localTunnel: false,
        compatMode: json['compat_mode'] == true,
      );

  /// 本地隧道开房：好友直接连 [connectAddress]。
  factory RoomJoinInfo.localHost({
    required String roomId,
    required String gameType,
    required String connectAddress,
    required FrpConnection frp,
    String? packId,
    bool compatMode = false,
  }) =>
      RoomJoinInfo(
        roomId: roomId,
        gameType: gameType,
        connectAddress: connectAddress,
        frp: frp,
        packId: packId,
        autoDistribute: false,
        expireAt: null,
        localTunnel: true,
        compatMode: compatMode,
      );

  /// 好友粘贴 host:port 直连（无需后端房间码）。
  factory RoomJoinInfo.directJoin({
    required String connectAddress,
    String gameType = 'java',
    bool compatMode = false,
    String? packId,
  }) =>
      RoomJoinInfo(
        roomId: connectAddress,
        gameType: gameType,
        connectAddress: connectAddress,
        frp: const FrpConnection(
          node: 'direct',
          host: '',
          controlPort: 0,
          remotePort: 0,
          token: '',
        ),
        packId: packId,
        autoDistribute: packId != null && packId.isNotEmpty,
        localTunnel: true,
        compatMode: compatMode,
      );

  RoomJoinInfo copyWith({
    bool? compatMode,
    String? packId,
    bool clearPackId = false,
  }) =>
      RoomJoinInfo(
        roomId: roomId,
        gameType: gameType,
        connectAddress: connectAddress,
        frp: frp,
        packId: clearPackId ? null : (packId ?? this.packId),
        autoDistribute: autoDistribute,
        expireAt: expireAt,
        localTunnel: localTunnel,
        compatMode: compatMode ?? this.compatMode,
      );
}

class FrpConnection {
  final String node;
  final String host;
  final int controlPort;
  final int remotePort;
  final String token;
  /// OpenFRP user / 访问密钥标识
  final String? user;
  final bool tlsEnable;
  final String? tlsServerName;
  final bool useEncryption;
  final bool useCompression;
  final String protocol;

  const FrpConnection({
    required this.node,
    required this.host,
    required this.controlPort,
    required this.remotePort,
    required this.token,
    this.user,
    this.tlsEnable = false,
    this.tlsServerName,
    this.useEncryption = false,
    this.useCompression = false,
    this.protocol = 'tcp',
  });

  factory FrpConnection.fromJson(Map<String, dynamic> json) => FrpConnection(
        node: (json['node'] ?? '') as String,
        host: (json['host'] ?? '') as String,
        controlPort: _asInt(json['control_port'], 7000),
        remotePort: _asInt(json['remote_port'], 0),
        token: (json['token'] ?? '') as String,
        user: _asString(json['user']),
        tlsEnable: json['tls_enable'] == true,
        tlsServerName: _asString(json['tls_server_name']),
        useEncryption: json['use_encryption'] == true,
        useCompression: json['use_compression'] == true,
        protocol: ((json['protocol'] as String?)?.trim().isNotEmpty == true)
            ? (json['protocol'] as String).trim()
            : 'tcp',
      );

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static String? _asString(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
