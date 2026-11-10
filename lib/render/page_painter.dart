import 'dart:convert' show jsonEncode;
import 'dart:math' as math;
import 'dart:ui' as ui show Image;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/brush.dart';
import '../model/curve.dart' show opacityPressureCurve;
import '../model/invert.dart';
import '../model/pressure_curve.dart';
import '../model/shape.dart' show shapeRings;
import '../model/smooth.dart';
import '../ui/kk.dart';
import 'asset_images.dart';
import 'pdf_pages.dart';
import '../model/pdf_rules.dart' show isPdfBackground, patternOf;
import 'page_background.dart';
import 'live_stroke.dart';
import 'pencil_texture.dart';
import 'stroke_outline.dart';
import 'text_painter.dart';

/// How the page sits in its widget: page point = (local - offset) / scale.
class PageViewport {
  const PageViewport(this.scale, this.offset);

  final double scale;
  final Offset offset;

  Offset toPage(Offset local) => (local - offset) / scale;

  static const zoomMin = 0.5;
  static const zoomMax = 8.0;

  static bool _ok(Size size, double w, double h, EdgeInsets pad) {
    final aw = size.width - pad.horizontal, ah = size.height - pad.vertical;
    return w.isFinite &&
        h.isFinite &&
        w > 0 &&
        h > 0 &&
        aw.isFinite &&
        ah.isFinite &&
        aw > 0 &&
        ah > 0;
  }

  /// The page fitted whole and centered in [size] with [pad] on every side.
  factory PageViewport.fit(Size size, double w, double h, EdgeInsets pad) {
    if (!_ok(size, w, h, pad)) {
      return PageViewport(1, Offset(pad.left, pad.top));
    }
    final aw = size.width - pad.horizontal, ah = size.height - pad.vertical;
    final scale = (aw / w < ah / h ? aw / w : ah / h).clamp(0.01, 1e6);
    return PageViewport(
      scale,
      Offset(pad.left + (aw - w * scale) / 2, pad.top + (ah - h * scale) / 2),
    );
  }

  /// The page as wide as the padded area (scale kept in the zoom range),
  /// centered across and with its top at the padded area's top.
  factory PageViewport.fitWidth(Size size, double w, double h, EdgeInsets pad) {
    if (!_ok(size, w, h, pad)) {
      return PageViewport(1, Offset(pad.left, pad.top));
    }
    final aw = size.width - pad.horizontal;
    final scale = (aw / w).clamp(zoomMin, zoomMax);
    return PageViewport(
      scale,
      Offset(pad.left + (aw - w * scale) / 2, pad.top),
    );
  }

  /// This scale with the offset moved into range. An axis where the page is
  /// no larger than the padded area is centered; on a larger one the page
  /// edge may not pass the padded area's edge. [extraBottom] is added below.
  PageViewport clamped(
    Size size,
    double w,
    double h,
    EdgeInsets pad, {
    double extraBottom = 0,
  }) {
    if (!_ok(size, w, h, pad)) return this;
    double axis(double o, double len, double lo, double hi, double extra) {
      final area = hi - lo;
      if (len <= area) return lo + (area - len) / 2;
      return o.clamp(hi - extra - len, lo);
    }

    return PageViewport(
      scale,
      Offset(
        axis(offset.dx, w * scale, pad.left, size.width - pad.right, 0),
        axis(
          offset.dy,
          h * scale,
          pad.top,
          size.height - pad.bottom,
          extraBottom,
        ),
      ),
    );
  }

  /// [newScale] (kept in the zoom range) with the page point under [focal]
  /// staying under it. Not clamped to the page: call [clamped] after.
  PageViewport zoomAbout(Offset focal, double newScale) {
    final s = newScale.clamp(zoomMin, zoomMax);
    return PageViewport(s, focal - toPage(focal) * s);
  }
}

/// True for an element [StrokePathCache] and the painter can draw.
bool drawableStroke(Object? e) =>
    e is Map<String, dynamic> &&
    e['type'] == 'stroke' &&
    e['id'] is String &&
    e['points'] is List &&
    e['width'] is num &&
    e['usePressure'] is bool;

/// The fill path of a stroke: pen outline, or the highlighter's rectangles.
/// The smoothing level is applied here, on screen only (export calls
/// [strokeOutline] directly).
Path strokePath(Map<String, dynamic> s) {
  // A shape is a closed ring of one width, whatever the pen (spec/shape.md).
  final rings = shapeRings(s['shape'], (s['width'] as num).toDouble());
  if (rings != null) {
    final path = Path();
    for (final r in rings) {
      path.addPolygon([for (final p in r) Offset(p[0], p[1])], true);
    }
    return path;
  }
  return polygonsPath(s['tool'], piecePolygons(s, s['points'] as List));
}

