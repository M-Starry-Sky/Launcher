import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// 世界生成类型（写入 level.dat 的 generatorName）。
enum WorldGeneratorType {
  /// 默认（普通世界）
  normal('default'),
  /// 超平坦
  flat('flat'),
  /// 大型生物群系
  largeBiomes('largeBiomes'),
  /// 放大化
  amplified('amplified');

  const WorldGeneratorType(this.generatorName);
  final String generatorName;
}

/// 写入可被 Minecraft 识别的最小存档（level.dat + 空 region）。
/// 进游戏后引擎会按当前版本升级 DataVersion。
class BlankWorldWriter {
  /// 在 [savesDir]/[folderName] 创建新世界。
  static Future<Directory> create({
    required Directory savesDir,
    required String folderName,
    String? displayName,
    int gameType = 0, // 0 生存 1 创造 2 冒险 3 旁观
    bool hardcore = false,
    int difficulty = 2, // 0 和平 … 3 困难
    String? seedText,
    WorldGeneratorType generator = WorldGeneratorType.normal,
    bool allowCommands = true,
    bool generateStructures = true,
    bool bonusChest = false,
  }) async {
    final safe = _sanitizeFolder(folderName);
    if (safe.isEmpty) {
      throw ArgumentError('存档名称无效');
    }
    final world = Directory(p.join(savesDir.path, safe));
    if (await world.exists()) {
      throw StateError('已存在同名存档「$safe」');
    }
    await world.create(recursive: true);
    await Directory(p.join(world.path, 'region')).create(recursive: true);
    await Directory(p.join(world.path, 'data')).create(recursive: true);

    final levelName = (displayName == null || displayName.trim().isEmpty)
        ? safe
        : displayName.trim();
    final seed = parseWorldSeed(seedText);
    final nbt = _buildLevelDat(
      levelName: levelName,
      gameType: hardcore ? 0 : gameType,
      hardcore: hardcore,
      difficulty: difficulty,
      seed: seed,
      generator: generator,
      allowCommands: allowCommands,
      generateStructures: generateStructures,
      bonusChest: bonusChest,
    );
    final gzipped = GZipEncoder().encode(nbt);
    if (gzipped == null) {
      throw StateError('压缩 level.dat 失败');
    }
    await File(p.join(world.path, 'level.dat')).writeAsBytes(gzipped);
    return world;
  }

