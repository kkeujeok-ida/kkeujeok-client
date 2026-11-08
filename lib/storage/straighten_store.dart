import 'package:shared_preferences/shared_preferences.dart';

/// Line straightening on/off lives on this device in SharedPreferences
/// (default off); not in the note, not synced.
class StraightenStore {
  StraightenStore(this._prefs);

  /// Null when preferences could not be opened: the flag then lasts for this
  /// session only.
  final SharedPreferences? _prefs;

  static const _key = 'straighten';

  bool read() {
    try {
      return _prefs?.getBool(_key) ?? false;
    } catch (_) {
      return false; // a value of the wrong type is treated as unset
    }
  }

  Future<void> write(bool v) async {
    try {
      await _prefs?.setBool(_key, v);
    } catch (_) {
      // Save failed: the flag still applies for this session.
    }
  }
}
