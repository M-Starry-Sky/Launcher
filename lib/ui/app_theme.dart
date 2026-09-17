import 'package:flutter/material.dart';

/// 全局视觉：圆角组件 + 明暗主题。
class AppTheme {
  static const Color brand = Color(0xFF5B6FE8);
  /// 大面板（侧栏、主内容、弹窗）
  static const double radiusGlass = 14;
  /// 操作系统窗体外框圆角（未最大化）
  static const double radiusWindow = 12;
  static const double radiusLg = 12;
  static const double radiusMd = 10;
  static const double radiusSm = 8;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
    );
    final shapeLg = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusLg),
    );
    final shapeMd = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    );
    final shapeSm = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSm),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: shapeLg,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        shape: shapeLg,
        clipBehavior: Clip.antiAlias,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusLg),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shapeMd,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface.withValues(alpha: 0.88),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor:
              WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          elevation: const WidgetStatePropertyAll(10),
          shape: WidgetStatePropertyAll(shapeMd),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: shapeMd,
        color: scheme.surfaceContainerHigh,
        elevation: 10,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor:
              WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          shape: WidgetStatePropertyAll(shapeMd),
          elevation: const WidgetStatePropertyAll(10),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: shapeMd),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: shapeMd),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shapeSm),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: shapeMd),
      ),
      chipTheme: ChipThemeData(
        shape: shapeSm,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: shapeMd,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        indicatorShape: shapeMd,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: shapeLg,
      ),
      listTileTheme: ListTileThemeData(
        shape: shapeMd,
      ),
      switchTheme: SwitchThemeData(
        splashRadius: 0,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
      ),
    );
  }

  static ThemeMode parseThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String themeModeKey(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
