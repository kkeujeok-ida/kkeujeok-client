import '../model/number.dart';

/// spec rule `page.background`: lines and dots of a page background. An
/// unknown [background] draws as plain.
Map<String, dynamic> pageBackground(String background, num w, num h) {
  const step = 28;
  final width = round2(w.toDouble()), height = round2(h.toDouble());
  final lines = <List<num>>[], dots = <List<num>>[];
  switch (background) {
    case 'lined':
      for (var y = 56; y <= h - step; y += step) {
        lines.add([0, y, width, y]);
      }
    case 'grid':
      for (var x = step; x < w; x += step) {
        lines.add([x, 0, x, height]);
      }
      for (var y = step; y < h; y += step) {
        lines.add([0, y, width, y]);
      }
    case 'dot':
      for (var y = step; y < h; y += step) {
        for (var x = step; x < w; x += step) {
          dots.add([x, y]);
        }
      }
  }
  return {
    'paper': '#ffffff',
    'lineColor': '#c5ced8',
    'lineWidth': 0.5,
    'lines': lines,
    'dotColor': '#a0aab5',
    'dotRadius': 0.75,
    'dots': dots,
  };
}
