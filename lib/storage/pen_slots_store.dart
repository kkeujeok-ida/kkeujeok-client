import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/pen.dart';

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// The pen slot list on this device. A device setting (SharedPreferences),
/// not note data: it survives log out and disconnect.
class PenSlotsStore {
  PenSlotsStore(this._prefs);

  /// Null when preferences could not be opened: the list then lasts for this
  /// session only.
  final SharedPreferences? _prefs;

  static const _key = 'penSlots';

  // Set by write(): this run's choice wins even if persisting it failed.
  List<Pen>? _session;

  /// [defaultPenSlots] when nothing valid is stored.
  List<Pen> read() {
    final session = _session;
    if (session != null) return session;
    try {
      final raw = _prefs?.getString(_key);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List && list.isNotEmpty) {
          return [for (final e in list) _pen(e)];
        }
      }
    } catch (_) {
      // Wrong type or shape: treated as nothing stored.
    }
    return defaultPenSlots;
  }

  // Writes run one after another, so rapid toggles end with the last value.
  Future<void> _pending = Future.value();

  Future<void> write(List<Pen> slots) {
    _session = List.unmodifiable(slots);
    final data = jsonEncode([for (final p in slots) p.toJson()]);
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_key, data);
      } catch (_) {
        // Save failed: the list still applies for this session.
      }
    });
  }

  // Throws on any invalid field; read() turns that into the default.
  static Pen _pen(Object? e) {
    final m = e as Map;
    final color = m['color'], width = m['width'], up = m['usePressure'];
    if (color is! String || !_hex.hasMatch(color)) throw const FormatException();
    if (width is! num || !(width >= 0.5 && width <= 10)) {
      throw const FormatException();
    }
    if (up is! bool) throw const FormatException();
    return Pen(
      color: color,
      width: width.toDouble(),
      usePressure: up,
      colorNameKey: 'black',
    );
  }
}
