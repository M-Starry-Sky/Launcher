import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/auth_manager.dart';
import 'about_dialogs.dart';
import 'accounts_page.dart';
import 'app_theme.dart';
import 'community_page.dart';
import 'game_resources_page.dart';
import 'glass/liquid_glass.dart';
import 'lab_page.dart';
import 'launch_home_page.dart';
import 'perf_center_page.dart';
import 'settings_page.dart';

/// 主导航：宽屏侧栏；窄屏底栏（手机适配）。
class LauncherShell extends StatefulWidget {
  const LauncherShell({super.key});

  @override
  State<LauncherShell> createState() => _LauncherShellState();
}

class _LauncherShellState extends State<LauncherShell> {
  int _index = 0;
  int _navTicket = 0;
  static const int _settingsIndex = 4;
  static const int _communityIndex = 5;
  static const int _labIndex = 3;

  static const _mobileDestinations = <(IconData, String)>[
    (Icons.play_arrow_rounded, '启动'),
    (Icons.sports_esports_outlined, '资源'),
    (Icons.speed_rounded, '性能'),
    (Icons.science_outlined, '实验室'),
    (Icons.settings_outlined, '设置'),
  ];

  static const _desktopDestinations = <(IconData, String)>[
    (Icons.play_arrow_rounded, '启动'),
    (Icons.sports_esports_outlined, '资源'),
    (Icons.speed_rounded, '性能'),
    (Icons.science_outlined, '实验室'),
    (Icons.settings_outlined, '设置'),
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

    final wide = MediaQuery.sizeOf(context).width >= 960;
    final pages = <Widget>[
      const LaunchHomePage(),
      const GameResourcesPage(),
      PerfCenterPage(active: _index == 2),
      LabPage(active: _index == _labIndex),
      const SettingsPage(),
      const CommunityPage(),
    ];
    final body = IndexedStack(index: _index, children: pages);

    if (!wide) return _mobileShell(body);
    return _desktopShell(body);
  }

  Widget _mobileShell(Widget body) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthManager>();
    final onPrimaryTabs = _index < _mobileDestinations.length;
    final selectedNav = onPrimaryTabs ? _index : 0;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          height: 1.1,
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountsPage(),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSm),
                          child: Image.asset(
                            auth.defaultAvatarAsset,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.none,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.person,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            auth.username?.trim().isNotEmpty == true
                                ? auth.username!
                                : '未登录',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '社区',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _index = _communityIndex),
                    icon: Icon(
                      Icons.groups_outlined,
                      size: 22,
                      color: _index == _communityIndex
                          ? scheme.primary
                          : null,
                    ),
                  ),
                  IconButton(
                    tooltip: '关于',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showAppAboutDialog(context),
                    icon: const Icon(Icons.info_outline, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: LiquidGlass(
            borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
            padding: EdgeInsets.zero,
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 56,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return labelStyle?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return IconThemeData(
                    size: 22,
                    color: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  );
                }),
              ),
              child: NavigationBar(
                height: 56,
                backgroundColor: Colors.transparent,
                elevation: 0,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: selectedNav,
                destinations: [
                  for (final d in _mobileDestinations)
                    NavigationDestination(
                      icon: Icon(d.$1, size: 22),
                      label: d.$2,
                    ),
                ],
                onDestinationSelected: (i) => setState(() => _index = i),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopShell(Widget body) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthManager>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Row(
          children: [
            LiquidGlass(
              width: 84,
              borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
              fillBoost: 0.04,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMd),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AccountsPage(),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.28),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusMd),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: 0.45),
                                width: 1.5,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.asset(
                              auth.defaultAvatarAsset,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.none,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.person,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            auth.username?.trim().isNotEmpty == true
                                ? auth.username!
                                : '未登录',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurface,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (var i = 0; i < _desktopDestinations.length; i++)
                    if (i < 4)
                      _SideNavButton(
                        icon: _desktopDestinations[i].$1,
                        label: _desktopDestinations[i].$2,
                        selected: _index == i,
                        onTap: () => setState(() => _index = i),
                      ),
                  const Spacer(),
                  _SideNavButton(
                    icon: Icons.info_outline_rounded,
                    label: '关于',
                    selected: false,
                    onTap: () => showAppAboutDialog(context),
                  ),
                  _SideNavButton(
                    icon: Icons.groups_outlined,
                    label: '社区',
                    selected: _index == _communityIndex,
                    onTap: () => setState(() => _index = _communityIndex),
                  ),
                  _SideNavButton(
                    icon: Icons.settings_outlined,
                    label: '设置',
                    selected: _index == _settingsIndex,
                    onTap: () => setState(() => _index = _settingsIndex),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LiquidGlass(
                borderRadius: BorderRadius.circular(AppTheme.radiusGlass),
                fillBoost: 0.02,
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SideNavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          letterSpacing: 0,
                          height: 1.1,
                          color: selected
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
