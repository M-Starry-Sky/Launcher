import 'dart:convert';
import 'dart:io';

/// 本机基岩版（微软商店 UWP）安装探测结果。
class BedrockInstallInfo {
  final String packageFamilyName;
  final String packageRoot;
  final String comMojangRoot;
  final bool preview;
  final String? displayVersion;

  const BedrockInstallInfo({
    required this.packageFamilyName,
    required this.packageRoot,
    required this.comMojangRoot,
    required this.preview,
    this.displayVersion,
  });

  Directory get optionsDir =>
      Directory('$comMojangRoot${Platform.pathSeparator}minecraftpe');

  File get optionsFile =>
      File('${optionsDir.path}${Platform.pathSeparator}options.txt');

  Directory get resourcePacksDir =>
      Directory('$comMojangRoot${Platform.pathSeparator}resource_packs');

  Directory get behaviorPacksDir =>
      Directory('$comMojangRoot${Platform.pathSeparator}behavior_packs');

  Directory get developmentResourcePacksDir => Directory(
      '$comMojangRoot${Platform.pathSeparator}development_resource_packs');

  Directory get developmentBehaviorPacksDir => Directory(
      '$comMojangRoot${Platform.pathSeparator}development_behavior_packs');

  String get label => preview ? 'Minecraft Preview' : 'Minecraft 基岩版';
}

/// 检测 Windows 本机已安装的基岩版（不下载、不重分发版本体）。
class BedrockInstall {
  static const _releaseFamily = 'Microsoft.MinecraftUWP_8wekyb3d8bbwe';
  static const _previewFamily = 'Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe';

  /// 微软商店 Minecraft 产品页（启动器不托管基岩版本体）。
  static const storeProductId = '9NBLGGH2JHXJ';
  static const storeDeepLink =
      'ms-windows-store://pdp/?ProductId=$storeProductId';
  static const storeWebUrl =
      'https://www.microsoft.com/store/productId/$storeProductId';

  /// 优先正式版，其次 Preview；再模糊扫描 Packages / AppxPackage。
  /// Android：检测已安装的 `com.mojang.minecraftpe`。
  static Future<BedrockInstallInfo?> detect() async {
    if (Platform.isAndroid) return _detectAndroid();
    if (!Platform.isWindows) return null;
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) return null;

    final packages = Directory('$localAppData${Platform.pathSeparator}Packages');
    if (!packages.existsSync()) {
      return _detectViaAppx(localAppData);
    }

    for (final family in [_releaseFamily, _previewFamily]) {
      final info = await _fromPackageFamily(packages, family);
      if (info != null) return info;
    }

    // 模糊：任意 Microsoft.Minecraft* 包族（含地区/渠道变体）
    try {
      final dirs = packages
          .listSync(followLinks: false)
          .whereType<Directory>()
          .toList();
      Directory? release;
      Directory? preview;
      for (final d in dirs) {
        final base =
            d.path.split(RegExp(r'[\\/]')).lastWhere((s) => s.isNotEmpty);
        final lower = base.toLowerCase();
        if (!lower.startsWith('microsoft.minecraft')) continue;
        if (lower.contains('windowsbeta') || lower.contains('preview')) {
          preview ??= d;
        } else if (lower.contains('minecraftuwp')) {
          release = d;
        } else {
          release ??= d;
        }
      }
      for (final d in [release, preview]) {
        if (d == null) continue;
        final family =
            d.path.split(RegExp(r'[\\/]')).lastWhere((s) => s.isNotEmpty);
        final info = await _fromPackageRoot(d, family);
        if (info != null) return info;
      }
    } catch (_) {}

