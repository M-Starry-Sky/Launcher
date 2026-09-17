import 'dart:io';

import '../config/app_config.dart';
import '../perf/gc_presets.dart';
import '../perf/jvm_args_builder.dart';
import '../perf/perf_config.dart';
import 'version_installer.dart';

/// 游戏启动器：组装 JVM 参数与游戏参数并拉起进程。
/// 游戏本体与库均来自官方源，本类只负责构建命令行。
class GameLauncher {
  final AppConfig config;
  final PerfConfig? perf;
  final void Function(String line)? onLog;

  GameLauncher({required this.config, this.perf, this.onLog});

  Future<Process> launch({
    required String javaPath,
    required Directory gameDir,
    required ResolvedVersion version,
    required LaunchProfile profile,
    String? serverHost,
    int? serverPort,
    /// 1.20+ 快速进入单人存档（文件夹名）
    String? singleplayerWorld,
    int? javaMajor,
    String? instanceJvmArgs,
    /// 资源索引根；实例隔离时指向共享本体 `assets/`，勿与 gameDir 混用。
    Directory? assetsDir,
    void Function(String line)? onLog,
  }) async {
    final log = onLog ?? this.onLog;
    final nativesDir = version.nativesDir.isNotEmpty
        ? version.nativesDir
        : '${gameDir.path}/versions/${version.id}/natives-${_osName()}';
    log?.call('natives: $nativesDir');
    log?.call('账号: ${profile.username} · ${profile.userType}');
    if (profile.isOffline &&
        !RegExp(r'^[A-Za-z0-9_]{3,16}$').hasMatch(profile.username)) {
      log?.call('警告：玩家名含非法字符，进单人世界会被踢出');
    }

    final heap = perf?.heapMb ?? config.maxMemoryMb;
    final gc = perf?.gcPreset ?? GcPreset.balanced;
    final major = javaMajor ?? 17;
    final extra = [
      if (instanceJvmArgs != null && instanceJvmArgs.trim().isNotEmpty)
        instanceJvmArgs.trim(),
      if (perf != null && perf!.customJvmArgs.trim().isNotEmpty)
        perf!.customJvmArgs.trim(),
    ].join(' ');

    final jvmArgs = <String>[
      ...JvmArgsBuilder(
        heapMb: heap,
        gcPreset: gc,
        javaMajor: major,
        largeModpack: perf?.largeModpack ?? false,
        aggressiveFps: perf?.fps.aggressiveJvmFps ?? true,
        extraArgs: extra.isEmpty ? null : extra,
        hardware: perf?.hardware,
      ).build(),
      '-Djava.library.path=$nativesDir',
      '-Djna.tmpdir=$nativesDir',
      '-Dorg.lwjgl.system.SharedLibraryExtractPath=$nativesDir',
      '-Dio.netty.native.workdir=$nativesDir',
      '-Dminecraft.launcher.brand=xingqiong',
      '-Dminecraft.launcher.version=0.1.0',
      // 避免认证请求在坏网上挂死（表现为进程在、窗口永不出现）
      '-Dsun.net.client.defaultConnectTimeout=2000',
      '-Dsun.net.client.defaultReadTimeout=2000',
      '-Djava.net.preferIPv4Stack=true',
    ];

    if (profile.isOffline) {
      log?.call('离线模式：缩短认证超时，避免卡在出窗口前');
    }

    final classpath = version.classpath.join(Platform.isWindows ? ';' : ':');
    final gameArgs = _pruneEmptyFlagArgs(
      _substituteGameArgs(
        version.gameArgs,
        gameDir,
        version,
        profile,
        assetsDir: assetsDir,
      ),
    );
    final join = _joinTarget(
      versionId: version.id,
      serverHost: serverHost,
      serverPort: serverPort,
      singleplayerWorld: singleplayerWorld,
    );
    if (join != null) {
      gameArgs.addAll(join);
      log?.call('自动进入: ${join.join(' ')}');
    } else if (singleplayerWorld != null &&
        singleplayerWorld.trim().isNotEmpty &&
        !_supportsQuickPlay(version.id)) {
      log?.call(
        '当前版本 ${version.id} 不支持快速进入存档（需 1.20+），将进入主菜单',
      );
    }

    final mainClass = version.mainClass;
    if (mainClass == null || mainClass.isEmpty) {
      throw StateError('版本 ${version.id} 缺少 mainClass');
    }

    log?.call(
      'classpath ${version.classpath.length} 项 · ${classpath.length} 字符',
    );

    // Windows 命令行长度上限：仅把 JVM / -cp / 长 classpath 放进 @argfile。
    // 主类与游戏参数（含中文存档名、空字符串）必须走进程参数列表——
    // argfile 会把空行当空白合并，导致 --clientId/--xuid 错位，
    // 进而 --quickPlaySingleplayer 吃错值，出现「无法找到具有标识的世界」。
    final useArgFile = Platform.isWindows && classpath.length >= 800;
    late final Process process;
    if (useArgFile) {
      final argFile =
          File('${gameDir.path}${Platform.pathSeparator}.xingqiong_launch.args');
      final jvmBlock = <String>[...jvmArgs, '-cp', classpath];
      final body = StringBuffer();
      for (final a in jvmBlock) {
        body.writeln(_argFileEscape(a));
      }
      await argFile.writeAsString(body.toString(), flush: true);
      final tail = <String>[mainClass, ...gameArgs];
      log?.call(
        '使用参数文件(仅JVM/classpath): ${argFile.path} · 游戏参数 ${tail.length} 项',
      );
      process = await Process.start(
        javaPath,
        ['@${argFile.path}', ...tail],
        workingDirectory: gameDir.path,
        mode: ProcessStartMode.normal,
      );
    } else {
      final mainArgs = <String>[
        ...jvmArgs,
        '-cp',
        classpath,
        mainClass,
        ...gameArgs,
      ];
      log?.call(
        '启动: $javaPath · classpath ${version.classpath.length} · 参数 ${mainArgs.length}',
      );
      process = await Process.start(
        javaPath,
        mainArgs,
        workingDirectory: gameDir.path,
        mode: ProcessStartMode.normal,
      );
    }
    // 必须排空 stdout/stderr：不读会导致管道缓冲填满，游戏卡在出窗口前。
    // 只丢弃字节，不做 UTF-8 解码，避免 CPU 被日志打满。
    process.stdout.listen((_) {}, onError: (_) {}, cancelOnError: true);
    process.stderr.listen((_) {}, onError: (_) {}, cancelOnError: true);
    return process;
  }