/// The polygons of [points] of stroke [s] (all its points, or a piece of a
/// live stroke). [head]/[tail]: the piece starts/ends at the stroke's own
/// start/end, which only matters for the fountain taper.
List<List<List<double>>> piecePolygons(
  Map<String, dynamic> s,
  List points, {
  bool head = true,
  bool tail = true,
  int? cutFrom,
  int? cutTo,
}) {
  final pts = smoothPoints(points, smoothInUse);
  // [cutFrom]/[cutTo] are indices in [points]; smoothing doubles them.
  final dense = smoothInUse > 0 && points.length >= 3 ? 2 : 1;
  final from = cutFrom == null ? null : cutFrom * dense;
  final to = cutTo == null ? null : cutTo * dense;
  final w = (s['width'] as num).toDouble();
  if (s['tool'] == 'highlighter') {
    return highlighterPolygons(
      w,
      pts.sublist(from ?? 0, to == null ? null : to + 1),
    );
  }
  final tool = s['tool'] as String?, up = s['usePressure'] as bool? ?? true;
  if (s['brush'] == null) {
    return [
      strokeOutlineFor(tool, w, up, pts, null, null, head, tail, from, to),
    ];
  }
  final b = brushResolve(tool, s['brush']);
  return [
    strokeOutlineFor(
      tool,
      w,
      up,
      pts,
      b.pressureCurve == null ? null : PressureCurve.fromCurve(b.pressureCurve),
      b.sizeTiltCurve == null
          ? null
          : (p) => tiltSizeFactor(p, PressureCurve.fromCurve(b.sizeTiltCurve)),
      head,
      tail,
      from,
      to,
    ),
  ];
}

/// True when stroke [s] is drawn with an alpha per point: a pen or fountain
/// stroke (no stamps, no shape) with an opacity pressure or tilt curve
/// (spec/brush.md "Drawing per-point alpha"). Other strokes keep one layer alpha.
bool perPointAlpha(Map<String, dynamic> s) {
  final t = s['tool'];
  if (t == 'highlighter' || t == 'tape' || t == 'pencil') return false;
  if (s['brush'] == null || s['shape'] != null || brushDraw(s).grain) {
    return false;
  }
  final b = brushResolve(t, s['brush']);
  return b.opacityTiltCurve != null ||
      (!b.curvesOff.contains('opacityPressure') &&
          opacityPressureCurve(s['brush']) != null);
}

typedef AlphaPiece = ({Path path, double alpha});

/// The pieces of a [perPointAlpha] stroke: one quad per gap between outline
/// samples, each starting half a gap early so neighbours overlap, plus the two
/// round caps. Draw them in order with [fillAlphaPieces]. Arguments as
/// [piecePolygons].
List<AlphaPiece> alphaPieces(
  Map<String, dynamic> s,
  List points, {
  bool head = true,
  bool tail = true,
  int? cutFrom,
  int? cutTo,
}) {
  final pts = smoothPoints(points, smoothInUse);
  final dense = smoothInUse > 0 && points.length >= 3 ? 2 : 1;
  final from = cutFrom == null ? null : cutFrom * dense;
  final to = cutTo == null ? null : cutTo * dense;
  final w = (s['width'] as num).toDouble();
  final tool = s['tool'] as String?, up = s['usePressure'] as bool? ?? true;
  final b = brushResolve(tool, s['brush']);
  final curve = b.pressureCurve == null
      ? null
      : PressureCurve.fromCurve(b.pressureCurve);
  final sizeOf = b.sizeTiltCurve == null
      ? null
      : (List p) => tiltSizeFactor(p, PressureCurve.fromCurve(b.sizeTiltCurve));
  final oc = b.curvesOff.contains('opacityPressure')
      ? null
      : opacityPressureCurve(s['brush']);
  double? at(List p, int i) =>
      p.length > i && p[i] is num ? (p[i] as num).toDouble() : null;
  double alphaOf(List p) => brushAlpha(
    opacity: b.opacity,
    opacityPressureCurve: oc,
    opacityTiltCurve: b.opacityTiltCurve,
    pressure: at(p, 2),
    tilt: at(p, 4),
    usePressure: up,
  );
  final poly = strokeOutlineFor(
    tool,
    w,
    up,
    pts,
    curve,
    sizeOf,
    head,
    tail,
    from,
    to,
  );
  // Same samples as the outline; the size channel carries the alpha instead.
  final a = strokeSamples(up, pts, curve, alphaOf, from, to).m;
  if (poly.isEmpty || a.isEmpty) return [];
  Path ring(Iterable<List<double>> ps) =>
      Path()..addPolygon([for (final p in ps) Offset(p[0], p[1])], true);
  if (a.length == 1) return [(path: ring(poly), alpha: a[0])];
  // polygon = left(N), end cap(7), right reversed(N), start cap(7)
  final n = a.length;
  List<double> l(int i) => poly[i];
  List<double> r(int i) => poly[n + 7 + (n - 1 - i)];
  List<double> mid(List<double> p, List<double> q) => [
    (p[0] + q[0]) / 2,
    (p[1] + q[1]) / 2,
  ];
  return [
    (path: ring([r(0), ...poly.sublist(2 * n + 7), l(0)]), alpha: a.first),
    for (var i = 0; i < n - 1; i++)
      (
        path: ring([
          i == 0 ? l(0) : mid(l(i - 1), l(i)),
          l(i + 1),
          r(i + 1),
          i == 0 ? r(0) : mid(r(i - 1), r(i)),
        ]),
        alpha: (a[i] + a[i + 1]) / 2,
      ),
    (
      path: ring([l(n - 1), ...poly.sublist(n, n + 7), r(n - 1)]),
      alpha: a.last,
    ),
  ];
}

