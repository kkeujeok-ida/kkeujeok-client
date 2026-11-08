import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../model/pressure_curve.dart';
import '../model/smooth.dart';
import 'stroke_outline.dart';

// spec rule `stroke.texture.pencil` (spec/pen-kinds.md): integer maths only.
const pencilCell = 0.5;
const _mask = 0xFFFFFFFF;

/// 32-bit FNV-1a of the UTF-8 bytes of the stroke id.
int pencilSeed(String id) {
  var h = 0x811C9DC5;
  for (final b in utf8.encode(id)) {
    h = ((h ^ b) * 0x01000193) & _mask;
  }
  return h;
}

/// The grain 0..65535 of cell ([i], [j]); negative cells wrap modulo 2^32.
int pencilGrain(int seed, int i, int j) {
  var h =
      (seed ^
          (((i & _mask) * 0x9E3779B1) & _mask) ^
          (((j & _mask) * 0x85EBCA77) & _mask)) &
      _mask;
  h ^= h >> 16;
  h = (h * 0x85EBCA6B) & _mask;
  h ^= h >> 13;
  h = (h * 0xC2B2AE35) & _mask;
  h ^= h >> 16;
  return h >> 16;
}

/// `density(q)` and `threshold(q)`; [q] is clamped to 0..1.
({double density, int threshold}) pencilDensity(double q) {
  final c = q.isNaN ? 0.5 : q.clamp(0.0, 1.0);
  final d = 0.35 + 0.6 * c;
  return (density: d, threshold: (d * 65536 + 1e-6).floor());
}

/// The cell holding page point ([x], [y]).
({int i, int j}) pencilCellOf(double x, double y) =>
    (i: (x / pencilCell).floor(), j: (y / pencilCell).floor());

/// The inked cells of one stroke: [w] x [h] RGBA pixels (white, opaque where
/// inked) for the cells starting at ([i0], [j0]).
class PencilCells {
  PencilCells(this.i0, this.j0, this.w, this.h, this.pixels);
  final int i0, j0, w, h;
  final Uint8List pixels;

  bool inked(int i, int j) {
    final u = i - i0, v = j - j0;
    return u >= 0 &&
        v >= 0 &&
        u < w &&
        v < h &&
        pixels[(v * w + u) * 4 + 3] != 0;
  }
}

