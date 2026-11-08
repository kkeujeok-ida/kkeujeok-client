import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../model/invert.dart';
import '../model/pressure_curve.dart';
import '../model/smooth.dart';
import '../ui/kk.dart';
import 'asset_images.dart';
import 'pdf_pages.dart';
import '../model/pdf_rules.dart' show isPdfBackground, patternOf;
import 'page_background.dart';
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
  final pts = smoothPoints(s['points'] as List, smoothInUse);
  final w = (s['width'] as num).toDouble();
  return s['tool'] == 'highlighter'
      ? highlighterPath(highlighterPolygons(w, pts))
      : outlinePath(
          strokeOutlineFor(
            s['tool'] as String?,
            w,
            s['usePressure'] as bool,
            pts,
          ),
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
}) {
  p.fillType = PathFillType.nonZero;
  final base = parseColor(
    invert && !highlighter && color is String ? inkHex(color) : color,
  );
  final fill = Paint()
    ..color = alpha == 1 || highlighter
        ? base
        : base.withValues(alpha: base.a * alpha)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  if (!highlighter) return c.drawPath(p, fill);
  c.saveLayer(
    p.getBounds().inflate(1),
    Paint()
      ..blendMode = invert ? BlendMode.srcOver : BlendMode.multiply
      ..color = Color.fromRGBO(255, 255, 255, 0.4 * alpha),
  );
  c.drawPath(p, fill);
  c.restore();
}

/// Draws a ready pencil texture in the stroke color (All Dark: inverted like a
/// pen). The cells are opaque in the image; the color filter paints them.
void fillPencil(
  Canvas c,
  PencilDraw d,
  Object? color, {
  double alpha = 1,
  bool invert = false,
  bool minified = false,
}) {
  final base = parseColor(invert && color is String ? inkHex(color) : color);
  final paint = Paint()
    ..colorFilter = ColorFilter.mode(
      alpha == 1 ? base : base.withValues(alpha: base.a * alpha),
      BlendMode.srcIn,
    )
    // Cells smaller than a pixel are averaged, larger ones stay crisp.
    ..filterQuality = minified ? FilterQuality.medium : FilterQuality.none;
  final m = d.m;
  c.save();
  if (m != null) {
    c.transform(
      Float64List.fromList([
        m[0], m[1], 0, 0, //
        -m[1], m[0], 0, 0,
        0, 0, 1, 0,
        m[2], m[3], 0, 1,
      ]),
    );
  }
  c.drawImageRect(
    d.image,
    Rect.fromLTWH(0, 0, d.image.width.toDouble(), d.image.height.toDouble()),
    d.dst,
    paint,
  );
  c.restore();
}

/// Alpha of the plain pencil polygon: while the pen is down, while the cells
/// build, and for a stroke too big for a texture.
double pencilAlpha(Map<String, dynamic> s) =>
    pencilDensity(meanPressure(s['usePressure'] as bool, s['points'] as List))
        .density;

/// Finished-stroke outlines by stroke id, so a repaint does not rebuild them.
/// The key holds what an edit could change: count, ends, width, pressure.
class StrokePathCache {
  /// Cell images of pencil strokes (spec/pen-kinds.md); they build off the
  /// paint path and notify the painter when one is ready.
  final textures = PencilTextures();
  final _byId = <String, (List<Object?>, Path)>{};

  static List<Object?> _key(Map<String, dynamic> s) {
    final pts = s['points'] as List;
    List<num> xy(int i) =>
        i < 0 || i >= pts.length ? const [0, 0] : [pts[i][0], pts[i][1]];
    return [
      s['tool'],
      pts.length,
      (s['width'] as num),
      (s['usePressure'] as bool) ? 1 : 0,
      ...pressureCurveInUse.values,
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
    textures.keepOnly(ids);
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
    if (pdfPages != null && isPdfBackground(page['background'])) {
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

    final clip = Rect.fromLTWH(
      -vp.offset.dx / vp.scale,
      -vp.offset.dy / vp.scale,
      size.width / vp.scale,
      size.height / vp.scale,
    );
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
      // Off-screen strokes build no texture; they show the alpha polygon.
      final tex = s['tool'] == 'pencil' && PencilTextures.touches(s, clip)
          ? cache.textures.lookup(s)
          : null;
      if (tex != null) {
        fillPencil(
          canvas,
          tex,
          s['color'],
          alpha: fade,
          invert: inv,
          minified: vp.scale * pencilCell < 1,
        );
      } else if (s['tool'] == 'tape' && openTapes.contains(s['id'])) {
        canvas.drawPath(
          cache.pathOf(s),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / vp.scale
            ..color = parseColor(s['color']).withValues(alpha: 0.6 * fade),
        );
      } else {
        fillStroke(
          canvas,
          cache.pathOf(s),
          s['color'],
          highlighter: s['tool'] == 'highlighter',
          alpha: s['tool'] == 'pencil' ? fade * pencilAlpha(s) : fade,
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
      fillStroke(
        canvas,
        strokePath(s),
        s['color'],
        highlighter: s['tool'] == 'highlighter',
        alpha: s['tool'] == 'pencil' ? pencilAlpha(s) : 1,
        invert: inv && s['tool'] != 'tape',
      );
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
