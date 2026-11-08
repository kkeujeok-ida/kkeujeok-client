import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/pressure_curve.dart';

/// The pressure curve lives on this device in SharedPreferences (a preset
/// name, or the four values as JSON). Not synced, not in the note.
class PressureCurveStore {
  PressureCurveStore(this._prefs);

  /// Null when preferences could not be opened: the choice then lasts for
  /// this session only.
  final SharedPreferences? _prefs;

  static const _key = 'pressureCurve';

  /// A missing, wrong-typed or invalid value is `normal`.
  PressureCurve read() {
    try {
      final raw = _prefs?.getString(_key);
      if (raw == null) return PressureCurve.normal;
      return PressureCurve.fromJson(jsonDecode(raw));
    } catch (_) {
      return PressureCurve.normal;
    }
  }

  Future<void> write(PressureCurve c) async {
    try {
      await _prefs?.setString(_key, jsonEncode(c.preset ?? c.values));
    } catch (_) {
      // Save failed: the choice still applies for this session.
    }
  }
}
