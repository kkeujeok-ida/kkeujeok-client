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

/// The stamp image, loaded once. [image] is null until it is ready (strokes then
/// show the plain alpha polygon) and stays null if the asset cannot load.
class PencilTextures extends ChangeNotifier {
  PencilTextures({Future<Uint8List> Function()? load}) {
    _ready = _load(
      load ??
          () async =>
              (await rootBundle.load(pencilStampAsset)).buffer.asUint8List(),
    );
  }

  ui.Image? image;
  late final Future<void> _ready;
  var _disposed = false;

  /// Completes when the tile is loaded (tests, export).
  Future<void> settled() => _ready;

  Future<void> _load(Future<Uint8List> Function() read) async {
    try {
      final codec = await ui.instantiateImageCodec(await read());
      final img = (await codec.getNextFrame()).image;
      codec.dispose();
      if (_disposed) {
        img.dispose();
        return;
      }
      image = img;
      notifyListeners();
    } catch (_) {
      // alpha polygon stays
    }
  }

  @override
  void dispose() {
    _disposed = true;
    image?.dispose();
    image = null;
    super.dispose();
  }
}
