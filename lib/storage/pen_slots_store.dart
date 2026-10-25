import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/eraser.dart';
import '../model/pen.dart';
import '../model/pen_only.dart';
import '../model/toolbar_pos.dart';

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
        if (list is List && list.isNotEmpty && list.length <= maxPenSlots) {
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
    final tool = m['tool'] ?? 'pen'; // saved before highlighters: a pen
    final color = m['color'], width = m['width'], up = m['usePressure'];
    if (tool != 'pen' && tool != 'highlighter') {
      throw const FormatException();
    }
    final (lo, hi) = penWidthRange(tool as String);
    if (color is! String || !_hex.hasMatch(color)) {
      throw const FormatException();
    }
    if (width is! num || !(width >= lo && width <= hi)) {
      throw const FormatException();
    }
    if (up is! bool) throw const FormatException();
    return Pen(
      tool: tool,
      color: color,
      width: width.toDouble(),
      usePressure: up,
    );
  }

  static const _recentKey = 'penRecentColors';
  static const maxRecent = 6;

  List<String>? _recentSession;

  /// Recent colors, newest first; empty when nothing valid is stored.
  List<String> readRecent() {
    final session = _recentSession;
    if (session != null) return session;
    try {
      final raw = _prefs?.getString(_recentKey);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List &&
            list.length <= maxRecent &&
            list.every((e) => e is String && _hex.hasMatch(e))) {
          return [for (final e in list) (e as String).toLowerCase()];
        }
      }
    } catch (_) {
      // Wrong type or shape: treated as nothing stored.
    }
    return const [];
  }

  Future<void> writeRecent(List<String> colors) {
    _recentSession = List.unmodifiable(colors);
    final data = jsonEncode(colors);
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_recentKey, data);
      } catch (_) {
        // Save failed: the list still applies for this session.
      }
    });
  }

  static const _modeKey = 'eraserMode';
  static const _returnKey = 'eraserReturnToPen';

  EraserSettings? _eraserSession;

  /// Defaults for a missing or invalid stored value.
  EraserSettings readEraser() {
    final session = _eraserSession;
    if (session != null) return session;
    try {
      final mode = _prefs?.getString(_modeKey);
      final back = _prefs?.get(_returnKey);
      return EraserSettings(
        mode: mode == 'partial' ? EraserMode.partial : EraserMode.stroke,
        returnToPen: back == true,
      );
    } catch (_) {
      return const EraserSettings();
    }
  }

  Future<void> writeEraser(EraserSettings s) {
    _eraserSession = s;
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_modeKey, s.mode.name);
        await _prefs?.setBool(_returnKey, s.returnToPen);
      } catch (_) {
        // Save failed: the setting still applies for this session.
      }
    });
  }

  static const _penOnlyKey = 'penOnlyMode';
  static const _seenKey = 'stylusSeen';

  PenOnlyMode? _penOnlySession;
  bool? _seenSession;

  /// [PenOnlyMode.auto] for a missing or invalid stored value.
  PenOnlyMode readPenOnly() {
    final session = _penOnlySession;
    if (session != null) return session;
    try {
      return PenOnlyMode.parse(_prefs?.getString(_penOnlyKey));
    } catch (_) {
      return PenOnlyMode.auto;
    }
  }

  Future<void> writePenOnly(PenOnlyMode m) {
    _penOnlySession = m;
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_penOnlyKey, m.name);
      } catch (_) {
        // Save failed: the setting still applies for this session.
      }
    });
  }

  /// Whether a stylus was ever seen on this device; false if unknown.
  bool readStylusSeen() {
    final session = _seenSession;
    if (session != null) return session;
    try {
      return _prefs?.get(_seenKey) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> writeStylusSeen(bool v) {
    _seenSession = v;
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setBool(_seenKey, v);
      } catch (_) {
        // Save failed: the record still applies for this session.
      }
    });
  }

  static const _toolbarKey = 'toolbarPos';

  ToolbarPos? _toolbarSession;

  /// [ToolbarPos.defaults] for a missing or invalid stored value.
  ToolbarPos readToolbar() {
    final session = _toolbarSession;
    if (session != null) return session;
    try {
      final raw = _prefs?.getString(_toolbarKey);
      return raw == null
          ? ToolbarPos.defaults
          : ToolbarPos.parse(jsonDecode(raw));
    } catch (_) {
      return ToolbarPos.defaults;
    }
  }

  Future<void> writeToolbar(ToolbarPos pos) {
    _toolbarSession = pos;
    final data = jsonEncode(pos.toJson());
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_toolbarKey, data);
      } catch (_) {
        // Save failed: the position still applies for this session.
      }
    });
  }
}
