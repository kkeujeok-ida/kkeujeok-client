import 'dart:math' as math;
import 'dart:ui';

import '../model/page_view_mode.dart';

const pageGap = 24.0;
const spineGap = 4.0;

/// A phone is a screen whose shorter side is under 600dp (no two-page there).
bool isPhone(Size s) => s.shortestSide < 600;

/// Page rectangles in document coordinates; page sizes are never changed.
({List<Rect> rects, double w, double h}) layoutPages(
  List<Size> sizes,
  PageViewMode mode,
) {
  if (sizes.isEmpty) return (rects: const [], w: 0, h: 0);
  if (mode == PageViewMode.vertical) {
    final w = sizes.map((s) => s.width).reduce(math.max);
    var y = 0.0;
    final rects = <Rect>[];
    for (final s in sizes) {
      rects.add(Rect.fromLTWH((w - s.width) / 2, y, s.width, s.height));
      y += s.height + pageGap;
    }
    return (rects: rects, w: w, h: y - pageGap);
  }
  // Groups of page indexes laid left to right, centered on the tallest.
  final groups = <List<int>>[];
  if (mode == PageViewMode.horizontal) {
    for (var i = 0; i < sizes.length; i++) {
      groups.add([i]);
    }
  } else {
    bool portrait(int i) => sizes[i].width <= sizes[i].height;
    for (var i = 0; i < sizes.length; i++) {
      if (portrait(i) && i + 1 < sizes.length && portrait(i + 1)) {
        groups.add([i, i + 1]);
        i++; // the partner is taken
      } else {
        groups.add([i]);
      }
    }
  }
  final h = sizes.map((s) => s.height).reduce(math.max);
  final rects = List<Rect>.filled(sizes.length, Rect.zero);
  var x = 0.0;
  for (final g in groups) {
    for (final i in g) {
      final s = sizes[i];
      rects[i] = Rect.fromLTWH(x, (h - s.height) / 2, s.width, s.height);
      x += s.width + (i == g.last ? 0 : spineGap);
    }
    x += pageGap;
  }
  return (rects: rects, w: x - pageGap, h: h);
}

/// The page whose rectangle is nearest [mid] (2-D); ties go to the earlier.
int activeIndexOf(List<Rect> rects, Offset mid) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < rects.length; i++) {
    final r = rects[i];
    final dx = math.max(math.max(r.left - mid.dx, mid.dx - r.right), 0.0);
    final dy = math.max(math.max(r.top - mid.dy, mid.dy - r.bottom), 0.0);
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}
