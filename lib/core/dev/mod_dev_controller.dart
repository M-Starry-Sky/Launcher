import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../game/game_instance.dart';
import '../perf/perf_mods_installer.dart';

/// 模组开发工作台：监视 jar 同步 + 开发命令通道 + HUD/ack 状态。
class ModDevController extends ChangeNotifier {
  static const String keyWatchDir = 'mod_dev_watch_dir';
  static const String keyAutoSync = 'mod_dev_auto_sync';

  static const String _cmdFileName = 'xingqiong_dev_cmd.json';
  static const String _ackFileName = 'xingqiong_dev_ack.json';
  static const String _hudFileName = 'xingqiong_hud.json';

  final AppConfig config;
  final InstanceStore instances;

  StreamSubscription<FileSystemEvent>? _watchSub;
  Timer? _pollTimer;
  Timer? _debounce;

  String _watchDir = '';
  bool _autoSync = true;
  bool _watching = false;
  String? _lastSyncedJar;
  DateTime? _lastSyncedAt;
  String? _statusMessage;

  int _cmdSeq = 0;
  int? _lastAckSeq;
  bool? _lastAckOk;
  String? _lastAckMessage;
  DateTime? _lastAckAt;

  bool _channelOnline = false;
  int? _hudFps;
  bool? _hudDamageNumbers;
  bool? _hudHealthBars;
  bool? _hudMinimap;

  ModDevController({
    required this.config,
    required this.instances,
  }) {
    _watchDir = config.getStringOr(keyWatchDir, '');
    _autoSync = config.getBoolOr(keyAutoSync, true);
  }

  String get watchDir => _watchDir;
  bool get autoSync => _autoSync;
  bool get watching => _watching;
  String? get lastSyncedJar => _lastSyncedJar;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get statusMessage => _statusMessage;

  int get cmdSeq => _cmdSeq;
  int? get lastAckSeq => _lastAckSeq;
  bool? get lastAckOk => _lastAckOk;
  String? get lastAckMessage => _lastAckMessage;
  DateTime? get lastAckAt => _lastAckAt;

  bool get channelOnline => _channelOnline;
  int? get hudFps => _hudFps;
  bool? get hudDamageNumbers => _hudDamageNumbers;
  bool? get hudHealthBars => _hudHealthBars;
  bool? get hudMinimap => _hudMinimap;

  GameInstance? get currentInstance => instances.selected;

  Directory gameDir() => instances.sharedGameRoot();

  Directory? instanceModsDir() {
    final inst = currentInstance;
    if (inst == null) return null;
    return Directory(p.join(instances.instanceDir(inst).path, 'mods'));
  }

  /// @deprecated 共享 mods 已废弃；仅兼容旧调用，实际应只用 [instanceModsDir]。
  Directory sharedModsDir() =>
      Directory(p.join(gameDir().path, 'mods'));

  bool get coreJarInstalled {
    const name = PerfModsInstaller.jarName;
    final inst = instanceModsDir();
    final local = inst == null ? null : File(p.join(inst.path, name));
    return local?.existsSync() ?? false;
  }

  bool get isFabric1201 {
    final i = currentInstance;
    if (i == null) return false;
    return i.loaderType == 'fabric' && i.gameVersion.startsWith('1.20.1');
  }

  Future<void> setWatchDir(String path) async {
    _watchDir = path.trim();
    await config.set(keyWatchDir, _watchDir);
    notifyListeners();
    if (_watching) {
      await stopWatch();
      await startWatch();
    }
  }

  Future<void> setAutoSync(bool value) async {
    _autoSync = value;
    await config.setBool(keyAutoSync, value);
    notifyListeners();
  }

