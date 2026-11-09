import 'dart:math' as math;

import 'shape.dart' show denseOf;

// spec/erase.md: eraser settings and the pure touch / split rules.

enum EraserMode { stroke, partial }

class EraserSettings {
  const EraserSettings({
    this.mode = EraserMode.stroke,
    this.returnToPen = false,
  });

  final EraserMode mode;
  final bool returnToPen;

  EraserSettings copyWith({EraserMode? mode, bool? returnToPen}) =>
      EraserSettings(
        mode: mode ?? this.mode,
        returnToPen: returnToPen ?? this.returnToPen,
      );

  @override
  bool operator ==(Object other) =>
      other is EraserSettings &&
      other.mode == mode &&
      other.returnToPen == returnToPen;

  @override
  int get hashCode => Object.hash(mode, returnToPen);
}

/// Device default eraser diameter in page pt (a device setting, not in the note).
const eraserDefaultWidth = 12.0;

/// Rounded once to 0.1 (half away from zero); null when outside 2..40.
double? roundEraserWidth(Object? w) {
  if (w is! num || !w.isFinite || w.abs() > 1000) return null;
  final r = (w * 10).round() / 10;
  return r >= 2 && r <= 40 ? r : null;
}

typedef Pt = (double, double);

const _eps = 1e-9;

double _dist(Pt a, Pt b) =>
    math.sqrt((a.$1 - b.$1) * (a.$1 - b.$1) + (a.$2 - b.$2) * (a.$2 - b.$2));

