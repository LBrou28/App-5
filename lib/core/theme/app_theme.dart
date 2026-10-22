import 'package:flutter/material.dart';

/// App-wide appearance setting. Starts by following the device; the toggle
/// button switches to an explicit light or dark mode for this session.
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.system);

class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xff176b87);

  static ThemeData light() => _build(ColorScheme.fromSeed(seedColor: seed));
  static ThemeData dark() => _build(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark));

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = base.textTheme;
    final rounded12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        scrolledUnderElevation: 2,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.primary, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), textStyle: const TextStyle(fontWeight: FontWeight.w600))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerHigh, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      popupMenuTheme: PopupMenuThemeData(shape: rounded12, color: scheme.surfaceContainer),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: rounded12),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      chipTheme: ChipThemeData(shape: const StadiumBorder(), side: BorderSide(color: scheme.outlineVariant)),
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
