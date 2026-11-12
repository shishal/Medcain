import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_mode_provider.g.dart';

const _themeModePrefKey = 'theme_mode';

/// Persisted System / Light / Dark. Light is the default until the student
/// picks something else.
@Riverpod(keepAlive: true)
class ThemeModeNotifier extends _$ThemeModeNotifier {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.light;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeModePrefKey);
    if (raw == null) return;
    final mode = fromName(raw);
    if (mode != state) state = mode;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePrefKey, mode.name);
  }

  /// Kept for tests that still cycle; UI uses [setMode].
  Future<void> cycle() async {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setMode(next);
  }

  static ThemeMode fromName(String raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.light,
    };
  }
}
