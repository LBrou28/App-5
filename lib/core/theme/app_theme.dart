import 'package:flutter/material.dart';

/// The inventory opens in its designed dark appearance. The toggle still
/// provides a light alternative for people who prefer it.
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);

class AppTheme {
  AppTheme._();

  // A warm "found it" accent and a cool periwinkle organizing accent, both chosen to be
  // comfortable against the near-black inventory surfaces.
  static const Color _amber = Color(0xffffb35c);
  static const Color _periwinkle = Color(0xffaabfff);
  static const Color _ink = Color(0xff0b0f12);

  static ThemeData light() => _build(
    ColorScheme.fromSeed(seedColor: const Color(0xffb76414)).copyWith(
      secondary: const Color(0xff3657ae),
      tertiary: const Color(0xff6750a4),
      surface: const Color(0xfffffbf7),
      surfaceContainerLow: const Color(0xfffff4e9),
      surfaceContainerHigh: const Color(0xffffead8),
    ),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(seedColor: _amber, brightness: Brightness.dark)
        .copyWith(
          primary: _amber,
          onPrimary: const Color(0xff3d2100),
          primaryContainer: const Color(0xff5a380a),
          onPrimaryContainer: const Color(0xffffdeb0),
          secondary: _periwinkle,
          onSecondary: const Color(0xff17295d),
          secondaryContainer: const Color(0xff30477f),
          onSecondaryContainer: const Color(0xffdee6ff),
          tertiary: const Color(0xffd1b9ff),
          onTertiary: const Color(0xff382364),
          tertiaryContainer: const Color(0xff4e387c),
          onTertiaryContainer: const Color(0xffeadcff),
          surface: _ink,
          onSurface: const Color(0xffe7edef),
          surfaceContainerLowest: const Color(0xff070a0c),
          surfaceContainerLow: const Color(0xff12181c),
          surfaceContainer: const Color(0xff171e22),
          surfaceContainerHigh: const Color(0xff20282d),
          surfaceContainerHighest: const Color(0xff2a343a),
          onSurfaceVariant: const Color(0xffbdc9c9),
          outline: const Color(0xff849292),
          outlineVariant: const Color(0xff3b474b),
        ),
  );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = base.textTheme;
    final rounded12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: rounded12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        selectedColor: scheme.onSecondaryContainer,
        selectedTileColor: scheme.secondaryContainer,
        iconColor: scheme.onSurfaceVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerHigh, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      popupMenuTheme: PopupMenuThemeData(shape: rounded12, color: scheme.surfaceContainer),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: scheme.surfaceContainerHighest, shape: rounded12),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      chipTheme: ChipThemeData(shape: const StadiumBorder(), side: BorderSide(color: scheme.outlineVariant)),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface),
        ),
      ),
    );
  }
}

/// Switches between light and dark appearance.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => RotationTransition(turns: Tween(begin: 0.75, end: 1.0).animate(animation), child: FadeTransition(opacity: animation, child: child)),
        child: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, key: ValueKey(isDark)),
      ),
      onPressed: () => appThemeMode.value = isDark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}
