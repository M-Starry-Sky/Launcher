import 'dart:io';

/// 解析最新崩溃/日志，给出可执行建议（不做玄学「一键修复」）。
class CrashDiagnoser {
  static Future<CrashDiagnosis> analyze(Directory gameDir) async {
    final findings = <CrashFinding>[];
    final crashDir = Directory('${gameDir.path}/crash-reports');
    final logsDir = Directory('${gameDir.path}/logs');

    File? newest;
    DateTime? newestAt;
    void consider(File f) {
      final t = f.lastModifiedSync();
      if (newestAt == null || t.isAfter(newestAt!)) {
        newest = f;
        newestAt = t;
      }
    }

    if (crashDir.existsSync()) {
      for (final f in crashDir.listSync().whereType<File>()) {
        if (f.path.endsWith('.txt')) consider(f);
      }
    }
    final latestLog = File('${logsDir.path}/latest.log');
    if (latestLog.existsSync()) consider(latestLog);

    if (newest == null) {
      return const CrashDiagnosis(
        sourcePath: null,
        findings: [
          CrashFinding(
            severity: CrashSeverity.info,
            title: '未找到崩溃报告或 latest.log',
            detail: '请先启动一次游戏，或确认游戏数据目录正确',
            action: null,
          ),
        ],
      );
    }

    final text = await newest!.readAsString();
    final lower = text.toLowerCase();

    void add(CrashSeverity s, String title, String detail, String? action) {
      findings.add(CrashFinding(
        severity: s,
        title: title,
        detail: detail,
        action: action,
      ));
    }

    if (lower.contains('outofmemoryerror') ||
        lower.contains('java.lang.outofmemoryerror')) {
      add(
        CrashSeverity.high,
        '内存不足 (OutOfMemory)',
        '堆或元空间耗尽，常见于大型整合包',
        '提高堆内存（勿超危险上限）并开启「大型整合包元空间扩容」',
      );
    }
    if (lower.contains('metaspace')) {
      add(
        CrashSeverity.high,
        '元空间溢出',
        '模组类太多导致 Metaspace 不足',
        '开启元空间扩容；精简冲突/重复模组',
      );
    }
    if (RegExp(r'sodium', caseSensitive: false).hasMatch(text) &&
        RegExp(r'optifine', caseSensitive: false).hasMatch(text)) {
      add(
        CrashSeverity.high,
        'Sodium 与 OptiFine 冲突',
        '二者渲染管线互斥，同装必炸或花屏',
        '二选一：保留 Sodium 栈，移除 OptiFine',
      );
    }
    if (lower.contains('mixin') &&
        (lower.contains('apply') || lower.contains('failed'))) {
      add(
        CrashSeverity.medium,
        'Mixin 注入失败',
        '模组字节码冲突或版本不匹配',
        '核对 Loader/游戏版本；运行模组冲突扫描',
      );
    }
    if (lower.contains('glfw') || lower.contains('lwjgl')) {
      add(
        CrashSeverity.medium,
        '图形/窗口层异常',
        '驱动、独显直连或全屏独占常见诱因',
        '更新显卡驱动；改窗口模式；关闭强制全屏后再试',
      );
    }
    if (lower.contains('could not find or load main class') ||
        lower.contains('unsupportedclassversionerror')) {
      add(
        CrashSeverity.high,
        'Java 版本不匹配',
        '当前 JVM 无法加载该版本客户端',
        '按版本安装 Java 17/21（见性能页一键绿色包）',
      );
    }
    if (findings.isEmpty) {
      add(
        CrashSeverity.info,
        '未匹配到常见性能崩溃模式',
        '已读取 ${newest!.uri.pathSegments.last}，请查看原文堆栈',
        '把 crash-reports 最新文件发给排查，或先跑模组冲突扫描',
      );
    }

    return CrashDiagnosis(sourcePath: newest!.path, findings: findings);
  }
}

enum CrashSeverity { info, medium, high }

class CrashFinding {
  final CrashSeverity severity;
  final String title;
  final String detail;
  final String? action;

  const CrashFinding({
    required this.severity,
    required this.title,
    required this.detail,
    required this.action,
  });
}

class CrashDiagnosis {
  final String? sourcePath;
  final List<CrashFinding> findings;

  const CrashDiagnosis({required this.sourcePath, required this.findings});
}
