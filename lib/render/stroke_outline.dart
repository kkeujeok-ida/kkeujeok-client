import 'dart:math' as math;
import 'dart:ui';

import '../model/number.dart';
import '../model/pressure_curve.dart';

// spec/stroke-geometry.md parameters.
const _dedupeDistance = 0.01;
const _smoothingPasses = 2;
const _smoothingFactor = 0.5;
const _spacing = 2.0;
const _minRatio = 0.25;
const _maxRatio = 1.75;
const _capSegments = 8;
const _taperMin = 0.25;

/// Steps 1-4 of spec/stroke-geometry.md: the resampled `(x, y, q)` of a pen
/// stroke. One kept point gives one sample; no points give empty lists. The
/// pencil texture reads the same samples (spec/pen-kinds.md).
({
  List<double> x,
  List<double> y,
  List<double> q,
  List<double> m,
  double length,
})
strokeSamples(
  bool usePressure,
  List points, [
  PressureCurve? curve,
  double Function(List p)? sizeOf,
]) {
  final useCurve = usePressure && points.any((p) => p.length > 2 && p[2] != 0.5)
      ? (curve ?? pressureCurveInUse)
      : null;
  // 1. Prepare: dedupe against the last kept point.
  final xs = <double>[], ys = <double>[], qs = <double>[], ms = <double>[];
  for (final p in points) {
    final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
    if (xs.isNotEmpty) {
      final dx = x - xs.last, dy = y - ys.last;
      if (math.sqrt(dx * dx + dy * dy) < _dedupeDistance) continue;
    }
    xs.add(x);
    ys.add(y);
    qs.add(_pressure(usePressure, p, useCurve));
    ms.add(sizeOf == null ? 1.0 : sizeOf(p));
  }
  if (xs.length < 2) return (x: xs, y: ys, q: qs, m: ms, length: 0.0);

  // 3. Smooth x, y and q; ends stay.
  for (var pass = 0; pass < _smoothingPasses; pass++) {
    for (final a in [xs, ys, qs, if (sizeOf != null) ms]) {
      final old = List<double>.of(a);
      for (var i = 1; i < a.length - 1; i++) {
        a[i] =
            old[i] +
            _smoothingFactor * ((old[i - 1] + old[i + 1]) / 2 - old[i]);
      }
    }
  }

  // 4. Resample at equal arc length.
  final cum = <double>[0];
  for (var i = 1; i < xs.length; i++) {
    cum.add(
      cum.last +
          math.sqrt(
            math.pow(xs[i] - xs[i - 1], 2) + math.pow(ys[i] - ys[i - 1], 2),
          ),
    );
  }
  final total = cum.last;
  final n = math.max(1, (total / _spacing + 0.5).floor());
  final sx = <double>[], sy = <double>[], sq = <double>[], sm = <double>[];
  var seg = 1;
  for (var i = 0; i <= n; i++) {
    if (i == n) {
      sx.add(xs.last);
      sy.add(ys.last);
      sq.add(qs.last);
      sm.add(ms.last);
      break;
    }
    final target = total * i / n;
    while (seg < cum.length - 1 && cum[seg] < target) {
      seg++;
    }
    final len = cum[seg] - cum[seg - 1];
    final t = len <= 0 ? 0.0 : ((target - cum[seg - 1]) / len).clamp(0.0, 1.0);
    sx.add(xs[seg - 1] + (xs[seg] - xs[seg - 1]) * t);
    sy.add(ys[seg - 1] + (ys[seg] - ys[seg - 1]) * t);
    sq.add(qs[seg - 1] + (qs[seg] - qs[seg - 1]) * t);
    sm.add(ms[seg - 1] + (ms[seg] - ms[seg - 1]) * t);
  }
  return (x: sx, y: sy, q: sq, m: sm, length: total);
}

/// Mean drawing pressure of [points]; the flat alpha of a polygon fallback.
double meanPressure(bool usePressure, List points, [PressureCurve? curve]) {
  if (points.isEmpty) return 0.5;
  final useCurve = usePressure && points.any((p) => p.length > 2 && p[2] != 0.5)
      ? (curve ?? pressureCurveInUse)
      : null;
  var sum = 0.0;
  for (final p in points) {
    sum += _pressure(usePressure, p, useCurve);
  }
  return sum / points.length;
}

