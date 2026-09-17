import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 选择本地图片路径（Windows 用系统对话框，其它平台回退为路径输入）。
Future<String?> pickImagePath(BuildContext context) async {
  if (!kIsWeb && Platform.isWindows) {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          r'''
Add-Type -AssemblyName System.Windows.Forms | Out-Null
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.Filter = 'Images|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif|All|*.*'
$d.Title = '选择背景图片'
if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $d.FileName }
''',
        ],
        runInShell: false,
      );
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) return path;
      return null;
    } catch (_) {
      // fall through
    }
  }

  if (!context.mounted) return null;
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('选择背景图片'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(
          labelText: '图片完整路径',
          hintText: r'C:\path\to\image.png',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定')),
      ],
    ),
  );
  final path = ctrl.text.trim();
  ctrl.dispose();
  if (ok == true && path.isNotEmpty) return path;
  return null;
}
