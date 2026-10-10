import 'dart:math' as math;
import 'dart:ui';

import '../model/number.dart';

// spec/stroke-geometry.md parameters.
const _dedupeDistance = 0.01;
const _smoothingPasses = 2;
const _smoothingFactor = 0.5;
const _spacing = 2.0;
const _minRatio = 0.25;
const _maxRatio = 1.75;
const _capSegments = 8;

/// spec rule `stroke.outline.pen`: the closed polygon of a pen stroke, built
/// from the stored [points] (`[x, y, pressure, t]`) only; never stored.
List<List<double>> strokeOutline(double width, bool usePressure, List points) {
  // 1. Prepare: dedupe against the last kept point.
  final xs = <double>[], ys = <double>[], qs = <double>[];
  for (final p in points) {
    final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
    if (xs.isNotEmpty) {
      final dx = x - xs.last, dy = y - ys.last;
      if (math.sqrt(dx * dx + dy * dy) < _dedupeDistance) continue;
    }
    xs.add(x);
    ys.add(y);
    qs.add(_pressure(usePressure, p));
  }
  if (xs.isEmpty) return [];

  double radius(double q) {
    final f = q < 0.5
        ? _minRatio + (1 - _minRatio) * (q / 0.5)
        : 1 + (_maxRatio - 1) * ((q - 0.5) / 0.5);
    return width / 2 * f;
  }

  // 2. One point: a 16-point circle.
  if (xs.length == 1) {
    final r = radius(qs[0]);
    return [
      for (var k = 0; k < 16; k++)
        [
          round2(xs[0] + r * math.cos(2 * math.pi * k / 16)),
          round2(ys[0] + r * math.sin(2 * math.pi * k / 16)),
        ],
    ];
  }

  // 3. Smooth x, y and q; ends stay.
  for (var pass = 0; pass < _smoothingPasses; pass++) {
    for (final a in [xs, ys, qs]) {
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
  final sx = <double>[], sy = <double>[], sq = <double>[];
  var seg = 1;
  for (var i = 0; i <= n; i++) {
    if (i == n) {
      sx.add(xs.last);
      sy.add(ys.last);
      sq.add(qs.last);
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
    final r = radius(sq[i]);
    left.add([sx[i] - r * ty[i], sy[i] + r * tx[i]]);
    right.add([sx[i] + r * ty[i], sy[i] - r * tx[i]]);
  }
  final rEnd = radius(sq[n]), rStart = radius(sq[0]);
  final endCap = <List<double>>[], startCap = <List<double>>[];
  for (var k = 1; k < _capSegments; k++) {
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

double _pressure(bool usePressure, List p) {
  if (!usePressure || p.length < 3) return 0.5;
  final v = p[2];
  if (v is! num || !v.isFinite) return 0.5;
  return v.toDouble().clamp(0.0, 1.0);
}

/// The polygon as a path; fill it non-zero (the default fill type).
Path outlinePath(List<List<double>> polygon) =>
    Path()..addPolygon([for (final p in polygon) Offset(p[0], p[1])], true);
