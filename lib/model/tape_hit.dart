import 'select.dart';
import '../render/stroke_outline.dart';

// spec/pen-kinds.md "Answer tape": which tape a press lands on.

const tapeTapMs = 400;
const tapeTapSlop = 6.0; // dp; the text tap uses its own, larger slop

/// Id of the topmost tape whose polygon contains [p] (page pt), or null.
String? tapeAt(List elements, (double, double) p) {
  for (var i = elements.length - 1; i >= 0; i--) {
    final e = elements[i];
    if (e is! Map || e['type'] != 'stroke' || e['tool'] != 'tape') continue;
    final id = e['id'];
    final pts = e['points'];
    final w = e['width'];
    if (id is! String || pts is! List || w is! num) continue;
    final poly = strokeOutlineFor('tape', w.toDouble(), false, pts);
    if (poly.length < 3) continue;
    if (pointInPolygon(p, [for (final q in poly) (q[0], q[1])])) return id;
  }
  return null;
}

/// A tap: up within 400 ms and moved less than 6 dp.
bool isTapeTap(int elapsedMs, double moved) =>
    elapsedMs < tapeTapMs && moved < tapeTapSlop;
