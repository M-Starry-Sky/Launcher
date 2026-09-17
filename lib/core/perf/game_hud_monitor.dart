import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'player_state_reader.dart';
import 'win_process.dart';

/// 悬浮窗一帧快照。
class GameHudSnapshot {
  final int? fps;
  /// gpu = 显卡呈现帧；file = 旁路文件；log = 日志
  final String? fpsSource;
  final double? cpuPercent;
  final int? memoryMb;
  final String? serverName;
  final String? serverAddress;
  final String? worldName;
  final bool multiplayer;
  final bool processAlive;
  final PlayerHudState? player;
  final DateTime at;

  const GameHudSnapshot({
    this.fps,
    this.fpsSource,
    this.cpuPercent,
    this.memoryMb,
    this.serverName,
    this.serverAddress,
    this.worldName,
    this.multiplayer = false,
    this.processAlive = true,
    this.player,
    required this.at,
  });

  GameHudSnapshot copyWith({
    int? fps,
    String? fpsSource,
    double? cpuPercent,
    int? memoryMb,
    String? serverName,
    String? serverAddress,
    String? worldName,
    bool? multiplayer,
    bool? processAlive,
    PlayerHudState? player,
    DateTime? at,
  }) {
    return GameHudSnapshot(
      fps: fps ?? this.fps,
      fpsSource: fpsSource ?? this.fpsSource,
      cpuPercent: cpuPercent ?? this.cpuPercent,
      memoryMb: memoryMb ?? this.memoryMb,
      serverName: serverName ?? this.serverName,
      serverAddress: serverAddress ?? this.serverAddress,
      worldName: worldName ?? this.worldName,
      multiplayer: multiplayer ?? this.multiplayer,
      processAlive: processAlive ?? this.processAlive,
      player: player ?? this.player,
      at: at ?? this.at,
    );
  }
}

/// 采样游戏实时状态：日志 / session.lock / 进程 / 人物坐标 / 可选 hud 文件。
class GameHudMonitor extends ChangeNotifier {
  final int pid;
  final Directory gameDir;
  final String? initialServerName;
  final String? initialServerAddress;
  final Map<String, String> serverNameByAddress;

  Timer? _timer;
  Timer? _fpsTimer;
  bool _fpsBusy = false;
  RandomAccessFile? _logRaf;
  int _logOffset = 0;
  String _logCarry = '';
  int? _prevCpuTicks;
  DateTime? _prevCpuAt;
  GameHudSnapshot _snap = GameHudSnapshot(at: DateTime.now());

  static final _reConnecting = RegExp(
    r'Connecting to ([^\s,]+)(?:,\s*(\d+))?',
    caseSensitive: false,
  );
  static final _reJoined = RegExp(
    r'(?:Joined world|Logging in|Resizing main window)',
    caseSensitive: false,
  );
  static final _reDisconnect = RegExp(
    r'(?:Disconnected|Stopping connection|Connection lost|Quitting)',
    caseSensitive: false,
  );
  static final _reFpsLine = RegExp(
    r'(?:fps|FPS)[^\d]{0,8}(\d{1,3})',
  );

  GameHudMonitor({
    required this.pid,
    required this.gameDir,
    this.initialServerName,
    this.initialServerAddress,
    this.serverNameByAddress = const {},
  });

  GameHudSnapshot get snapshot => _snap;

