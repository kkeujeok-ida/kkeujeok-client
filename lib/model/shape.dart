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
/// or null when nothing fits. [tilted] (`shape.recognizeTilted`) fits the
/// rect as an oriented one.
Map<String, dynamic>? recognizeShape(
  List<List<num>> points, {
  bool tilted = false,
}) {
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
  if (_dist(p.first[0], p.first[1], p.last[0], p.last[1]) > 0.30 * diag) {
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
  var eRect =
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
  // Oriented rect: least area around the hull (rotating calipers), the angle
  // folded to [0, 90); within 4 degrees of an axis it is the bounding box.
  var rcx = cx, rcy = cy, rw = w, rh = h, rrot = 0.0;
  if (tilted && hull.length >= 3) {
    var bestArea = double.infinity;
    for (var i = 0; i < hull.length; i++) {
      final a = s[hull[i]], b = s[hull[(i + 1) % hull.length]];
      final deg = math.atan2(b[1] - a[1], b[0] - a[0]) * 180 / math.pi;
      final th = (deg % 90 + 90) % 90;
      final ux = math.cos(th * math.pi / 180), uy = math.sin(th * math.pi / 180);
      var u0 = double.infinity, u1 = -double.infinity;
      var v0 = double.infinity, v1 = -double.infinity;
      for (final k in hull) {
        final du = s[k][0] * ux + s[k][1] * uy;
        final dv = -s[k][0] * uy + s[k][1] * ux;
        u0 = math.min(u0, du);
        u1 = math.max(u1, du);
        v0 = math.min(v0, dv);
        v1 = math.max(v1, dv);
      }
      if ((u1 - u0) * (v1 - v0) < bestArea) {
        bestArea = (u1 - u0) * (v1 - v0);
        rw = u1 - u0;
        rh = v1 - v0;
        final mu = (u0 + u1) / 2, mv = (v0 + v1) / 2;
        rcx = mu * ux - mv * uy;
        rcy = mu * uy + mv * ux;
        rrot = th;
      }
    }
    if (rrot < 4 || rrot > 86) {
      rcx = cx;
      rcy = cy;
      rw = w;
      rh = h;
      rrot = 0;
    }
    final ux = math.cos(rrot * math.pi / 180);
    final uy = math.sin(rrot * math.pi / 180);
    eRect =
        rms((q) {
          final lu = (q[0] - rcx) * ux + (q[1] - rcy) * uy;
          final lv = -(q[0] - rcx) * uy + (q[1] - rcy) * ux;
          final dx = lu.abs() - rw / 2, dy = lv.abs() - rh / 2;
          if (dx <= 0 && dy <= 0) return math.min(-dx, -dy);
          return _dist(math.max(dx, 0), math.max(dy, 0), 0, 0);
        }) /
        diag;
  }
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
  if (kind == 1 && tilted) {
    return {
      'kind': 'rect',
      'x': round2(rcx - rw / 2),
      'y': round2(rcy - rh / 2),
      'width': round2(rw),
      'height': round2(rh),
      'rotation': round2(rrot),
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

/// `shape.resize`: [s] with [handle] (`nw ne se sw` or `v0 v1 v2`) dragged to
/// [to]; the opposite corner stays on the page. Null for an unknown shape or
/// handle.
Map<String, dynamic>? shapeResize(
  Map s,
  String handle,
  List<num> to,
  bool keepRatio,
) {
  if (!isKnownShape(s)) return null;
  final tx = to[0].toDouble(), ty = to[1].toDouble();
  if (s['kind'] == 'triangle') {
    final i = const ['v0', 'v1', 'v2'].indexOf(handle);
    if (i < 0) return null;
    return {
      'kind': 'triangle',
      'vertices': [
        for (var k = 0; k < 3; k++)
          if (k == i)
            [round2(tx), round2(ty)]
          else
            [
              ((s['vertices'] as List)[k] as List)[0],
              ((s['vertices'] as List)[k] as List)[1],
            ],
      ],
    };
  }
  final corner = const ['nw', 'ne', 'se', 'sw'].indexOf(handle);
  if (corner < 0) return null;
  final x = (s['x'] as num).toDouble(), y = (s['y'] as num).toDouble();
  final w = (s['width'] as num).toDouble(), h = (s['height'] as num).toDouble();
  final cx = x + w / 2, cy = y + h / 2;
  final r = (s['rotation'] as num) * math.pi / 180;
  final ux = math.cos(r), uy = math.sin(r); // the box's own x axis
  // The opposite corner in the box frame, then on the page.
  final ox = (corner == 0 || corner == 3) ? w / 2 : -w / 2;
  final oy = (corner == 0 || corner == 1) ? h / 2 : -h / 2;
  final px = cx + ox * ux - oy * uy, py = cy + ox * uy + oy * ux;
  var du = (tx - px) * ux + (ty - py) * uy;
  var dv = -(tx - px) * uy + (ty - py) * ux;
  if (keepRatio) {
    final k = math.max(du.abs() / w, dv.abs() / h);
    du = (du < 0 ? -1 : 1) * w * k;
    dv = (dv < 0 ? -1 : 1) * h * k;
  }
  if (du.abs() < 1) du = du < 0 ? -1 : 1;
  if (dv.abs() < 1) dv = dv < 0 ? -1 : 1;
  final ncx = px + (du * ux - dv * uy) / 2, ncy = py + (du * uy + dv * ux) / 2;
  return {
    'kind': s['kind'],
    'x': round2(ncx - du.abs() / 2),
    'y': round2(ncy - dv.abs() / 2),
    'width': round2(du.abs()),
    'height': round2(dv.abs()),
    'rotation': s['rotation'],
  };
}

/// `shape.rotate`: the `rotation` a rotation handle dragged to [to] gives,
/// snapped within 3 degrees of a multiple of 15.
double shapeRotate(Map s, List<num> to) {
  final cx = (s['x'] as num) + (s['width'] as num) / 2;
  final cy = (s['y'] as num) + (s['height'] as num) / 2;
  var a = math.atan2(to[1] - cy, to[0] - cx) * 180 / math.pi + 90;
  a = (a % 360 + 360) % 360;
  final near = (a / 15).round() * 15;
  if ((a - near).abs() <= 3) a = near.toDouble();
  return round2(a) % 360;
}

/// `shape.recognizeTilted`: the shape (oriented rect) of a held stroke, and
/// whether a stroke that is no shape is straight enough to become a line.
({Map<String, dynamic>? shape, bool line}) recognizeTilted(
  List<List<num>> points,
) {
  final shape = recognizeShape(points, tilted: true);
  if (shape != null || points.length < 2) return (shape: shape, line: false);
  final a = [points.first[0].toDouble(), points.first[1].toDouble()];
  final b = [points.last[0].toDouble(), points.last[1].toDouble()];
  final len = _dist(a[0], a[1], b[0], b[1]);
  if (len < 1e-9) return (shape: null, line: false);
  var worst = 0.0;
  for (final p in points) {
    worst = math.max(worst, _segDist(p[0].toDouble(), p[1].toDouble(), a, b));
  }
  return (shape: null, line: worst <= 0.08 * len);
}

/// `shape.corners`: the `points` a shape stroke stores. Polygons keep one point
/// per corner, closed; a circle is its dense ring. Null for an unknown shape.
List<List<num>>? shapeCorners(Object? s) {
  if (!isKnownShape(s)) return null;
  s as Map;
  if (s['kind'] == 'circle') return shapePoints(s);
  List<(double, double)> q;
  if (s['kind'] == 'triangle') {
    q = [
      for (final p in s['vertices'] as List)
        ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
  } else {
    final x = (s['x'] as num).toDouble(), y = (s['y'] as num).toDouble();
    final w = (s['width'] as num).toDouble();
    final h = (s['height'] as num).toDouble();
    final cx = x + w / 2, cy = y + h / 2;
    final r = (s['rotation'] as num) * math.pi / 180;
    final c = math.cos(r), sn = math.sin(r);
    q = [
      for (final (px, py) in [(x, y), (x + w, y), (x + w, y + h), (x, y + h)])
        (
          cx + (px - cx) * c - (py - cy) * sn,
          cy + (px - cx) * sn + (py - cy) * c,
        ),
    ];
  }
  q.add(q.first);
  return [
    for (var i = 0; i < q.length; i++)
      <num>[round2(q[i].$1), round2(q[i].$2), 0.5, 16 * i],
  ];
}

/// The points partial erase cuts: the dense points of a known shape
/// (`shape.points`), else the stored ones.
Object? denseOf(Map e) => shapePoints(e['shape']) ?? e['points'];

/// `shape.outline`: the two rings (left, right) of the closed polyline
/// [points] at [width]; [join] is `miter` or `round`. Fill both with non-zero.
List<List<List<double>>> shapeOutline(List points, double width, String join) {
  final v = <(double, double)>[];
  for (final p in points) {
    final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
    if (v.isEmpty || _dist(x, y, v.last.$1, v.last.$2) >= 0.01) v.add((x, y));
  }
  if (v.length > 1 &&
      _dist(v.last.$1, v.last.$2, v.first.$1, v.first.$2) < 0.01) {
    v.removeLast();
  }
  final n = v.length;
  if (n < 2) return [[], []];
  final d = <(double, double)>[], nm = <(double, double)>[];
  for (var i = 0; i < n; i++) {
    final a = v[i], b = v[(i + 1) % n];
    final l = _dist(a.$1, a.$2, b.$1, b.$2);
    final dx = (b.$1 - a.$1) / l, dy = (b.$2 - a.$2) / l;
    d.add((dx, dy));
    nm.add((-dy, dx));
  }
  final h = width / 2;
  List<List<double>> side(double sg) {
    final out = <List<double>>[];
    void add(double x, double y) => out.add([round2(x), round2(y)]);
    for (var i = 0; i < n; i++) {
      final pv = (i + n - 1) % n;
      final a = nm[pv], b = nm[i];
      final (vx, vy) = v[i];
      final c = a.$1 * b.$1 + a.$2 * b.$2;
      final k = d[pv].$1 * d[i].$2 - d[pv].$2 * d[i].$1;
      void miter() => add(
        vx + sg * h * (a.$1 + b.$1) / (1 + c),
        vy + sg * h * (a.$2 + b.$2) / (1 + c),
      );
      void bevel() {
        add(vx + sg * h * a.$1, vy + sg * h * a.$2);
        add(vx + sg * h * b.$1, vy + sg * h * b.$2);
      }

      if (1 + c < 1e-9) {
        bevel();
      } else if (sg * k > 0 || k == 0) {
        miter();
      } else if (join == 'round') {
        final phi = math.acos(c.clamp(-1.0, 1.0));
        final kk = math.max(1, (phi / (math.pi / 8)).ceil());
        final s0 = math.atan2(a.$2, a.$1), dir = k >= 0 ? 1 : -1;
        for (var j = 0; j <= kk; j++) {
          final al = s0 + dir * phi * j / kk;
          add(vx + sg * h * math.cos(al), vy + sg * h * math.sin(al));
        }
      } else if ((1 + c) / 2 >= 1 / 16) {
        miter();
      } else {
        bevel();
      }
    }
    return out;
  }

  return [side(1), side(-1).reversed.toList()];
}

/// The outline rings of a known shape at [width] (null for an unknown one),
/// made from the shape itself so a stroke with old dense `points` draws too.
List<List<List<double>>>? shapeRings(Object? s, double width) {
  final pts = shapeCorners(s);
  if (pts == null) return null;
  return shapeOutline(
    pts,
    width,
    (s as Map)['kind'] == 'circle' ? 'round' : 'miter',
  );
}

/// `shape.holdResize`: [s] with the box corner nearest to [p0] following the
/// pen at [p] and the opposite corner fixed. Null for an unknown shape.
Map<String, dynamic>? shapeHoldResize(Map s, List<num> p0, List<num> p) {
  if (!isKnownShape(s)) return null;
  final tri = s['kind'] == 'triangle';
  double cx, cy, w, h, r;
  if (tri) {
    final v = [
      for (final q in s['vertices'] as List)
        ((q[0] as num).toDouble(), (q[1] as num).toDouble()),
    ];
    var best = -1.0, ang = 0.0;
    for (var i = 0; i < 3; i++) {
      final a = v[i], b = v[(i + 1) % 3];
      final l = _dist(a.$1, a.$2, b.$1, b.$2);
      if (l > best) {
        best = l;
        ang = math.atan2(b.$2 - a.$2, b.$1 - a.$1) * 180 / math.pi;
      }
    }
    r = (ang % 90 + 90) % 90;
    final ux = math.cos(r * math.pi / 180), uy = math.sin(r * math.pi / 180);
    var u0 = double.infinity, u1 = -double.infinity;
    var v0 = double.infinity, v1 = -double.infinity;
    for (final q in v) {
      final du = q.$1 * ux + q.$2 * uy, dv = -q.$1 * uy + q.$2 * ux;
      u0 = math.min(u0, du);
      u1 = math.max(u1, du);
      v0 = math.min(v0, dv);
      v1 = math.max(v1, dv);
    }
    w = u1 - u0;
    h = v1 - v0;
    final mu = (u0 + u1) / 2, mv = (v0 + v1) / 2;
    cx = mu * ux - mv * uy;
    cy = mu * uy + mv * ux;
  } else {
    w = (s['width'] as num).toDouble();
    h = (s['height'] as num).toDouble();
    cx = (s['x'] as num) + w / 2;
    cy = (s['y'] as num) + h / 2;
    r = (s['rotation'] as num).toDouble();
  }
  final ux = math.cos(r * math.pi / 180), uy = math.sin(r * math.pi / 180);
  const sx = [-1, 1, 1, -1], sy = [-1, -1, 1, 1]; // nw, ne, se, sw
  (double, double) corner(int i) => (
    cx + sx[i] * w / 2 * ux - sy[i] * h / 2 * uy,
    cy + sx[i] * w / 2 * uy + sy[i] * h / 2 * ux,
  );
  var hi = 0, bd = double.infinity;
  for (var i = 0; i < 4; i++) {
    final c = corner(i);
    final dd = _dist(c.$1, c.$2, p0[0].toDouble(), p0[1].toDouble());
    if (dd < bd) {
      bd = dd;
      hi = i;
    }
  }
  final hc = corner(hi), a = corner((hi + 2) % 4);
  final tx = hc.$1 + (p[0] - p0[0]), ty = hc.$2 + (p[1] - p0[1]);
  var du = (tx - a.$1) * ux + (ty - a.$2) * uy;
  var dv = -(tx - a.$1) * uy + (ty - a.$2) * ux;
  if (du.abs() < 1) du = du < 0 ? -1 : 1;
  if (dv.abs() < 1) dv = dv < 0 ? -1 : 1;
  if (tri) {
    if (w < 1 || h < 1) return null;
    final hx = sx[hi] * w / 2, hy = sy[hi] * h / 2;
    return {
      'kind': 'triangle',
      'vertices': [
        for (final q in s['vertices'] as List)
          () {
            final qx = (q[0] as num) - a.$1, qy = (q[1] as num) - a.$2;
            final nu = (qx * ux + qy * uy) * du / (2 * hx);
            final nv = (-qx * uy + qy * ux) * dv / (2 * hy);
            return [
              round2(a.$1 + nu * ux - nv * uy),
              round2(a.$2 + nu * uy + nv * ux),
            ];
          }(),
      ],
    };
  }
  final ncx = a.$1 + (du * ux - dv * uy) / 2;
  final ncy = a.$2 + (du * uy + dv * ux) / 2;
  return {
    'kind': s['kind'],
    'x': round2(ncx - du.abs() / 2),
    'y': round2(ncy - dv.abs() / 2),
    'width': round2(du.abs()),
    'height': round2(dv.abs()),
    'rotation': s['rotation'],
  };
}
