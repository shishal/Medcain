import 'package:material_ui/material_ui.dart';

import 'comic_colors.dart';
import 'spacing.dart';

/// Material 3 + MEDCAIN blue chrome on charcoal. Docci stays in brand assets.
abstract final class AppTheme {
  /// Brand blue (logo mid-gradient) — CTAs, filled buttons, chrome.
  static const Color seedColor = Color(0xFF008FD6);

  /// Deeper blue for urgent actions (timer-low / submit).
  static const Color accentUrgent = Color(0xFF0072BC);

  /// Dark native/Flutter splash canvas — matches logo black field.
  static const Color splashCanvas = Color(0xFF000000);

  /// Light native/Flutter splash canvas — matches [ComicColors.light.paper].
  static const Color splashCanvasLight = Color(0xFFF4F4F5);

  /// Splash canvas for the active theme polarity.
  static Color splashCanvasFor(Brightness brightness) =>
      brightness == Brightness.dark ? splashCanvas : splashCanvasLight;

  static const double cardRadius = 22;

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final comic = brightness == Brightness.dark
        ? ComicColors.dark
        : ComicColors.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    ).copyWith(
      surface: comic.paper,
      surfaceContainerLowest: comic.paper,
      surfaceContainerLow: comic.sticker,
      surfaceContainer: comic.sticker,
      surfaceContainerHigh: comic.stickerLift,
      surfaceContainerHighest: comic.stickerLift,
      primary: seedColor,
      onPrimary: Colors.white,
      secondary: comic.accentPurple,
      onSecondary: Colors.white,
      tertiary: comic.proGold,
      surfaceTint: seedColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: comic.paper,
      extensions: [comic],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: comic.paper,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: brightness == Brightness.dark ? 6 : 2,
        color: comic.sticker,
        shadowColor: comic.shadow,
        surfaceTintColor: seedColor.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: comic.sticker,
        indicatorColor: seedColor.withValues(alpha: 0.22),
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md,
          ),
          shape: const StadiumBorder(),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seedColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: comic.sticker,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.md,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
      ),
    );
  }
}

/// Access the urgent accent without sprinkling the raw color through widgets.
extension AppThemeExtension on ThemeData {
  Color get urgentAccent => AppTheme.accentUrgent;
}
