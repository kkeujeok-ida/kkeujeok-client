import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'page_background.dart';
import 'stroke_outline.dart';

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

/// Finished-stroke outlines by stroke id, so a repaint does not rebuild them.
/// The key holds what an edit could change: count, ends, width, pressure.
class StrokePathCache {
  final _byId = <String, (List<num>, Path)>{};

  static List<num> _key(Map<String, dynamic> s) {
    final pts = s['points'] as List;
    List<num> xy(int i) =>
        i < 0 || i >= pts.length ? const [0, 0] : [pts[i][0], pts[i][1]];
    return [
      pts.length,
      (s['width'] as num),
      (s['usePressure'] as bool) ? 1 : 0,
      ...xy(0),
      ...xy(pts.length - 1),
    ];
  }

  Path pathOf(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final key = _key(s);
    final hit = _byId[id];
    if (hit != null && _same(hit.$1, key)) return hit.$2;
    final path = outlinePath(
      strokeOutline(
        (s['width'] as num).toDouble(),
        s['usePressure'] as bool,
        s['points'] as List,
      ),
    );
    _byId[id] = (key, path);
    return path;
  }

  static bool _same(List<num> a, List<num> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Forgets strokes that are no longer on the page.
  void keepOnly(Set<String> ids) =>
      _byId.removeWhere((k, _) => !ids.contains(k));
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
    super.repaint,
  });

  final Map<String, dynamic> page;
  final StrokePathCache cache;
  final PageViewport? viewport;

  /// The in-progress stroke (same shape as a stored one); rebuilt per paint.
  final Map<String, dynamic>? Function()? live;

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

    final bg = _bg ??= pageBackground(
      page['background'] as String? ?? 'plain',
      w,
      h,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = parseColor(bg['paper']),
    );
    final line = Paint()
      ..color = parseColor(bg['lineColor'])
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
    final dot = Paint()..color = parseColor(bg['dotColor']);
    final r = (bg['dotRadius'] as num).toDouble();
    for (final d in bg['dots'] as List) {
      final n = (d as List).cast<num>();
      canvas.drawCircle(Offset(n[0].toDouble(), n[1].toDouble()), r, dot);
    }

    final ids = <String>{};
    for (final e in page['elements'] as List) {
      if (!drawableStroke(e)) continue;
      final s = e as Map<String, dynamic>;
      ids.add(s['id'] as String);
      _fill(canvas, cache.pathOf(s), s['color']);
    }
    cache.keepOnly(ids);
    final s = live?.call();
    if (s != null && drawableStroke(s)) {
      _fill(
        canvas,
        outlinePath(
          strokeOutline(
            (s['width'] as num).toDouble(),
            s['usePressure'] as bool,
            s['points'] as List,
          ),
        ),
        s['color'],
      );
    }
    canvas.restore();
  }

  void _fill(Canvas c, Path p, Object? color) => c.drawPath(
    p..fillType = PathFillType.nonZero,
    Paint()
      ..color = parseColor(color)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true,
  );

  // The page map and the live stroke change by identity or by repaint tick.
  @override
  bool shouldRepaint(PagePainter old) =>
      !identical(old.page, page) ||
      old.viewport?.scale != viewport?.scale ||
      old.viewport?.offset != viewport?.offset;
}
