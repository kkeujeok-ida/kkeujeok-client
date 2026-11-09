// spec rule `brush.resolve` (spec/brush.md): the drawing parameters of a
// stroke from its `tool` and optional `brush`.
import 'dart:convert' show jsonEncode;

import 'curve.dart';
import 'pressure_curve.dart';

const _linear = [1 / 3, 1 / 3, 2 / 3, 2 / 3];

/// Default opacity of a tool; the highlighter layer alpha.
double toolOpacity(Object? tool) => tool == 'highlighter' ? 0.4 : 1.0;

typedef BrushParams = ({
  List? pressureCurve,
  List tiltCurve,
  String tiltTarget,
  double opacity,
  String texture,
});

BrushParams brushResolve(Object? tool, Object? brush) {
  final b = brush is Map ? brush : const {};
  final o = b['opacity'];
  final opacity = tool == 'tape'
      ? 1.0
      : o is num && o >= 0.05 && o <= 1
      ? o.toDouble()
      : toolOpacity(tool);
  final tx = b['texture'];
  final tt = b['tiltTarget'];
  return (
    pressureCurve: validCurve(b['pressureCurve']),
    tiltCurve: validCurve(b['tiltCurve']) ?? _linear,
    tiltTarget: tt == 'size' || tt == 'opacity' ? tt as String : 'none',
    opacity: opacity,
    texture: tx == 'none' || tx == 'pencil'
        ? tx as String
        : tool == 'pencil'
        ? 'pencil'
        : 'none',
  );
}

/// Curve output q (0..1) of a point's tilt, or null when it has none.
double? tiltQ(List p, Object curve) {
  if (p.length < 6 || p[4] is! num) return null;
  final t = ((p[4] as num).toDouble().clamp(0.0, 90.0)) / 90;
  return (curve is PressureCurve ? curve : PressureCurve.fromCurve(curve)).q(t);
}

/// Width factor of a point: `0.5 + q` under tilt `size`; 1 when unknown.
double tiltSizeFactor(List p, Object curve) {
  final q = tiltQ(p, curve);
  return q == null ? 1.0 : 0.5 + q;
}

/// Multiplier of the stroke's layer alpha relative to the tool default.
/// shortcut: tilt `opacity` is one mean value per stroke (a stroke is one
/// filled layer), not per point; upgrade with a per-segment renderer.
double brushAlphaFactor(
  Object? tool,
  Object? brush,
  List points, [
  bool usePressure = true,
  bool pressureOpacity = true,
]) {
  if (brush == null) return 1;
  final b = brushResolve(tool, brush);
  var a = b.opacity / toolOpacity(tool);
  if (b.tiltTarget == 'opacity' && tool != 'tape') {
    final tc = PressureCurve.fromCurve(b.tiltCurve);
    final qs = [for (final p in points) ?tiltQ(p as List, tc)];
    if (qs.isNotEmpty) a *= qs.reduce((x, y) => x + y) / qs.length;
  }
  // Pressure alone drives it; usePressure off counts as 0.5 (spec/brush.md).
  // [pressureOpacity] false: the stamps carry it per stamp.
  final oc = pressureOpacity && tool != 'tape'
      ? opacityPressureCurve(brush)
      : null;
  if (oc != null && points.isNotEmpty) {
    final c = PressureCurve.fromCurve(oc);
    var sum = 0.0;
    for (final p in points) {
      final v = p is List && p.length > 2 ? p[2] : null;
      sum += c.q(usePressure && v is num && v.isFinite ? v.toDouble() : 0.5);
    }
    a *= sum / points.length;
  }
  return a;
}

/// `brush` with [patch] applied, keeping only what differs from the tool
/// default (spec/brush.md). A null value clears a parameter. Unknown
/// parameters stay. Null when nothing is left.
Map<String, Object?>? patchBrush(
  Object? tool,
  Object? brush,
  Map<String, Object?> patch,
) {
  final out = <String, Object?>{
    if (brush is Map) ...brush.cast<String, Object?>(),
  };
  final d = brushResolve(tool, null);
  final defaults = <String, Object?>{
    'tiltCurve': d.tiltCurve,
    'tiltTarget': d.tiltTarget,
    'opacity': d.opacity,
    'texture': d.texture,
  };
  for (final e in patch.entries) {
    final v = e.value;
    if (v == null ||
        (e.key != 'pressureCurve' &&
            jsonEncode(v) == jsonEncode(defaults[e.key]))) {
      out.remove(e.key);
    } else {
      out[e.key] = v;
    }
  }
  return out.isEmpty ? null : out;
}