  /// 1.20+ 用 quickPlay；更早版本用 --server/--port。
  static List<String>? _joinTarget({
    required String versionId,
    String? serverHost,
    int? serverPort,
    String? singleplayerWorld,
  }) {
    // 联机优先于单人存档，避免两者同时勾选时进错目标。
    final host = serverHost?.trim();
    if (host != null && host.isNotEmpty) {
      final port = serverPort ?? 25565;
      if (_supportsQuickPlay(versionId)) {
        return ['--quickPlayMultiplayer', '$host:$port'];
      }
      return ['--server', host, '--port', '$port'];
    }
    final world = singleplayerWorld?.trim();
    if (world != null && world.isNotEmpty) {
      if (_supportsQuickPlay(versionId)) {
        return ['--quickPlaySingleplayer', world];
      }
      return null;
    }
    return null;
  }

  /// 从 version id（含 fabric-loader-*-1.20.1）判断是否支持 Quick Play。
  static bool _supportsQuickPlay(String versionId) {
    final matches = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').allMatches(versionId);
    if (matches.isEmpty) return true;
    final last = matches.last;
    final major = int.parse(last.group(1)!);
    final minor = int.parse(last.group(2)!);
    if (major > 1) return true;
    if (major == 1 && minor >= 20) return true;
    return false;
  }

  /// Java 参数文件转义（见 java 手册 Argument Files）。
  /// Windows 路径含 `\` 时不要整段加引号，否则易把 `-cp` 多段路径解析搞乱；
  /// 仅空白 / 引号 / 控制字符才需要引号。
  static String _argFileEscape(String arg) {
    final needQuote = arg.contains(' ') ||
        arg.contains('"') ||
        arg.contains("'") ||
        arg.contains('\t') ||
        arg.contains('\n') ||
        arg.contains('\r') ||
        arg.contains('#');
    if (!needQuote) return arg;
    final escaped = arg
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }

  /// 替换官方版本 JSON 中的 ${...} 占位符。
  List<String> _substituteGameArgs(
      List<String> args, Directory gameDir, ResolvedVersion version,
      LaunchProfile profile, {Directory? assetsDir}) {
    // 正斜杠路径在 Windows / Java 下同样合法，且写入 @argfile 时更安全。
    final gameDirPath = gameDir.path.replaceAll('\\', '/');
    final assetsRoot = (assetsDir ?? Directory('${gameDir.path}/assets'))
        .path
        .replaceAll('\\', '/');
    final values = <String, String>{
      'auth_player_name': profile.username,
      'version_name': version.id,
      'game_directory': gameDirPath,
      'assets_root': assetsRoot,
      'assets_index_name': version.assetsIndexName,
      'auth_uuid': profile.uuid,
      'auth_access_token': profile.accessToken,
      'auth_session': 'token:${profile.accessToken}:${profile.uuid}',
      'user_type': profile.userType,
      'user_properties': '{}',
      'clientid': '',
      'auth_xuid': '',
      'version_type': 'xingqiong',
      'resolution_width': '854',
      'resolution_height': '480',
    };
    return args.map((arg) {
      return arg.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (m) {
        return values[m.group(1)] ?? m.group(0)!;
      });
    }).toList();
  }

  /// 去掉「开关 + 空值」对。空值写进 @argfile 会变成空行，JVM 合并空白后参数错位。
  static List<String> _pruneEmptyFlagArgs(List<String> args) {
    const optionalFlags = {
      '--clientId',
      '--clientid',
      '--xuid',
      '--width',
      '--height',
    };
    final out = <String>[];
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (optionalFlags.contains(a) &&
          i + 1 < args.length &&
          args[i + 1].isEmpty) {
        i++;
        continue;
      }
      out.add(a);
    }
    return out;
  }


  String _osName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'osx';
    return 'linux';
  }
}

/// 启动所用玩家档案（来自认证流程的游戏会话）。
class LaunchProfile {
  final String username;
  final String uuid;
  final String accessToken;
  /// mojang / msa / legacy；离线须用 legacy，否则 1.16+ 常秒退。
  final String userType;

  const LaunchProfile({
    required this.username,
    required this.uuid,
    required this.accessToken,
    this.userType = 'msa',
  });

  bool get isOffline =>
      userType == 'legacy' ||
      accessToken.isEmpty ||
      accessToken == '0';
}
