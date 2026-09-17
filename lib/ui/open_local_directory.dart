import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 在系统文件管理器中打开本地目录（先创建，再规范化绝对路径）。
///
/// Windows 上混用 `/` `\` 或相对路径时，explorer 常会打开错误位置；
/// 这里统一成绝对路径 + 系统分隔符后再打开。
Future<bool> openLocalDirectory(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;

  final dir = Directory(p.normalize(trimmed));
  try {
    await dir.create(recursive: true);
  } catch (_) {
    return false;
  }

  final abs = Directory(dir.absolute.path).path;
  final native = p.normalize(abs);

  try {
    if (kIsWeb) return false;
    if (Platform.isWindows) {
      // 必须用反斜杠；传相对路径时 explorer 会落到「此电脑/文档」等错误位置
      final winPath = native.replaceAll('/', r'\');
      final result = await Process.run(
        'explorer.exe',
        [winPath],
        runInShell: false,
      );
      // explorer 即使成功也可能返回非 0；只要进程启动即视为已请求打开
      return result.exitCode == 0 || result.exitCode == 1;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', [native]);
      return result.exitCode == 0;
    }
    if (Platform.isAndroid) {
      // 用系统文件管理打开目录（file://）；失败时仍返回路径可读
      final uri = Uri.file(native).toString();
      final result = await Process.run('am', [
        'start',
        '-a',
        'android.intent.action.VIEW',
        '-d',
        uri,
        '-t',
        'resource/folder',
      ]);
      if (result.exitCode == 0) return true;
      // 回退：只打开父路径的 VIEW（部分机型无文件夹 MIME）
      final fallback = await Process.run('am', [
        'start',
        '-a',
        'android.intent.action.VIEW',
        '-d',
        uri,
      ]);
      return fallback.exitCode == 0;
    }
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [native]);
      return result.exitCode == 0;
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// 用系统默认程序打开本地文件（如录像 mp4）。
Future<bool> openLocalFile(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  final file = File(p.normalize(trimmed));
  if (!await file.exists()) return false;
  final native = p.normalize(file.absolute.path);

  try {
    if (kIsWeb) return false;
    if (Platform.isWindows) {
      final winPath = native.replaceAll('/', r'\');
      final result = await Process.run(
        'cmd',
        ['/c', 'start', '', winPath],
        runInShell: false,
      );
      return result.exitCode == 0;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', [native]);
      return result.exitCode == 0;
    }
    final result = await Process.run('xdg-open', [native]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// 在资源管理器中选中文件。
Future<bool> revealLocalFile(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  final file = File(p.normalize(trimmed));
  if (!await file.exists()) return false;
  final native = p.normalize(file.absolute.path);

  try {
    if (kIsWeb) return false;
    if (Platform.isWindows) {
      final winPath = native.replaceAll('/', r'\');
      final result = await Process.run(
        'explorer.exe',
        ['/select,', winPath],
        runInShell: false,
      );
      return result.exitCode == 0 || result.exitCode == 1;
    }
    return await openLocalDirectory(p.dirname(native));
  } catch (_) {
    return false;
  }
}
