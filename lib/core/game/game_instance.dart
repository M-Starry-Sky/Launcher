import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

/// 游戏实例（对齐 Prism / HMCL：独立目录 + 版本/加载器配置）。
class GameInstance {
  final String id;
  final String name;
  final String gameVersion;
  final String loaderType; // none | fabric
  final String loaderVersion;
  final int createdAtMs;
  final int lastPlayedMs;
  final String jvmArgs;

  const GameInstance({
    required this.id,
    required this.name,
    required this.gameVersion,
    this.loaderType = 'none',
    this.loaderVersion = '',
    required this.createdAtMs,
    this.lastPlayedMs = 0,
    this.jvmArgs = '',
  });

  String get launchVersionId {
    if (loaderType == 'fabric' && loaderVersion.isNotEmpty) {
      return 'fabric-loader-$loaderVersion-$gameVersion';
    }
    return gameVersion;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'game_version': gameVersion,
        'loader_type': loaderType,
        'loader_version': loaderVersion,
        'created_at_ms': createdAtMs,
        'last_played_ms': lastPlayedMs,
        'jvm_args': jvmArgs,
      };

  factory GameInstance.fromJson(Map<String, dynamic> json) {
    return GameInstance(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名',
      gameVersion: json['game_version'] as String? ?? '1.20.1',
      loaderType: json['loader_type'] as String? ?? 'none',
      loaderVersion: json['loader_version'] as String? ?? '',
      createdAtMs: (json['created_at_ms'] as num?)?.toInt() ?? 0,
      lastPlayedMs: (json['last_played_ms'] as num?)?.toInt() ?? 0,
      jvmArgs: json['jvm_args'] as String? ?? '',
    );
  }

  GameInstance copyWith({
    String? name,
    String? gameVersion,
    String? loaderType,
    String? loaderVersion,
    int? lastPlayedMs,
    String? jvmArgs,
  }) {
    return GameInstance(
      id: id,
      name: name ?? this.name,
      gameVersion: gameVersion ?? this.gameVersion,
      loaderType: loaderType ?? this.loaderType,
      loaderVersion: loaderVersion ?? this.loaderVersion,
      createdAtMs: createdAtMs,
      lastPlayedMs: lastPlayedMs ?? this.lastPlayedMs,
      jvmArgs: jvmArgs ?? this.jvmArgs,
    );
  }
}

/// 实例仓库：持久化到 SharedPreferences，目录落在 gameDataDir/instances。
class InstanceStore extends ChangeNotifier {
  static const String _keyList = 'game_instances_v1';
  static const String _keySelected = 'selected_instance_id';

  /// Android / iOS 稳定数据根（非 systemTemp）。
  static String? _platformDefaultRoot;

  final AppConfig config;
  List<GameInstance> _items = [];
  String? _selectedId;

  InstanceStore(this.config);

