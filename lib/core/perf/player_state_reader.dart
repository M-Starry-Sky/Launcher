import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'minecraft_nbt.dart';

/// 人物状态：坐标 / 维度 / 朝向 / 生命等。
class PlayerHudState {
  final double? x, y, z;
  final double? yaw, pitch;
  final String? dimension;
  final String? biome;
  final double? health;
  final double? maxHealth;
  final int? food;
  final int? xpLevel;
  final int? gameMode;
  final String? facing;
  /// live=json桥 · nbt=存档 · none
  final String source;

  const PlayerHudState({
    this.x,
    this.y,
    this.z,
    this.yaw,
    this.pitch,
    this.dimension,
    this.biome,
    this.health,
    this.maxHealth,
    this.food,
    this.xpLevel,
    this.gameMode,
    this.facing,
    this.source = 'none',
  });

  bool get hasCoords => x != null && y != null && z != null;

  String get coordsText {
    if (!hasCoords) return '—';
    return '${x!.toStringAsFixed(1)} / ${y!.toStringAsFixed(1)} / ${z!.toStringAsFixed(1)}';
  }

  String get blockCoordsText {
    if (!hasCoords) return '—';
    return '${x!.floor()} ${y!.floor()} ${z!.floor()}';
  }

  static String? facingFromYaw(double? yaw) {
    if (yaw == null) return null;
    var a = yaw % 360;
    if (a < 0) a += 360;
    // MC：0=南, 90=西, 180=北, 270=东
    if (a >= 315 || a < 45) return '南 (+Z)';
    if (a < 135) return '西 (-X)';
    if (a < 225) return '北 (-Z)';
    return '东 (+X)';
  }

  static String prettyDimension(String? dim) {
    if (dim == null || dim.isEmpty) return '—';
    final d = dim.replaceFirst('minecraft:', '');
    return switch (d) {
      'overworld' => '主世界',
      'the_nether' => '下界',
      'the_end' => '末地',
      _ => d,
    };
  }

  static String? prettyGameMode(int? gm) {
    return switch (gm) {
      0 => '生存',
      1 => '创造',
      2 => '冒险',
      3 => '旁观',
      _ => gm == null ? null : '模式$gm',
    };
  }
}

/// 从 xingqiong_hud.json（实时）或存档 NBT（单人近似）读取人物状态。
class PlayerStateReader {
  /// 优先实时 JSON；否则读单人存档。
  static PlayerHudState? read({
    required Directory gameDir,
    String? worldName,
    bool multiplayer = false,
  }) {
    final live = _readHudJson(gameDir);
    if (live != null && live.hasCoords) return live;

    if (!multiplayer && worldName != null && worldName.isNotEmpty) {
      final nbt = _readWorldPlayer(gameDir, worldName);
      if (nbt != null) return nbt;
    }

    // 无世界名时扫所有带 session.lock 的存档
    if (!multiplayer) {
      final open = _findOpenWorld(gameDir);
      if (open != null) {
        final nbt = _readWorldPlayer(gameDir, open);
        if (nbt != null) return nbt;
      }
    }

    return live; // 可能只有血量等无坐标
  }

  static PlayerHudState? _readHudJson(Directory gameDir) {
    final file = File(p.join(gameDir.path, 'xingqiong_hud.json'));
    if (!file.existsSync()) return null;
    try {
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age > const Duration(seconds: 8)) return null;
      final j = jsonDecode(file.readAsStringSync()) as Map;
      final x = _num(j['x'] ?? j['pos_x']);
      final y = _num(j['y'] ?? j['pos_y']);
      final z = _num(j['z'] ?? j['pos_z']);
      final yaw = _num(j['yaw'] ?? j['rotation_yaw']);
      final pitch = _num(j['pitch'] ?? j['rotation_pitch']);
      final dim = j['dimension']?.toString() ?? j['dim']?.toString();
      final biome = j['biome']?.toString();
      final health = _num(j['health'] ?? j['hp']);
      final maxHp = _num(j['max_health'] ?? j['max_hp']);
      final food = _int(j['food'] ?? j['hunger']);
      final xp = _int(j['xp_level'] ?? j['level']);
      final gm = _int(j['game_mode'] ?? j['gamemode']);
      return PlayerHudState(
        x: x,
        y: y,
        z: z,
        yaw: yaw,
        pitch: pitch,
        dimension: dim,
        biome: biome,
        health: health,
        maxHealth: maxHp,
        food: food,
        xpLevel: xp,
        gameMode: gm,
        facing: PlayerHudState.facingFromYaw(yaw),
        source: 'live',
      );
    } catch (_) {
      return null;
    }
  }

  static PlayerHudState? _readWorldPlayer(Directory gameDir, String worldName) {
    final worldDir = Directory(p.join(gameDir.path, 'saves', worldName));
    if (!worldDir.existsSync()) return null;

    PlayerNbtInfo? best;
    DateTime? bestTime;

    final playerDir = Directory(p.join(worldDir.path, 'playerdata'));
    if (playerDir.existsSync()) {
      for (final f in playerDir.listSync().whereType<File>()) {
        if (!f.path.toLowerCase().endsWith('.dat')) continue;
        // 跳过旧备份
        if (f.path.endsWith('.dat_old')) continue;
        try {
          final t = f.lastModifiedSync();
          if (bestTime != null && t.isBefore(bestTime)) continue;
          final info = MinecraftNbt.readPlayerFile(f);
          if (info != null) {
            best = info;
            bestTime = t;
          }
        } catch (_) {}
      }
    }

    final level = File(p.join(worldDir.path, 'level.dat'));
    if (level.existsSync()) {
      try {
        final t = level.lastModifiedSync();
        if (bestTime == null || t.isAfter(bestTime)) {
          final info = MinecraftNbt.readPlayerFile(level);
          if (info != null) {
            best = info;
            bestTime = t;
          }
        }
      } catch (_) {}
    }

    if (best == null) return null;
    return PlayerHudState(
      x: best.x,
      y: best.y,
      z: best.z,
      yaw: best.yaw,
      pitch: best.pitch,
      dimension: best.dimension,
      health: best.health,
      food: best.food,
      xpLevel: best.xpLevel,
      gameMode: best.gameMode,
      facing: PlayerHudState.facingFromYaw(best.yaw),
      source: 'nbt',
    );
  }

  static String? _findOpenWorld(Directory gameDir) {
    final saves = Directory(p.join(gameDir.path, 'saves'));
    if (!saves.existsSync()) return null;
    String? name;
    DateTime? at;
    for (final e in saves.listSync().whereType<Directory>()) {
      final lock = File(p.join(e.path, 'session.lock'));
      if (!lock.existsSync()) continue;
      final t = lock.lastModifiedSync();
      if (at == null || t.isAfter(at)) {
        at = t;
        name = p.basename(e.path);
      }
    }
    return name;
  }

  static double? _num(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  static int? _int(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse('$v');
  }
}
