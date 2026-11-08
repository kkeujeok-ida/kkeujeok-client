import 'package:shared_preferences/shared_preferences.dart';

import '../model/smooth.dart';

/// The stroke smoothing level lives on this device in SharedPreferences
/// (default off); not in the note, not synced.
class SmoothStore {
  SmoothStore(this._prefs);

  /// Null when preferences could not be opened: the level then lasts for this
  /// session only.
  final SharedPreferences? _prefs;

  static const _key = 'smooth';

  SmoothLevel read() {
    try {
      final v = _prefs?.getString(_key);
      return SmoothLevel.values.where((l) => l.name == v).firstOrNull ??
          SmoothLevel.off;
    } catch (_) {
      return SmoothLevel.off; // a value of the wrong type is treated as unset
    }
  }

  Future<void> write(SmoothLevel v) async {
    try {
      await _prefs?.setString(_key, v.name);
    } catch (_) {
      // Save failed: the level still applies for this session.
    }
  }
}