  /// 手机端启动时解析稳定目录，避免本体落到会被清理的 Temp。
  static Future<void> preparePlatformRoots() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_platformDefaultRoot != null) return;

    Directory? base;
    if (Platform.isAndroid) {
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {}
    }
    base ??= await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'xingqiong'));
    await root.create(recursive: true);
    _platformDefaultRoot = p.normalize(root.absolute.path);
  }

  List<GameInstance> get items => List.unmodifiable(_items);
  String? get selectedId => _selectedId;
  GameInstance? get selected {
    if (_items.isEmpty) return null;
    for (final e in _items) {
      if (e.id == _selectedId) return e;
    }
    return _items.first;
  }

  Future<void> load() async {
    final raw = config.getJson(_keyList);
    final list = (raw['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => GameInstance.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty)
        .toList();
    _items = list;
    _selectedId = config.getJson(_keySelected)['id'] as String?;
    if (_items.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final def = GameInstance(
        id: 'default',
        name: '默认实例',
        gameVersion: '1.20.1',
        createdAtMs: now,
      );
      _items = [def];
      _selectedId = def.id;
      await _persist();
    } else if (_selectedId == null ||
        !_items.any((e) => e.id == _selectedId)) {
      _selectedId = _items.first.id;
      await _persistSelected();
    }
    notifyListeners();
  }

  Directory instanceDir(GameInstance instance) {
    return Directory(p.join(dataRootPath(), 'instances', instance.id));
  }

  /// 实例运行目录（mods / config / saves / logs）。与共享本体严格隔离。
  Directory instanceGameDir(GameInstance instance) => instanceDir(instance);

  /// 数据根目录（其下为 instances/、skins/；默认还含 game/）。
  String dataRootPath() {
    final custom = config.gameDataDir.trim();
    if (custom.isNotEmpty) {
      return p.normalize(Directory(custom).absolute.path);
    }
    if (Platform.isWindows) {
      return _resolveWindowsDataRoot();
    }
    if (_platformDefaultRoot != null) {
      return _platformDefaultRoot!;
    }
    return p.normalize(Directory.systemTemp.absolute.path);
  }

  static bool _pathUnderTemp(String path) {
    if (path.trim().isEmpty) return true;
    final temp = p.normalize(Directory.systemTemp.absolute.path);
    final n = p.normalize(Directory(path).absolute.path);
    return n == temp || p.isWithin(temp, n);
  }

  /// Windows：优先已有本体的稳定目录；禁止默默落在 Temp（会被系统清理）。
  String _resolveWindowsDataRoot() {
    final preferred = Directory(r'C:\xingqiong');
    final legacyParent = Directory(Directory.systemTemp.path);
    final preferredGame = Directory(p.join(preferred.path, 'game'));
    final legacyGame = Directory(p.join(legacyParent.path, 'game'));

    final prefHas = _gameHasVersions(preferredGame);
    final legHas = _gameHasVersions(legacyGame);

    if (prefHas) {
      return p.normalize(preferred.absolute.path);
    }
    // 仅 Temp 有旧数据时暂用 Temp，但首次解析后应被 ensurePathsPersisted 迁到稳定盘
    if (legHas && !preferred.existsSync()) {
      return p.normalize(legacyParent.absolute.path);
    }
    preferred.createSync(recursive: true);
    return p.normalize(preferred.absolute.path);
  }

  static bool _gameHasVersions(Directory gameDir) {
    final versions = Directory(p.join(gameDir.path, 'versions'));
    if (!versions.existsSync()) return false;
    try {
      return versions.listSync().whereType<Directory>().any((d) {
        final id = p.basename(d.path);
        return id.isNotEmpty && !id.startsWith('.');
      });
    } catch (_) {
      return false;
    }
  }

  /// 皮肤目录：{dataRoot}/skins
  Directory skinsDir() => Directory(p.join(dataRootPath(), 'skins'));

  /// 未自定义时的推荐默认根（Windows 纯英文路径，勿用 Temp）。
  static String defaultDataRootHint() {
    if (Platform.isWindows) return r'C:\xingqiong';
    return _platformDefaultRoot ?? Directory.systemTemp.path;
  }

  /// 游戏本体默认路径提示：{dataRoot}/game
  String defaultGameBodyHint() => p.join(dataRootPath(), 'game');

  /// 共享游戏本体根（仅 versions / libraries / assets）。
  /// 模组与存档不落此目录，避免实例间互相污染。
  /// 优先使用独立「本体下载目录」；否则为 {dataRoot}/game。
  Directory sharedGameRoot() {
    final body = config.gameBodyDir.trim();
    if (body.isNotEmpty) {
      final dir = Directory(p.normalize(Directory(body).absolute.path));
      dir.createSync(recursive: true);
      return dir;
    }
    final dir = Directory(p.join(dataRootPath(), 'game'));
    dir.createSync(recursive: true);
    return dir;
  }

  /// 把当前生效路径写进设置；手机/PC 若误持久化到 Temp 则迁到稳定目录。
  Future<void> ensurePathsPersisted() async {
    var changed = false;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await preparePlatformRoots();
      final stable = _platformDefaultRoot!;
      final data = config.gameDataDir.trim();
      final body = config.gameBodyDir.trim();
      if (_pathUnderTemp(data)) {
        await config.set(AppConfig.keyGameDataDir, stable);
        changed = true;
      }
      if (_pathUnderTemp(body)) {
        final root =
            config.gameDataDir.trim().isEmpty ? stable : dataRootPath();
        final newBody = p.join(root, 'game');
        await Directory(newBody).create(recursive: true);
        await config.set(
          AppConfig.keyGameBodyDir,
          p.normalize(Directory(newBody).absolute.path),
        );
        changed = true;
      }
    }

    if (!kIsWeb && Platform.isWindows) {
      final stable = _resolveWindowsDataRoot();
      final data = config.gameDataDir.trim();
      final body = config.gameBodyDir.trim();
      if (_pathUnderTemp(data)) {
        await config.set(AppConfig.keyGameDataDir, stable);
        changed = true;
      }
      if (_pathUnderTemp(body)) {
        final root =
            config.gameDataDir.trim().isEmpty ? stable : dataRootPath();
        final newBody = p.join(root, 'game');
        await Directory(newBody).create(recursive: true);
        await config.set(
          AppConfig.keyGameBodyDir,
          p.normalize(Directory(newBody).absolute.path),
        );
        changed = true;
      }
    }

    if (config.gameDataDir.trim().isEmpty) {
      await config.set(AppConfig.keyGameDataDir, dataRootPath());
      changed = true;
    }
    if (config.gameBodyDir.trim().isEmpty) {
      final body = Directory(p.join(dataRootPath(), 'game'));
      body.createSync(recursive: true);
      await config.set(
        AppConfig.keyGameBodyDir,
        p.normalize(body.absolute.path),
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<GameInstance> create({
    required String name,
    required String gameVersion,
    String loaderType = 'none',
    String loaderVersion = '',
  }) async {
    final id = 'inst-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final item = GameInstance(
      id: id,
      name: name.trim().isEmpty ? '新实例' : name.trim(),
      gameVersion: gameVersion,
      loaderType: loaderType,
      loaderVersion: loaderVersion,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _items = [..._items, item];
    _selectedId = id;
    await instanceDir(item).create(recursive: true);
    await Directory(p.join(instanceDir(item).path, 'mods')).create(recursive: true);
    await _persist();
    notifyListeners();
    return item;
  }

  Future<void> update(GameInstance item) async {
    _items = _items.map((e) => e.id == item.id ? item : e).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id, {bool deleteFiles = true}) async {
    if (_items.length <= 1) {
      throw StateError('至少保留一个实例');
    }
    GameInstance? removed;
    for (final e in _items) {
      if (e.id == id) {
        removed = e;
        break;
      }
    }
    _items = _items.where((e) => e.id != id).toList();
    if (_selectedId == id) _selectedId = _items.first.id;
    await _persist();
    notifyListeners();

    if (deleteFiles && removed != null) {
      final dir = instanceDir(removed);
      if (dir.existsSync()) {
        // 真删除实例目录（mods 等）
        Object? err;
        for (var i = 0; i < 5; i++) {
          try {
            await dir.delete(recursive: true);
            if (!dir.existsSync()) {
              err = null;
              break;
            }
          } catch (e) {
            err = e;
            await Future<void>.delayed(Duration(milliseconds: 120 * (i + 1)));
          }
        }
        if (dir.existsSync()) {
          throw StateError('实例记录已移除，但目录删除失败: ${dir.path} ($err)');
        }
      }
    }
  }

  Future<void> select(String id) async {
    if (!_items.any((e) => e.id == id)) return;
    _selectedId = id;
    await _persistSelected();
    notifyListeners();
  }

  Future<void> touchPlayed(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _items = _items
        .map((e) => e.id == id ? e.copyWith(lastPlayedMs: now) : e)
        .toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await config.setJson(_keyList, {
      'items': _items.map((e) => e.toJson()).toList(),
    });
    await _persistSelected();
  }

  Future<void> _persistSelected() async {
    await config.setJson(_keySelected, {'id': _selectedId});
  }
}
