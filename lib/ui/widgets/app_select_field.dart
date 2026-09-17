import 'package:flutter/material.dart';

import '../app_theme.dart';

class AppSelectOption<T> {
  final T value;
  final String label;
  final bool enabled;

  const AppSelectOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });
}

/// 桌面安全下拉：标题固定在框上方；菜单插入 root Overlay。
class AppSelectField<T> extends StatefulWidget {
  final T? value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final String? labelText;
  final String? hintText;
  final bool isExpanded;
  final bool isDense;
  final InputDecoration? decoration;

  const AppSelectField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelText,
    this.hintText,
    this.isExpanded = true,
    this.isDense = true,
    this.decoration,
  });

  @override
  State<AppSelectField<T>> createState() => _AppSelectFieldState<T>();
}

class _AppSelectFieldState<T> extends State<AppSelectField<T>> {
  final LayerLink _link = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _entry;
  bool _open = false;
  bool _hover = false;

  T? get _safeValue {
    final v = widget.value;
    if (v == null) return null;
    for (final o in widget.options) {
      if (o.value == v) return v;
    }
    return null;
  }

  String get _displayLabel {
    final v = _safeValue;
    if (v == null) return widget.hintText ?? '';
    for (final o in widget.options) {
      if (o.value == v) return o.label;
    }
    return widget.hintText ?? '';
  }

  @override
  void dispose() {
    _removeMenu();
    super.dispose();
  }

  void _removeMenu() {
    _entry?.remove();
    _entry = null;
    if (_open && mounted) {
      setState(() => _open = false);
    } else {
      _open = false;
    }
  }

  void _toggle() {
    if (widget.onChanged == null) return;
    if (_open) {
      _removeMenu();
      return;
    }
    _showMenu();
  }

  void _showMenu() {
    final overlay = Overlay.of(context, rootOverlay: true);
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final fieldSize = box.size;
    final scheme = Theme.of(context).colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.45;

    _entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _removeMenu,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              offset: Offset(0, fieldSize.height + 4),
              child: Material(
                color: scheme.surfaceContainerHigh,
                elevation: 10,
                shadowColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.8),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: fieldSize.width,
                    maxWidth: fieldSize.width,
                    maxHeight: maxH,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    itemCount: widget.options.length,
                    itemBuilder: (_, i) {
                      final opt = widget.options[i];
                      final selected = opt.value == _safeValue;
                      return InkWell(
                        onTap: !opt.enabled || widget.onChanged == null
                            ? null
                            : () {
                                widget.onChanged!(opt.value);
                                _removeMenu();
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  opt.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: opt.enabled
                                            ? scheme.onSurface
                                            : scheme.onSurface
                                                .withValues(alpha: 0.38),
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                ),
                              ),
                              if (selected)
                                Icon(Icons.check_rounded,
                                    size: 18, color: scheme.primary),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_entry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.onChanged != null;
    final label = widget.decoration?.labelText ?? widget.labelText;
    final hint = widget.decoration?.hintText ?? widget.hintText;
    final borderColor = _open
        ? scheme.primary
        : (_hover && enabled
            ? scheme.outline
            : scheme.outlineVariant.withValues(alpha: 0.75));

    final field = CompositedTransformTarget(
      link: _link,
      child: KeyedSubtree(
        key: _fieldKey,
        child: MouseRegion(
          onEnter: enabled ? (_) => setState(() => _hover = true) : null,
          onExit: enabled ? (_) => setState(() => _hover = false) : null,
          cursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: enabled ? _toggle : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              constraints: BoxConstraints(
                minHeight: widget.isDense ? 40 : 48,
              ),
              padding: EdgeInsets.fromLTRB(
                12,
                widget.isDense ? 8 : 12,
                8,
                widget.isDense ? 8 : 12,
              ),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: enabled ? 0.9 : 0.5),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: borderColor,
                  width: _open ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _displayLabel.isEmpty ? (hint ?? '') : _displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: !enabled
                            ? scheme.onSurface.withValues(alpha: 0.38)
                            : _safeValue == null
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (label == null || label.isEmpty) {
      return field;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        field,
      ],
    );
  }
}
