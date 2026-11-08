import 'dart:math' as math;

import 'number.dart';

// spec/shape.md: shapes are strokes with a `shape` object; `points` are made
// from it (`shape.points`). Drag to draw is `shape.fromDrag`.

const shapeKinds = ['triangle', 'rect', 'circle'];
const _step = 4.0;

bool _num(Object? v) => v is num && v.isFinite;

/// Whether [s] is a complete shape of a known kind (else it is kept as is and
/// its stroke is a plain stroke).
bool isKnownShape(Object? s) {
  if (s is! Map) return false;
  switch (s['kind']) {
    case 'triangle':
      final v = s['vertices'];
      return v is List &&
          v.length == 3 &&
          v.every(
            (p) => p is List && p.length >= 2 && _num(p[0]) && _num(p[1]),
          );
    case 'rect' || 'circle':
      return [
            'x',
            'y',
            'width',
            'height',
            'rotation',
          ].every((k) => _num(s[k])) &&
          (s['width'] as num) > 0 &&
          (s['height'] as num) > 0;
    default:
      return false;
  }
}

/// `shape.points`: the outline of [s] as `[x, y, 0.5, 16 * i]`, closed; null
/// for an unknown or incomplete shape.
List<List<num>>? shapePoints(Object? s) {
  if (!isKnownShape(s)) return null;
  s as Map;
  final raw = <(double, double)>[];
  void edge((double, double) a, (double, double) b) {
    final len = math.sqrt(math.pow(b.$1 - a.$1, 2) + math.pow(b.$2 - a.$2, 2));
    final n = math.max(1, (len / _step).ceil());
    for (var k = 0; k < n; k++) {
      raw.add((a.$1 + (b.$1 - a.$1) * k / n, a.$2 + (b.$2 - a.$2) * k / n));
    }
  }

  var rot = (double x, double y) => (x, y);
  if (s['kind'] == 'triangle') {
    final v = [
      for (final p in s['vertices'] as List)
        ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
    for (var i = 0; i < 3; i++) {
      edge(v[i], v[(i + 1) % 3]);
    }
  } else {
    final x = (s['x'] as num).toDouble(), y = (s['y'] as num).toDouble();
    final w = (s['width'] as num).toDouble(),
        h = (s['height'] as num).toDouble();
    final cx = x + w / 2, cy = y + h / 2;
    final r = (s['rotation'] as num) * math.pi / 180;
    final c = math.cos(r), sn = math.sin(r);
    rot = (px, py) => (
      cx + (px - cx) * c - (py - cy) * sn,
      cy + (px - cx) * sn + (py - cy) * c,
    );
    if (s['kind'] == 'rect') {
      final q = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)];
      for (var i = 0; i < 4; i++) {
        edge(q[i], q[(i + 1) % 4]);
      }
    } else {
      final a = w / 2, b = h / 2;
      final p = math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b)));
      final n = (p / _step).ceil().clamp(16, 256);
      for (var k = 0; k < n; k++) {
        final t = 2 * math.pi * k / n;
        raw.add((cx + a * math.cos(t), cy + b * math.sin(t)));
      }
    }
  }
  raw.add(raw.first);
  return [
    for (var i = 0; i < raw.length; i++)
      () {
        final (px, py) = rot(raw[i].$1, raw[i].$2);
        return <num>[round2(px), round2(py), 0.5, 16 * i];
      }(),
  ];
}

