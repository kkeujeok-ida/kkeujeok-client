import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../model/pressure_curve.dart';

// spec rules `stroke.texture.pencil` and `stroke.texture.pencilStamps`
// (spec/pen-kinds.md): stamps placed along the stroke from its points and id,
// never stored in a note. The stamp is `assets/pencil_stamp.png`.
const pencilStampAsset = 'assets/pencil_stamp.png';

/// The three stamp image variants of `stroke.texture.stamps` (spec/pen-kinds.md).
const pencilStampAssets = [
  'assets/pencil_stamp_0.png',
  'assets/pencil_stamp_1.png',
  'assets/pencil_stamp_2.png',
];

typedef PencilStamp = ({
  double x,
  double y,
  double size,
  double angle,
  double alpha,
});

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// The stamps of a pencil stroke (`stroke.texture.pencilStamps`). [curve] and
/// [opacityCurve] turn a stored pressure into `q`; null means identity.
List<PencilStamp> pencilStamps({
  required String id,
  required double width,
  required bool usePressure,
  required List points,
  double opacity = 1,
  PressureCurve? curve,
  PressureCurve? opacityCurve,
}) {
  double qOf(List p) {
    if (!usePressure || p.length < 3) return 0.5;
    final v = p[2];
    if (v is! num || !v.isFinite) return 0.5;
    var q = curve?.q(v.toDouble()) ?? v.toDouble().clamp(0.0, 1.0);
    if (opacityCurve != null) q = opacityCurve.q(q);
    return q;
  }

  final xs = <double>[], ys = <double>[], qs = <double>[];
  for (final p in points) {
    final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
    if (xs.isNotEmpty &&
        math.sqrt(math.pow(x - xs.last, 2) + math.pow(y - ys.last, 2)) < 0.01) {
      continue;
    }
    xs.add(x);
    ys.add(y);
    qs.add(qOf(p as List));
  }
  if (xs.isEmpty) return const [];
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
  final seed = _fnv1a(id);
  final out = <PencilStamp>[];
  var seg = 0;
  var s = 0.0;
  for (var k = 0; ; k++) {
    final last = !(s < total - 1e-9);
    if (last) s = total;
    while (seg < xs.length - 2 && cum[seg + 1] <= s) {
      seg++;
    }
    double px, py, q, tx = 1, ty = 0;
    if (xs.length == 1) {
      px = xs[0];
      py = ys[0];
      q = qs[0];
    } else {
      final len = cum[seg + 1] - cum[seg];
      final t = len <= 0 ? 0.0 : ((s - cum[seg]) / len).clamp(0.0, 1.0);
      px = xs[seg] + (xs[seg + 1] - xs[seg]) * t;
      py = ys[seg] + (ys[seg + 1] - ys[seg]) * t;
      q = qs[seg] + (qs[seg + 1] - qs[seg]) * t;
      tx = (xs[seg + 1] - xs[seg]) / len;
      ty = (ys[seg + 1] - ys[seg]) / len;
    }
    final d = (pencilDensity(q).density * opacity).clamp(0.0, 1.0);
    final f = q < 0.5 ? 0.6 + 0.8 * q : 0.7 + 0.6 * q;
    final w = width * f;
    var x = (seed ^ k) & 0xFFFFFFFF;
    if (x == 0) x = 1;
    double draw() {
      x ^= (x << 13) & 0xFFFFFFFF;
      x ^= x >> 17;
      x ^= (x << 5) & 0xFFFFFFFF;
      return x / 4294967296;
    }

    final off = (2 * draw() - 1) * 0.18 * w;
    final ang = draw() * 360;
    out.add((
      x: _round2(px + off * -ty),
      y: _round2(py + off * tx),
      size: _round2(1.6 * w),
      angle: _round2(ang),
      alpha: (0.45 * d * 10000).roundToDouble() / 10000,
    ));
    if (last) break;
    s += math.max(0.3, w * (0.9 - 0.78 * d));
  }
  return out;
}

typedef PencilStampV2 = ({
  double x,
  double y,
  double size,
  double angle,
  double alpha,
  int variant,
});

/// Where a live walk of [pencilStampsV2] stopped: the next stamp number [k],
/// its nominal arc length [s] and the segment that held it.
class PencilWalk {
  int k = 0, seg = 0;
  double s = 0;
}

