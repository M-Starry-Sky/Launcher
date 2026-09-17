import 'dart:io';

import '../perf/bedrock_render_presets.dart';
import 'bedrock_install.dart';

/// 基岩版启动与本地配置写入。
class BedrockLauncher {
  final void Function(String message)? onLog;

  BedrockLauncher({this.onLog});

  void _log(String m) => onLog?.call(m);

  /// 将性能预设合并写入 options.txt（保留未知键）。
  Future<void> applyRenderSettings(
    BedrockInstallInfo install,
    BedrockRenderSettings settings,
  ) async {
    final file = install.optionsFile;
    await file.parent.create(recursive: true);
    final existing = <String, String>{};
    if (file.existsSync()) {
      for (final line in await file.readAsLines()) {
        final raw = line.trimRight();
        if (raw.isEmpty || raw.startsWith('#')) continue;
        final i = raw.indexOf(':');
        if (i <= 0) continue;
        existing[raw.substring(0, i)] = raw.substring(i + 1);
      }
    }
    existing.addAll(settings.toOptionsTxtEntries());
    final buf = StringBuffer();
    for (final e in existing.entries) {
      buf.writeln('${e.key}:${e.value}');
    }
    await file.writeAsString(buf.toString());
    _log('已写入基岩 options.txt（${settings.preset.label}）');
  }

  /// 同步资源包 / 行为包到基岩目录（development_* 便于热加载）。
  Future<void> syncPackFolders({
    required BedrockInstallInfo install,
    Directory? resourcePacksSource,
    Directory? behaviorPacksSource,
  }) async {
    if (resourcePacksSource != null && resourcePacksSource.existsSync()) {
      await Directory(install.comMojangRoot).create(recursive: true);
      await _copyTree(
        resourcePacksSource,
        install.developmentResourcePacksDir,
        label: '资源包',
      );
    }
    if (behaviorPacksSource != null && behaviorPacksSource.existsSync()) {
      await Directory(install.comMojangRoot).create(recursive: true);
      await _copyTree(
        behaviorPacksSource,
        install.developmentBehaviorPacksDir,
        label: '行为包',
      );
    }
  }

  Future<void> _copyTree(
    Directory from,
    Directory to, {
    required String label,
  }) async {
    await to.create(recursive: true);
    var n = 0;
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = entity.path.substring(from.path.length).replaceAll('\\', '/');
      final clean = rel.startsWith('/') ? rel.substring(1) : rel;
      if (clean.isEmpty) continue;
      final dest = File('${to.path}${Platform.pathSeparator}'
          '${clean.replaceAll('/', Platform.pathSeparator)}');
      await dest.parent.create(recursive: true);
      if (!dest.existsSync() || dest.lengthSync() != entity.lengthSync()) {
        await entity.copy(dest.path);
        n++;
      }
    }
    _log('已同步$label $n 个文件 → ${to.path}');
  }

  /// 启动本机已安装的基岩版。
  Future<void> launch(BedrockInstallInfo install) async {
    if (!Platform.isWindows) {
      throw StateError('当前仅支持在 Windows 上启动基岩版');
    }
    _log('正在启动 ${install.label}…');

    // 优先协议；失败再试 AppsFolder AUMID
    final protocolOk = await _tryStartUri(
      install.preview ? 'minecraft-preview:' : 'minecraft:',
    );
    if (protocolOk) {
      _log('${install.label} 已通过协议唤起');
      return;
    }

    final aumid = '${install.packageFamilyName}!App';
    final explorer = await Process.start(
      'explorer.exe',
      ['shell:AppsFolder\\$aumid'],
      mode: ProcessStartMode.detached,
    );
    // explorer 立即返回；无法用 exitCode 判断成败
    _log('${install.label} 已请求系统启动 (shell:$aumid, pid=${explorer.pid})');
  }

  Future<bool> _tryStartUri(String uri) async {
    try {
      final result = await Process.run(
        'cmd',
        ['/c', 'start', '', uri],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
