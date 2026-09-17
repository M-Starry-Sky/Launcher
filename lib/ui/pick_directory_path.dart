import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 选择本地文件夹路径（Windows 用系统对话框）。
Future<String?> pickDirectoryPath(
  BuildContext context, {
  String title = '选择文件夹',
}) async {
  if (!kIsWeb && Platform.isWindows) {
    try {
      final escaped = title.replaceAll("'", "''");
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '''
Add-Type -AssemblyName System.Windows.Forms | Out-Null
\$d = New-Object System.Windows.Forms.FolderBrowserDialog
\$d.Description = '$escaped'
\$d.ShowNewFolderButton = \$true
if (\$d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { \$d.SelectedPath }
''',
        ],
        runInShell: false,
      );
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) return path;
      return null;
    } catch (_) {}
  }

  if (!context.mounted) return null;
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(
          labelText: '文件夹路径',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
      ],
    ),
  );
  final path = ctrl.text.trim();
  ctrl.dispose();
  if (ok == true && path.isNotEmpty) return path;
  return null;
}
