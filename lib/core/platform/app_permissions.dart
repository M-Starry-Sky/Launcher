import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 下载相关运行时权限（Android / iOS）。桌面直接放行。
class AppPermissions {
  AppPermissions._();

  /// 版本库 / 启动安装前调用。通知被拒不阻断；存储永久拒时可去设置。
  static Future<bool> ensureForDownload({
    BuildContext? context,
    void Function(String message)? onLog,
  }) async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    onLog?.call('检查下载相关权限…');

    final needed = <Permission>[
      Permission.notification,
      if (Platform.isAndroid) Permission.storage,
    ];

    PermissionStatus? storageStatus;
    PermissionStatus? notifyStatus;

    for (final perm in needed) {
      try {
        var status = await perm.status;
        if (!status.isGranted && !status.isLimited) {
          status = await perm.request();
        }
        final name = perm.toString().split('.').last;
        onLog?.call('权限 $name: ${status.name}');
        if (perm == Permission.storage) storageStatus = status;
        if (perm == Permission.notification) notifyStatus = status;
      } catch (e) {
        onLog?.call('权限 ${perm.toString().split('.').last} 跳过: $e');
      }
    }

    if (notifyStatus != null &&
        !notifyStatus.isGranted &&
        context != null &&
        context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('未开启通知权限：下载仍可进行，但无法在通知栏提示进度'),
          duration: Duration(seconds: 3),
        ),
      );
    }

    if (Platform.isAndroid &&
        storageStatus != null &&
        storageStatus.isPermanentlyDenied &&
        context != null &&
        context.mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('存储权限未开启'),
          content: const Text(
            '建议允许存储权限，以便游戏本体写入应用数据目录。'
            '若仅使用应用专属空间，也可继续下载。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续下载'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      if (go == true) {
        await openAppSettings();
        onLog?.call('已打开系统设置，请开启存储权限后重试');
        return false;
      }
    }

    onLog?.call('下载权限就绪');
    return true;
  }

  /// 冷启动预申请（不阻断）。
  static Future<void> warmUp() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await Permission.notification.request();
      if (Platform.isAndroid) {
        await Permission.storage.request();
      }
    } catch (_) {}
  }
}
