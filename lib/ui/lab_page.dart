import 'package:flutter/material.dart';

import 'mod_dev_page.dart';

enum LabSection { modDev }

/// 实验室：一级导航入口；内部用二级标签切换实验功能。
class LabPage extends StatefulWidget {
  const LabPage({
    super.key,
    this.active = true,
    this.initial = LabSection.modDev,
  });

  final bool active;
  final LabSection initial;

  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> {
  late LabSection _section = widget.initial;

  static const _menu = <(LabSection, String, IconData)>[
    (LabSection.modDev, '模组开发工作台', Icons.code_outlined),
  ];

  Widget _body() {
    switch (_section) {
      case LabSection.modDev:
        return ModDevPage(
          active: widget.active && _section == LabSection.modDev,
          embeddedInLab: true,
        );
    }
  }

  @override
  void didUpdateWidget(covariant LabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切走实验室一级页时，子页会靠 active=false 停轮询
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 24,
            compact ? 10 : 16,
            compact ? 14 : 24,
            0,
          ),
          child: Text(
            '实验室',
            style: compact
                ? theme.textTheme.titleLarge
                : theme.textTheme.headlineSmall,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 16,
            10,
            compact ? 10 : 16,
            0,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in _menu)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(item.$3, size: 16),
                      label: Text(item.$2),
                      selected: _section == item.$1,
                      onSelected: (_) => setState(() => _section = item.$1),
                    ),
                  ),
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
