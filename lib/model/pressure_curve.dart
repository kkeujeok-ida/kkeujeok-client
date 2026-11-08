// spec rule `pen.pressureCurve` (spec/pen-feel.md): maps a stored pressure p
// to the drawing pressure q before the radius factor is applied.

/// A monotone cubic through (0,0), the inner points and (1,1). [values] is the
/// flat inner list `[x1, y1, x2, y2, ...]`. [preset] is the name when it is
/// one of the three presets, else null.
class PressureCurve {
  const PressureCurve._(this.preset, this.values);

  static const maxInner = 6;
  static const soft = PressureCurve._('soft', [0.2, 0.4, 0.5, 0.8]);
  static const normal = PressureCurve._('normal', []);
  static const firm = PressureCurve._('firm', [0.5, 0.1, 0.8, 0.5]);
  static const presets = [soft, normal, firm];

  final String? preset;
  final List<double> values;

  /// Even length up to 12, values in 0..1, x strictly increasing inside
  /// (0,1), y never decreasing; an invalid set is `normal`.
  factory PressureCurve.fromValues(List<num> v) {
    final d = [for (final n in v) n.toDouble()];
    if (d.length.isOdd || d.length > maxInner * 2) return normal;
    var px = 0.0, py = 0.0;
    for (var i = 0; i < d.length; i += 2) {
      final x = d[i], y = d[i + 1];
      if (!(x > px && x < 1 && y >= py && y <= 1)) return normal;
      px = x;
      py = y;
    }
    for (final c in presets) {
      if (_same(c.values, d)) return c;
    }
    return PressureCurve._(null, d);
  }

  static bool _same(List<double> a, List<double> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((e) => e);

  /// A preset name or the flat inner list (the fixture form); else `normal`.
  factory PressureCurve.fromJson(Object? j) {
    if (j is String) {
      return presets.firstWhere((c) => c.preset == j, orElse: () => normal);
    }
    if (j is List && j.every((e) => e is num)) {
      return PressureCurve.fromValues(j.cast<num>());
    }
    return normal;
  }

  /// The inner points as (x, y) pairs.
  List<(double, double)> get inner => [
    for (var i = 0; i < values.length; i += 2) (values[i], values[i + 1]),
  ];

  @override
  bool operator ==(Object other) =>
      other is PressureCurve && _same(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);

  /// q for a stored pressure [p] (clamped to 0..1): monotone cubic Hermite
  /// (Fritsch-Butland tangents), spec/pen-feel.md.
  double q(double p) {
    p = p.clamp(0.0, 1.0);
    if (p == 0 || p == 1 || values.isEmpty) return p;
    final x = [0.0, for (var i = 0; i < values.length; i += 2) values[i], 1.0];
    final y = [0.0, for (var i = 1; i < values.length; i += 2) values[i], 1.0];
    final n = x.length - 1;
    final h = [for (var k = 0; k < n; k++) x[k + 1] - x[k]];
    final d = [for (var k = 0; k < n; k++) (y[k + 1] - y[k]) / h[k]];
    final m = List<double>.filled(n + 1, 0);
    m[0] = d[0];
    m[n] = d[n - 1];
    for (var k = 1; k < n; k++) {
      if (d[k - 1] * d[k] <= 0) continue;
      final w1 = 2 * h[k] + h[k - 1], w2 = h[k] + 2 * h[k - 1];
      m[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k]);
    }
    var k = 0;
    while (k < n - 1 && p > x[k + 1]) {
      k++;
    }
    final u = (p - x[k]) / h[k], u2 = u * u, u3 = u2 * u;
    final r =
        (2 * u3 - 3 * u2 + 1) * y[k] +
        (u3 - 2 * u2 + u) * h[k] * m[k] +
        (-2 * u3 + 3 * u2) * y[k + 1] +
        (u3 - u2) * h[k] * m[k + 1];
    return r.clamp(0.0, 1.0);
  }
}

/// The device setting in use while drawing. Set by main() and the settings.
PressureCurve pressureCurveInUse = PressureCurve.normal;

/// Radius factor f(q) of spec/stroke-geometry.md.
double radiusFactor(double q) =>
    q < 0.5 ? 0.25 + 0.75 * (q / 0.5) : 1 + 0.75 * ((q - 0.5) / 0.5);

/// q of a point: no curve without `usePressure` or with a missing pressure.
double drawPressure(PressureCurve curve, bool usePressure, num? pressure) {
  if (!usePressure || pressure == null || !pressure.isFinite) return 0.5;
  return curve.q(pressure.toDouble());
}
