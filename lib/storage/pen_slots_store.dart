import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/eraser.dart';
import '../model/library_view.dart';
import '../model/page_view_mode.dart';
import '../model/pen.dart';
import '../model/pen_only.dart';
import '../model/pen_palette.dart';
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

  static const _viewModeKey = 'pageViewMode';

  PageViewMode? _viewModeSession;

  /// [PageViewMode.vertical] for a missing or invalid stored value.
  PageViewMode readViewMode() {
    final session = _viewModeSession;
    if (session != null) return session;
    try {
      return PageViewMode.parse(_prefs?.get(_viewModeKey));
    } catch (_) {
      return PageViewMode.vertical;
    }
  }

  Future<void> writeViewMode(PageViewMode m) {
    _viewModeSession = m;
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_viewModeKey, m.name);
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

  static const visibleToolsDefault = 7,
      visibleToolsMin = 3,
      visibleToolsMax = 12;
  static const _visibleKey = 'toolbarVisibleTools';

  int? _visibleSession;

  /// A number is rounded into 3..12; anything else is 7.
  static int clampVisibleTools(Object? v) => v is num && v.isFinite
      ? v.round().clamp(visibleToolsMin, visibleToolsMax)
      : visibleToolsDefault;

  /// How many tools the toolbar shows at once.
  int readVisibleTools() {
    final session = _visibleSession;
    if (session != null) return session;
    try {
      return clampVisibleTools(_prefs?.get(_visibleKey));
    } catch (_) {
      return visibleToolsDefault;
    }
  }

  Future<void> writeVisibleTools(int n) {
    n = clampVisibleTools(n);
    _visibleSession = n;
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setInt(_visibleKey, n);
      } catch (_) {
        // Save failed: the setting still applies for this session.
      }
    });
  }

  static const _viewKey = 'libraryView';
  LibraryView? _viewSession;

  /// How the note list is shown; [LibraryView.defaults] when nothing valid is stored.
  LibraryView readLibraryView() {
    final session = _viewSession;
    if (session != null) return session;
    try {
      return LibraryView.parse(_prefs?.get(_viewKey));
    } catch (_) {
      return LibraryView.defaults;
    }
  }

  Future<void> writeLibraryView(LibraryView v) {
    _viewSession = v;
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_viewKey, v.encode());
      } catch (_) {
        // Save failed: the choice still applies for this session.
      }
    });
  }

  static const _sortKey = 'librarySort';
  String? _sortSession;

  /// The stored sort name, or null when nothing valid is stored.
  String? readLibrarySort() {
    if (_sortSession != null) return _sortSession;
    try {
      final v = _prefs?.get(_sortKey);
      return v is String ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeLibrarySort(String name) {
    _sortSession = name;
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_sortKey, name);
      } catch (_) {
        // Save failed: the choice still applies for this session.
      }
    });
  }

  static const _folderColorKey = 'folderColors';
  Map<String, int>? _folderColorSession;

  /// Folder id to palette index. shortcut: color local per device, sync via
  /// folderOp/appProperties when needed.
  Map<String, int> readFolderColors() {
    if (_folderColorSession != null) return _folderColorSession!;
    try {
      final v = _prefs?.get(_folderColorKey);
      if (v is String) {
        return {
          for (final e in (jsonDecode(v) as Map).entries)
            if (e.value is int) e.key as String: e.value as int,
        };
      }
    } catch (_) {}
    return {};
  }

  Future<void> writeFolderColors(Map<String, int> m) {
    _folderColorSession = m;
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_folderColorKey, jsonEncode(m));
      } catch (_) {
        // Save failed: the choice still applies for this session.
      }
    });
  }

  static const paletteMax = 18; // 3 rows of 6
  static const _paletteKey = 'penPalette';

  // Lists written by this run, per tool; they win even if persisting failed.
  final Map<String, List<String>> _paletteSession = {};

  static List<String> defaultPalette(String tool) => [
    for (final c in paletteFor(tool)) c.hex,
  ];

  /// 1..18 distinct `#rrggbb` (lowercased), else null.
  static List<String>? validPalette(Object? v) {
    if (v is! List || v.isEmpty || v.length > paletteMax) return null;
    if (!v.every((e) => e is String && _hex.hasMatch(e))) return null;
    final list = [for (final e in v) (e as String).toLowerCase()];
    return list.toSet().length == list.length ? list : null;
  }

  Map<String, Object?> _storedPalettes() {
    try {
      final raw = _prefs?.getString(_paletteKey);
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map) return m.cast<String, Object?>();
      }
    } catch (_) {
      // Wrong type or shape: treated as nothing stored.
    }
    return {};
  }

  /// The tool's palette; the default when nothing valid is stored.
  List<String> readPalette(String tool) =>
      _paletteSession[tool] ??
      validPalette(_storedPalettes()[tool]) ??
      defaultPalette(tool);

  /// An invalid list is ignored. Null [colors] resets to the default.
  Future<void> writePalette(String tool, List<String>? colors) {
    final list = colors == null ? defaultPalette(tool) : validPalette(colors);
    if (list == null) return _pending;
    _paletteSession[tool] = list;
    final all = _storedPalettes();
    if (colors == null) {
      all.remove(tool);
    } else {
      all[tool] = list;
    }
    final data = jsonEncode(all);
    return _pending = _pending.then((_) async {
      try {
        await _prefs?.setString(_paletteKey, data);
      } catch (_) {
        // Save failed: the palette still applies for this session.
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
