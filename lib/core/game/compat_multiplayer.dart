import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/pack_service.dart';
import '../auth/auth_manager.dart';
import 'game_launcher.dart';

/// 兼容联机：私服关闭正版校验 +（Java）跨版本协议模组辅助。
///
/// 不做客户端破解；仅改本机开服配置，并尽量装 ViaFabricPlus 等合法模组。
/// 下载前按 MC 版本选定唯一项目与文件，不双装、不先下后删。
class CompatMultiplayer {
  /// 写入 / 修补 Java 或基岩 dedicated 的 server.properties。
  static Future<void> patchServerProperties(
    Directory gameDir, {
    required String gameType,
    int? port,
    void Function(String)? onLog,
  }) async {
    final candidates = <File>[
      File(p.join(gameDir.path, 'server.properties')),
      if (gameType == 'bedrock') ...[
        File(p.join(gameDir.path, 'bedrock_server', 'server.properties')),
        File(p.join(gameDir.path, 'bds', 'server.properties')),
      ],
    ];

    File? target;
    for (final f in candidates) {
      if (await f.exists()) {
        target = f;
        break;
      }
    }
    target ??= candidates.first;
    await target.parent.create(recursive: true);

    final map = <String, String>{};
    if (await target.exists()) {
      for (final line in await target.readAsLines()) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        final i = t.indexOf('=');
        if (i <= 0) continue;
        map[t.substring(0, i).trim()] = t.substring(i + 1).trim();
      }
    }

    // 关闭正版 / Xbox 强制校验，离线与正版可同房
    map['online-mode'] = 'false';
    if (gameType == 'java') {
      map['enforce-secure-profile'] = 'false';
      map['prevent-proxy-connections'] = 'false';
      if (port != null && port > 0) map['server-port'] = '$port';
    } else {
      // 基岩专用服常见键
      map['online-mode'] = 'false';
      if (port != null && port > 0) map['server-port'] = '$port';
      map['allow-cheats'] = map['allow-cheats'] ?? 'true';
    }