/// Cuts the texture out of [polygon] (non-zero rule). A cell is inked when its
/// centre is inside and `grain < threshold(q)`, `q` from the nearest sample
/// (lower index on a tie). Null when the box exceeds [maxCells] or [maxSide].
PencilCells? buildPencilCells(
  List<List<double>> polygon,
  ({List<double> x, List<double> y, List<double> q, double length}) smp,
  int seed, {
  int maxCells = 4000000,
  int maxSide = 8192,
}) {
  if (polygon.length < 3 || smp.x.isEmpty) return null;
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in polygon) {
    minX = math.min(minX, p[0]);
    maxX = math.max(maxX, p[0]);
    minY = math.min(minY, p[1]);
    maxY = math.max(maxY, p[1]);
  }
  final i0 = (minX / pencilCell).floor(), j0 = (minY / pencilCell).floor();
  final w = (maxX / pencilCell).floor() - i0 + 1;
  final h = (maxY / pencilCell).floor() - j0 + 1;
  if (w > maxSide || h > maxSide || w * h > maxCells) return null;

  // Crossings of the cell-centre rows with the polygon edges, with winding.
  final rows = List<List<(double, int)>?>.filled(h, null);
  for (var k = 0; k < polygon.length; k++) {
    final a = polygon[k], b = polygon[(k + 1) % polygon.length];
    if (a[1] == b[1]) continue;
    final lo = math.min(a[1], b[1]), hi = math.max(a[1], b[1]);
    final dir = b[1] > a[1] ? 1 : -1;
    final jFrom = math.max(j0, (lo / pencilCell - 0.5).ceil());
    final jTo = math.min(j0 + h - 1, (hi / pencilCell - 0.5).ceil() - 1);
    for (var j = jFrom; j <= jTo; j++) {
      final yc = (j + 0.5) * pencilCell;
      final x = a[0] + (yc - a[1]) * (b[0] - a[0]) / (b[1] - a[1]);
      (rows[j - j0] ??= []).add((x, dir));
    }
  }

  // Bucket grid of the samples for the nearest-sample search.
  const bs = 4.0;
  final n = smp.x.length;
  var sMinX = double.infinity, sMinY = double.infinity;
  var sMaxX = -double.infinity, sMaxY = -double.infinity;
  for (var s = 0; s < n; s++) {
    sMinX = math.min(sMinX, smp.x[s]);
    sMaxX = math.max(sMaxX, smp.x[s]);
    sMinY = math.min(sMinY, smp.y[s]);
    sMaxY = math.max(sMaxY, smp.y[s]);
  }
  final gw = ((sMaxX - sMinX) / bs).floor() + 1;
  final gh = ((sMaxY - sMinY) / bs).floor() + 1;
  final grid = List<List<int>?>.filled(gw * gh, null);
  for (var s = 0; s < n; s++) {
    final gx = ((smp.x[s] - sMinX) / bs).floor();
    final gy = ((smp.y[s] - sMinY) / bs).floor();
    (grid[gy * gw + gx] ??= []).add(s);
  }
  double nearestQ(double cx, double cy) {
    final gx = ((cx - sMinX) / bs).floor(), gy = ((cy - sMinY) / bs).floor();
    var best = double.infinity;
    var bestIdx = 0;
    for (var k = 0; k <= gw + gh + 3; k++) {
      if (best.isFinite) {
        // Distance from the centre to outside the buckets already searched.
        final margin = math.min(
          math.min(
            cx - (sMinX + (gx - k + 1) * bs),
            sMinX + (gx + k) * bs - cx,
          ),
          math.min(
            cy - (sMinY + (gy - k + 1) * bs),
            sMinY + (gy + k) * bs - cy,
          ),
        );
        if (math.sqrt(best) <= margin) break;
      }
      for (var y = gy - k; y <= gy + k; y++) {
        if (y < 0 || y >= gh) continue;
        final edge = y == gy - k || y == gy + k;
        for (var x = gx - k; x <= gx + k; x += edge || k == 0 ? 1 : 2 * k) {
          if (x < 0 || x >= gw) continue;
          final list = grid[y * gw + x];
          if (list == null) continue;
          for (final s in list) {
            final dx = smp.x[s] - cx, dy = smp.y[s] - cy;
            final d = dx * dx + dy * dy;
            if (d < best || (d == best && s < bestIdx)) {
              best = d;
              bestIdx = s;
            }
          }
        }
      }
    }
    return smp.q[bestIdx];
  }

  final maxThreshold = pencilDensity(1).threshold;
  final px = Uint8List(w * h * 4);
  for (var r = 0; r < h; r++) {
    final cr = rows[r];
    if (cr == null) continue;
    cr.sort((p, q) => p.$1.compareTo(q.$1));
    final j = j0 + r, cy = (j + 0.5) * pencilCell;
    var wind = 0;
    for (var k = 0; k + 1 < cr.length; k++) {
      wind += cr[k].$2;
      if (wind == 0) continue;
      final iFrom = math.max(i0, (cr[k].$1 / pencilCell - 0.5).ceil());
      final iTo = math.min(i0 + w, (cr[k + 1].$1 / pencilCell - 0.5).ceil());
      for (var i = iFrom; i < iTo; i++) {
        final g = pencilGrain(seed, i, j);
        if (g >= maxThreshold) continue;
        if (g >=
            pencilDensity(nearestQ((i + 0.5) * pencilCell, cy)).threshold) {
          continue;
        }
        final o = ((r * w) + (i - i0)) * 4;
        px[o] = px[o + 1] = px[o + 2] = px[o + 3] = 255;
      }
    }
  }
  return PencilCells(i0, j0, w, h, px);
}

/// A ready texture: [image] covers [dst] in the frame it was built in; draw it
/// under the similarity [m] `[a, b, tx, ty]` (x' = a x - b y + tx,
/// y' = b x + a y + ty), null when the stroke has not moved.
typedef PencilDraw = ({ui.Image image, ui.Rect dst, List<double>? m});

class _Entry {
  _Entry(this.id, this.sig, this.points, this.width, this.usePressure)
    : frame = _xy(points);
  final String id;
  final List<Object?> sig;
  final List points;
  final double width;
  final bool usePressure;
  final Float64List frame; // x, y of every point when the texture was built
  ui.Image? image; // null while queued, building, or too big for a texture
  ui.Rect dst = ui.Rect.zero;
  int cells = 0, used = 0;
  List<double>? m, curKey;
  bool lost = false; // moved in a way a rigid change cannot describe

  static Float64List _xy(List pts) {
    final f = Float64List(pts.length * 2);
    for (var i = 0; i < pts.length; i++) {
      f[2 * i] = (pts[i][0] as num).toDouble();
      f[2 * i + 1] = (pts[i][1] as num).toDouble();
    }
    return f;
  }
}

/// Cell images of finished pencil strokes by id (never stored in the note).
/// Built one stroke at a time off the paint path; [lookup] is null until a
/// texture is ready, then the caller draws the alpha polygon. A move, scale or
/// rotate that is a similarity (0.5..2) reuses the image under a transform.
class PencilTextures extends ChangeNotifier {
  static const maxTotalCells = 16000000;
  final _byId = <String, _Entry>{};
  final _queue = <_Entry>[];
  var _running = false, _clock = 0, _total = 0;

