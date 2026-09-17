import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../community_page.dart';
import '../game_resources_nav.dart';
import '../glass/liquid_glass.dart';
import '../lab_page.dart';
import '../perf_center_page.dart';
import 'mobile_launch_home_page.dart';
import 'mobile_resources_page.dart';
import 'mobile_settings_page.dart';

/// App 端主导航：底部悬浮玻璃坞 + 独立页面树（不复用桌面侧栏）。
class MobileLauncherShell extends StatefulWidget {
  const MobileLauncherShell({super.key});

  @override
  State<MobileLauncherShell> createState() => _MobileLauncherShellState();
}

class _MobileLauncherShellState extends State<MobileLauncherShell> {
  int _index = 0;
  int _navTicket = 0;

  static const int _communityIndex = 5;
  static const int _labIndex = 3;

  static const _tabs = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, '首页'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, '资源'),
    (Icons.bolt_outlined, Icons.bolt_rounded, '性能'),
    (Icons.science_outlined, Icons.science_rounded, '实验'),
    (Icons.tune_outlined, Icons.tune_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<GameResourcesNav>();
    if (nav.ticket != _navTicket) {
      final ticket = nav.ticket;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ticket == _navTicket) return;
        setState(() {
          _navTicket = ticket;
          _index = 1;
        });
      });
    }

    final scheme = Theme.of(context).colorScheme;
    final onPrimaryTabs = _index < _tabs.length;
    final selectedNav = onPrimaryTabs ? _index : 0;

    final pages = <Widget>[
      MobileLaunchHomePage(
        onOpenCommunity: () => setState(() => _index = _communityIndex),
      ),
      const MobileResourcesPage(),
      PerfCenterPage(active: _index == 2),
      LabPage(active: _index == _labIndex),
      const MobileSettingsPage(),
      const CommunityPage(),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(22),
          fillBoost: 0.06,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _DockItem(
                    icon: _tabs[i].$1,
                    selectedIcon: _tabs[i].$2,
                    label: _tabs[i].$3,
                    selected: selectedNav == i && onPrimaryTabs,
                    onTap: () => setState(() => _index = i),
                  ),
                ),
              _DockItem(
                icon: Icons.groups_outlined,
                selectedIcon: Icons.groups_rounded,
                label: '社区',
                selected: _index == _communityIndex,
                onTap: () => setState(() => _index = _communityIndex),
                accent: scheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected
        ? (accent ?? scheme.primary)
        : scheme.onSurfaceVariant;

    return Material(
      color: selected
          ? (accent ?? scheme.primary).withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? selectedIcon : icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                      height: 1.1,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