    final buf = StringBuffer()
      ..writeln('# 星穹次元 · 兼容联机自动写入')
      ..writeln('# online-mode=false：不校验正版，离线/正版昵称都可进');
    map.forEach((k, v) => buf.writeln('$k=$v'));
    await target.writeAsString(buf.toString());
    onLog?.call('已写入兼容开服配置：${target.path}');
    onLog?.call('已关闭服务器正版登录校验（仅建议私人好友房间使用）');
  }

  /// 为 Fabric 客户端安装跨版本协议模组（尽力而为，失败不阻断）。
  ///
  /// 先查询再下载：只选一个项目（优先 ViaFabricPlus），且只拉取匹配
  /// [gameVersion] 的文件列表，从源头避免互斥/错版 jar。
  static Future<void> ensureJavaCompatMods({
    required String gameVersion,
    required String loaderType,
    required Directory modsDir,
    void Function(String)? onLog,
  }) async {
    final loader = loaderType.toLowerCase();
    if (loader != 'fabric' && loader != 'quilt') {
      onLog?.call(
        '跨版本模组需 Fabric/Quilt。原版/Forge 请用带 ViaVersion 的 Paper 服，或改用 Fabric 实例。',
      );
      return;
    }
    await modsDir.create(recursive: true);
    final client = ModrinthClient();
    final loaderId = loader == 'quilt' ? 'quilt' : 'fabric';
    final gv = gameVersion.trim();

    onLog?.call('查询 $gv 可用的跨版本模组…');
    final plan = await _resolveCompatDownload(
      client: client,
      gameVersion: gv,
      loader: loaderId,
    );
    if (plan == null) {
      onLog?.call('未找到精确适配 $gv 的 ViaFabricPlus / ViaFabric，跳过');
      return;
    }

    onLog?.call(
      '选定 ${plan.label}（${plan.slug} @ ${plan.versionNumber}），'
      '将下载 ${plan.files.length} 个文件：'
      '${plan.files.map((f) => f.filename).join(', ')}',
    );

    if (_hasChosenMod(modsDir, plan.kind) &&
        !_hasForeignCompatMods(modsDir, plan.kind)) {
      onLog?.call('已有 ${plan.label} 且无互斥项，跳过下载');
      return;
    }

    // 仅移除与「本次选定」互斥的旧文件，再写入已解析好的文件（不再下完再筛）
    _removeForeignCompatMods(modsDir, plan.kind);

    try {
      final written = await client.downloadResolvedFiles(
        files: plan.files,
        targetDir: modsDir,
      );
      onLog?.call(
        '已写入 ${written.map((f) => p.basename(f.path)).join(', ')}',
      );
    } catch (e) {
      onLog?.call('跨版本模组下载失败: $e');
    }
  }

  /// 下载前解析：选项目 → 选版本 → 选文件（不落盘）。
  static Future<_CompatDownloadPlan?> _resolveCompatDownload({
    required ModrinthClient client,
    required String gameVersion,
    required String loader,
  }) async {
    // 优先 Plus
    final plus = await client.resolveExactGameFiles(
      projectId: 'viafabricplus',
      gameVersion: gameVersion,
      loader: loader,
      fileSelect: ModrinthFileSelect.singleBest,
    );
    if (plus != null) {
      return _CompatDownloadPlan(
        kind: CompatModKind.viafabricplus,
        slug: 'viafabricplus',
        label: 'ViaFabricPlus',
        versionNumber: plus.versionNumber,
        files: plus.files,
      );
    }

    // 回退 ViaFabric：只解析当前 MC 对应文件，其它 mc* 根本不进列表
    final via = await client.resolveExactGameFiles(
      projectId: 'viafabric',
      gameVersion: gameVersion,
      loader: loader,
      fileSelect: ModrinthFileSelect.viaFabricForGame,
    );
    if (via != null) {
      return _CompatDownloadPlan(
        kind: CompatModKind.viafabric,
        slug: 'viafabric',
        label: 'ViaFabric',
        versionNumber: via.versionNumber,
        files: via.files,
      );
    }
    return null;
  }

  static bool _hasChosenMod(Directory modsDir, CompatModKind kind) {
    if (!modsDir.existsSync()) return false;
    for (final f in modsDir.listSync().whereType<File>()) {
      final name = p.basename(f.path).toLowerCase();
      if (!name.endsWith('.jar')) continue;
      switch (kind) {
        case CompatModKind.viafabricplus:
          if (_isViaFabricPlus(name)) return true;
        case CompatModKind.viafabric:
          if (_isViaFabricFamily(name)) return true;
      }
    }
    return false;
  }

  static bool _hasForeignCompatMods(Directory modsDir, CompatModKind keep) {
    if (!modsDir.existsSync()) return false;
    for (final f in modsDir.listSync().whereType<File>()) {
      final name = p.basename(f.path).toLowerCase();
      if (!name.endsWith('.jar')) continue;
      if (_isForeignCompatJar(name, keep)) return true;
    }
    return false;
  }

  static void _removeForeignCompatMods(Directory modsDir, CompatModKind keep) {
    if (!modsDir.existsSync()) return;
    for (final f in modsDir.listSync().whereType<File>()) {
      final name = p.basename(f.path).toLowerCase();
      if (!name.endsWith('.jar')) continue;
      if (!_isForeignCompatJar(name, keep)) continue;
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// 与本次选定互斥或无关的旧兼容联机 jar（不含「本次应保留」的那一族）。
  static bool _isForeignCompatJar(String name, CompatModKind keep) {
    if (_isLegacyViaDep(name)) return true;
    return switch (keep) {
      CompatModKind.viafabricplus => _isViaFabricFamily(name),
      CompatModKind.viafabric => _isViaFabricPlus(name),
    };
  }

  static bool _isViaFabricPlus(String name) =>
      name.contains('viafabricplus');

  static bool _isViaFabricFamily(String name) {
    if (_isViaFabricPlus(name)) return false;
    return name.contains('viafabric');
  }

  static bool _isLegacyViaDep(String name) =>
      name.contains('cotton-client-commands') ||
      name.contains('cottonclientcommands');

  /// 兼容进服身份：无令牌时用离线 UUID；有正版令牌仍可用（服需 online-mode=false）。
  static LaunchProfile resolveCompatProfile({
    required String username,
    required String uuid,
    required String accessToken,
    bool forceOfflineIdentity = false,
  }) {
    final name = AuthManager.sanitizeMinecraftUsername(username);
    final offline = forceOfflineIdentity ||
        uuid.isEmpty ||
        accessToken.isEmpty ||
        accessToken == '0';
    if (offline) {
      return LaunchProfile(
        username: name,
        uuid: AuthManager.offlineUuidFor(name),
        accessToken: accessToken.isEmpty ? '0' : accessToken,
        userType: 'legacy',
      );
    }
    return LaunchProfile(
      username: username.isEmpty ? name : username,
      uuid: uuid,
      accessToken: accessToken,
      userType: 'msa',
    );
  }

  /// 解析 host:port。
  static ({String host, int port})? parseAddress(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final colon = s.lastIndexOf(':');
    if (colon <= 0 || colon >= s.length - 1) {
      return (host: s, port: 25565);
    }
    final host = s.substring(0, colon).trim();
    final port = int.tryParse(s.substring(colon + 1).trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    return (host: host, port: port);
  }

  static String hostHint(String gameType) {
    const tip = '提示：兼容联机请只用于私人好友房间，并遵守游戏服务条款。';
    if (gameType == 'bedrock') {
      return '$tip 基岩：已尽量关闭专用服正版校验；跨版本能力有限，仍建议大家版本一致。';
    }
    return '$tip Java：专用服会关闭正版校验；Fabric 可尝试安装跨版本模组。';
  }
}

enum CompatModKind { viafabricplus, viafabric }

class _CompatDownloadPlan {
  final CompatModKind kind;
  final String slug;
  final String label;
  final String versionNumber;
  final List<ModrinthFileRef> files;

  const _CompatDownloadPlan({
    required this.kind,
    required this.slug,
    required this.label,
    required this.versionNumber,
    required this.files,
  });
}
