import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../download/download_sources.dart';
import '../network/secure_endpoint.dart';

/// 客户端本地设置（shared_preferences）。
/// 授权凭据：默认拉远程配置；设置页开启「使用本地配置」才用本地字段。
class AppConfig extends ChangeNotifier {
  static const String keyBackendBaseUrl = 'backend_base_url';

  // 本地备用 OAuth（仅 useLocalAuthOverride=true 时生效）
  static const String keyMsClientId = 'ms_client_id';
  static const String keyElybyClientId = 'elyby_client_id';
  static const String keyElybyClientSecret = 'elyby_client_secret';
  static const String keyElybyRedirectPort = 'elyby_redirect_port';

  // 后端下发缓存（始终由 applyRemoteAuth 写入）
  static const String keyRemoteMsClientId = 'remote_ms_client_id';
  static const String keyRemoteElybyClientId = 'remote_elyby_client_id';
  static const String keyRemoteElybyClientSecret = 'remote_elyby_client_secret';
  static const String keyRemoteElybyRedirectPort = 'remote_elyby_redirect_port';

  static const String keyGameDataDir = 'game_data_dir';
  /// 游戏本体下载目录（versions / libraries / assets）；空则用 {dataRoot}/game
  static const String keyGameBodyDir = 'game_body_dir';
  static const String keyJavaPath = 'java_path';
  static const String keyFrpcPath = 'frpc_path';
  static const String keyMaxMemoryMb = 'max_memory_mb';
  static const String keyAcceptedDisclaimer = 'accepted_disclaimer_version';
  /// 已点过「知道了」的启动页通知 ID（逗号分隔）
  static const String keyDismissedHomeNotices = 'home_notice_dismissed_ids';
  static const String keyLocalServerPort = 'local_server_port';
  static const String keyGameProfiles = 'game_profiles';

  /// 设置页：使用本地配置（默认关 = 直接用后端，不显示本地授权字段）
  static const String keyUseLocalAuthOverride = 'settings_use_local_config';
  /// 启动前自动安装缺失版本
  static const String keyLaunchAutoInstall = 'launch_auto_install';
  /// 启动前同步实例模组到游戏目录
  static const String keyLaunchSyncMods = 'launch_sync_mods';
  /// 详细启动日志
  static const String keyLaunchVerboseLog = 'launch_verbose_log';
  /// 启动后最小化启动器窗口
  static const String keyLaunchMinimizeOnStart = 'launch_minimize_on_start';
  /// 游戏运行时显示置顶悬浮窗（帧率 / 服务器 / 世界）
  static const String keyGameHudOverlay = 'game_hud_overlay';
  /// 悬浮窗录像保存目录（空=系统「视频」或用户目录下 Xingqiong/Recordings）
  static const String keyRecordSaveDir = 'record_save_dir';
  /// FFmpeg 可执行文件路径（空则 PATH / 常见安装位）
  static const String keyFfmpegPath = 'ffmpeg_path';
  /// 录制：捕获系统声音（默认开）
  static const String keyRecordSystemAudio = 'record_system_audio';
  /// 录制：捕获麦克风（默认关）
  static const String keyRecordMic = 'record_mic';
  /// 录制帧率
  static const String keyRecordFps = 'record_fps';
  /// 联机：上次填写的加入地址 / 房间码
  static const String keyLastRoomJoin = 'room_last_join_code';
  /// 联机隧道：一键开房仅启动本地打洞（平台不提供中继流量）。
  static const String keyFrpServerAddr = 'frp_server_addr';
  static const String keyFrpServerPort = 'frp_server_port';
  static const String keyFrpToken = 'frp_token';
  /// 0 表示未配置本地远程端口（离线账号必须自行填写）
  static const String keyFrpRemotePort = 'frp_remote_port';
  /// OpenFRP / frp：user 字段
  static const String keyFrpUser = 'frp_user';
  static const String keyFrpTlsEnable = 'frp_tls_enable';
  static const String keyFrpTlsServerName = 'frp_tls_server_name';
  static const String keyFrpUseEncryption = 'frp_use_encryption';
  static const String keyFrpUseCompression = 'frp_use_compression';
  static const String keyFrpProtocol = 'frp_protocol';
  /// 开房连接模式：lan | frp | platform | public
  static const String keyRoomConnectMode = 'room_connect_mode';
  /// 公网映射模式下的公网主机名 / IP
  static const String keyRoomPublicHost = 'room_public_host';
  /// 联机：兼容模式（关正版校验 / 跨版本辅助）。默认关，启用前向玩家展示须知。
  static const String keyRoomCompatMode = 'room_compat_mode';
  /// 玩家已确认「兼容联机」使用须知
  static const String keyRoomCompatWhitelistAck = 'room_compat_whitelist_ack_v1';