  Future<void> startPolling() async {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _refreshStatus();
    });
    _refreshStatus();
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> startWatch() async {
    await stopWatch();
    final dirPath = _watchDir.trim();
    if (dirPath.isEmpty) {
      _statusMessage = '请先选择监视目录';
      notifyListeners();
      return;
    }
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      _statusMessage = '监视目录不存在';
      notifyListeners();
      return;
    }
    try {
      _watchSub = dir
          .watch(recursive: false)
          .listen(_onFsEvent, onError: (Object e) {
        _statusMessage = '监视出错: $e';
        notifyListeners();
      });
      _watching = true;
      _statusMessage = '正在监视 $dirPath';
      notifyListeners();
      if (_autoSync) {
        await syncNewestJar();
      }
    } catch (e) {
      _watching = false;
      _statusMessage = '无法监视: $e';
      notifyListeners();
    }
  }

  Future<void> stopWatch() async {
    await _watchSub?.cancel();
    _watchSub = null;
    _debounce?.cancel();
    _debounce = null;
    if (_watching) {
      _watching = false;
      _statusMessage = '已停止监视';
      notifyListeners();
    }
  }

  void _onFsEvent(FileSystemEvent event) {
    if (!_autoSync) return;
    final path = event.path;
    if (!_isSyncableJar(path)) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      final f = File(path);
      if (f.existsSync()) {
        unawaited(syncJar(f));
      } else {
        unawaited(syncNewestJar());
      }
    });
  }

  static bool _isSyncableJar(String path) {
    final name = p.basename(path).toLowerCase();
    if (!name.endsWith('.jar')) return false;
    if (name.contains('-sources') ||
        name.contains('-dev') ||
        name.contains('-javadoc')) {
      return false;
    }
    return true;
  }

  Future<void> syncNewestJar() async {
    final dirPath = _watchDir.trim();
    if (dirPath.isEmpty) return;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    File? newest;
    DateTime? newestAt;
    try {
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        if (!_isSyncableJar(e.path)) continue;
        final t = e.lastModifiedSync();
        if (newestAt == null || t.isAfter(newestAt)) {
          newestAt = t;
          newest = e;
        }
      }
    } catch (_) {
      return;
    }
    if (newest != null) await syncJar(newest);
  }

  Future<bool> syncJar(File jar) async {
    if (!_isSyncableJar(jar.path) || !jar.existsSync()) {
      _statusMessage = '无效 jar';
      notifyListeners();
      return false;
    }
    final name = p.basename(jar.path);
    try {
      final instMods = instanceModsDir();
      if (instMods == null) {
        _statusMessage = '未选择实例，无法同步';
        notifyListeners();
        return false;
      }
      await instMods.create(recursive: true);
      await jar.copy(p.join(instMods.path, name));

      _lastSyncedJar = name;
      _lastSyncedAt = DateTime.now();
      _statusMessage = '已同步到实例 $name';
      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = '同步失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> ensureCoreInstalled() async {
    final installer = PerfModsInstaller(onLog: (m) {
      _statusMessage = m;
      notifyListeners();
    });
    final inst = instanceModsDir();
    if (inst == null) {
      _statusMessage = '未选择实例';
      notifyListeners();
      return false;
    }
    final ok = await installer.ensureCoreJar(inst, force: true);
    _statusMessage = ok ? '星穹核心已安装到本实例' : '星穹核心安装失败';
    notifyListeners();
    return ok;
  }

  Future<int> sendDevCmd(Map<String, dynamic> body) async {
    _cmdSeq += 1;
    final seq = _cmdSeq;
    final payload = <String, dynamic>{
      ...body,
      'seq': seq,
    };
    final file = File(p.join(gameDir().path, _cmdFileName));
    try {
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );
      _statusMessage = '已发送 #$seq ${body['cmd']}';
      notifyListeners();
    } catch (e) {
      _statusMessage = '写命令失败: $e';
      notifyListeners();
    }
    return seq;
  }

  Future<void> ping() => sendDevCmd({'cmd': 'ping'});

  Future<void> setDamageNumbers(bool enabled) =>
      sendDevCmd({'cmd': 'set_damage_numbers', 'enabled': enabled});

  Future<void> setHealthBars(bool enabled) =>
      sendDevCmd({'cmd': 'set_health_bars', 'enabled': enabled});

  Future<void> setMinimap(bool enabled) =>
      sendDevCmd({'cmd': 'set_minimap', 'enabled': enabled});

  Future<void> spawnTestDamage({double amount = 12}) => sendDevCmd({
        'cmd': 'spawn_damage',
        'amount': amount,
        'relative': true,
        'dx': 0,
        'dy': 2.2,
        'dz': 0,
      });

  Future<void> addTestMarker() => sendDevCmd({
        'cmd': 'add_marker',
        'label': 'dev-test',
        'kind': 'CUSTOM',
        'relative': true,
      });

  Future<void> clearMarkers() => sendDevCmd({'cmd': 'clear_markers'});

  void _refreshStatus() {
    var changed = false;
    final hudFile = File(p.join(gameDir().path, _hudFileName));
    try {
      if (hudFile.existsSync()) {
        final age = DateTime.now().difference(hudFile.lastModifiedSync());
        final online = age < const Duration(seconds: 12);
        if (online != _channelOnline) {
          _channelOnline = online;
          changed = true;
        }
        if (online) {
          final j = jsonDecode(hudFile.readAsStringSync()) as Map;
          final fps = (j['fps'] as num?)?.round();
          final dn = j['damage_numbers'] as bool?;
          final hb = j['health_bars'] as bool?;
          final mm = j['minimap'] as bool?;
          if (fps != _hudFps ||
              dn != _hudDamageNumbers ||
              hb != _hudHealthBars ||
              mm != _hudMinimap) {
            _hudFps = fps;
            _hudDamageNumbers = dn;
            _hudHealthBars = hb;
            _hudMinimap = mm;
            changed = true;
          }
        } else if (_hudFps != null) {
          _hudFps = null;
          changed = true;
        }
      } else if (_channelOnline) {
        _channelOnline = false;
        _hudFps = null;
        changed = true;
      }
    } catch (_) {}

    final ackFile = File(p.join(gameDir().path, _ackFileName));
    try {
      if (ackFile.existsSync()) {
        final j = jsonDecode(ackFile.readAsStringSync()) as Map;
        final seq = (j['seq'] as num?)?.toInt();
        final ok = j['ok'] as bool?;
        final msg = j['message']?.toString();
        final atMs = (j['at'] as num?)?.toInt();
        if (seq != null && seq != _lastAckSeq) {
          _lastAckSeq = seq;
          _lastAckOk = ok;
          _lastAckMessage = msg;
          _lastAckAt = atMs == null
              ? DateTime.now()
              : DateTime.fromMillisecondsSinceEpoch(atMs);
          changed = true;
        }
      }
    } catch (_) {}

    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stopWatch());
    stopPolling();
    super.dispose();
  }
}