/// spec rule `stroke.texture.stamps` (stamps v2). [curve] and [densityCurve]
/// turn a stored pressure into `q` (size) and `qd` (step); null is the clamped
/// pressure. [alphaOf] gives the alpha factor `O` of a point (brush.alpha);
/// null uses [opacityFactor]. With [live] and a [walk], only the stamps new
/// since the walk's last call are returned (append-only, so the earlier ones
/// stay valid). [nominal] collects the nominal `s` of each returned stamp.
List<PencilStampV2> pencilStampsV2({
  required String id,
  required double width,
  required bool usePressure,
  required List points,
  double density = 1,
  double opacityFactor = 1,
  bool live = false,
  PressureCurve? curve,
  PressureCurve? densityCurve,
  double Function(List p)? alphaOf,
  PencilWalk? walk,
  List<double>? nominal,
}) {
  double pressure(List p) {
    if (!usePressure || p.length < 3) return 0.5;
    final v = p[2];
    return v is! num || !v.isFinite ? 0.5 : v.toDouble();
  }

  final xs = <double>[], ys = <double>[], qs = <double>[];
  final ds = <double>[], os = <double>[];
  for (final p in points) {
    final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
    if (xs.isNotEmpty &&
        math.sqrt(math.pow(x - xs.last, 2) + math.pow(y - ys.last, 2)) < 0.01) {
      continue;
    }
    final pr = pressure(p as List);
    xs.add(x);
    ys.add(y);
    qs.add(curve?.q(pr) ?? pr.clamp(0.0, 1.0));
    ds.add(densityCurve?.q(pr) ?? pr.clamp(0.0, 1.0));
    os.add(alphaOf?.call(p) ?? opacityFactor);
  }
  if (xs.isEmpty) return const [];
  final n = xs.length;
  final cum = <double>[0];
  for (var i = 1; i < n; i++) {
    cum.add(
      cum.last +
          math.sqrt(
            math.pow(xs[i] - xs[i - 1], 2) + math.pow(ys[i] - ys[i - 1], 2),
          ),
    );
  }
  final total = cum.last;
  final seed = _fnv1a(id);
  final w0 = walk ?? PencilWalk();
  var seg = w0.seg, s = w0.s, k = w0.k;
  final out = <PencilStampV2>[];

  // Segment that holds [at]; a vertex belongs to the segment that starts at it.
  int segOf(int from, double at) {
    var g = math.min(math.max(from, 0), math.max(0, n - 2));
    while (g > 0 && cum[g] > at) {
      g--;
    }
    while (g < n - 2 && cum[g + 1] <= at) {
      g++;
    }
    return g;
  }

  double lerp(List<double> v, int g, double at) {
    if (n == 1) return v[0];
    final len = cum[g + 1] - cum[g];
    final t = len <= 0 ? 0.0 : ((at - cum[g]) / len).clamp(0.0, 1.0);
    return v[g] + (v[g + 1] - v[g]) * t;
  }

  while (true) {
    seg = segOf(seg, s);
    final last = !live && !(s < total - 1e-9);
    if (last) s = total;
    final q = lerp(qs, seg, s), qd = lerp(ds, seg, s);
    final f = q < 0.5 ? 0.6 + 0.8 * q : 0.7 + 0.6 * q;
    final w = width * f;
    final d = (0.35 + 0.6 * qd).clamp(0.0, 1.0) * density;
    final step = math.max(0.3, w * (0.9 - 0.78 * d));
    if (live && !(s < total - 1e-9 && s + 0.3 * step < total - 1e-9)) break;
    var x = (seed ^ k) & 0xFFFFFFFF;
    if (x == 0) x = 1;
    double draw() {
      x ^= (x << 13) & 0xFFFFFFFF;
      x ^= x >> 17;
      x ^= (x << 5) & 0xFFFFFFFF;
      return x / 4294967296;
    }

    final u1 = draw(), u2 = draw(), u3 = draw();
    final u4 = draw(), u5 = draw(), u6 = draw();
    final sp = (s + (2 * u6 - 1) * 0.3 * step).clamp(0.0, total);
    final g = segOf(seg, sp);
    double tx = 1, ty = 0;
    if (n > 1) {
      final len = cum[g + 1] - cum[g];
      tx = (xs[g + 1] - xs[g]) / len;
      ty = (ys[g + 1] - ys[g]) / len;
    }
    final off = (2 * u1 - 1) * 0.25 * w;
    out.add((
      x: _round2(lerp(xs, g, sp) + off * -ty),
      y: _round2(lerp(ys, g, sp) + off * tx),
      size: _round2(1.6 * w * (0.85 + 0.3 * u4)),
      angle: _round2(u2 * 360),
      alpha:
          (0.45 * (0.7 + 0.6 * u5) * lerp(os, g, sp) * 10000).roundToDouble() /
          10000,
      variant: math.min(2, (u3 * 3).floor()),
    ));
    nominal?.add(s);
    if (last) break;
    s += step;
    k++;
  }
  w0
    ..seg = seg
    ..s = s
    ..k = k;
  return out;
}

int _fnv1a(String id) {
  var h = 2166136261;
  for (final b in utf8.encode(id)) {
    h = ((h ^ b) * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

/// `density(q)` and `threshold(q)`; [q] is clamped to 0..1.
({double density, int threshold}) pencilDensity(double q) {
  final c = q.isNaN ? 0.5 : q.clamp(0.0, 1.0);
  final d = 0.35 + 0.6 * c;
  return (density: d, threshold: (d * 65536 + 1e-6).floor());
}

/// The three stamp images, loaded once. [images] is null until all are ready
/// (strokes then show the plain alpha polygon) and stays null if one cannot load.
class PencilTextures extends ChangeNotifier {
  PencilTextures({Future<Uint8List> Function(String asset)? load}) {
    _ready = _load(
      load ?? (a) async => (await rootBundle.load(a)).buffer.asUint8List(),
    );
  }

  List<ui.Image>? images;
  late final Future<void> _ready;
  var _disposed = false;

  /// Completes when the images are loaded (tests, export).
  Future<void> settled() => _ready;

  Future<void> _load(Future<Uint8List> Function(String asset) read) async {
    final got = <ui.Image>[];
    try {
      for (final a in pencilStampAssets) {
        final codec = await ui.instantiateImageCodec(await read(a));
        got.add((await codec.getNextFrame()).image);
        codec.dispose();
      }
    } catch (_) {
      for (final g in got) {
        g.dispose();
      }
      return; // alpha polygon stays
    }
    if (_disposed) {
      for (final g in got) {
        g.dispose();
      }
      return;
    }
    images = got;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final i in images ?? const <ui.Image>[]) {
      i.dispose();
    }
    images = null;
    super.dispose();
  }
}