/// Draws [pieces] in one layer, each with `BlendMode.src` so a later piece
/// replaces an earlier one: seams and self-crossings do not get darker.
void fillAlphaPieces(
  Canvas c,
  Iterable<AlphaPiece> pieces,
  Object? color, {
  double fade = 1,
  bool invert = false,
}) {
  if (pieces.isEmpty) return;
  final base = parseColor(invert && color is String ? inkHex(color) : color);
  var box = pieces.first.path.getBounds();
  for (final p in pieces) {
    box = box.expandToInclude(p.path.getBounds());
  }
  c.saveLayer(box.inflate(1), Paint());
  for (final p in pieces) {
    p.path.fillType = PathFillType.nonZero;
    c.drawPath(
      p.path,
      Paint()
        ..blendMode = BlendMode.src
        ..isAntiAlias = true
        ..color = base.withValues(
          alpha: (base.a * p.alpha * fade).clamp(0.0, 1.0),
        ),
    );
  }
  c.restore();
}

Path polygonsPath(Object? tool, List<List<List<double>>> polys) =>
    tool == 'highlighter' ? highlighterPath(polys) : outlinePath(polys.first);

/// Layer alpha of a stroke from its brush, and whether it is drawn through
/// the pencil grain (spec/brush.md).
({double alpha, bool grain}) brushDraw(Map<String, dynamic> s) {
  final tool = s['tool'];
  final grain = tool == 'highlighter' || tool == 'tape'
      ? false
      : s['brush'] == null
      ? tool == 'pencil'
      : brushResolve(tool, s['brush']).texture == 'pencil';
  return (
    // grain: the stamps carry the pressure opacity (paintPencil adds it back
    // for the plain fallback)
    alpha: brushAlphaFactor(
      tool,
      s['brush'],
      s['points'] as List,
      s['usePressure'] as bool? ?? true,
      !grain,
    ),
    grain: grain,
  );
}

/// Fills [p] with [color]. A highlighter is one layer in the opaque color,
/// composited once at 0.4 with multiply, so it never darkens on itself.
/// [invert] (All Dark): a pen color is shown as `invert.ink`; a highlighter
/// keeps its color and composites source-over at 0.4 (spec/invert.md).
void fillStroke(
  Canvas c,
  Path p,
  Object? color, {
  bool highlighter = false,
  double alpha = 1,
  bool invert = false,
  Path? extra,
}) {
  p.fillType = PathFillType.nonZero;
  extra?.fillType = PathFillType.nonZero;
  final base = parseColor(
    invert && !highlighter && color is String ? inkHex(color) : color,
  );
  // [extra] (a live stroke's open piece) joins [p] in one layer when the layer
  // alpha or the multiply blend would show their overlap twice.
  final layered = highlighter || (extra != null && alpha != 1);
  final fill = Paint()
    ..color = layered || alpha == 1
        ? base
        : base.withValues(alpha: base.a * alpha)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  if (!layered) {
    c.drawPath(p, fill);
    if (extra != null) c.drawPath(extra, fill);
    return;
  }
  c.saveLayer(
    (extra == null
            ? p.getBounds()
            : p.getBounds().expandToInclude(extra.getBounds()))
        .inflate(1),
    Paint()
      ..blendMode = highlighter && !invert
          ? BlendMode.multiply
          : BlendMode.srcOver
      ..color = Color.fromRGBO(
        255,
        255,
        255,
        highlighter ? 0.4 * alpha : alpha,
      ),
  );
  c.drawPath(p, fill);
  if (extra != null) c.drawPath(extra, fill);
  c.restore();
}

/// Fills the plain pencil polygon [p] at the pencil density (texture `none`,
/// or the stamp image is not loaded).
void fillPencil(
  Canvas c,
  Path p,
  Object? color,
  double density, {
  double alpha = 1,
  bool invert = false,
}) {
  final base = parseColor(invert && color is String ? inkHex(color) : color);
  c.drawPath(
    p,
    Paint()..color = base.withValues(alpha: base.a * alpha * density),
  );
}

/// The stamps of a stroke ready for `drawAtlas` (one call per image variant).
/// [add] appends, so a live stroke keeps its earlier stamps.
class StampBatch {
  StampBatch(this.base, this.factor);

  final Color base;
  final double factor;
  static const _stampPx = 128.0;
  final _layers = [for (var i = 0; i < 3; i++) _Layer()];

  int get length => _layers.fold(0, (n, l) => n + l.colors.length);

  void add(List<PencilStampV2> stamps) {
    for (final t in stamps) {
      final l = _layers[t.variant.clamp(0, 2)];
      final sc = t.size / _stampPx;
      final r = t.angle * math.pi / 180;
      // RSTransform.fromComponents with the anchor at the stamp centre.
      final scos = math.cos(r) * sc, ssin = math.sin(r) * sc;
      l.transforms.add(
        RSTransform(
          scos,
          ssin,
          t.x - scos * _stampPx / 2 + ssin * _stampPx / 2,
          t.y - ssin * _stampPx / 2 - scos * _stampPx / 2,
        ),
      );
      l.rects.add(const Rect.fromLTWH(0, 0, _stampPx, _stampPx));
      l.colors.add(
        base.withValues(alpha: (base.a * t.alpha * factor).clamp(0.0, 1.0)),
      );
    }
  }