  /// 解析种子：空=随机；纯数字=该 Long；否则按 Java String.hashCode。
  static int parseWorldSeed(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) {
      return DateTime.now().microsecondsSinceEpoch ^
          (DateTime.now().millisecondsSinceEpoch << 16);
    }
    final asInt = int.tryParse(t);
    if (asInt != null) return asInt;
    // Java String.hashCode → 有符号 32 位，再当作世界种子。
    var h = 0;
    for (final c in t.codeUnits) {
      h = (31 * h + c) & 0xFFFFFFFF;
    }
    if (h >= 0x80000000) h -= 0x100000000;
    return h;
  }

  /// 复制已有存档为新文件夹名。
  static Future<Directory> copyFrom({
    required Directory source,
    required Directory savesDir,
    required String folderName,
  }) async {
    final safe = _sanitizeFolder(folderName);
    if (safe.isEmpty) throw ArgumentError('存档名称无效');
    final target = Directory(p.join(savesDir.path, safe));
    if (await target.exists()) {
      throw StateError('已存在同名存档「$safe」');
    }
    await _copyDir(source, target);
    return target;
  }

  static String _sanitizeFolder(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s == '.' || s == '..') return '';
    return s;
  }

  static Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list(followLinks: false)) {
      final name = p.basename(e.path);
      if (name == 'session.lock') continue;
      final out = p.join(dst.path, name);
      if (e is Directory) {
        await _copyDir(e, Directory(out));
      } else if (e is File) {
        await e.copy(out);
      }
    }
  }

  static Uint8List _buildLevelDat({
    required String levelName,
    required int seed,
    int gameType = 0,
    bool hardcore = false,
    int difficulty = 2,
    WorldGeneratorType generator = WorldGeneratorType.normal,
    bool allowCommands = true,
    bool generateStructures = true,
    bool bonusChest = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dataBody = BytesBuilder();
    void field(int type, String name, void Function() writePayload) {
      dataBody.addByte(type);
      _writeString(dataBody, name);
      writePayload();
    }

    field(3, 'DataVersion', () => _writeInt(dataBody, 3465));
    field(8, 'LevelName', () => _writeString(dataBody, levelName));
    field(8, 'generatorName', () => _writeString(dataBody, generator.generatorName));
    if (generator == WorldGeneratorType.flat) {
      field(
        8,
        'generatorOptions',
        () => _writeString(
          dataBody,
          '{"biome":"minecraft:plains","layers":[{"block":"minecraft:bedrock","height":1},{"block":"minecraft:dirt","height":2},{"block":"minecraft:grass_block","height":1}],"structures":{"structures":{}}}',
        ),
      );
    } else {
      field(8, 'generatorOptions', () => _writeString(dataBody, ''));
    }
    field(4, 'RandomSeed', () => _writeLong(dataBody, seed));
    // 现代版本会读 WorldGenSettings.seed；写入精简复合标签便于升级。
    field(10, 'WorldGenSettings', () {
      final wg = BytesBuilder();
      void wgField(int type, String name, void Function() writePayload) {
        wg.addByte(type);
        _writeString(wg, name);
        writePayload();
      }

      wgField(4, 'seed', () => _writeLong(wg, seed));
      wgField(1, 'generate_features', () => wg.addByte(generateStructures ? 1 : 0));
      wgField(1, 'bonus_chest', () => wg.addByte(bonusChest ? 1 : 0));
      wg.addByte(0);
      dataBody.add(wg.toBytes());
    });
    field(3, 'GameType', () => _writeInt(dataBody, gameType));
    field(1, 'hardcore', () => dataBody.addByte(hardcore ? 1 : 0));
    field(1, 'Difficulty', () => dataBody.addByte(difficulty.clamp(0, 3)));
    field(1, 'DifficultyLocked', () => dataBody.addByte(hardcore ? 1 : 0));
    field(1, 'initialized', () => dataBody.addByte(0));
    field(3, 'SpawnX', () => _writeInt(dataBody, 0));
    field(3, 'SpawnY', () => _writeInt(dataBody, 64));
    field(3, 'SpawnZ', () => _writeInt(dataBody, 0));
    field(4, 'Time', () => _writeLong(dataBody, 0));
    field(4, 'DayTime', () => _writeLong(dataBody, 1000));
    field(4, 'LastPlayed', () => _writeLong(dataBody, now));
    field(4, 'SizeOnDisk', () => _writeLong(dataBody, 0));
    field(1, 'allowCommands', () => dataBody.addByte(allowCommands ? 1 : 0));
    field(1, 'MapFeatures', () => dataBody.addByte(generateStructures ? 1 : 0));
    field(1, 'raining', () => dataBody.addByte(0));
    field(1, 'thundering', () => dataBody.addByte(0));
    field(3, 'rainTime', () => _writeInt(dataBody, 12000));
    field(3, 'thunderTime', () => _writeInt(dataBody, 120000));
    field(3, 'clearWeatherTime', () => _writeInt(dataBody, 0));
    field(3, 'version', () => _writeInt(dataBody, 19133));
    dataBody.addByte(0);

    final out = BytesBuilder();
    out.addByte(10);
    _writeString(out, '');
    out.addByte(10);
    _writeString(out, 'Data');
    out.add(dataBody.toBytes());
    out.addByte(0);
    return Uint8List.fromList(out.toBytes());
  }

  static void _writeString(BytesBuilder b, String s) {
    final bytes = utf8.encode(s);
    b.addByte((bytes.length >> 8) & 0xff);
    b.addByte(bytes.length & 0xff);
    b.add(bytes);
  }

  static void _writeInt(BytesBuilder b, int v) {
    b.addByte((v >> 24) & 0xff);
    b.addByte((v >> 16) & 0xff);
    b.addByte((v >> 8) & 0xff);
    b.addByte(v & 0xff);
  }

  static void _writeLong(BytesBuilder b, int v) {
    final hi = (v >> 32) & 0xffffffff;
    final lo = v & 0xffffffff;
    _writeInt(b, hi);
    _writeInt(b, lo);
  }
}
