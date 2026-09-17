import 'package:flutter/foundation.dart';

enum GameResourceSection { versions, mods, servers, packs, rooms, skins }

/// 侧栏「游戏资源」导航：启动页等可跳转到指定二级目录。
class GameResourcesNav extends ChangeNotifier {
  GameResourceSection section = GameResourceSection.versions;
  int _ticket = 0;

  /// 打开联机页时预填的加入地址 / 房间码（用一次即清空）。
  String? pendingJoinCode;

  /// 预填后是否自动点击加入。
  bool pendingAutoJoin = false;

  int get ticket => _ticket;

  void open(GameResourceSection target) {
    section = target;
    _ticket++;
    notifyListeners();
  }

  /// 跳到联机加入，并带上地址。
  void openJoinRoom(String code, {bool autoJoin = false}) {
    final t = code.trim();
    pendingJoinCode = t.isEmpty ? null : t;
    pendingAutoJoin = autoJoin && t.isNotEmpty;
    section = GameResourceSection.rooms;
    _ticket++;
    notifyListeners();
  }

  /// RoomPage 取走预填后调用。
  ({String? code, bool autoJoin}) takePendingJoin() {
    final code = pendingJoinCode;
    final auto = pendingAutoJoin;
    pendingJoinCode = null;
    pendingAutoJoin = false;
    return (code: code, autoJoin: auto);
  }
}
