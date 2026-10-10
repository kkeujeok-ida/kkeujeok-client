import 'package:shared_preferences/shared_preferences.dart';

import '../model/note.dart';

const _orientations = {'portrait', 'landscape'};

/// Background and orientation of the note created last on this device.
/// A device setting (SharedPreferences), not note data: it survives log out
/// and disconnect.
class NewNoteDefaultsStore {
  NewNoteDefaultsStore(this._prefs);

  /// Null when preferences could not be opened: the values then last for this
  /// session only.
  final SharedPreferences? _prefs;

  static const _bgKey = 'newNoteBackground';
  static const _orKey = 'newNoteOrientation';

  // Set by write(): this run's choice wins even if persisting it failed.
  ({String background, String orientation})? _session;

  /// `plain`/`portrait` when nothing valid is stored.
  ({String background, String orientation}) read() {
    final session = _session;
    if (session != null) return session;
    try {
      final b = _prefs?.getString(_bgKey);
      final o = _prefs?.getString(_orKey);
      if (b != null || o != null) {
        return (
          background: backgrounds.contains(b) ? b! : 'plain',
          orientation: _orientations.contains(o) ? o! : 'portrait',
        );
      }
    } catch (_) {
      // A value of the wrong type is treated as nothing stored.
    }
    return (background: 'plain', orientation: 'portrait');
  }

  Future<void> write({
    required String background,
    required String orientation,
  }) async {
    _session = (background: background, orientation: orientation);
    try {
      await _prefs?.setString(_bgKey, background);
      await _prefs?.setString(_orKey, orientation);
    } catch (_) {
      // Save failed: the values still apply for this session.
    }
  }
}
