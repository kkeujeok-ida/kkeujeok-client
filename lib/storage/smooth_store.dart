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

  /// 0..[smoothMax]. An old build stored a name: it maps to a level.
  int read() {
    try {
      final v = _prefs?.get(_key);
      if (v is int) return v.clamp(0, smoothMax);
      return const {'light': 3, 'normal': 5, 'strong': 8}[v] ?? 0;
    } catch (_) {
      return 0; // a value of the wrong type is treated as unset
    }
  }

  Future<void> write(int v) async {
    try {
      await _prefs?.setInt(_key, v);
    } catch (_) {
      // Save failed: the level still applies for this session.
    }
  }
}
