import 'package:shared_preferences/shared_preferences.dart';

/// Light (default), Dark (UI only) or All Dark (UI, page and writing).
enum ThemeChoice { light, dark, allDark }

/// The theme choice lives on this device in SharedPreferences.
class ThemeStore {
  ThemeStore(this._prefs);

  /// Null when preferences could not be opened: the choice then lasts for
  /// this session only.
  final SharedPreferences? _prefs;

  static const _key = 'theme';

  ThemeChoice read() {
    String? name;
    try {
      name = _prefs?.getString(_key);
    } catch (_) {
      // A value of the wrong type is treated as no choice.
    }
    return ThemeChoice.values.asNameMap()[name] ?? ThemeChoice.light;
  }

  Future<void> write(ThemeChoice choice) async {
    try {
      await _prefs?.setString(_key, choice.name);
    } catch (_) {
      // Save failed: the choice still applies for this session.
    }
  }
}
