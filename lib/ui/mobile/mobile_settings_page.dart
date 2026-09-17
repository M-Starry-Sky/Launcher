import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../glass/liquid_glass.dart';
import '../settings_page.dart';
import 'mobile_page_header.dart';

/// App 端设置入口：分区列表 → 进入详情，不复用桌面横滑 Chip 壳。
///
/// 详情页仍复用 [SettingsPage] 的配置能力，但以全屏分区呈现。
class MobileSettingsPage extends StatelessWidget {
  const MobileSettingsPage({super.key});

  static const _items = <(_MobileSettingsKind, String, String, IconData)>[
    (
      _MobileSettingsKind.appearance,
      '外观',
      '主题、背景与玻璃效果',
      Icons.palette_outlined,
    ),
    (
      _MobileSettingsKind.source,
      '配置来源',
      '后端与本地授权',
      Icons.cloud_outlined,
    ),
    (
      _MobileSettingsKind.runtime,
      '运行环境',
      '目录、Java 与启动行为',
      Icons.memory_outlined,
    ),
    (
      _MobileSettingsKind.download,
      '下载加速',
      '镜像与加速开关',
      Icons.speed_rounded,
    ),
    (
      _MobileSettingsKind.tunnel,
      '联机隧道',
      'frp 与本地端口',
      Icons.vpn_key_outlined,
    ),
    (
      _MobileSettingsKind.update,
      '版本更新',
      '检查与安装启动器更新',
      Icons.system_update_alt_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MobilePageHeader(
          title: '设置',
          subtitle: '外观与运行环境',
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final item = _items[i];
              return LiquidGlass(
                allowBackdrop: false,
                interactive: true,
                fillBoost: 0.05,
                borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(
                      appSectionOnly: item.$1.name,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.16),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: Icon(item.$4, color: scheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$2,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.$3,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

enum _MobileSettingsKind {
  appearance,
  source,
  runtime,
  download,
  tunnel,
  update,
}
