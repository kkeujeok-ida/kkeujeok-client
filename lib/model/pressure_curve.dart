// spec rule `pen.pressureCurve` (spec/pen-feel.md): maps a stored pressure p
// to the drawing pressure q before the radius factor is applied.

/// A cubic Bezier from (0,0) to (1,1) with control points (x1,y1), (x2,y2).
/// [preset] is the name when it is one of the three presets, else null.
class PressureCurve {
  const PressureCurve._(this.preset, this.x1, this.y1, this.x2, this.y2);

  static const soft = PressureCurve._('soft', 0.2, 0.4, 0.5, 0.8);
  static const normal = PressureCurve._('normal', 1 / 3, 1 / 3, 2 / 3, 2 / 3);
  static const firm = PressureCurve._('firm', 0.5, 0.1, 0.8, 0.5);
  static const presets = [soft, normal, firm];

  final String? preset;
  final double x1, y1, x2, y2;

  List<double> get values => [x1, y1, x2, y2];

  /// Four values in 0..1 with x1 <= x2 and y1 <= y2; an invalid set is
  /// `normal`.
  factory PressureCurve.fromValues(List<num> v) {
    if (v.length != 4) return normal;
    final d = [for (final n in v) n.toDouble()];
    final ok =
        d.every((n) => n >= 0 && n <= 1) && d[0] <= d[2] && d[1] <= d[3];
    return ok ? PressureCurve._(null, d[0], d[1], d[2], d[3]) : normal;
  }

  /// A preset name or `[x1, y1, x2, y2]` (the fixture form); else `normal`.
  factory PressureCurve.fromJson(Object? j) {
    if (j is String) {
      return presets.firstWhere((c) => c.preset == j, orElse: () => normal);
    }
    if (j is List && j.every((e) => e is num)) {
      return PressureCurve.fromValues(j.cast<num>());
    }
    return normal;
  }

  @override
  bool operator ==(Object other) =>
      other is PressureCurve &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);

  static double _b(double a, double b, double t) =>
      3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t;

  /// q for a stored pressure [p] (clamped to 0..1), by bisection on x(t) = p.
  double q(double p) {
    p = p.clamp(0.0, 1.0);
    if (p == 0 || p == 1) return p;
    if (x1 == y1 && x2 == y2) return p; // y = x exactly (normal preset)
    var lo = 0.0, hi = 1.0, mid = 0.5;
    while (hi - lo >= 1e-6) {
      mid = (lo + hi) / 2;
      if (_b(x1, x2, mid) < p) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return _b(y1, y2, mid);
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