  void start({Duration interval = const Duration(milliseconds: 2000)}) {
    stop();
    if (initialServerAddress != null && initialServerAddress!.isNotEmpty) {
      _applyServer(initialServerAddress!, initialServerName);
    }
    _openLogTail();
    // 主采样放缓：避免 PowerShell / 磁盘扫描拖高悬浮窗 CPU
    _timer = Timer.periodic(interval, (_) => _tick());
    // 与桥接约 1Hz 对齐，便于平滑
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickFps());
    _tick();
    _tickFps();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _fpsTimer?.cancel();
    _fpsTimer = null;
    try {
      _logRaf?.closeSync();
    } catch (_) {}
    _logRaf = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  Future<void> _tick() async {
    final alive = await _isAlive(pid);
    if (!alive) {
      _snap = _snap.copyWith(processAlive: false, at: DateTime.now());
      notifyListeners();
      stop();
      return;
    }

    await _readNewLogLines();
    final world = _detectOpenWorld();
    final mem = await _readMemoryMb(pid);
    final cpu = await _readCpuPercent(pid);

    final multiplayer = _snap.multiplayer;
    final showWorld = !multiplayer ? world : (_snap.worldName ?? world);

    final player = PlayerStateReader.read(
      gameDir: gameDir,
      worldName: showWorld,
      multiplayer: multiplayer,
    );

    _snap = GameHudSnapshot(
      fps: _snap.fps,
      fpsSource: _snap.fpsSource,
      cpuPercent: cpu,
      memoryMb: mem,
      serverName: _snap.serverName,
      serverAddress: _snap.serverAddress,
      worldName: showWorld,
      multiplayer: multiplayer,
      processAlive: true,
      player: player,
      at: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> _tickFps() async {
    if (_fpsBusy) return;
    _fpsBusy = true;
    try {
      if (!await _isAlive(pid)) return;
      final got = await _readFps();
      if (got == null) return;
      if (_snap.fps == got.$1 && _snap.fpsSource == got.$2) return;
      _snap = _snap.copyWith(
        fps: got.$1,
        fpsSource: got.$2,
        at: DateTime.now(),
      );
      notifyListeners();
    } finally {
      _fpsBusy = false;
    }
  }

  void _applyServer(String address, String? name) {
    final host = address.split(':').first.trim();
    final mapped = name?.trim().isNotEmpty == true
        ? name!.trim()
        : _lookupServerName(address) ?? _lookupServerName(host);
    final isLocal = host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host == '::1';
    _snap = _snap.copyWith(
      serverAddress: address,
      serverName: mapped ?? (isLocal ? null : host),
      multiplayer: !isLocal,
      at: DateTime.now(),
    );
  }

  String? _lookupServerName(String addressOrHost) {
    final key = addressOrHost.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final e in serverNameByAddress.entries) {
      final a = e.key.trim().toLowerCase();
      if (a == key || a.startsWith('$key:') || key.startsWith(a)) {
        final n = e.value.trim();
        if (n.isNotEmpty) return n;
      }
    }
    return null;
  }

  void _openLogTail() {
    final logFile = File(p.join(gameDir.path, 'logs', 'latest.log'));
    if (!logFile.existsSync()) return;
    try {
      _logRaf = logFile.openSync(mode: FileMode.read);
      _logOffset = logFile.lengthSync();
      if (_logOffset > 256 * 1024) {
        _logOffset = _logOffset - 64 * 1024;
        _logRaf!.setPositionSync(_logOffset);
      } else {
        _logRaf!.setPositionSync(0);
        _logOffset = 0;
      }
    } catch (_) {
      _logRaf = null;
    }
  }

  Future<void> _readNewLogLines() async {
    final logFile = File(p.join(gameDir.path, 'logs', 'latest.log'));
    if (!logFile.existsSync()) return;
    try {
      if (_logRaf == null) _openLogTail();
      final raf = _logRaf;
      if (raf == null) return;
      final len = logFile.lengthSync();
      if (len < _logOffset) {
        await raf.close();
        _logRaf = null;
        _logOffset = 0;
        _openLogTail();
        return;
      }
      if (len == _logOffset) return;
      raf.setPositionSync(_logOffset);
      final bytes = raf.readSync(len - _logOffset);
      _logOffset = len;
      final chunk = _logCarry + utf8.decode(bytes, allowMalformed: true);
      final parts = chunk.split('\n');
      _logCarry = parts.isEmpty ? '' : parts.removeLast();
      for (final line in parts) {
        _consumeLogLine(line);
      }
    } catch (_) {}
  }

  void _consumeLogLine(String line) {
    final fpsMatch = _reFpsLine.firstMatch(line);
    if (fpsMatch != null && line.toLowerCase().contains('fps')) {
      final v = int.tryParse(fpsMatch.group(1)!);
      if (v != null && v > 0 && v < 1000) {
        _snap = _snap.copyWith(fps: v, fpsSource: 'log', at: DateTime.now());
      }
    }

    final conn = _reConnecting.firstMatch(line);
    if (conn != null) {
      final host = conn.group(1)!.trim();
      final port = conn.group(2);
      final addr = port == null || port.isEmpty ? host : '$host:$port';
      _applyServer(addr, null);
      return;
    }

    if (_reDisconnect.hasMatch(line)) {
      if (_snap.multiplayer) {
        _snap = GameHudSnapshot(
          fps: _snap.fps,
          fpsSource: _snap.fpsSource,
          cpuPercent: _snap.cpuPercent,
          memoryMb: _snap.memoryMb,
          worldName: _detectOpenWorld(),
          multiplayer: false,
          processAlive: true,
          player: _snap.player,
          at: DateTime.now(),
        );
      }
    }

    if (_reJoined.hasMatch(line) && !_snap.multiplayer) {
      final w = _detectOpenWorld();
      if (w != null) {
        _snap = _snap.copyWith(worldName: w, at: DateTime.now());
      }
    }
  }

  String? _detectOpenWorld() {
    final saves = Directory(p.join(gameDir.path, 'saves'));
    if (!saves.existsSync()) return null;
    try {
      String? locked;
      DateTime? lockedAt;
      String? newest;
      DateTime? newestAt;
      for (final entity in saves.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final lock = File(p.join(entity.path, 'session.lock'));
        final level = File(p.join(entity.path, 'level.dat'));
        if (lock.existsSync()) {
          final t = lock.lastModifiedSync();
          if (lockedAt == null || t.isAfter(lockedAt)) {
            lockedAt = t;
            locked = name;
          }
        } else if (level.existsSync()) {
          final t = level.lastModifiedSync();
          if (newestAt == null || t.isAfter(newestAt)) {
            newestAt = t;
            newest = name;
          }
        }
      }
      return locked ??
          (newestAt != null &&
                  DateTime.now().difference(newestAt) <
                      const Duration(minutes: 2)
              ? newest
              : null);
    } catch (_) {
      return null;
    }
  }

  Future<(int, String)?> _readFps() async {
    final hudFile = File(p.join(gameDir.path, 'xingqiong_hud.json'));
    if (hudFile.existsSync()) {
      try {
        final age = DateTime.now().difference(hudFile.lastModifiedSync());
        // 桥接约 1Hz；放宽到 12s，避免偶发 IO 卡顿后立刻掉回「…」
        if (age < const Duration(seconds: 12)) {
          final j = jsonDecode(await hudFile.readAsString()) as Map;
          final v = j['fps'];
          int? n;
          if (v is num) n = v.round();
          if (v is String) n = int.tryParse(v);
          // 允许 0：表示桥接在线但尚未出帧，UI 可显示 0 而非 …
          if (n != null && n >= 0 && n < 1000) return (n, 'file');
        }
      } catch (_) {}
    }

    // 默认不再跑 GPU 计数器 PowerShell（约 1s 睡眠/次，极易把悬浮窗打到高 CPU）。
    // 仅当从未拿到过帧率时，才偶尔兜底一次。
    if (Platform.isWindows && _snap.fps == null) {
      final gpu = await _sampleGpuFpsWindows(pid);
      if (gpu != null) return (gpu, 'gpu');
    }
    return null;
  }

  Future<int?> _sampleGpuFpsWindows(int targetPid) async {
    try {
      final script = '''
\$ErrorActionPreference='SilentlyContinue'
\$pids = New-Object System.Collections.Generic.List[int]
[void]\$pids.Add($targetPid)
try {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { \$_.ParentProcessId -eq $targetPid } |
    ForEach-Object { [void]\$pids.Add([int]\$_.ProcessId) }
} catch {}
function Read-Fps([int[]]\$idList) {
  \$set = Get-Counter -ListSet 'GPU Engine' -ErrorAction SilentlyContinue
  if (-not \$set) { return \$null }
  \$all = @(\$set.PathsWithInstances | Where-Object { \$_ -like '*Frames Per Second*' })
  if (\$all.Count -eq 0) { return \$null }
  \$paths = @()
  foreach (\$id in \$idList) {
    \$key = 'pid_' + \$id
    \$paths += @(\$all | Where-Object { \$_ -like "*\$key*" })
  }
  if (\$paths.Count -eq 0) { \$paths = \$all }
  \$paths = \$paths | Select-Object -Unique
  \$null = Get-Counter -Counter \$paths -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 950
  \$c = Get-Counter -Counter \$paths -ErrorAction SilentlyContinue
  if (-not \$c) { return \$null }
  \$best = 0.0
  \$sum3d = 0.0
  foreach (\$s in \$c.CounterSamples) {
    \$v = [double]\$s.CookedValue
    if (\$v -le 0.5) { continue }
    \$path = [string]\$s.Path
    if (\$path -match 'engtype_3D|engtype_Graphics|engtype_Render') {
      \$sum3d += \$v
    }
    if (\$v -gt \$best) { \$best = \$v }
  }
  if (\$sum3d -gt 1) { return [int][Math]::Round(\$sum3d) }
  if (\$best -gt 1) { return [int][Math]::Round(\$best) }
  return \$null
}
\$n = Read-Fps \$pids.ToArray()
if (\$null -ne \$n -and \$n -gt 1 -and \$n -lt 1000) { Write-Output \$n }
''';
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        runInShell: false,
      );
      final out = '${r.stdout}'.trim();
      if (out.isEmpty) return null;
      final v = int.tryParse(out.split(RegExp(r'\r?\n')).last.trim());
      if (v != null && v > 1 && v < 1000) return v;
    } catch (_) {}
    return null;
  }