/// spec rule `stroke.outline.pen`: the closed polygon of a pen stroke, built
/// from the stored [points] (`[x, y, pressure, t]`) only; never stored.
/// [curve] defaults to the device setting (spec/pen-feel.md). A mouse stores
/// 0.5 for every point: a stroke with no other pressure gets no curve.
/// [minRatio]/[maxRatio] and [taper] are the kind changes of spec/pen-kinds.md
/// (fountain: 0.2, 1.6, taper); the defaults are the pen.
List<List<double>> strokeOutline(
  double width,
  bool usePressure,
  List points, [
  PressureCurve? curve,
  double minRatio = _minRatio,
  double maxRatio = _maxRatio,
  bool taper = false,
  bool flat = false,
  double Function(List p)? sizeOf,
  bool taperHead = true,
  bool taperTail = true,
]) {
  final smp = strokeSamples(usePressure, points, curve, sizeOf);
  if (smp.x.isEmpty) return [];
  final sx = smp.x, sy = smp.y, sq = smp.q, sm = smp.m, total = smp.length;

  double radius(double q) {
    if (flat) return width / 2;
    final f = q < 0.5
        ? minRatio + (1 - minRatio) * (q / 0.5)
        : 1 + (maxRatio - 1) * ((q - 0.5) / 0.5);
    return width / 2 * f;
  }

  // 2. One point: a 16-point circle (tape: the square).
  if (sx.length == 1) {
    final r = radius(sq[0]) * sm[0];
    if (flat) {
      return [
        for (final d in [
          [-1, -1],
          [1, -1],
          [1, 1],
          [-1, 1],
        ])
          [round2(sx[0] + d[0] * r), round2(sy[0] + d[1] * r)],
      ];
    }
    return [
      for (var k = 0; k < 16; k++)
        [
          round2(sx[0] + r * math.cos(2 * math.pi * k / 16)),
          round2(sy[0] + r * math.sin(2 * math.pi * k / 16)),
        ],
    ];
  }

  final n = sx.length - 1;

  // Fountain taper: the radius narrows toward both ends (pen-kinds.md).
  final g = List<double>.filled(n + 1, 1);
  // taperHead/taperTail false: a piece of a live stroke (live_stroke.dart)
  // tapers only the end that is the stroke's own end.
  if (taper && (taperHead || taperTail)) {
    final both = taperHead && taperTail;
    final taperLength = both ? math.min(3 * width, total / 2) : 3 * width;
    if (taperLength >= 1e-9) {
      for (var i = 0; i <= n; i++) {
        final s = total * i / n;
        final d = both
            ? math.min(s, total - s)
            : taperHead
            ? s
            : total - s;
        g[i] = _taperMin + (1 - _taperMin) * math.min(1, d / taperLength);
      }
    }
  }

  // 5. Tangents (never NaN).
  final tx = List<double>.filled(n + 1, 1), ty = List<double>.filled(n + 1, 0);
  for (var i = 0; i <= n; i++) {
    final a = math.max(0, i - 1), b = math.min(n, i + 1);
    var dx = sx[b] - sx[a], dy = sy[b] - sy[a];
    var len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9 && i > 0) {
      dx = sx[i] - sx[i - 1];
      dy = sy[i] - sy[i - 1];
      len = math.sqrt(dx * dx + dy * dy);
    }
    if (len < 1e-9) {
      if (i > 0) {
        tx[i] = tx[i - 1];
        ty[i] = ty[i - 1];
      }
    } else {
      tx[i] = dx / len;
      ty[i] = dy / len;
    }
  }

  // 6-8. Sides, caps, polygon. Normal N = (-Ty, Tx).
  final left = <List<double>>[], right = <List<double>>[];
  for (var i = 0; i <= n; i++) {
    final r = radius(sq[i]) * g[i] * sm[i];
    left.add([sx[i] - r * ty[i], sy[i] + r * tx[i]]);
    right.add([sx[i] + r * ty[i], sy[i] - r * tx[i]]);
  }
  final rEnd = radius(sq[n]) * g[n] * sm[n],
      rStart = radius(sq[0]) * g[0] * sm[0];
  final endCap = <List<double>>[], startCap = <List<double>>[];
  for (var k = 1; k < (flat ? 0 : _capSegments); k++) {
    final phi = math.pi * k / _capSegments;
    final c = math.cos(phi), s = math.sin(phi);
    endCap.add([
      sx[n] + rEnd * (-ty[n] * c + tx[n] * s),
      sy[n] + rEnd * (tx[n] * c + ty[n] * s),
    ]);
    startCap.add([
      sx[0] - rStart * (-ty[0] * c + tx[0] * s),
      sy[0] - rStart * (tx[0] * c + ty[0] * s),
    ]);
  }
  return [
    for (final p in [...left, ...endCap, ...right.reversed, ...startCap])
      [round2(p[0]), round2(p[1])],
  ];
}

