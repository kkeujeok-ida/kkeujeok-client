// spec rule `brush.curve` (spec/brush.md): a curve is legacy `[x1, y1, x2, y2]`
// (always rising) or a point list `[[x, y], ...]` (ends free, can fall).
import 'dart:math' as math;

const maxCurvePoints = 8;

bool _unit(Object? n) => n is num && n >= 0 && n <= 1;

bool isPointList(Object? c) => c is List && c.isNotEmpty && c.first is List;

/// The curve in either valid form (numbers as doubles), as read; null when
/// it is invalid.
List? validCurve(Object? c) {
  if (c is! List) return null;
  if (c.isNotEmpty && c.every((q) => q is num)) {
    if (c.length != 4 || !c.every(_unit)) return null;
    final v = [for (final n in c) (n as num).toDouble()];
    return v[0] > 0 && v[0] < v[2] && v[2] < 1 && v[1] <= v[3] ? v : null;
  }
  if (c.length < 2 || c.length > maxCurvePoints) return null;
  var px = -1.0;
  final out = <List<double>>[];
  for (final q in c) {
    if (q is! List || q.length != 2 || !_unit(q[0]) || !_unit(q[1])) {
      return null;
    }
    final x = (q[0] as num).toDouble();
    if (x <= px) return null;
    px = x;
    out.add([x, (q[1] as num).toDouble()]);
  }
  return out.first[0] == 0 && px == 1 ? out : null;
}

/// y for [x] (clamped to 0..1) on a valid curve; null when invalid. Both forms
/// use the Fritsch-Carlson spline (the fixture values match it); drawing a
/// stored legacy curve still goes through `PressureCurve` (Fritsch-Butland).
double? curveEval(Object? curve, double x) {
  final c = validCurve(curve);
  if (c == null) return null;
  x = x.clamp(0.0, 1.0);
  final pts = isPointList(c)
      ? c.cast<List<double>>()
      : [
          [0.0, 0.0],
          [c[0] as double, c[1] as double],
          [c[2] as double, c[3] as double],
          [1.0, 1.0],
        ];
  final xs = [for (final q in pts) q[0]], ys = [for (final q in pts) q[1]];
  final n = xs.length - 1;
  final d = [
    for (var k = 0; k < n; k++) (ys[k + 1] - ys[k]) / (xs[k + 1] - xs[k]),
  ];
  final m = List<double>.filled(n + 1, 0);
  m[0] = d[0];
  m[n] = d[n - 1];
  for (var k = 1; k < n; k++) {
    if (d[k - 1] * d[k] <= 0) continue;
    final t = (ys[k + 1] - ys[k - 1]) / (xs[k + 1] - xs[k - 1]);
    m[k] =
        t.sign *
        math.min(t.abs(), math.min(3 * d[k - 1].abs(), 3 * d[k].abs()));
  }
  var k = 0;
  while (k < n - 1 && x > xs[k + 1]) {
    k++;
  }
  final h = xs[k + 1] - xs[k];
  final u = (x - xs[k]) / h, u2 = u * u, u3 = u2 * u;
  final r =
      (2 * u3 - 3 * u2 + 1) * ys[k] +
      (u3 - 2 * u2 + u) * h * m[k] +
      (-2 * u3 + 3 * u2) * ys[k + 1] +
      (u3 - u2) * h * m[k + 1];
  return r.clamp(0.0, 1.0);
}

/// A valid legacy curve sampled at 0, .25, .5, .75, 1; null for anything else
/// (a point list needs no conversion).
List<List<double>>? curveToPoints(Object? curve) {
  final c = validCurve(curve);
  if (c == null || isPointList(c)) return null;
  return [
    for (final x in const [0.0, 0.25, 0.5, 0.75, 1.0]) [x, curveEval(c, x)!],
  ];
}

/// `brush.opacityPressureCurve` as read when valid, else null.
List? opacityPressureCurve(Object? brush) =>
    brush is Map ? validCurve(brush['opacityPressureCurve']) : null;

/// The point list the editor edits: a point list as it is, a legacy curve
/// converted; null when invalid.
List<List<double>>? editPoints(Object? c) {
  final v = validCurve(c);
  return v == null
      ? null
      : isPointList(v)
      ? v.cast<List<double>>()
      : curveToPoints(v);
}
