import 'dart:io';

/// 模组冲突预检：基于文件名特征，不做「保证不闪退」承诺。
class ModConflictScanner {
  /// 自动消解「弱冲突」：规则明确、可安全删 jar 的互斥项。
  ///
  /// [loaderType] 为 fabric/quilt/forge 时，用于 Iris/Oculus、Sodium/Embeddium 取舍。
  /// 返回已删除的文件名。
  static List<String> autoResolve(
    Iterable<Directory> dirs, {
    String loaderType = '',
  }) {
    final jars = <File>[];
    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        final n = f.uri.pathSegments.last.toLowerCase();
        if (n.endsWith('.jar')) jars.add(f);
      }
    }
    if (jars.isEmpty) return const [];

    final names = jars.map((f) => f.uri.pathSegments.last.toLowerCase()).toList();
    bool any(bool Function(String n) test) => names.any(test);

    final hasPlus = any((n) => n.contains('viafabricplus'));
    final hasSodium = any((n) => n.contains('sodium') && !n.contains('embeddium'));
    final hasIris = any((n) => n.contains('iris') && !n.contains('oculus'));
    final hasOculus = any((n) => n.contains('oculus'));
    final loader = loaderType.toLowerCase();
    final preferIris = loader == 'fabric' || loader == 'quilt' || loader.isEmpty;
    final preferSodium = loader != 'forge' && loader != 'neoforge';

    final ferrite = jars
        .where((f) => f.uri.pathSegments.last.toLowerCase().contains('ferrite'))
        .toList()
      ..sort((a, b) => a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last));

    final removed = <String>[];
    for (final f in jars) {
      final name = f.uri.pathSegments.last;
      final n = name.toLowerCase();
      var drop = false;

      // ViaFabricPlus 优先：删掉全部 ViaFabric / viafabric-mc*
      if (hasPlus && n.contains('viafabric') && !n.contains('viafabricplus')) {
        drop = true;
      }
      // 过时 Cotton Client Commands
      if (n.contains('cotton-client-commands') ||
          n.contains('cottonclientcommands')) {
        drop = true;
      }
      // Sodium 在时去掉 OptiFine
      if (hasSodium && n.contains('optifine')) {
        drop = true;
      }
      // 光影栈在时去掉 OptiFine
      if ((hasIris || hasOculus) && n.contains('optifine')) {
        drop = true;
      }
      // Fabric/Quilt：Iris + Oculus → 留 Iris
      if (preferIris && hasIris && n.contains('oculus')) {
        drop = true;
      }
      // Forge：Iris + Oculus → 留 Oculus
      if (!preferIris && hasOculus && n.contains('iris') && !n.contains('oculus')) {
        drop = true;
      }
      // Fabric：Sodium + Embeddium → 留 Sodium
      if (preferSodium &&
          hasSodium &&
          n.contains('embeddium')) {
        drop = true;
      }
      // FerriteCore 重复：只留排序后第一个
      if (ferrite.length > 1 &&
          n.contains('ferrite') &&
          f.path != ferrite.first.path) {
        drop = true;
      }

      if (!drop) continue;
      try {
        f.deleteSync();
        removed.add(name);
      } catch (_) {}
    }
    return removed;
  }

  /// 扫描多个 mods 目录，按文件名去重后检测冲突。
  static List<ModConflict> scanAll(Iterable<Directory> dirs) {
    final names = <String>{};
    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        final n = f.uri.pathSegments.last.toLowerCase();
        if (n.endsWith('.jar')) names.add(n);
      }
    }
    return _scanNames(names.toList());
  }

  static List<ModConflict> scan(Directory modsDir) {
    if (!modsDir.existsSync()) return const [];
    final jars = modsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jar'))
        .map((f) => f.uri.pathSegments.last.toLowerCase())
        .toList();
    return _scanNames(jars);
  }

  static List<ModConflict> _scanNames(List<String> jars) {
    bool has(RegExp re) => jars.any(re.hasMatch);
    String? find(RegExp re) {
      for (final j in jars) {
        if (re.hasMatch(j)) return j;
      }
      return null;
    }

    final out = <ModConflict>[];

    final sodium = find(RegExp(r'sodium'));
    final optifine = find(RegExp(r'optifine'));
    if (sodium != null && optifine != null) {
      out.add(const ModConflict(
        severity: ConflictSeverity.soft,
        title: 'Sodium 与 OptiFine 互斥',
        detail: '可自动删除 OptiFine，保留 Sodium',
        suggestion: '自动修复：删除 OptiFine',
      ));
    }

    final embeddium = find(RegExp(r'embeddium'));
    if (sodium != null && embeddium != null) {
      out.add(const ModConflict(
        severity: ConflictSeverity.soft,
        title: 'Sodium 与 Embeddium 重复',
        detail: '同属渲染优化核心',
        suggestion: '自动修复：Fabric 删 Embeddium；Forge 需手动处理',
      ));
    }

    final rubidium = find(RegExp(r'rubidium'));
    if ((sodium != null || embeddium != null) && rubidium != null) {
      out.add(const ModConflict(
        severity: ConflictSeverity.block,
        title: '多套 Sodium 分支共存',
        detail: 'Rubidium 与 Sodium/Embeddium 功能重叠',
        suggestion: '只保留与当前 Loader 匹配的一套',
      ));
    }

    final iris = find(RegExp(r'iris'));
    final oculus = find(RegExp(r'oculus'));
    if (iris != null && oculus != null) {
      out.add(const ModConflict(
        severity: ConflictSeverity.soft,
        title: 'Iris 与 Oculus 重复',
        detail: '光影加载器双开',
        suggestion: '自动修复：Fabric 留 Iris，Forge 留 Oculus',
      ));
    }

    if (has(RegExp(r'optifine')) && has(RegExp(r'iris|oculus'))) {
      out.add(const ModConflict(
        severity: ConflictSeverity.soft,
        title: 'OptiFine 与 Iris/Oculus',
        detail: '光影链路与 OptiFine 不兼容',
        suggestion: '自动修复：删除 OptiFine',
      ));
    }

    final ferrite = jars.where((j) => j.contains('ferrite')).toList();
    if (ferrite.length > 1) {
      out.add(ModConflict(
        severity: ConflictSeverity.soft,
        title: 'FerriteCore 疑似重复',
        detail: ferrite.join(', '),
        suggestion: '自动修复：只保留一个 FerriteCore jar',
      ));
    }

    final viaPlus = find(RegExp(r'viafabricplus'));
    final viaFabric = jars.where((j) {
      final n = j.toLowerCase();
      return n.contains('viafabric') && !n.contains('viafabricplus');
    }).toList();
    if (viaPlus != null && viaFabric.isNotEmpty) {
      out.add(ModConflict(
        severity: ConflictSeverity.soft,
        title: 'ViaFabric 与 ViaFabricPlus 互斥',
        detail: '检测到 $viaPlus 与 ${viaFabric.join(', ')}',
        suggestion: '自动修复：只保留 ViaFabricPlus，删除 ViaFabric / viafabric-mc*',
      ));
    }

    final cotton = find(RegExp(r'cotton-?client-?commands'));
    if (cotton != null) {
      out.add(ModConflict(
        severity: ConflictSeverity.soft,
        title: 'Cotton Client Commands 版本过旧',
        detail: '检测到 $cotton（仅支持 1.14–1.15）',
        suggestion: '自动修复：删除该 jar',
      ));
    }

    return out;
  }
}

/// [soft] 规则明确，可自动删 jar 后继续启动；[block] 须人工处理；[warn] 仅提示。
enum ConflictSeverity { warn, soft, block }

class ModConflict {
  final ConflictSeverity severity;
  final String title;
  final String detail;
  final String suggestion;

  const ModConflict({
    required this.severity,
    required this.title,
    required this.detail,
    required this.suggestion,
  });
}
