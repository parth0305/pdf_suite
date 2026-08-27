import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/data/local/preferences_dao.dart';

/// Overridden at app start; reading it unoverridden is a programming error.
final preferencesDaoProvider = Provider<PreferencesDao>(
  (ref) =>
      throw UnimplementedError('preferencesDaoProvider must be overridden'),
);

const _themeKey = 'themeMode';

/// The user's chosen theme, defaulting to whatever the system asks for.
class ThemeModeSetting extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final stored = await ref.read(preferencesDaoProvider).read(_themeKey);

    // An unrecognised value falls back rather than throwing: a preferences row
    // written by a newer build must not stop the app from starting.
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = AsyncValue.data(mode);
    await ref.read(preferencesDaoProvider).write(_themeKey, mode.name);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeSetting, ThemeMode>(
  ThemeModeSetting.new,
);
