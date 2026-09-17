/// 将 Mojang / Fabric / Modrinth 官方 URL 映射为可选镜像候选（官方始终保留为回落）。
/// 改写规则对齐 HMCL [BMCLAPIDownloadProvider]：
/// - 本体：BMCLAPI replacement
/// - 模组：MCIM fallbackReplacement（前端直连，不经自家后端代理）
class DownloadSources {
  static const userAgent = 'xingqiong-launcher/0.1.0';

  /// 内置镜像（去掉已失效的 mcbbs；优先国内可达源）。
  static const List<String> defaultMirrorBases = [
    'https://bmclapi2.bangbang93.com',
    'https://bmclapi.bangbang93.com',
  ];

  /// HMCL fallbackReplacement：Modrinth / CurseForge → MCIM（国内直连）。
  static const List<(String from, String to)> mcimReplacements = [
    ('https://api.modrinth.com', 'https://mod.mcimirror.top/modrinth'),
    ('https://cdn.modrinth.com', 'https://mod.mcimirror.top'),
    ('https://api.curseforge.com', 'https://mod.mcimirror.top/curseforge'),
    ('https://edge.forgecdn.net', 'https://mod.mcimirror.top'),
  ];

  /// 版本清单候选（镜像优先时可再排序）。
  static List<Uri> versionManifestCandidates({
    List<String> mirrorBases = defaultMirrorBases,
  }) {
    final out = <Uri>[];
    final seen = <String>{};
    void add(String s) {
      if (seen.add(s)) out.add(Uri.parse(s));
    }

    for (final base in mirrorBases) {
      final b = base.replaceAll(RegExp(r'/$'), '');
      add('$b/mc/game/version_manifest_v2.json');
      add('$b/mc/game/version_manifest.json');
    }
    add('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json');
    add('https://launchermeta.mojang.com/mc/game/version_manifest_v2.json');
    return out;
  }

  /// 返回镜像改写 URL + MCIM + 官方回落（官方在最后）。
  static List<Uri> candidates(
    Uri official, {
    List<String> mirrorBases = defaultMirrorBases,
    String? versionId,
  }) {
    final out = <Uri>[];
    final seen = <String>{};

    void add(Uri u) {
      final s = u.toString();
      if (seen.add(s)) out.add(u);
    }

    for (final base in mirrorBases) {
      for (final mirrored in rewriteAll(official, base, versionId: versionId)) {
        add(mirrored);
      }
    }
    for (final mirrored in mcimRewriteAll(official)) {
      add(mirrored);
    }
    add(official);
    return out;
  }

  /// 客户端 jar 优先走 BMCLAPI `/version/{id}/client`（会 302 到正确对象路径）。
  static List<Uri> rewriteAll(
    Uri official,
    String mirrorBase, {
    String? versionId,
  }) {
    final host = official.host.toLowerCase();
    final path = official.path;
    final base = mirrorBase.replaceAll(RegExp(r'/$'), '');
    final out = <Uri>[];

    final isClientJar = path.toLowerCase().endsWith('/client.jar') ||
        path.toLowerCase().endsWith('client.jar');
    if (versionId != null &&
        versionId.isNotEmpty &&
        isClientJar &&
        (host.contains('mojang') || host.contains('minecraft'))) {
      out.add(Uri.parse('$base/version/$versionId/client'));
    }

    final single = rewrite(official, base);
    if (single != null) out.add(single);
    return out;
  }

  /// Modrinth / CurseForge → MCIM（与 HMCL fallbackReplacement 一致）。
  static List<Uri> mcimRewriteAll(Uri official) {
    final full = official.toString();
    final out = <Uri>[];
    for (final (from, to) in mcimReplacements) {
      if (full.startsWith(from)) {
        out.add(Uri.parse('$to${full.substring(from.length)}'));
      }
    }
    return out;
  }

  /// 按 HMCL 风格前缀替换；无法改写时返回 null。
  static Uri? rewrite(Uri official, String mirrorBase) {
    final host = official.host.toLowerCase();
    final path = official.path;
    final base = mirrorBase.replaceAll(RegExp(r'/$'), '');
    final full = official.toString();

    // 前缀表（与 HMCL BMCLAPIDownloadProvider.replacement 对齐）
    const prefixes = <String>[
      'https://bmclapi2.bangbang93.com',
      'https://launchermeta.mojang.com',
      'https://piston-meta.mojang.com',
      'https://piston-data.mojang.com',
      'https://launcher.mojang.com',
    ];
    for (final p in prefixes) {
      if (full.startsWith(p)) {
        return Uri.parse('$base${full.substring(p.length)}');
      }
    }

    if (host == 'resources.download.minecraft.net') {
      return Uri.parse('$base/assets$path');
    }
    if (host == 'libraries.minecraft.net') {
      return Uri.parse('$base/libraries$path');
    }
    if (host == 'meta.fabricmc.net') {
      return Uri.parse('$base/fabric-meta$path');
    }
    if (host == 'maven.fabricmc.net') {
      return Uri.parse('$base/maven$path');
    }
    // Forge / NeoForge / LiteLoader → BMCL maven（HMCL）
    if (full.startsWith('https://files.minecraftforge.net/maven') ||
        full.startsWith('http://files.minecraftforge.net/maven') ||
        full.startsWith('https://maven.minecraftforge.net')) {
      final idx = full.indexOf('/maven');
      final rest = idx >= 0 ? full.substring(idx + '/maven'.length) : path;
      return Uri.parse('$base/maven$rest');
    }
    if (full.startsWith('https://maven.neoforged.net/releases/')) {
      return Uri.parse(
        '$base/maven/${full.substring('https://maven.neoforged.net/releases/'.length)}',
      );
    }
    if (host == 'authlib-injector.yushi.moe') {
      return Uri.parse('$base/mirrors/authlib-injector$path');
    }
    if (host.endsWith('minecraft.net') || host.endsWith('mojang.com')) {
      return Uri.parse('$base$path');
    }
    return null;
  }
}