  void paint(Canvas c, List<ui.Image> images) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (var v = 0; v < 3; v++) {
      final l = _layers[v];
      if (l.colors.isEmpty) continue;
      c.drawAtlas(
        images[v],
        l.transforms,
        l.rects,
        l.colors,
        BlendMode.modulate, // the stamp is white: colour x its alpha
        null,
        paint,
      );
    }
  }
}

class _Layer {
  final transforms = <RSTransform>[], rects = <Rect>[], colors = <Color>[];
}

/// Stamps of a stroke (spec stroke.texture.stamps) from its id, points and
/// brush. The device pressure curve applies unless the brush has its own.
/// [live] with a [walk]: only the stamps new since the walk's last call.
List<PencilStampV2> stampsOf(
  Map<String, dynamic> s, {
  bool live = false,
  PencilWalk? walk,
}) {
  final b = brushResolve(s['tool'], s['brush']);
  final up = s['usePressure'] as bool? ?? true;
  final oc = b.curvesOff.contains('opacityPressure')
      ? null
      : opacityPressureCurve(s['brush']);
  double? at(List p, int i) =>
      p.length > i && p[i] is num ? (p[i] as num).toDouble() : null;
  return pencilStampsV2(
    id: s['id'] as String,
    width: (s['width'] as num).toDouble(),
    usePressure: up,
    points: s['points'] as List,
    density: b.density,
    opacityFactor: b.opacity,
    live: live,
    walk: walk,
    curve: !up
        ? null
        : b.pressureCurve == null || b.curvesOff.contains('pressure')
        ? pressureCurveInUse
        : PressureCurve.fromCurve(b.pressureCurve),
    densityCurve: !up || b.densityPressureCurve == null
        ? null
        : PressureCurve.fromCurve(b.densityPressureCurve),
    // shortcut: with no opacity curve the alpha is the constant brush opacity;
    // upgrade with a per-point cache if curves make live frames slow.
    alphaOf: oc == null && b.opacityTiltCurve == null
        ? null
        : (p) => brushAlpha(
            opacity: b.opacity,
            opacityPressureCurve: oc,
            opacityTiltCurve: b.opacityTiltCurve,
            pressure: at(p, 2),
            tilt: at(p, 4),
            usePressure: up,
          ),
  );
}

/// Draws a stroke's pencil look: stamps along its path, or the plain polygon
/// when [stamp] is null (texture `none`, image not loaded). [batch] is the
/// stamp batch to reuse, built on demand.
void paintPencil(
  Canvas c,
  Map<String, dynamic> s,
  List<ui.Image>? stamp,
  Path Function() polygon, {
  required double fade,
  required bool invert,
  StampBatch? batch,
}) {
  final bd = brushDraw(s);
  if (stamp == null || !bd.grain) {
    return fillPencil(
      c,
      polygon(),
      s['color'],
      pencilAlpha(s),
      alpha:
          fade *
          (bd.grain
              ? brushAlphaFactor(
                  s['tool'],
                  s['brush'],
                  s['points'] as List,
                  s['usePressure'] as bool? ?? true,
                )
              : bd.alpha),
      invert: invert,
    );
  }
  (batch ?? buildBatch(s, fade, invert)).paint(c, stamp);
}

StampBatch buildBatch(Map<String, dynamic> s, double fade, bool invert) {
  final color = s['color'];
  final base = parseColor(invert && color is String ? inkHex(color) : color);
  // The stamps carry the whole brush alpha (opacity, pressure, tilt).
  return StampBatch(base, fade)..add(stampsOf(s));
}

/// Mean-pressure density of a pencil stroke: how dark it is overall.
double pencilAlpha(Map<String, dynamic> s) => pencilDensity(
  meanPressure(s['usePressure'] as bool? ?? true, s['points'] as List),
).density;

/// What is kept of the stroke being drawn (spec rule `stroke.liveFreeze`).
/// Pens: the points are cut into pieces of [chunk] kept points that share
/// their joint; a piece that ends inside the frozen part (all but the last
/// three points) is built once and kept. Resampling and smoothing look at the
/// whole stroke, so one outline of it would shift every frame; only the open
/// piece at the end is built again. Pencil stamps: the live list is
/// append-only, so each frame adds the new stamps only.
class LiveCache {
  static const chunk = 8, margin = 6;

  List<Object?>? _key;
  Path _frozen = Path();

  /// The polygons of the closed pieces, in order.
  final polygons = <List<List<double>>>[];
  int _start = 0, _kept = 0;
  List<num>? _first, _joint;

  PencilWalk _walk = PencilWalk();
  StampBatch? _batch;
  int _stampKept = 0;
  List<num>? _stampLast;

  /// Per-point alpha stroke ([perPointAlpha]): the closed pieces (their alpha
  /// is fixed once made) and the open piece of the last [pathOf].
  final frozenAlpha = <AlphaPiece>[];
  List<AlphaPiece> openAlpha = [];

