import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'version_installer.dart';

/// 上次成功启动的本地快照：暖启动时直接复用 Java + classpath，跳过解析与探测。
class LaunchSnapshot {
  final String versionId;
  final String javaPath;
  final int? javaMajor;
  final ResolvedVersion version;
  final String instanceId;

  const LaunchSnapshot({
    required this.versionId,
    required this.javaPath,
    required this.javaMajor,
    required this.version,
    required this.instanceId,
  });

  static File pathFor(Directory bodyDir, String versionId) => File(
        p.join(bodyDir.path, 'versions', versionId, '.xq_launch_snap.json'),
      );

  Map<String, dynamic> toJson() => {
        'versionId': versionId,
        'javaPath': javaPath,
        'javaMajor': javaMajor,
        'instanceId': instanceId,
        'id': version.id,
        'mainClass': version.mainClass,
        'classpath': version.classpath,
        'gameArgs': version.gameArgs,
        'assetsIndexName': version.assetsIndexName,
        'nativesDir': version.nativesDir,
        'at': DateTime.now().toIso8601String(),
      };

  static LaunchSnapshot? fromJson(Map<String, dynamic> json) {
    final versionId = json['versionId']?.toString();
    final javaPath = json['javaPath']?.toString();
    final id = json['id']?.toString();
    final mainClass = json['mainClass']?.toString();
    if (versionId == null ||
        javaPath == null ||
        id == null ||
        mainClass == null ||
        mainClass.isEmpty) {
      return null;
    }
    final cp = (json['classpath'] as List?)?.whereType<String>().toList();
    final args = (json['gameArgs'] as List?)?.whereType<String>().toList();
    if (cp == null || cp.isEmpty) return null;
    return LaunchSnapshot(
      versionId: versionId,
      javaPath: javaPath,
      javaMajor: (json['javaMajor'] as num?)?.toInt(),
      instanceId: json['instanceId']?.toString() ?? '',
      version: ResolvedVersion(
        id: id,
        mainClass: mainClass,
        classpath: cp,
        gameArgs: args ?? const [],
        assetsIndexName: json['assetsIndexName']?.toString() ?? '',
        nativesDir: json['nativesDir']?.toString() ?? '',
      ),
    );
  }

  /// 快照可用：java 在、主 jar/库抽样在、natives 目录在。
  static Future<LaunchSnapshot?> tryLoad({
    required Directory bodyDir,
    required String versionId,
    required String instanceId,
  }) async {
    final file = pathFor(bodyDir, versionId);
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final snap = fromJson(json);
      if (snap == null) return null;
      if (snap.versionId != versionId) return null;
      if (snap.instanceId.isNotEmpty &&
          instanceId.isNotEmpty &&
          snap.instanceId != instanceId) {
        // 实例不同仍可复用本体 classpath；仅 java/version 需匹配
      }
      if (!File(snap.javaPath).existsSync()) return null;
      // 抽样校验 classpath 前 3 项 + 末项
      final cp = snap.version.classpath;
      final probes = <String>{
        if (cp.isNotEmpty) cp.first,
        if (cp.length > 1) cp[1],
        if (cp.length > 2) cp[2],
        if (cp.length > 3) cp.last,
      };
      for (final path in probes) {
        if (!File(path).existsSync()) return null;
      }
      final natives = snap.version.nativesDir;
      if (natives.isNotEmpty && !Directory(natives).existsSync()) {
        return null;
      }
      return snap;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Directory bodyDir) async {
    final file = pathFor(bodyDir, versionId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(toJson()));
  }
}