/// The outline of a stroke by its `tool`.
List<List<double>> strokeOutlineFor(
  String? tool,
  double width,
  bool usePressure,
  List points, [
  PressureCurve? curve,
  double Function(List p)? sizeOf,
  bool taperHead = true,
  bool taperTail = true,
]) => switch (tool) {
  'fountain' => strokeOutline(
    width,
    usePressure,
    points,
    curve,
    0.2,
    1.6,
    true,
    false,
    sizeOf,
    taperHead,
    taperTail,
  ),
  'pencil' => strokeOutline(
    width,
    usePressure,
    points,
    curve,
    0.6,
    1.3,
    false,
    false,
    sizeOf,
  ),
  'tape' => strokeOutline(
    width,
    usePressure,
    points,
    curve,
    0.5,
    1,
    false,
    true,
  ),
  _ => strokeOutline(
    width,
    usePressure,
    points,
    curve,
    _minRatio,
    _maxRatio,
    false,
    false,
    sizeOf,
  ),
};

/// spec rule `stroke.outline.highlighter`: the chisel-nib rectangles of a
/// highlighter stroke, in point order; their union is the stroke.
List<List<List<double>>> highlighterPolygons(double width, List points) {
  final xs = <double>[], ys = <double>[];
  for (final p in points) {
    final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
    if (xs.isNotEmpty) {
      final dx = x - xs.last, dy = y - ys.last;
      if (math.sqrt(dx * dx + dy * dy) < _dedupeDistance) continue;
    }
    xs.add(x);
    ys.add(y);
  }
  if (xs.isEmpty) return [];
  // Upright chisel; the 1/16 lean keeps a straight vertical stroke visible.
  final ax = width / 16;
  final ay = -width / 2;
  List<double> pt(double x, double y) => [round2(x), round2(y)];
  if (xs.length == 1) {
    final nx = -ay * 0.25, ny = ax * 0.25;
    return [
      [
        pt(xs[0] + ax, ys[0] + ay),
        pt(xs[0] + nx, ys[0] + ny),
        pt(xs[0] - ax, ys[0] - ay),
        pt(xs[0] - nx, ys[0] - ny),
      ],
    ];
  }
  return [
    for (var i = 0; i + 1 < xs.length; i++)
      [
        pt(xs[i] + ax, ys[i] + ay),
        pt(xs[i + 1] + ax, ys[i + 1] + ay),
        pt(xs[i + 1] - ax, ys[i + 1] - ay),
        pt(xs[i] - ax, ys[i] - ay),
      ],
  ];
}

/// All [highlighterPolygons] as one non-zero path. Each rectangle is turned
/// to the same direction, or opposite ones would cancel where they overlap.
Path highlighterPath(List<List<List<double>>> polygons) {
  final path = Path();
  for (final poly in polygons) {
    var area = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      area += a[0] * b[1] - b[0] * a[1];
    }
    final pts = [for (final p in poly) Offset(p[0], p[1])];
    path.addPolygon(area < 0 ? pts.reversed.toList() : pts, true);
  }
  return path;
}

double _pressure(bool usePressure, List p, PressureCurve? curve) {
  if (!usePressure || p.length < 3) return 0.5;
  final v = p[2];
  if (v is! num || !v.isFinite) return 0.5;
  return curve?.q(v.toDouble()) ?? v.toDouble().clamp(0.0, 1.0);
}

/// The polygon as a path; fill it non-zero. Long outlines go through the edge
/// midpoints as quadratic curves, so no corner shows; a 4-point tape square
/// stays square.
Path outlinePath(List<List<double>> polygon) {
  final n = polygon.length;
  if (n < 8) {
    return Path()
      ..addPolygon([for (final p in polygon) Offset(p[0], p[1])], true);
  }
  Offset mid(int i, int j) => Offset(
    (polygon[i][0] + polygon[j][0]) / 2,
    (polygon[i][1] + polygon[j][1]) / 2,
  );
  final path = Path();
  final s = mid(n - 1, 0);
  path.moveTo(s.dx, s.dy);
  for (var i = 0; i < n; i++) {
    final m = mid(i, (i + 1) % n);
    path.quadraticBezierTo(polygon[i][0], polygon[i][1], m.dx, m.dy);
  }
  return path..close();
}
