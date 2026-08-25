import 'package:flutter/material.dart';

/// Original visual identity. Deliberately not modelled on any commercial PDF
/// product's interface (brief section 9).
abstract final class AppTheme {
  static const Color _seed = Color(0xFF2F5D62);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // Accessibility: 48dp minimum touch target (brief section 35).
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
      focusColor: scheme.primary.withValues(alpha: 0.24),
    );
  }
}
