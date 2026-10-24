import 'dart:math' as math;
import 'dart:ui' show Rect;

// spec rules select.lasso, select.tap, select.rect (spec/select.md) and the
// bounding box of spec/transform.md. Pure functions over raw element maps.

typedef P = (double, double);
typedef El = Map<String, dynamic>;

const _eps = 1e-9;

double _n(Object? v) => (v as num).toDouble();

bool _isStroke(El e) => e['type'] == 'stroke';

bool _isNum(Object? v) => v is num && v.isFinite;

// An element that cannot be judged (no id, a box without numeric geometry, a
// stroke with a malformed point) is ignored, never thrown on.
bool _usable(El e) {
  if (e['id'] is! String) return false;
  if (_isStroke(e)) {
    final pts = e['points'];
    return pts == null ||
        (pts is List &&
            pts.every(
              (p) => p is List && p.length >= 2 && _isNum(p[0]) && _isNum(p[1]),
            ));
  }
  return ['x', 'y', 'width', 'height'].every((k) => _isNum(e[k])) &&
      (e['rotation'] == null || _isNum(e['rotation']));
}

List<P> _points(El e) => [
  for (final p in (e['points'] as List? ?? const [])) (_n(p[0]), _n(p[1])),
];

/// The four corners of a box element after rotation, clockwise from top-left.
List<P> boxCorners(El e) {
  final x = _n(e['x']), y = _n(e['y']), w = _n(e['width']), h = _n(e['height']);
  final a = _n(e['rotation'] ?? 0) * math.pi / 180;
  final cx = x + w / 2, cy = y + h / 2;
  final c = math.cos(a), s = math.sin(a);
  return [
    for (final (px, py) in [(x, y), (x + w, y), (x + w, y + h), (x, y + h)])
      (cx + (px - cx) * c - (py - cy) * s, cy + (px - cx) * s + (py - cy) * c),
  ];
}

double _area(List<P> poly) {
  var s = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final (x0, y0) = poly[i];
    final (x1, y1) = poly[(i + 1) % poly.length];
    s += x0 * y1 - x1 * y0;
  }
  return s.abs() / 2;
}

bool _inPolygon(P p, List<P> poly) {
  final (px, py) = p;
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final (xi, yi) = poly[i];
    final (xj, yj) = poly[j];
    final cross = (xj - xi) * (py - yi) - (yj - yi) * (px - xi);
    if (cross.abs() <= _eps &&
        px >= math.min(xi, xj) - _eps &&
        px <= math.max(xi, xj) + _eps &&
        py >= math.min(yi, yj) - _eps &&
        py <= math.max(yi, yj) + _eps) {
      return true; // on the boundary
    }
    if ((yi > py) != (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

// Sutherland-Hodgman: [subject] clipped by the convex [clip].
List<P> _clip(List<P> subject, List<P> clip) {
  // Orientation of the clip decides which side is inside.
  var signed = 0.0;
  for (var i = 0; i < clip.length; i++) {
    final (x0, y0) = clip[i];
    final (x1, y1) = clip[(i + 1) % clip.length];
    signed += x0 * y1 - x1 * y0;
  }
  final k = signed >= 0 ? 1.0 : -1.0;
  var out = subject;
  for (var i = 0; i < clip.length && out.isNotEmpty; i++) {
    final (ax, ay) = clip[i];
    final (bx, by) = clip[(i + 1) % clip.length];
    double side(P p) => k * ((bx - ax) * (p.$2 - ay) - (by - ay) * (p.$1 - ax));
    final input = out;
    out = [];
    for (var j = 0; j < input.length; j++) {
      final cur = input[j], prev = input[(j + input.length - 1) % input.length];
      final dc = side(cur), dp = side(prev);
      if (dc >= 0) {
        if (dp < 0) out.add(_cut(prev, cur, dp, dc));
        out.add(cur);
      } else if (dp >= 0) {
        out.add(_cut(prev, cur, dp, dc));
      }
    }
  }
  return out;
}

P _cut(P a, P b, double da, double db) {
  final t = da / (da - db);
  return (a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t);
}

/// `select.lasso`: ids in array order.
List<String> selectLasso(List<El> elements, List<P> polygon) {
  if (polygon.length < 3 || _area(polygon) == 0) return [];
  final ids = <String>[];
  for (final e in elements.where(_usable)) {
    if (_isStroke(e)) {
      final pts = _points(e);
      if (pts.isEmpty) continue;
      final need = (pts.length + 1) ~/ 2;
      if (pts.where((p) => _inPolygon(p, polygon)).length >= need) {
        ids.add(e['id'] as String);
      }
    } else {
      final box = boxCorners(e);
      final area = _n(e['width']).abs() * _n(e['height']).abs();
      if (box.every((p) => _inPolygon(p, polygon)) ||
          (area > 0 && _area(_clip(polygon, box)) >= area * 0.5 - _eps)) {
        ids.add(e['id'] as String);
      }
    }
  }
  return ids;
}

double _segDist(P p, P a, P b) {
  final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
  final l2 = dx * dx + dy * dy;
  final t = l2 == 0
      ? 0.0
      : (((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / l2).clamp(0.0, 1.0);
  return math.sqrt(
    math.pow(p.$1 - (a.$1 + t * dx), 2) + math.pow(p.$2 - (a.$2 + t * dy), 2),
  );
}

/// `select.tap`: the topmost hit element id, or null.
String? selectTap(List<El> elements, P point, [double tolerance = 6]) {
  for (final e in elements.reversed.where(_usable)) {
    if (_isStroke(e)) {
      final pts = _points(e);
      if (pts.isEmpty) continue;
      final reach =
          (e['width'] is num ? _n(e['width']) : 0) / 2 + tolerance + _eps;
      var d = _segDist(point, pts.first, pts.first);
      for (var i = 0; i + 1 < pts.length; i++) {
        d = math.min(d, _segDist(point, pts[i], pts[i + 1]));
      }
      if (d <= reach) return e['id'] as String;
    } else {
      final w = _n(e['width']), h = _n(e['height']);
      final cx = _n(e['x']) + w / 2, cy = _n(e['y']) + h / 2;
      final a = -_n(e['rotation'] ?? 0) * math.pi / 180;
      final dx = point.$1 - cx, dy = point.$2 - cy;
      // Into the box's own axes.
      final lx = dx * math.cos(a) - dy * math.sin(a);
      final ly = dx * math.sin(a) + dy * math.cos(a);
      final ox = math.max(lx.abs() - w / 2, 0),
          oy = math.max(ly.abs() - h / 2, 0);
      if (math.sqrt(ox * ox + oy * oy) <= tolerance + _eps) {
        return e['id'] as String;
      }
    }
  }
  return null;
}

/// `select.rect`: [r] is x0, y0, x1, y1 in any corner order.
List<String> selectRect(List<El> elements, List<double> r) => selectLasso(
  elements,
  [(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])],
);

/// Union of the bounding boxes of [elements] (transform.md); null when none
/// has one.
Rect? selectionBounds(Iterable<El> elements) {
  Rect? out;
  for (final e in elements.where(_usable)) {
    final pts = _isStroke(e) ? _points(e) : boxCorners(e);
    if (pts.isEmpty) continue;
    var l = pts.first.$1, t = pts.first.$2, r = l, b = t;
    for (final (x, y) in pts) {
      l = math.min(l, x);
      r = math.max(r, x);
      t = math.min(t, y);
      b = math.max(b, y);
    }
    final box = Rect.fromLTRB(l, t, r, b);
    out = out == null ? box : out.expandToInclude(box);
  }
  return out;
}