  void _reset() {
    _frozen = Path();
    frozenAlpha.clear();
    openAlpha = [];
    polygons.clear();
    _start = _kept = _stampKept = 0;
    _first = _joint = _stampLast = null;
    _walk = PencilWalk();
    _batch = null;
  }

  // Plain equality, but maps and lists by content (the brush is rebuilt per frame).
  static bool _sameJson(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _sameJson(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          [for (var i = 0; i < a.length; i++) _sameJson(a[i], b[i])]
              .every((e) => e);
    }
    return a == b;
  }

  static List<num> _xy(List p) => [p[0] as num, p[1] as num];

  static bool _eq(List<num>? a, List p) =>
      a != null && a[0] == p[0] && a[1] == p[1];

  void _sync(Map<String, dynamic> s, Object? extra) {
    final key = [
      s['id'],
      s['tool'],
      s['width'],
      s['usePressure'],
      s['brush'],
      s['color'],
      extra,
      smoothInUse,
      ...pressureCurveInUse.values,
    ];
    if (_key == null || !_sameJson(_key, key)) {
      _reset();
      _key = key;
    }
  }

  /// The polygons of the open piece built by the last [pathOf].
  List<List<List<double>>> openPolygons = [];

  /// Forgets the stroke (pen up or cancel; the next pen down starts clean).
  void clear() {
    if (_key == null) return;
    _reset();
    _key = null;
  }

  /// The live pen stroke [s] as its kept [frozen] part and the [open] piece.
  ({Path frozen, Path open}) pathOf(Map<String, dynamic> s) {
    _sync(s, 'path');
    final kept = keptPoints(s['points'] as List);
    if (kept.length < _kept ||
        (kept.isNotEmpty && _first != null && !_eq(_first, kept.first)) ||
        (_joint != null && !_eq(_joint, kept[_start]))) {
      _reset();
      _key = null;
      return pathOf(s);
    }
    _kept = kept.length;
    if (kept.isNotEmpty) _first ??= _xy(kept.first);
    final frozen = math.max(0, kept.length - 3);
    final pp = perPointAlpha(s);
    // Smoothing and resampling reach [margin] points beyond a piece, so a piece
    // is built from a window around it and cut back to its own points: its
    // ends then match what the whole stroke gives at pen up.
    while (true) {
      final e = _start + chunk - 1;
      if (e > frozen - 1 || e + margin > kept.length - 1) break;
      final ws = math.max(0, _start - margin);
      if (pp) {
        frozenAlpha.addAll(
          alphaPieces(
            s,
            kept.sublist(ws, e + margin + 1),
            head: _start == 0,
            tail: false,
            cutFrom: _start - ws,
            cutTo: e - ws,
          ),
        );
      } else {
        final polys = piecePolygons(
          s,
          kept.sublist(ws, e + margin + 1),
          head: _start == 0,
          tail: false,
          cutFrom: _start - ws,
          cutTo: e - ws,
        );
        polygons.addAll(polys);
        _frozen.addPath(polygonsPath(s['tool'], polys), Offset.zero);
      }
      _start = e;
      _joint = _xy(kept[_start]);
    }
    final ws = math.max(0, _start - margin);
    if (pp) {
      openAlpha = alphaPieces(
        s,
        kept.sublist(ws),
        head: _start == 0,
        cutFrom: _start - ws,
      );
      return (frozen: _frozen, open: Path());
    }
    openPolygons = piecePolygons(
      s,
      kept.sublist(ws),
      head: _start == 0,
      cutFrom: _start - ws,
    );
    return (frozen: _frozen, open: polygonsPath(s['tool'], openPolygons));
  }

  /// The stamps of the live pencil stroke [s], with the new ones added.
  StampBatch batchOf(Map<String, dynamic> s, bool invert) {
    _sync(s, invert);
    final kept = keptPoints(s['points'] as List);
    if (kept.length < _stampKept ||
        (_stampKept > 0 && !_eq(_stampLast, kept[_stampKept - 1]))) {
      _reset();
      _key = null;
      return batchOf(s, invert);
    }
    final color = s['color'];
    final b = _batch ??= StampBatch(
      parseColor(invert && color is String ? inkHex(color) : color),
      1,
    );
    b.add(stampsOf(s, live: true, walk: _walk));
    _stampKept = kept.length;
    _stampLast = kept.isEmpty ? null : _xy(kept.last);
    return b;
  }
}

/// Finished-stroke outlines by stroke id, so a repaint does not rebuild them.
/// The key holds what an edit could change: count, ends, width, pressure.
class StrokePathCache {
  /// The pencil stamp image (spec/pen-kinds.md); notifies the painter when loaded.
  final textures = PencilTextures();

  /// The stroke being drawn: its frozen part is kept between frames.
  final live = LiveCache();
  final _byId = <String, (List<Object?>, Path)>{};
  final _batches = <String, (List<Object?>, StampBatch)>{};

