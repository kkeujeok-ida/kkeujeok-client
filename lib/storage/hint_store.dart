import 'package:shared_preferences/shared_preferences.dart';

/// Which one-line hints are used up on this device (SharedPreferences).
enum Hint { firstNote, penEdit }

class HintStore {
  HintStore(this._prefs);

  /// Null when preferences could not be opened: a hint then lasts for this
  /// session only.
  final SharedPreferences? _prefs;

  String _key(Hint h) => 'hintDone.${h.name}';

  bool done(Hint h) {
    try {
      return _prefs?.getBool(_key(h)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markDone(Hint h) async {
    try {
      await _prefs?.setBool(_key(h), true);
    } catch (_) {
      // Save failed: the hint is gone for this session only.
    }
  }
}
