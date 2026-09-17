import 'package:flutter/material.dart';

import '../core/perf/screen_recorder.dart';

/// 弹出桌面窗口列表，点选要录制的软件窗口。
Future<CapturableWindow?> pickCapturableWindow(
  BuildContext context, {
  bool preferGame = true,
}) async {
  final wins = await ScreenRecorder.listWindows();
  if (!context.mounted) return null;
  if (wins.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('未找到可录制的桌面窗口')),
    );
    return null;
  }
  final preferred =
      preferGame ? ScreenRecorder.preferGameWindow(wins) : null;
  return showDialog<CapturableWindow>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('选择要录制的窗口'),
        content: SizedBox(
          width: 420,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '点击下方任意软件窗口开始录制（显示的是当前打开的桌面窗口）',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (preferred != null) ...[
                const SizedBox(height: 10),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  leading: const Icon(Icons.sports_esports_outlined),
                  title: Text(preferred.title, maxLines: 2),
                  subtitle: Text('推荐 · pid ${preferred.pid}'),
                  onTap: () => Navigator.pop(ctx, preferred),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: wins.length,
                  itemBuilder: (_, i) {
                    final w = wins[i];
                    final isPref = preferred?.pid == w.pid &&
                        preferred?.title == w.title;
                    return ListTile(
                      dense: true,
                      selected: isPref,
                      leading: const Icon(Icons.desktop_windows_outlined),
                      title: Text(w.title, maxLines: 2),
                      subtitle: Text('pid ${w.pid}'),
                      onTap: () => Navigator.pop(ctx, w),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      );
    },
  );
}