  static List<Object?> _key(Map<String, dynamic> s) {
    final pts = s['points'] as List;
    List<num> xy(int i) =>
        i < 0 || i >= pts.length ? const [0, 0] : [pts[i][0], pts[i][1]];
    return [
      s['tool'],
      pts.length,
      (s['width'] as num),
      (s['usePressure'] as bool? ?? true) ? 1 : 0,
      ...pressureCurveInUse.values,
      jsonEncode(s['brush']),
      jsonEncode(s['shape']),
      smoothInUse,
      ...xy(0),
      ...xy(pts.length - 1),
    ];
  }

  Path pathOf(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final key = _key(s);
    final hit = _byId[id];
    if (hit != null && _same(hit.$1, key)) return hit.$2;
    final path = strokePath(s);
    _byId[id] = (key, path);
    return path;
  }

  final _alpha = <String, (List<Object?>, List<AlphaPiece>)>{};

  /// Finished per-point alpha stroke ([perPointAlpha]) as its pieces.
  List<AlphaPiece> alphaOf(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final key = _key(s);
    final hit = _alpha[id];
    if (hit != null && _same(hit.$1, key)) return hit.$2;
    final p = alphaPieces(s, s['points'] as List);
    _alpha[id] = (key, p);
    return p;
  }

  /// Finished-stroke stamp batch, rebuilt only when the stroke or its look changes.
  StampBatch batchOf(Map<String, dynamic> s, double fade, bool invert) {
    final id = s['id'] as String;
    final key = [..._key(s), s['color'], fade, invert];
    final hit = _batches[id];
    if (hit != null && _same(hit.$1, key)) return hit.$2;
    final b = buildBatch(s, fade, invert);
    _batches[id] = (key, b);
    return b;
  }

  static bool _same(List<Object?> a, List<Object?> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Releases the texture images; call when the owner is done with the cache.
  void dispose() => textures.dispose();

  /// Forgets strokes that are no longer on the page.
  void keepOnly(Set<String> ids) {
    _byId.removeWhere((k, _) => !ids.contains(k));
    _batches.removeWhere((k, _) => !ids.contains(k));
    _alpha.removeWhere((k, _) => !ids.contains(k));
  }
}

Color parseColor(Object? hex) {
  final m = RegExp(r'^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$').firstMatch('$hex');
  if (m == null) return const Color(0xFF000000);
  final rgb = int.parse(m.group(1)!, radix: 16);
  final a = m.group(2) == null ? 0xFF : int.parse(m.group(2)!, radix: 16);
  return Color((a << 24) | rgb);
}

/// Paper, background, strokes (clipped to the page) and the stroke being
/// drawn. [viewport] null fits the page to the widget (thumbnails).
class PagePainter extends CustomPainter {
  PagePainter({
    required this.page,
    required this.cache,
    this.viewport,
    this.live,
    this.hidden,
    this.draft,
    this.images,
    this.pdf,
    this.pdfImage,
    this.erasePreview,
    this.openTapes = const {},
    this.tapeLabels,
    this.onTapeTap,
    bool? invert,
    Listenable? repaint,
  }) : invert = invert ?? Kk.allDark,
       super(
         repaint: repaint == null
             ? cache.textures
             : Listenable.merge([repaint, cache.textures]),
       );

  /// All Dark: paper, pattern, pen, highlighter and text are drawn inverted
  /// (display only). Defaults to the current theme; a PDF page never inverts.
  final bool invert;

  final Map<String, dynamic> page;
  final StrokePathCache cache;
  final PageViewport? viewport;

  /// The in-progress stroke (same shape as a stored one); rebuilt per paint.
  final Map<String, dynamic>? Function()? live;

  /// Id of a text box that is being edited and so not drawn.
  final String? Function()? hidden;

  /// The text box being edited as it reads now: drawn here, so the box looks the same in edit and after it. The field over it draws no glyphs.
  final Map<String, dynamic>? Function()? draft;

  /// Decoded assets for image elements; null draws grey placeholders.
  final PageImages? images;

  /// Renders the PDF ground of a PDF page; null draws it as plain paper.
  final PdfPages? pdf;

  /// A ready picture of the PDF ground, drawn over the whole page (export
  /// raster); wins over [pdf].
  final ui.Image? pdfImage;

  /// While the eraser is down: the elements to draw instead of the page's, and
  /// the stroke ids drawn at [alpha] (the ones the erase would remove).
  final ({List<Object?> elements, Set<String> fade, double alpha})? Function()?
  erasePreview;

  /// Ids of the answer tapes that are open (screen state, spec/pen-kinds.md):
  /// drawn as an outline only. Replace the set to change it.
  final Set<String> openTapes;

  /// Semantics labels `(closed, open)` of a tape and its toggle; null gives
  /// tapes no node (thumbnails, history).
  final ({String closed, String open})? tapeLabels;
  final void Function(String id)? onTapeTap;

  Map<String, dynamic>? _bg; // page is fixed for this painter

