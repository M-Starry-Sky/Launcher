import '../models/pack.dart';
import '../models/room.dart';
import '../core/network/api_client.dart';
import '../core/network/secure_endpoint.dart';

/// 联机房间服务。
class RoomService {
  final ApiClient api;

  RoomService(this.api);

  Future<({String roomId, String? frpNode, int? frpPort, String? expireAt})>
      create({String? packId, String gameType = 'java'}) async {
    final body = <String, dynamic>{
      'game_type': gameType,
      if (packId != null && packId.isNotEmpty) 'pack_id': packId,
    };
    final json = await api.post(SecureRoutes.roomCreate, body: body);
    return (
      roomId: json['room_id'] as String,
      frpNode: json['frp_node'] as String?,
      frpPort: json['frp_port'] as int?,
      expireAt: json['expire_at'] as String?,
    );
  }

  Future<RoomJoinInfo> join(String code) async {
    final json = await api.get(SecureRoutes.roomJoin(code));
    return RoomJoinInfo.fromJson(json);
  }

  Future<void> close(String roomId) async {
    await api.post(SecureRoutes.roomClose, body: {'room_id': roomId});
  }

  Future<PackManifestResponse> packManifest(String roomId) async {
    final json = await api.get(SecureRoutes.roomPackManifest(roomId));
    return PackManifestResponse.fromJson(json);
  }
}