double pointSegDist(Pt p, Pt a, Pt b) {
  final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
  final l2 = dx * dx + dy * dy;
  if (l2 == 0) return _dist(p, a);
  final t = (((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / l2).clamp(0.0, 1.0);
  return _dist(p, (a.$1 + t * dx, a.$2 + t * dy));
}

double _cross(Pt o, Pt a, Pt b) =>
    (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);

bool _cross2(Pt a, Pt b, Pt c, Pt d) {
  final d1 = _cross(c, d, a), d2 = _cross(c, d, b);
  final d3 = _cross(a, b, c), d4 = _cross(a, b, d);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// Distance between two segments (0 when they cross).
double segSegDist(Pt a, Pt b, Pt c, Pt d) {
  if (_cross2(a, b, c, d)) return 0;
  return math.min(
    math.min(pointSegDist(a, c, d), pointSegDist(b, c, d)),
    math.min(pointSegDist(c, a, b), pointSegDist(d, a, b)),
  );
}

double _pointPathDist(Pt p, List<Pt> path) {
  if (path.length == 1) return _dist(p, path[0]);
  var m = double.infinity;
  for (var i = 0; i + 1 < path.length; i++) {
    m = math.min(m, pointSegDist(p, path[i], path[i + 1]));
  }
  return m;
}

double _segPathDist(Pt a, Pt b, List<Pt> path) {
  if (path.length == 1) return pointSegDist(path[0], a, b);
  var m = double.infinity;
  for (var i = 0; i + 1 < path.length; i++) {
    m = math.min(m, segSegDist(a, b, path[i], path[i + 1]));
  }
  return m;
}

/// Which stroke points the eraser path (radius [r]) touches.
List<bool> touchedPoints(List<Pt> pts, List<Pt> path, double r) => [
  for (final p in pts) _pointPathDist(p, path) <= r + _eps,
];

/// Which segments `i -> i+1` the path touches (length `pts.length - 1`).
List<bool> touchedSegments(List<Pt> pts, List<Pt> path, double r) => [
  for (var i = 0; i + 1 < pts.length; i++)
    _segPathDist(pts[i], pts[i + 1], path) <= r + _eps,
];

/// Index lists of the pieces left after erasing; pieces of one point are dropped.
List<List<int>> splitPieces(List<Pt> pts, List<Pt> path, double r) {
  final tp = touchedPoints(pts, path, r);
  final ts = touchedSegments(pts, path, r);
  final out = <List<int>>[];
  var cur = <int>[];
  void flush() {
    if (cur.length >= 2) out.add(cur);
    cur = [];
  }

  for (var i = 0; i < pts.length; i++) {
    if (tp[i]) {
      flush();
      continue;
    }
    if (cur.isNotEmpty && ts[i - 1]) flush();
    cur.add(i);
  }
  flush();
  return out;
}

/// The live eraser preview of a page's [elements]: each struck stroke stays in
/// place (its id in `fade`, drawn translucent) and, in partial mode, its
/// surviving pieces follow it (opaque, ids `<id>~<j>`). Same touch/split rules
/// as the `eraseStrokes`/`erasePartial` ops. Story 15.8 may make it incremental.
({List<Object?> elements, Set<String> fade}) eraseTargets(
  List elements,
  List<Pt> path,
  double r,
  bool partial,
) {
  final out = <Object?>[];
  final fade = <String>{};
  if (path.isEmpty) return (elements: List.of(elements), fade: fade);
  var x0 = double.infinity, x1 = -double.infinity;
  var y0 = double.infinity, y1 = -double.infinity;
  for (final p in path) {
    if (p.$1 < x0) x0 = p.$1;
    if (p.$1 > x1) x1 = p.$1;
    if (p.$2 < y0) y0 = p.$2;
    if (p.$2 > y1) y1 = p.$2;
  }
  x0 -= r;
  x1 += r;
  y0 -= r;
  y1 += r;
  for (final e in elements) {
    // A stroke whose box is farther than r from the path's box cannot be touched.
    final tw = e is Map && e['tool'] == 'tape'
        ? ((e['width'] as num?)?.toDouble() ?? 0) / 2
        : 0.0;
    final pts =
        e is Map &&
            e['type'] == 'stroke' &&
            _boxNear(e, x0 - tw, x1 + tw, y0 - tw, y1 + tw)
        ? _strokePts(e)
        : null;
    // A tape is touched by its whole band (center line + width / 2).
    final er = pts != null && e is Map && e['tool'] == 'tape'
        ? r + ((e['width'] as num?)?.toDouble() ?? 0) / 2
        : r;
    if (pts == null ||
        !(touchedPoints(pts, path, er).any((t) => t) ||
            touchedSegments(pts, path, er).any((t) => t))) {
      out.add(e);
      continue;
    }
    final m = e as Map;
    fade.add(m['id'] as String);
    out.add(e);
    if (!partial || m['tool'] == 'tape') continue;
    final entries = denseOf(m) as List;
    var j = 0;
    for (final piece in splitPieces(pts, path, r)) {
      out.add({
        for (final en in m.entries)
          if (en.key != 'shape') en.key: en.value, // a piece is a plain stroke
        'id': '${m['id']}~${j++}',
        'points': [for (final k in piece) entries[k]],
      });
    }
  }
  return (elements: out, fade: fade);
}

bool _boxNear(Map e, double x0, double x1, double y0, double y1) {
  final pts = e['points'];
  if (pts is! List || pts.isEmpty || e['id'] is! String) return false;
  var a = double.infinity, b = -double.infinity;
  var c = double.infinity, d = -double.infinity;
  for (final p in pts) {
    if (p is! List || p.length < 2 || p[0] is! num || p[1] is! num) {
      return false;
    }
    final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
    if (x < a) a = x;
    if (x > b) b = x;
    if (y < c) c = y;
    if (y > d) d = y;
  }
  return a <= x1 && b >= x0 && c <= y1 && d >= y0;
}

List<Pt>? _strokePts(Map e) {
  final pts = denseOf(e);
  if (pts is! List || pts.isEmpty || e['id'] is! String) return null;
  final out = <Pt>[];
  for (final p in pts) {
    if (p is! List || p.length < 2 || p[0] is! num || p[1] is! num) return null;
    out.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
  }
  return out;
}