/// `shape.fromDrag`: the shape of a drag from [from] to [to], null when the
/// drag is under 4 pt on both axes.
Map<String, dynamic>? shapeFromDrag(
  String kind,
  List<num> from,
  List<num> to,
  bool lockRatio,
) {
  var dx = (to[0] - from[0]).toDouble(), dy = (to[1] - from[1]).toDouble();
  if (dx.abs() < 4 && dy.abs() < 4) return null;
  if (lockRatio) {
    final side = math.max(dx.abs(), dy.abs());
    dx = dx < 0 ? -side : side;
    dy = dy < 0 ? -side : side;
  }
  final x = math.min(from[0].toDouble(), from[0] + dx);
  final y = math.min(from[1].toDouble(), from[1] + dy);
  final w = dx.abs(), h = dy.abs();
  if (kind == 'triangle') {
    return {
      'kind': 'triangle',
      'vertices': [
        [round2(x + w / 2), round2(y)],
        [round2(x + w), round2(y + h)],
        [round2(x), round2(y + h)],
      ],
    };
  }
  if (kind != 'rect' && kind != 'circle') return null;
  return {
    'kind': kind,
    'x': round2(x),
    'y': round2(y),
    'width': round2(w),
    'height': round2(h),
    'rotation': 0,
  };
}

/// Moves, scales or turns a known [s] in place with the point map [f]
/// (spec/transform.md: the box center is mapped, size scales along the box's
/// own axes, `rotation` gets [turn] degrees). Returns false for an unknown one.
bool transformShape(
  Map s,
  (double, double) Function(double, double) f,
  double sx,
  double sy,
  double turn,
) {
  if (!isKnownShape(s)) return false;
  if (s['kind'] == 'triangle') {
    s['vertices'] = [
      for (final p in s['vertices'] as List)
        () {
          final (x, y) = f((p[0] as num).toDouble(), (p[1] as num).toDouble());
          return [round2(x), round2(y)];
        }(),
    ];
    return true;
  }
  final w = (s['width'] as num).toDouble() * sx;
  final h = (s['height'] as num).toDouble() * sy;
  if (round2(w) <= 0 || round2(h) <= 0) return false; // keep it valid
  final (cx, cy) = f(
    (s['x'] as num) + (s['width'] as num) / 2,
    (s['y'] as num) + (s['height'] as num) / 2,
  );
  s['x'] = round2(cx - w / 2);
  s['y'] = round2(cy - h / 2);
  s['width'] = round2(w);
  s['height'] = round2(h);
  s['rotation'] =
      round2((((s['rotation'] as num) + turn) % 360 + 360) % 360) % 360;
  return true;
}

double _dist(double ax, double ay, double bx, double by) =>
    math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));

double _segDist(double px, double py, List<double> a, List<double> b) {
  final dx = b[0] - a[0], dy = b[1] - a[1];
  final l2 = dx * dx + dy * dy;
  final t = l2 == 0
      ? 0.0
      : (((px - a[0]) * dx + (py - a[1]) * dy) / l2).clamp(0.0, 1.0);
  return _dist(px, py, a[0] + t * dx, a[1] + t * dy);
}