  /// 主题：system | light | dark
  static const String keyThemeMode = 'ui_theme_mode';
  /// 自定义背景图本地绝对路径（空=无）
  static const String keyBackgroundImagePath = 'ui_background_image_path';
  /// 液态玻璃：liquid | frosted | clear | off
  static const String keyGlassMode = 'ui_glass_mode';
  /// Windows：曾把默认液态玻璃迁到纯净，避免 BackdropFilter 占满 CPU
  static const String keyGlassWinCpuMigrated = 'ui_glass_win_cpu_migrated_v1';

  /// 下载加速总开关
  static const String keyDownloadAccel = 'download_accel_enabled';
  /// 局域网节点互传
  static const String keyDownloadPeer = 'download_peer_enabled';
  /// 镜像基址，逗号分隔
  static const String keyDownloadMirrors = 'download_mirror_bases';

  late SharedPreferences _prefs;
  bool loaded = false;

  /// 内置远端主机（密封载荷；界面不展示；可用 --dart-define=BACKEND_BASE_URL= 覆盖）。
  static String get embeddedBackendBaseUrl => SecureEndpoint.backendBaseUrl;

  /// 始终使用内置地址，不读设置、不在界面暴露。
  String get backendBaseUrl => embeddedBackendBaseUrl;

  String get themeModeRaw => _prefs.getString(keyThemeMode) ?? 'system';

  String get backgroundImagePath =>
      _prefs.getString(keyBackgroundImagePath) ?? '';

  /// 液态玻璃档位，默认 liquid。
  /// 液态玻璃默认值：Windows 桌面嵌套 BackdropFilter 极易占满 CPU，默认纯净。
  String get glassModeRaw =>
      _prefs.getString(keyGlassMode) ??
      (defaultTargetPlatform == TargetPlatform.windows ? 'off' : 'liquid');

  bool get downloadAccelEnabled =>
      _prefs.getBool(keyDownloadAccel) ?? true;

  /// 局域网互传：桌面默认开；手机默认关（无桌面同网段场景，且易触发权限问题）。
  bool get downloadPeerEnabled {
    final stored = _prefs.getBool(keyDownloadPeer);
    if (stored != null) return stored;
    return defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS;
  }

  /// 镜像根 URL 列表；空则用内置 BMCLAPI（手机/PC 对齐 HMCL 第三方源）。
  List<String> get downloadMirrorBases {
    final raw = _prefs.getString(keyDownloadMirrors) ?? '';
    final list = raw
        .split(RegExp(r'[,;\s]+'))
        .map((e) => e.trim())
        .where((e) => e.startsWith('http'))
        .toList();
    if (list.isEmpty) {
      return List<String>.from(DownloadSources.defaultMirrorBases);
    }
    return list;
  }

  String get downloadMirrorBasesRaw =>
      _prefs.getString(keyDownloadMirrors) ?? '';

  /// 是否使用本地配置（设置页开关）。关：隐藏本地字段，一律读后端缓存。
  bool get useLocalConfig =>
      _prefs.getBool(keyUseLocalAuthOverride) ?? false;

  @Deprecated('Use useLocalConfig')
  bool get useLocalAuthOverride => useLocalConfig;

