import 'package:flutter/material.dart';

/// Original visual identity. Deliberately not modelled on any commercial PDF
/// product's interface (brief section 9).
///
/// No font is bundled and none is fetched. A downloaded typeface would breach
/// the no-network rule, and a bundled one costs megabytes and a licence entry
/// for a gain the system font mostly already delivers. What is shaped instead
/// is the SCALE: sizes, weights, line height and letter spacing. Stock Material
/// looks generic mainly because those are left at their defaults.
abstract final class AppTheme {
  static const Color _seed = Color(0xFF2F5D62);

  /// One spacing step. Every gap in the app should be a multiple of this, so
  /// spacing reads as rhythm rather than as a series of unrelated guesses.
  static const double space = 8;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final text = _typography(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: text,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // Accessibility: 48dp minimum touch target (brief section 35).
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          textStyle: text.labelLarge,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: space + 4,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      focusColor: scheme.primary.withValues(alpha: 0.24),

      // A document app should feel like paper on a desk: quiet surfaces, one
      // accent, and no floating shadows competing with the page itself.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 1,
        titleTextStyle: text.titleLarge,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
      ),
      dividerTheme: DividerThemeData(
        space: space * 2,
        thickness: 1,
        color: scheme.outlineVariant,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(space * 1.5),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(space * 3),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(space * 1.5),
        ),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(space * 1.5),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }

  /// A deliberate scale rather than Material's defaults.
  ///
  /// Two changes carry most of the effect. Large text gets NEGATIVE letter
  /// spacing — headings set at default tracking are the clearest tell of an
  /// unstyled app. Body text gets a 1.45 line height, because this is an app
  /// for reading documents and Material's default is tight for prose.
  static TextTheme _typography(ColorScheme scheme) {
    final base = Typography.material2021(colorScheme: scheme).black;
    final tinted = scheme.brightness == Brightness.dark
        ? Typography.material2021(colorScheme: scheme).white
        : base;

    return tinted.copyWith(
      headlineSmall: tinted.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      titleLarge: tinted.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleMedium: tinted.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      bodyLarge: tinted.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: tinted.bodyMedium?.copyWith(height: 1.45),
      bodySmall: tinted.bodySmall?.copyWith(height: 1.4),
      // Section headings and buttons: slightly wider tracking is what makes
      // small text read as a label rather than as shrunken prose.
      labelLarge: tinted.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      labelSmall: tinted.labelSmall?.copyWith(letterSpacing: 0.5),
    );
  }
}