  @override
  void paint(Canvas canvas, Size size) {
    final w = (page['width'] as num).toDouble();
    final h = (page['height'] as num).toDouble();
    if (!(w.isFinite && h.isFinite && w > 0 && h > 0)) return;
    final vp = viewport ?? PageViewport.fit(size, w, h, EdgeInsets.zero);
    // A page of a long note that is off screen draws nothing.
    if (!(Offset.zero & size).overlaps(
      Rect.fromLTWH(vp.offset.dx, vp.offset.dy, w * vp.scale, h * vp.scale),
    )) {
      return;
    }
    canvas
      ..save()
      ..translate(vp.offset.dx, vp.offset.dy)
      ..scale(vp.scale)
      ..clipRect(Rect.fromLTWH(0, 0, w, h));

    final inv = invert && !isPdfBackground(page['background']);
    Color shown(Object? hex) => inv
        ? Color.fromARGB(
            255,
            invertColor('$hex')[0],
            invertColor('$hex')[1],
            invertColor('$hex')[2],
          )
        : parseColor(hex);
    final bg = _bg ??= pageBackground(patternOf(page['background']), w, h);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..color = inv
            ? Color.fromARGB(255, paperRgb[0], paperRgb[1], paperRgb[2])
            : parseColor(bg['paper']),
    );
    final line = Paint()
      ..color = shown(bg['lineColor'])
      ..strokeWidth = (bg['lineWidth'] as num).toDouble()
      ..style = PaintingStyle.stroke;
    for (final l in bg['lines'] as List) {
      final n = (l as List).cast<num>();
      canvas.drawLine(
        Offset(n[0].toDouble(), n[1].toDouble()),
        Offset(n[2].toDouble(), n[3].toDouble()),
        line,
      );
    }
    final dot = Paint()..color = shown(bg['dotColor']);
    final r = (bg['dotRadius'] as num).toDouble();
    for (final d in bg['dots'] as List) {
      final n = (d as List).cast<num>();
      canvas.drawCircle(Offset(n[0].toDouble(), n[1].toDouble()), r, dot);
    }