  bool get launchAutoInstall => _prefs.getBool(keyLaunchAutoInstall) ?? true;
  bool get launchSyncMods => _prefs.getBool(keyLaunchSyncMods) ?? true;
  bool get launchVerboseLog => _prefs.getBool(keyLaunchVerboseLog) ?? true;
  bool get launchMinimizeOnStart =>
      _prefs.getBool(keyLaunchMinimizeOnStart) ?? true;
  bool get gameHudOverlay => _prefs.getBool(keyGameHudOverlay) ?? true;
  String get recordSaveDir => _prefs.getString(keyRecordSaveDir) ?? '';
  String get ffmpegPath => _prefs.getString(keyFfmpegPath) ?? '';
  bool get recordSystemAudio =>
      _prefs.getBool(keyRecordSystemAudio) ?? true;
  bool get recordMic => _prefs.getBool(keyRecordMic) ?? false;
  int get recordFps {
    final v = _prefs.getInt(keyRecordFps) ?? 30;
    if (v < 15) return 15;
    if (v > 60) return 60;
    return v;
  }
  String get lastRoomJoin => _prefs.getString(keyLastRoomJoin) ?? '';

  String get remoteMsClientId =>
      _prefs.getString(keyRemoteMsClientId) ?? '';
  String get remoteElybyClientId =>
      _prefs.getString(keyRemoteElybyClientId) ?? '';
  String get remoteElybyClientSecret =>
      _prefs.getString(keyRemoteElybyClientSecret) ?? '';
  int get remoteElybyRedirectPort =>
      _prefs.getInt(keyRemoteElybyRedirectPort) ?? 7788;

  String get localMsClientId => _prefs.getString(keyMsClientId) ?? '';
  String get localElybyClientId => _prefs.getString(keyElybyClientId) ?? '';
  String get localElybyClientSecret =>
      _prefs.getString(keyElybyClientSecret) ?? '';
  int get localElybyRedirectPort =>
      _prefs.getInt(keyElybyRedirectPort) ?? 7788;

  /// 生效值：关闭本地配置时只读后端；开启本地时优先本地，本地为空则回退后端。
  String get msClientId {
    if (useLocalConfig) {
      final local = localMsClientId.trim();
      if (local.isNotEmpty) return local;
    }
    return remoteMsClientId.trim();
  }

  String get elybyClientId {
    if (useLocalConfig) {
      final local = localElybyClientId.trim();
      if (local.isNotEmpty) return local;
    }
    return remoteElybyClientId.trim();
  }

  String get elybyClientSecret {
    if (useLocalConfig) {
      final local = localElybyClientSecret.trim();
      if (local.isNotEmpty) return local;
    }
    return remoteElybyClientSecret.trim();
  }

  int get elybyRedirectPort =>
      useLocalConfig ? localElybyRedirectPort : remoteElybyRedirectPort;

  String get authSourceLabel => useLocalConfig ? '本地配置' : '后端配置';

  String get gameDataDir => _prefs.getString(keyGameDataDir) ?? '';

  /// 游戏本体目录（版本/库/资产）。空表示使用数据根下的 game/。
  String get gameBodyDir => _prefs.getString(keyGameBodyDir) ?? '';

  String get javaPath => _prefs.getString(keyJavaPath) ?? 'java';
  String get frpcPath => _prefs.getString(keyFrpcPath) ?? '';
  String get frpServerAddr => _prefs.getString(keyFrpServerAddr) ?? '';
  int get frpServerPort => _prefs.getInt(keyFrpServerPort) ?? 7000;
  String get frpToken => _prefs.getString(keyFrpToken) ?? '';
  int get frpRemotePort => _prefs.getInt(keyFrpRemotePort) ?? 0;
  String get frpUser => _prefs.getString(keyFrpUser) ?? '';
  bool get frpTlsEnable => _prefs.getBool(keyFrpTlsEnable) ?? false;
  String get frpTlsServerName => _prefs.getString(keyFrpTlsServerName) ?? '';
  bool get frpUseEncryption => _prefs.getBool(keyFrpUseEncryption) ?? false;
  bool get frpUseCompression => _prefs.getBool(keyFrpUseCompression) ?? false;
  String get frpProtocol {
    final v = _prefs.getString(keyFrpProtocol)?.trim() ?? '';
    return v.isEmpty ? 'tcp' : v;
  }

