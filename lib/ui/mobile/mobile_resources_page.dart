import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../download_page.dart';
import '../game_resources_nav.dart';
import '../glass/liquid_glass.dart';
import '../mods_page.dart';
import '../pack_page.dart';
import '../room_page.dart';
import '../servers_page.dart';
import '../skins_page.dart';
import 'mobile_page_header.dart';

/// App 端资源中心：卡片宫格入口，点进分区；不复用桌面横滑 Chip 壳。
class MobileResourcesPage extends StatefulWidget {
  const MobileResourcesPage({super.key});

  @override
  State<MobileResourcesPage> createState() => _MobileResourcesPageState();
}

class _MobileResourcesPageState extends State<MobileResourcesPage> {
  GameResourceSection? _section;
  int _navTicket = -1;

  static const _items = <(GameResourceSection, String, String, IconData)>[
    (GameResourceSection.versions, '版本库', '下载与管理游戏版本', Icons.download_outlined),
    (GameResourceSection.mods, '模组', '浏览与安装模组', Icons.extension_outlined),
    (GameResourceSection.servers, '服务器', '常用服务器直连', Icons.dns_outlined),
    (GameResourceSection.packs, '整合包', '一键载入整合包', Icons.inventory_2_outlined),
    (GameResourceSection.rooms, '联机', '房间与隧道联机', Icons.lan_outlined),
    (GameResourceSection.skins, '皮肤库', '皮肤预览与应用', Icons.checkroom_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<GameResourcesNav>();
    if (nav.ticket != _navTicket) {
      final ticket = nav.ticket;
      final section = nav.section;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ticket == _navTicket) return;
        setState(() {
          _navTicket = ticket;
          _section = section;
        });
      });
    }

    if (_section != null) {
      return _SectionHost(
        section: _section!,
        onBack: () => setState(() => _section = null),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MobilePageHeader(
          title: '游戏资源',
          subtitle: '版本 · 模组 · 联机 · 皮肤',
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
            ),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final item = _items[i];
              return LiquidGlass(
                allowBackdrop: false,
                interactive: true,
                fillBoost: 0.05,
                borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
                onTap: () {
                  setState(() => _section = item.$1);
                  context.read<GameResourcesNav>().section = item.$1;
                },
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const Spacer(),
                    Text(
                      item.$2,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.$3,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.25,
                      ),
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

class _SectionHost extends StatelessWidget {
  const _SectionHost({
    required this.section,
    required this.onBack,
  });

  final GameResourceSection section;
  final VoidCallback onBack;

  String get _title {
    switch (section) {
      case GameResourceSection.versions:
        return '版本库';
      case GameResourceSection.mods:
        return '模组';
      case GameResourceSection.servers:
        return '服务器';
      case GameResourceSection.packs:
        return '整合包';
      case GameResourceSection.rooms:
        return '联机';
      case GameResourceSection.skins:
        return '皮肤库';
    }
  }

  Widget get _body {
    switch (section) {
      case GameResourceSection.versions:
        return const DownloadPage(embeddedInResources: true);
      case GameResourceSection.mods:
        return const ModsPage();
      case GameResourceSection.servers:
        return const ServersPage();
      case GameResourceSection.packs:
        return const PackPage();
      case GameResourceSection.rooms:
        return const RoomPage();
      case GameResourceSection.skins:
        return const SkinsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  _title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body),
      ],
    );
  }
}
