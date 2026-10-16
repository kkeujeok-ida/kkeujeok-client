import 'number.dart';

/// Highest `formatVersion` this client reads and writes.
const supportedFormatVersion = 1;

const backgrounds = {'plain', 'lined', 'grid', 'dot'};

enum ReadStatus { ok, unsupportedVersion, unreadable }

/// Outcome of reading a note file (spec `note.formatVersion`).
class NoteReadResult {
  const NoteReadResult(this.status, [this.note]);
  final ReadStatus status;
  final Note? note;

  /// Only an ok note may be written back.
  bool get writable => status == ReadStatus.ok;
}

/// A note as the original JSON map, so fields this client does not know ride
/// along untouched. Treat as immutable: ops work on [copyJson] copies.
class Note {
  Note._(this._json);

  /// Wraps a map an op built; no validation, no copy.
  factory Note.trusted(Map<String, dynamic> json) = Note._;

  final Map<String, dynamic> _json;

  /// Validates [json] (spec `note.formatVersion`, steps 1-3) and wraps a deep
  /// copy of it. Numbers are not rounded here.
  static NoteReadResult parse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return const NoteReadResult(ReadStatus.unreadable);
    }
    final v = json['formatVersion'];
    if (_isInt(v) && (v as num) > supportedFormatVersion) {
      return const NoteReadResult(ReadStatus.unsupportedVersion);
    }
    if (!_validNote(json)) return const NoteReadResult(ReadStatus.unreadable);
    return NoteReadResult(
      ReadStatus.ok,
      Note._(_copy(json) as Map<String, dynamic>),
    );
  }

  String get noteId => _json['noteId'] as String;
  String get orderRev => _json['orderRev'] as String;
  String get metaRev => _json['metaRev'] as String;
  String get title => (_json['meta'] as Map)['title'] as String;

  /// Do not modify.
  List<Map<String, dynamic>> get pages =>
      (_json['pages'] as List).cast<Map<String, dynamic>>();

  /// Exact deep copy, free to mutate.
  Map<String, dynamic> copyJson() => _copy(_json) as Map<String, dynamic>;

  /// What gets written: a deep copy with every defined number through round2.
  Map<String, dynamic> toJson() {
    final j = copyJson();
    for (final k in const ['metaSeq', 'orderSeq']) {
      j[k] = _round(j[k]);
    }
    for (final p in (j['pages'] as List).cast<Map<String, dynamic>>()) {
      for (final k in const ['width', 'height', 'seq']) {
        p[k] = _round(p[k]);
      }
      for (final e in p['elements'] as List) {
        if (e is Map<String, dynamic> && e['type'] == 'stroke') roundStroke(e);
      }
    }
    return j;
  }
}

/// Rounds the defined numbers of a stroke in place (`width`, every point).
void roundStroke(Map<String, dynamic> s) {
  s['width'] = _round(s['width']);
  s['points'] = [
    for (final p in s['points'] as List) [for (final n in p as List) _round(n)],
  ];
}

/// Deep equality of two JSON values; key order does not matter and numbers
/// compare by value (1 equals 1.0).
bool jsonEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && jsonEqual(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => jsonEqual(a[i], b[i]));
  }
  return a == b;
}

/// Deep copy of a JSON value.
Object? copyJsonValue(Object? v) => _copy(v);

Object? _copy(Object? v) => v is Map
    ? {for (final e in v.entries) e.key as String: _copy(e.value)}
    : v is List
    ? [for (final e in v) _copy(e)]
    : v;

Object? _round(Object? v) {
  if (v is! double) return v;
  final r = round2(v);
  return r == r.truncateToDouble() && r.abs() < 1e15 ? r.toInt() : r;
}

bool _isInt(Object? v) => v is num && v.isFinite && v == v.truncateToDouble();
bool _isStr(Object? v) => v is String;

bool _validNote(Map<String, dynamic> m) {
  if (!_isInt(m['formatVersion']) || (m['formatVersion'] as num) < 1) {
    return false;
  }
  final meta = m['meta'];
  if (meta is! Map<String, dynamic> || !_isStr(meta['title'])) return false;
  if (meta.containsKey('coverId') && !_isStr(meta['coverId'])) return false;
  final pages = m['pages'];
  return _isStr(m['noteId']) &&
      _isStr(m['metaRev']) &&
      _isInt(m['metaSeq']) &&
      _isStr(m['orderRev']) &&
      _isInt(m['orderSeq']) &&
      pages is List &&
      pages.every(_validPage);
}

bool _validPage(Object? p) {
  if (p is! Map<String, dynamic>) return false;
  final w = p['width'], h = p['height'], els = p['elements'];
  return _isStr(p['id']) &&
      w is num &&
      w > 0 &&
      h is num &&
      h > 0 &&
      backgrounds.contains(p['background']) &&
      _isStr(p['rev']) &&
      _isInt(p['seq']) &&
      _isStr(p['editedAt']) &&
      _isStr(p['editedBy']) &&
      els is List &&
      els.every(_validElement);
}

/// True for a well-formed element of `type: "stroke"`.
bool isValidStroke(Object? e) =>
    e is Map<String, dynamic> && e['type'] == 'stroke' && _validElement(e);

bool _validElement(Object? e) {
  if (e is! Map<String, dynamic> || !_isStr(e['id']) || !_isStr(e['type'])) {
    return false;
  }
  if (e['type'] != 'stroke') return true;
  final pts = e['points'];
  return e['tool'] == 'pen' &&
      _isStr(e['color']) &&
      e['width'] is num &&
      e['usePressure'] is bool &&
      pts is List &&
      pts.every((p) => p is List && p.length == 4 && p.every((n) => n is num));
}