/// `shape.recognize` (spec/shape.md): the shape a held stroke is turned into,
/// or null when nothing fits.
Map<String, dynamic>? recognizeShape(List<List<num>> points) {
  // 1. Prepare.
  final p = <List<double>>[];
  for (final q in points) {
    final x = q[0].toDouble(), y = q[1].toDouble();
    if (p.isEmpty || _dist(x, y, p.last[0], p.last[1]) >= 0.01) p.add([x, y]);
  }
  if (p.length < 8) return null;
  // 2. Size and closing.
  var x0 = p[0][0], x1 = x0, y0 = p[0][1], y1 = y0;
  for (final q in p) {
    x0 = math.min(x0, q[0]);
    x1 = math.max(x1, q[0]);
    y0 = math.min(y0, q[1]);
    y1 = math.max(y1, q[1]);
  }
  final w = x1 - x0, h = y1 - y0, diag = math.sqrt(w * w + h * h);
  if (diag < 30) return null;
  if (_dist(p.first[0], p.first[1], p.last[0], p.last[1]) > 0.25 * diag) {
    return null;
  }
  final path = [...p, p.first];
  var len = 0.0;
  for (var i = 1; i < path.length; i++) {
    len += _dist(path[i - 1][0], path[i - 1][1], path[i][0], path[i][1]);
  }
  if (len < 1.8 * diag) return null;
  // 3. Resample into 64 points at equal arc length.
  final s = <List<double>>[];
  var seg = 1, acc = 0.0;
  for (var i = 0; i < 64; i++) {
    final target = len * i / 64;
    while (seg < path.length - 1 &&
        acc +
                _dist(
                  path[seg - 1][0],
                  path[seg - 1][1],
                  path[seg][0],
                  path[seg][1],
                ) <
            target) {
      acc += _dist(
        path[seg - 1][0],
        path[seg - 1][1],
        path[seg][0],
        path[seg][1],
      );
      seg++;
    }
    final a = path[seg - 1], b = path[seg];
    final sl = _dist(a[0], a[1], b[0], b[1]);
    final t = sl == 0 ? 0.0 : ((target - acc) / sl).clamp(0.0, 1.0);
    s.add([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
  }
  // 4. Fit.
  double rms(double Function(List<double>) f) =>
      math.sqrt(s.fold<double>(0, (m, q) => m + math.pow(f(q), 2)) / s.length);
  final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  final eCircle = (w > 0 && h > 0)
      ? rms(
          (q) => _dist((q[0] - cx) / (w / 2), (q[1] - cy) / (h / 2), 0, 0) - 1,
        )
      : double.infinity;
  final eRect =
      rms(
        (q) => [
          (q[0] - x0).abs(),
          (q[0] - x1).abs(),
          (q[1] - y0).abs(),
          (q[1] - y1).abs(),
        ].reduce(math.min),
      ) /
      diag;
  // Convex hull (monotone chain, collinear dropped) of S, indices kept.
  final idx = List.generate(64, (i) => i)
    ..sort((a, b) {
      final c = s[a][0].compareTo(s[b][0]);
      return c != 0 ? c : s[a][1].compareTo(s[b][1]);
    });
  double cross(int o, int a, int b) =>
      (s[a][0] - s[o][0]) * (s[b][1] - s[o][1]) -
      (s[a][1] - s[o][1]) * (s[b][0] - s[o][0]);
  List<int> half(Iterable<int> order) {
    final r = <int>[];
    for (final i in order) {
      while (r.length >= 2 && cross(r[r.length - 2], r.last, i) <= 0) {
        r.removeLast();
      }
      r.add(i);
    }
    return r..removeLast();
  }

  final hull = [...half(idx), ...half(idx.reversed)]..sort();
  var best = -1.0;
  var tri = <int>[];
  for (var i = 0; i < hull.length; i++) {
    for (var j = i + 1; j < hull.length; j++) {
      for (var k = j + 1; k < hull.length; k++) {
        final a = cross(hull[i], hull[j], hull[k]).abs();
        if (a > best) {
          best = a;
          tri = [hull[i], hull[j], hull[k]];
        }
      }
    }
  }
  final eTri = tri.length < 3
      ? double.infinity
      : rms(
              (q) => [
                for (var i = 0; i < 3; i++)
                  _segDist(q[0], q[1], s[tri[i]], s[tri[(i + 1) % 3]]),
              ].reduce(math.min),
            ) /
            diag;
  // 5. Choose: lowest score, circle, rect, triangle on ties.
  final scores = [eCircle / 0.10, eRect / 0.05, eTri / 0.05];
  var kind = 0;
  for (var i = 1; i < 3; i++) {
    if (scores[i] < scores[kind]) kind = i;
  }
  if (!(scores[kind] <= 1)) return null;
  // 6. Make the shape.
  if (kind == 2) {
    // Order along the path: tri is already in index order of S.
    return {
      'kind': 'triangle',
      'vertices': [
        for (final i in tri) [round2(s[i][0]), round2(s[i][1])],
      ],
    };
  }
  var bx = x0, by = y0, bw = w, bh = h;
  if (kind == 0 && (w - h).abs() <= 0.15 * math.max(w, h)) {
    bw = bh = (w + h) / 2;
    bx = cx - bw / 2;
    by = cy - bh / 2;
  }
  return {
    'kind': kind == 0 ? 'circle' : 'rect',
    'x': round2(bx),
    'y': round2(by),
    'width': round2(bw),
    'height': round2(bh),
    'rotation': 0,
  };
}
