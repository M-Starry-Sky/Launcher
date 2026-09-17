import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 选择本地文件路径（Windows 系统对话框；其它平台回退为路径输入）。
Future<String?> pickFilePath(
  BuildContext context, {
  required String title,
  required String filter,
  String fallbackHint = r'C:\path\to\file',
}) async {
  if (!kIsWeb && Platform.isWindows) {
    try {
      final safeTitle = title.replaceAll("'", "''");
      final safeFilter = filter.replaceAll("'", "''");
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '''
Add-Type -AssemblyName System.Windows.Forms | Out-Null
\$d = New-Object System.Windows.Forms.OpenFileDialog
\$d.Filter = '$safeFilter'
\$d.Title = '$safeTitle'
\$d.Multiselect = \$false
if (\$d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { \$d.FileName }
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
        decoration: InputDecoration(
          labelText: '文件完整路径',
          hintText: fallbackHint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  final path = ctrl.text.trim();
  ctrl.dispose();
  if (ok == true && path.isNotEmpty) return path;
  return null;
}

/// 保存文件路径（Windows SaveFileDialog）。
Future<String?> pickSaveFilePath(
  BuildContext context, {
  required String title,
  required String filter,
  String defaultName = 'pack.zip',
}) async {
  if (!kIsWeb && Platform.isWindows) {
    try {
      final safeTitle = title.replaceAll("'", "''");
      final safeFilter = filter.replaceAll("'", "''");
      final safeName = defaultName.replaceAll("'", "''");
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '''
Add-Type -AssemblyName System.Windows.Forms | Out-Null
\$d = New-Object System.Windows.Forms.SaveFileDialog
\$d.Filter = '$safeFilter'
\$d.Title = '$safeTitle'
\$d.FileName = '$safeName'
\$d.AddExtension = \$true
\$d.OverwritePrompt = \$true
if (\$d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { \$d.FileName }
''',
        ],
        runInShell: false,
      );
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) return path;
      return null;
    } catch (_) {}
  }
  return pickFilePath(context, title: title, filter: filter, fallbackHint: defaultName);
}

/// 多选本地文件（Windows）；失败时退回单选。
Future<List<String>> pickFilePaths(
  BuildContext context, {
  required String title,
  required String filter,
}) async {
  if (!kIsWeb && Platform.isWindows) {
    try {
      final safeTitle = title.replaceAll("'", "''");
      final safeFilter = filter.replaceAll("'", "''");
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '''
Add-Type -AssemblyName System.Windows.Forms | Out-Null
\$d = New-Object System.Windows.Forms.OpenFileDialog
\$d.Filter = '$safeFilter'
\$d.Title = '$safeTitle'
\$d.Multiselect = \$true
if (\$d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { \$d.FileNames -join "`n" }
''',
        ],
        runInShell: false,
      );
      final raw = (result.stdout as String).trim();
      if (raw.isNotEmpty) {
        return raw
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    } catch (_) {}
  }
  final one = await pickFilePath(context, title: title, filter: filter);
  return one == null ? const [] : [one];
}