    return _detectViaAppx(localAppData);
  }

  static Future<BedrockInstallInfo?> _fromPackageFamily(
    Directory packages,
    String family,
  ) async {
    final root = Directory('${packages.path}${Platform.pathSeparator}$family');
    if (!root.existsSync()) return null;
    return _fromPackageRoot(root, family);
  }

  static Future<BedrockInstallInfo?> _fromPackageRoot(
    Directory root,
    String family,
  ) async {
    final comMojang = Directory(
      '${root.path}${Platform.pathSeparator}LocalState'
      '${Platform.pathSeparator}games${Platform.pathSeparator}com.mojang',
    );
    final version = await _readAppxVersion(root);
    final preview = family.toLowerCase().contains('windowsbeta') ||
        family.toLowerCase().contains('preview');
    return BedrockInstallInfo(
      packageFamilyName: family,
      packageRoot: root.path,
      comMojangRoot: comMojang.path,
      preview: preview,
      displayVersion: version,
    );
  }

  /// 用 Get-AppxPackage 补漏（包已装但 Packages 目录名异常时）。
  static Future<BedrockInstallInfo?> _detectViaAppx(String localAppData) async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r"Get-AppxPackage -Name '*Minecraft*' | Select-Object Name,PackageFamilyName | ConvertTo-Json -Compress",
        ],
        runInShell: false,
      ).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return null;
      final raw = (result.stdout as String? ?? '').trim();
      if (raw.isEmpty || raw == 'null') return null;

      final decoded = jsonDecode(raw);
      final list = decoded is List
          ? decoded
          : decoded is Map
              ? [decoded]
              : const <dynamic>[];

      String? releaseFamily;
      String? previewFamily;
      for (final item in list) {
        if (item is! Map) continue;
        final family = '${item['PackageFamilyName'] ?? ''}';
        final name = '${item['Name'] ?? ''}'.toLowerCase();
        if (family.isEmpty) continue;
        if (name.contains('windowsbeta') || family.toLowerCase().contains('windowsbeta')) {
          previewFamily ??= family;
        } else if (name.contains('minecraftuwp') ||
            family.toLowerCase().contains('minecraftuwp')) {
          releaseFamily = family;
        } else if (name.contains('minecraft')) {
          releaseFamily ??= family;
        }
      }

      final packages =
          Directory('$localAppData${Platform.pathSeparator}Packages');
      for (final family in [releaseFamily, previewFamily]) {
        if (family == null) continue;
        if (packages.existsSync()) {
          final info = await _fromPackageFamily(packages, family);
          if (info != null) return info;
        }
        // 仅有 Appx 记录时仍返回可用 family，便于协议/AUMID 启动
        final preview = family.toLowerCase().contains('windowsbeta');
        final syntheticRoot = packages.existsSync()
            ? '${packages.path}${Platform.pathSeparator}$family'
            : family;
        return BedrockInstallInfo(
          packageFamilyName: family,
          packageRoot: syntheticRoot,
          comMojangRoot:
              '$syntheticRoot${Platform.pathSeparator}LocalState${Platform.pathSeparator}games${Platform.pathSeparator}com.mojang',
          preview: preview,
          displayVersion: null,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _readAppxVersion(Directory packageRoot) async {
    try {
      final manifest = File(
          '${packageRoot.path}${Platform.pathSeparator}AppxManifest.xml');
      if (!manifest.existsSync()) return null;
      final text = await manifest.readAsString();
      final match = RegExp(r'Version="([^"]+)"').firstMatch(text);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// 打开微软商店 Minecraft 产品页。
  static Future<bool> openMicrosoftStore() async {
    if (!Platform.isWindows) return false;
    try {
      final deep = await Process.run(
        'cmd',
        ['/c', 'start', '', storeDeepLink],
        runInShell: true,
      );
      if (deep.exitCode == 0) return true;
    } catch (_) {}
    try {
      final web = await Process.run(
        'cmd',
        ['/c', 'start', '', storeWebUrl],
        runInShell: true,
      );
      return web.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static const androidPackage = 'com.mojang.minecraftpe';

  static Future<BedrockInstallInfo?> _detectAndroid() async {
    try {
      final r = await Process.run('pm', ['path', androidPackage]);
      final out = '${r.stdout}${r.stderr}';
      if (r.exitCode != 0 || !out.contains('package:')) return null;

      // 常见 com.mojang 数据目录（按存在优先）
      final candidates = <String>[
        '/storage/emulated/0/games/com.mojang',
        '/sdcard/games/com.mojang',
        '/storage/emulated/0/Android/data/$androidPackage/files/games/com.mojang',
      ];
      var comRoot = candidates.first;
      for (final c in candidates) {
        if (Directory(c).existsSync()) {
          comRoot = c;
          break;
        }
      }
      return BedrockInstallInfo(
        packageFamilyName: androidPackage,
        packageRoot: '',
        comMojangRoot: comRoot,
        preview: false,
        displayVersion: null,
      );
    } catch (_) {
      return null;
    }
  }
}
