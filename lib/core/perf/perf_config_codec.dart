import 'dart:convert';

import 'bedrock_render_presets.dart';
import 'fps_presets.dart';
import 'gc_presets.dart';
import 'perf_config.dart';
import 'perf_profiles.dart';

/// 性能配置导入导出（可核对的 JSON，不含账号密钥）。
class PerfConfigCodec {
  static const version = 1;

  static Map<String, dynamic> exportMap(PerfConfig perf) {
    return {
      'xingqiong_perf': version,
      'heap_mb': perf.heapMb,
      'gc': perf.gcPreset.storageKey,
      'large_modpack': perf.largeModpack,
      'auto_memory': perf.autoMemory,
      'auto_gc': perf.autoGc,
      'auto_fix_java': perf.autoFixJava,
      'block_on_conflict': perf.blockOnModConflict,
      'auto_fix_soft_conflict': perf.autoFixSoftConflict,
      'clean_cache_on_launch': perf.cleanCacheOnLaunch,
      'trim_launcher_on_launch': perf.trimLauncherOnLaunch,
      'launcher_perf_mode': perf.launcherPerfMode,
      'custom_jvm': perf.customJvmArgs,
      'fps': perf.fps.toJson(),
      'bedrock': perf.bedrock.toJson(),
      'active_profile': perf.activeProfile?.storageKey,
    };
  }

  static String exportJson(PerfConfig perf, {bool pretty = true}) {
    final map = exportMap(perf);
    if (pretty) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(map);
    }
    return jsonEncode(map);
  }

  /// 返回人类可读的变更摘要。
  static Future<List<String>> importJson(PerfConfig perf, String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('配置不是 JSON 对象');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['xingqiong_perf'] == null) {
      throw const FormatException('缺少 xingqiong_perf 标记，拒绝导入');
    }
    final changes = <String>[];

    final heap = (map['heap_mb'] as num?)?.toInt();
    if (heap != null) {
      await perf.setHeapMb(heap);
      changes.add('堆内存 → ${perf.heapMb}M');
    }
    final gc = map['gc'] as String?;
    if (gc != null) {
      await perf.setGcPreset(GcPresetX.parse(gc));
      changes.add('GC → ${perf.gcPreset.label}');
    }
    if (map['large_modpack'] is bool) {
      await perf.setLargeModpack(map['large_modpack'] as bool);
    }
    if (map['auto_memory'] is bool) {
      await perf.setAutoMemory(map['auto_memory'] as bool);
    }
    if (map['auto_gc'] is bool) {
      await perf.setAutoGc(map['auto_gc'] as bool);
    }
    if (map['auto_fix_java'] is bool) {
      await perf.setAutoFixJava(map['auto_fix_java'] as bool);
    }
    if (map['block_on_conflict'] is bool) {
      await perf.setBlockOnModConflict(map['block_on_conflict'] as bool);
    }
    if (map['auto_fix_soft_conflict'] is bool) {
      await perf.setAutoFixSoftConflict(map['auto_fix_soft_conflict'] as bool);
    }
    if (map['clean_cache_on_launch'] is bool) {
      await perf.setCleanCacheOnLaunch(map['clean_cache_on_launch'] as bool);
    }
    if (map['trim_launcher_on_launch'] is bool) {
      await perf.setTrimLauncherOnLaunch(map['trim_launcher_on_launch'] as bool);
    }
    if (map['launcher_perf_mode'] is bool) {
      await perf.setLauncherPerfMode(map['launcher_perf_mode'] as bool);
    }
    if (map['custom_jvm'] is String) {
      await perf.setCustomJvmArgs(map['custom_jvm'] as String);
    }
    final fps = map['fps'];
    if (fps is Map) {
      await perf.setFps(
        JavaFpsSettings.fromJson(Map<String, dynamic>.from(fps)),
      );
      changes.add('帧率档 → ${perf.fps.preset.label}');
    }
    final bedrock = map['bedrock'];
    if (bedrock is Map) {
      await perf.setBedrock(
        BedrockRenderSettings.fromJson(Map<String, dynamic>.from(bedrock)),
      );
      changes.add('基岩预设 → ${perf.bedrock.preset.label}');
    }
    if (changes.isEmpty) changes.add('已导入（无字段变更或值相同）');
    return changes;
  }
}