  /// lan | frp | platform | public
  String get roomConnectMode {
    final v = _prefs.getString(keyRoomConnectMode)?.trim() ?? '';
    if (v == 'lan' || v == 'frp' || v == 'platform' || v == 'public') return v;
    return 'frp';
  }

  String get roomPublicHost => _prefs.getString(keyRoomPublicHost) ?? '';

  /// 兼容联机默认关：关闭正版校验属受限能力，须玩家阅读须知后主动开启。
  bool get roomCompatMode => _prefs.getBool(keyRoomCompatMode) ?? false;
  bool get roomCompatWhitelistAck =>
      _prefs.getBool(keyRoomCompatWhitelistAck) ?? false;
  int get maxMemoryMb => _prefs.getInt(keyMaxMemoryMb) ?? 2048;
  String get acceptedDisclaimerVersion =>
      _prefs.getString(keyAcceptedDisclaimer) ?? '';

  Set<String> get dismissedHomeNoticeIds {
    final raw = _prefs.getString(keyDismissedHomeNotices) ?? '';
    if (raw.trim().isEmpty) return {};
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Future<void> dismissHomeNotice(String noticeId) async {
    final id = noticeId.trim();
    if (id.isEmpty) return;
    final next = {...dismissedHomeNoticeIds, id};
    await _prefs.setString(keyDismissedHomeNotices, next.join(','));
    notifyListeners();
  }

  int get localServerPort => _prefs.getInt(keyLocalServerPort) ?? 25565;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    // 旧默认 liquid 在 Windows 上嵌套模糊会打满 CPU；一次性迁到纯净
    if (defaultTargetPlatform == TargetPlatform.windows &&
        !(_prefs.getBool(keyGlassWinCpuMigrated) ?? false)) {
      final cur = _prefs.getString(keyGlassMode);
      if (cur == null || cur == 'liquid') {
        await _prefs.setString(keyGlassMode, 'off');
      }
      await _prefs.setBool(keyGlassWinCpuMigrated, true);
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> set(String key, Object value) async {
    if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is int) {
      await _prefs.setInt(key, value);
    } else if (value is bool) {
      await _prefs.setBool(key, value);
    }
    notifyListeners();
  }

  String getStringOr(String key, String fallback) =>
      _prefs.getString(key) ?? fallback;

  bool getBoolOr(String key, bool fallback) =>
      _prefs.getBool(key) ?? fallback;

  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }

  /// 远程配置下发写入「远程缓存」，不覆盖本地备用字段。
  Future<void> applyRemoteAuth({
    String? msClientId,
    String? elybyClientId,
    String? elybyClientSecret,
    int? elybyRedirectPort,
  }) async {
    var changed = false;
    Future<void> putString(String key, String? remote) async {
      if (remote == null) return;
      if (_prefs.getString(key) == remote) return;
      await _prefs.setString(key, remote);
      changed = true;
    }

    await putString(keyRemoteMsClientId, msClientId ?? '');
    await putString(keyRemoteElybyClientId, elybyClientId ?? '');
    await putString(keyRemoteElybyClientSecret, elybyClientSecret ?? '');
    if (elybyRedirectPort != null &&
        _prefs.getInt(keyRemoteElybyRedirectPort) != elybyRedirectPort) {
      await _prefs.setInt(keyRemoteElybyRedirectPort, elybyRedirectPort);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> setJson(String key, Map<String, dynamic> value) async {
    await _prefs.setString(key, jsonEncode(value));
    notifyListeners();
  }

  Map<String, dynamic> getJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
