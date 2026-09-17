import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'download_page.dart';
import 'game_resources_nav.dart';
import 'mods_page.dart';
import 'pack_page.dart';
import 'room_page.dart';
import 'servers_page.dart';
import 'skins_page.dart';

export 'game_resources_nav.dart' show GameResourceSection, GameResourcesNav;

/// 游戏资源库：版本库 / 模组 / 服务器 / 整合包 / 联机 / 皮肤库。
class GameResourcesPage extends StatefulWidget {
  const GameResourcesPage({
    super.key,
    this.initial = GameResourceSection.versions,
  });

  final GameResourceSection initial;

  @override
  State<GameResourcesPage> createState() => _GameResourcesPageState();
}

class _GameResourcesPageState extends State<GameResourcesPage> {
  late GameResourceSection _section = widget.initial;
  int _navTicket = -1;

  static const _menu = <(GameResourceSection, String, IconData)>[
    (GameResourceSection.versions, '版本库', Icons.download_outlined),
    (GameResourceSection.mods, '模组', Icons.extension_outlined),
    (GameResourceSection.servers, '服务器', Icons.dns_outlined),
    (GameResourceSection.packs, '整合包', Icons.inventory_2_outlined),
    (GameResourceSection.rooms, '联机', Icons.lan_outlined),
    (GameResourceSection.skins, '皮肤库', Icons.checkroom_outlined),
  ];

  Widget _body() {
    switch (_section) {
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
    final theme = Theme.of(context);
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

    final compact = MediaQuery.sizeOf(context).width < 720;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 14 : 24, compact ? 10 : 16, compact ? 14 : 24, 0),
          child: Text(
            '游戏资源',
            style: compact
                ? theme.textTheme.titleLarge
                : theme.textTheme.headlineSmall,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 10 : 16, 10, compact ? 10 : 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in _menu) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(item.$3, size: 16),
                      label: Text(item.$2),
                      selected: _section == item.$1,
                      onSelected: (_) {
                        setState(() => _section = item.$1);
                        context.read<GameResourcesNav>().section = item.$1;
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(child: _body()),
      ],
    );
  }
}