    final pdfPages = pdf;
    final pi = pdfImage;
    if (pi != null && isPdfBackground(page['background'])) {
      canvas.drawImageRect(
        pi,
        Rect.fromLTWH(0, 0, pi.width.toDouble(), pi.height.toDouble()),
        Rect.fromLTWH(0, 0, w, h),
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else if (pdfPages != null && isPdfBackground(page['background'])) {
      final sc = vp.scale;
      Rect? vis;
      if (viewport != null) {
        final r = (Offset.zero & size).shift(-vp.offset);
        vis = Rect.fromLTRB(
          r.left / sc,
          r.top / sc,
          r.right / sc,
          r.bottom / sc,
        ).intersect(Rect.fromLTWH(0, 0, w, h));
      }
      paintPdfBackground(canvas, page, pdfPages, vis, sc);
    }

    final ids = <String>{};
    final skip = hidden?.call();
    final ep = erasePreview?.call();
    final els = ep?.elements ?? page['elements'] as List;
    // Partial erase: the pieces of a faded stroke, so its faded copy skips them.
    final pieces = <String, List<Map<String, dynamic>>>{};
    if (ep != null) {
      for (final e in els) {
        if (!drawableStroke(e)) continue;
        final id = (e as Map)['id'] as String;
        final i = id.lastIndexOf('~');
        if (i > 0 && ep.fade.contains(id.substring(0, i))) {
          pieces
              .putIfAbsent(id.substring(0, i), () => [])
              .add(e as Map<String, dynamic>);
        }
      }
    }
    for (final e in els) {
      if (drawableImage(e)) {
        paintImageElement(
          canvas,
          e as Map<String, dynamic>,
          images,
          vp.scale,
          underlay: inv,
        );
        continue;
      }
      if (drawableText(e)) {
        final t = e as Map<String, dynamic>;
        if (t['id'] != skip) paintTextBox(canvas, t, invert: inv);
        continue;
      }
      if (!drawableStroke(e)) continue;
      final s = e as Map<String, dynamic>;
      ids.add(s['id'] as String);
      final pcs = pieces[s['id']];
      if (pcs != null) {
        // shortcut: even-odd clip, so a self-overlapping piece leaks a sliver of the faded copy.
        final hole = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(const Rect.fromLTWH(-1e5, -1e5, 2e5, 2e5));
        for (final p in pcs) {
          hole.addPath(cache.pathOf(p), Offset.zero);
        }
        canvas.save();
        canvas.clipPath(hole);
      }
      final fade = ep != null && ep.fade.contains(s['id']) ? ep.alpha : 1.0;
      final bd = brushDraw(s);
      if (s['tool'] == 'pencil' || bd.grain) {
        final st = bd.grain ? cache.textures.images : null;
        paintPencil(
          canvas,
          s,
          st,
          () => cache.pathOf(s),
          fade: fade,
          invert: inv,
          batch: st == null ? null : cache.batchOf(s, fade, inv),
        );
      } else if (s['tool'] == 'tape' && openTapes.contains(s['id'])) {
        canvas.drawPath(
          cache.pathOf(s),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / vp.scale
            ..color = parseColor(s['color']).withValues(alpha: 0.6 * fade),
        );
      } else if (perPointAlpha(s)) {
        fillAlphaPieces(
          canvas,
          cache.alphaOf(s),
          s['color'],
          fade: fade,
          invert: inv,
        );
      } else {
        fillStroke(
          canvas,
          cache.pathOf(s),
          s['color'],
          highlighter: s['tool'] == 'highlighter',
          alpha: fade * bd.alpha,
          invert: inv && s['tool'] != 'tape',
        );
      }
      if (pcs != null) canvas.restore();
    }
    final d = draft?.call();
    if (d != null && drawableText(d)) paintTextBox(canvas, d, invert: inv);
    cache.keepOnly(ids);
    final s = live?.call();
    if (s != null && drawableStroke(s)) {
      final bd = brushDraw(s);
      // A shape has no pen points to freeze: it is built each frame.
      final cached = s['shape'] == null;
      if (s['tool'] == 'pencil' || bd.grain) {
        final st = bd.grain ? cache.textures.images : null;
        paintPencil(
          canvas,
          s,
          st,
          () => strokePath(s),
          fade: 1,
          invert: inv,
          batch: st == null
              ? null
              : cached
              ? cache.live.batchOf(s, inv)
              : null,
        );
      } else if (cached && perPointAlpha(s)) {
        cache.live.pathOf(s);
        fillAlphaPieces(
          canvas,
          [...cache.live.frozenAlpha, ...cache.live.openAlpha],
          s['color'],
          invert: inv,
        );
      } else {
        final lp = cached ? cache.live.pathOf(s) : null;
        fillStroke(
          canvas,
          lp?.frozen ?? strokePath(s),
          s['color'],
          highlighter: s['tool'] == 'highlighter',
          alpha: bd.alpha,
          invert: inv && s['tool'] != 'tape',
          extra: lp?.open,
        );
      }
    } else {
      cache.live.clear();
    }
    canvas.restore();
  }

  // Text boxes are readable: each is a node with its text as label.
  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final w = (page['width'] as num).toDouble();
    final h = (page['height'] as num).toDouble();
    if (!(w.isFinite && h.isFinite && w > 0 && h > 0)) return const [];
    final vp = viewport ?? PageViewport.fit(size, w, h, EdgeInsets.zero);
    return [
      for (final e in page['elements'] as List)
        if (drawableImage(e))
          () {
            final m = e as Map<String, dynamic>;
            final w = (m['width'] as num).toDouble();
            final h = (m['height'] as num).toDouble();
            final x = (m['x'] as num).toDouble(),
                y = (m['y'] as num).toDouble();
            final r = _rotatedBounds(x, y, w, h, m['rotation']);
            final src = images;
            return CustomPainterSemantics(
              key: ValueKey(m['id']),
              rect: Rect.fromPoints(
                vp.offset + r.topLeft * vp.scale,
                vp.offset + r.bottomRight * vp.scale,
              ),
              properties: SemanticsProperties(
                label: src == null
                    ? null
                    : src.pending('${m['asset']}')
                    ? '${src.imageLabel}, ${src.pendingLabel}'
                    : src.imageLabel,
                image: true,
                textDirection: TextDirection.ltr,
              ),
            );
          }()
        else if (drawableText(e) &&
            (e as Map)['text'].toString().trim().isNotEmpty)
          () {
            final t = e as Map<String, dynamic>;
            final r = textBounds(t);
            return CustomPainterSemantics(
              key: ValueKey(t['id']),
              rect: Rect.fromPoints(
                vp.offset + r.topLeft * vp.scale,
                vp.offset + r.bottomRight * vp.scale,
              ),
              properties: SemanticsProperties(
                label: t['text'] as String,
                textDirection: TextDirection.ltr,
              ),
            );
          }()
        else if (tapeLabels != null &&
            drawableStroke(e) &&
            (e as Map)['tool'] == 'tape')
          () {
            final t = e as Map<String, dynamic>;
            final id = t['id'] as String;
            final r = cache.pathOf(t).getBounds();
            return CustomPainterSemantics(
              key: ValueKey(id),
              rect: Rect.fromPoints(
                vp.offset + r.topLeft * vp.scale,
                vp.offset + r.bottomRight * vp.scale,
              ),
              properties: SemanticsProperties(
                button: true,
                label: openTapes.contains(id)
                    ? tapeLabels!.open
                    : tapeLabels!.closed,
                textDirection: TextDirection.ltr,
                onTap: onTapeTap == null ? null : () => onTapeTap!(id),
              ),
            );
          }(),
    ];
  };

  static Rect _rotatedBounds(
    double x,
    double y,
    double w,
    double h,
    Object? r,
  ) {
    final a = ((r as num?) ?? 0).toDouble() * math.pi / 180;
    final c = Offset(x + w / 2, y + h / 2);
    final dx = (w / 2) * math.cos(a).abs() + (h / 2) * math.sin(a).abs();
    final dy = (w / 2) * math.sin(a).abs() + (h / 2) * math.cos(a).abs();
    return Rect.fromLTRB(c.dx - dx, c.dy - dy, c.dx + dx, c.dy + dy);
  }

  @override
  bool shouldRebuildSemantics(PagePainter oldDelegate) =>
      shouldRepaint(oldDelegate);

  // The page map and the live stroke change by identity or by repaint tick.
  @override
  bool shouldRepaint(PagePainter old) =>
      !identical(old.page, page) ||
      !identical(old.openTapes, openTapes) ||
      old.invert != invert ||
      old.viewport?.scale != viewport?.scale ||
      old.viewport?.offset != viewport?.offset;
}