  /// Completes when every queued build is done (tests).
  Future<void> settled() async {
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  PencilDraw? lookup(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final pts = s['points'] as List;
    if (pts.isEmpty) return null;
    final sig = <Object?>[
      pts.length,
      s['width'],
      s['usePressure'],
      ...pressureCurveInUse.values,
      smoothInUse,
    ];
    var e = _byId[id];
    if (e != null && (e.lost || !listEquals(e.sig, sig))) {
      _drop(e);
      e = null;
    }
    if (e == null) {
      e = _Entry(
        id,
        sig,
        pts,
        (s['width'] as num).toDouble(),
        s['usePressure'] as bool,
      );
      _byId[id] = e;
      _queue.add(e);
      _pump();
    }
    e.used = ++_clock;
    final img = e.image;
    if (img == null) return null;
    final mid = pts.length ~/ 2, last = pts.length - 1;
    final key = <double>[
      for (final i in [0, mid, last]) ...[
        (pts[i][0] as num).toDouble(),
        (pts[i][1] as num).toDouble(),
      ],
    ];
    if (e.curKey == null || !listEquals(e.curKey, key)) {
      e.curKey = key;
      final fit = _fit(e.frame, pts);
      if (fit == null) {
        e.lost = true;
        return null;
      }
      e.m = fit.isEmpty ? null : fit;
    }
    return (image: img, dst: e.dst, m: e.m);
  }

  /// Forgets strokes that are no longer on the page.
  void keepOnly(Set<String> ids) {
    for (final e in [..._byId.values]) {
      if (!ids.contains(e.id)) _drop(e);
    }
  }

  void _drop(_Entry e) {
    if (identical(_byId[e.id], e)) _byId.remove(e.id);
    _total -= e.cells;
    e.cells = 0;
    e.image?.dispose();
    e.image = null;
    e.lost = true;
  }

  // The similarity taking the build frame to [pts]: solved from the first two
  // distinct points, checked at the middle and last point to 0.01. Null when
  // it does not hold or the scale is outside 0.5..2; empty for no change.
  static List<double>? _fit(Float64List f, List pts) {
    double x(int i) => (pts[i][0] as num).toDouble();
    double y(int i) => (pts[i][1] as num).toDouble();
    var k = 0;
    for (var i = 1; i < pts.length; i++) {
      if ((f[2 * i] - f[0]).abs() > 1e-9 ||
          (f[2 * i + 1] - f[1]).abs() > 1e-9) {
        k = i;
        break;
      }
    }
    var a = 1.0, b = 0.0;
    if (k > 0) {
      final ax = f[2 * k] - f[0], ay = f[2 * k + 1] - f[1];
      final bx = x(k) - x(0), by = y(k) - y(0);
      final d = ax * ax + ay * ay;
      a = (bx * ax + by * ay) / d;
      b = (by * ax - bx * ay) / d;
      final sc = math.sqrt(a * a + b * b);
      if (!(sc >= 0.5 && sc <= 2)) return null;
    }
    final tx = x(0) - (a * f[0] - b * f[1]);
    final ty = y(0) - (b * f[0] + a * f[1]);
    for (final i in [pts.length ~/ 2, pts.length - 1]) {
      final ex = a * f[2 * i] - b * f[2 * i + 1] + tx;
      final ey = b * f[2 * i] + a * f[2 * i + 1] + ty;
      if ((ex - x(i)).abs() > 0.01 || (ey - y(i)).abs() > 0.01) return null;
    }
    final id =
        (a - 1).abs() < 1e-9 &&
        b.abs() < 1e-9 &&
        tx.abs() < 1e-9 &&
        ty.abs() < 1e-9;
    return id ? const [] : [a, b, tx, ty];
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        await Future<void>.delayed(Duration.zero); // let frames run between
        final e = _queue.removeAt(0);
        if (!identical(_byId[e.id], e)) continue;
        final pts = smoothPoints(e.points, smoothInUse);
        final cells = buildPencilCells(
          strokeOutlineFor('pencil', e.width, e.usePressure, pts),
          strokeSamples(e.usePressure, pts),
          pencilSeed(e.id),
        );
        if (cells == null) continue; // too big or empty: alpha polygon
        final done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          cells.pixels,
          cells.w,
          cells.h,
          ui.PixelFormat.rgba8888,
          done.complete,
        );
        final img = await done.future;
        if (!identical(_byId[e.id], e)) {
          img.dispose();
          continue;
        }
        e.image = img;
        e.cells = cells.w * cells.h;
        e.dst = ui.Rect.fromLTWH(
          cells.i0 * pencilCell,
          cells.j0 * pencilCell,
          cells.w * pencilCell,
          cells.h * pencilCell,
        );
        _total += e.cells;
        _evict(e);
        notifyListeners();
      }
    } finally {
      _running = false;
    }
  }

  // Least recently used first, never [keep].
  void _evict(_Entry keep) {
    if (_total <= maxTotalCells) return;
    final old = _byId.values.where((e) => e != keep && e.image != null).toList()
      ..sort((a, b) => a.used.compareTo(b.used));
    for (final e in old) {
      if (_total <= maxTotalCells) break;
      _drop(e);
    }
  }
}