  Future<int?> _readMemoryMb(int pid) async {
    try {
      if (Platform.isWindows) {
        return WinProcess.workingSetMb(pid);
      }
      final status = File('/proc/$pid/status');
      if (status.existsSync()) {
        for (final line in status.readAsLinesSync()) {
          if (line.startsWith('VmRSS:')) {
            final kb = int.tryParse(
              line.replaceAll(RegExp(r'[^0-9]'), ''),
            );
            if (kb != null) return (kb / 1024).round();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<double?> _readCpuPercent(int pid) async {
    try {
      if (Platform.isWindows) {
        final ticks100ns = WinProcess.cpuTime100ns(pid);
        final now = DateTime.now();
        if (ticks100ns == null) return null;
        // 换算为毫秒，沿用原公式
        final ticks = ticks100ns / 10000.0;
        final prev = _prevCpuTicks;
        final prevAt = _prevCpuAt;
        _prevCpuTicks = ticks.round();
        _prevCpuAt = now;
        if (prev == null || prevAt == null) return null;
        final dtMs = now.difference(prevAt).inMilliseconds;
        if (dtMs <= 0) return null;
        final cores = Platform.numberOfProcessors.clamp(1, 256);
        final pct = ((ticks - prev) / dtMs) * 100;
        return pct.clamp(0, 100.0 * cores).toDouble();
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _isAlive(int pid) async => gameProcessAlive(pid);
}
