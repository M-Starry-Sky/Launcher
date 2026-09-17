import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 极简 Minecraft NBT 读取（gzip / 裸二进制），只取人物坐标相关字段。
class MinecraftNbt {
  /// 从 playerdata/*.dat 或 level.dat 解析人物信息。
  static PlayerNbtInfo? readPlayerFile(File file) {
    try {
      final raw = file.readAsBytesSync();
      if (raw.isEmpty) return null;
      final bytes = _maybeGunzip(raw);
      final r = _NbtReader(bytes);
      final root = r.readNamed();
      if (root is! Map) return null;

      // level.dat → Data.Player；playerdata → 根即玩家
      Map? player = root;
      final data = root['Data'];
      if (data is Map && data['Player'] is Map) {
        player = data['Player'] as Map;
      }
      if (player == null) return null;

      final pos = player['Pos'];
      double? x, y, z;
      if (pos is List && pos.length >= 3) {
        x = _asDouble(pos[0]);
        y = _asDouble(pos[1]);
        z = _asDouble(pos[2]);
      }

      final rot = player['Rotation'];
      double? yaw, pitch;
      if (rot is List && rot.length >= 2) {
        yaw = _asDouble(rot[0]);
        pitch = _asDouble(rot[1]);
      }

      String? dimension;
      final dim = player['Dimension'];
      if (dim is String) {
        dimension = dim;
      } else if (dim is int) {
        dimension = switch (dim) {
          0 => 'minecraft:overworld',
          -1 => 'minecraft:the_nether',
          1 => 'minecraft:the_end',
          _ => 'dim:$dim',
        };
      }

      final health = _asDouble(player['Health']);
      final food = player['foodLevel'] is int
          ? player['foodLevel'] as int
          : int.tryParse('${player['foodLevel']}');
      final xpLevel = player['XpLevel'] is int
          ? player['XpLevel'] as int
          : int.tryParse('${player['XpLevel']}');
      final gm = player['playerGameType'] ?? player['GameType'];
      final gameMode = gm is int ? gm : int.tryParse('$gm');

      if (x == null && y == null && z == null) return null;
      return PlayerNbtInfo(
        x: x,
        y: y,
        z: z,
        yaw: yaw,
        pitch: pitch,
        dimension: dimension,
        health: health,
        food: food,
        xpLevel: xpLevel,
        gameMode: gameMode,
        source: 'nbt',
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _maybeGunzip(Uint8List raw) {
    // gzip magic 1f 8b
    if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
      return Uint8List.fromList(gzip.decode(raw));
    }
    return raw;
  }

  static double? _asDouble(Object? v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}

class PlayerNbtInfo {
  final double? x, y, z;
  final double? yaw, pitch;
  final String? dimension;
  final double? health;
  final int? food;
  final int? xpLevel;
  final int? gameMode;
  final String source;

  const PlayerNbtInfo({
    this.x,
    this.y,
    this.z,
    this.yaw,
    this.pitch,
    this.dimension,
    this.health,
    this.food,
    this.xpLevel,
    this.gameMode,
    this.source = 'nbt',
  });
}

class _NbtReader {
  final ByteData _bd;
  final Uint8List _bytes;
  int _i = 0;

  _NbtReader(Uint8List bytes)
      : _bytes = bytes,
        _bd = ByteData.sublistView(bytes);

  Object? readNamed() {
    final type = _u8();
    if (type == 0) return null;
    _readString(); // name
    return _readPayload(type);
  }

  Object? _readPayload(int type) {
    switch (type) {
      case 1: // byte
        return _i8();
      case 2: // short
        return _i16();
      case 3: // int
        return _i32();
      case 4: // long
        return _i64();
      case 5: // float
        return _f32();
      case 6: // double
        return _f64();
      case 7: // byte array
        final n = _i32();
        _i += n;
        return null;
      case 8: // string
        return _readString();
      case 9: // list
        final et = _u8();
        final n = _i32();
        final list = <Object?>[];
        for (var k = 0; k < n; k++) {
          list.add(_readPayload(et));
        }
        return list;
      case 10: // compound
        final map = <String, Object?>{};
        while (true) {
          final t = _u8();
          if (t == 0) break;
          final name = _readString();
          map[name] = _readPayload(t);
        }
        return map;
      case 11: // int array
        final n = _i32();
        _i += n * 4;
        return null;
      case 12: // long array
        final n = _i32();
        _i += n * 8;
        return null;
      default:
        throw FormatException('未知 NBT 类型 $type @$_i');
    }
  }

  String _readString() {
    final len = _u16();
    if (len == 0) return '';
    final s = utf8.decode(_bytes.sublist(_i, _i + len), allowMalformed: true);
    _i += len;
    return s;
  }

  int _u8() => _bytes[_i++];
  int _i8() {
    final v = _bd.getInt8(_i);
    _i += 1;
    return v;
  }

  int _u16() {
    final v = _bd.getUint16(_i, Endian.big);
    _i += 2;
    return v;
  }

  int _i16() {
    final v = _bd.getInt16(_i, Endian.big);
    _i += 2;
    return v;
  }

  int _i32() {
    final v = _bd.getInt32(_i, Endian.big);
    _i += 4;
    return v;
  }

  int _i64() {
    final v = _bd.getInt64(_i, Endian.big);
    _i += 8;
    return v;
  }

  double _f32() {
    final v = _bd.getFloat32(_i, Endian.big);
    _i += 4;
    return v;
  }

  double _f64() {
    final v = _bd.getFloat64(_i, Endian.big);
    _i += 8;
    return v;
  }
}
