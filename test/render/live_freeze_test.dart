import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/render/pencil_texture.dart';

List<List<num>> _pts(int n) => [
  for (var i = 0; i < n; i++)
    [10 + i * 4.1, 10 + (i.isEven ? 0 : 1.3), 0.5, i * 20],
];

Map<String, dynamic> _stroke(String tool, int n, {Object? brush}) => {
  'id': 'live-1',
  'type': 'stroke',
  'tool': tool,
  'color': '#000000',
  'width': tool == 'pencil' ? 3 : 2,
  'usePressure': true,
  'brush': brush,
  'points': _pts(n),
};

void main() {
  test('stamps: the list for n points is the front of the list for n + m', () {
    final a = stampsOf(_stroke('pencil', 20), live: true);
    final b = stampsOf(_stroke('pencil', 30), live: true);
    expect(b.length, greaterThan(a.length));
    expect(b.sublist(0, a.length), a);
    // resuming a walk gives the same stamps as walking again
    final walk = PencilWalk();
    final first = stampsOf(_stroke('pencil', 20), live: true, walk: walk);
    final more = stampsOf(_stroke('pencil', 30), live: true, walk: walk);
    expect([...first, ...more], b);
  });

  test('pen outline: closed pieces do not change when points are appended', () {
    for (final tool in ['pen', 'fountain', 'highlighter', 'tape']) {
      final c = LiveCache();
      c.pathOf(_stroke(tool, 40));
      final before = [for (final p in c.polygons) p];
      expect(before, isNotEmpty, reason: tool);
      c.pathOf(_stroke(tool, 41));
      c.pathOf(_stroke(tool, 60));
      expect(c.polygons.sublist(0, before.length), before, reason: tool);
      expect(c.polygons.length, greaterThan(before.length), reason: tool);
    }
  });

  test('density changes the steps only, opacity the alpha only', () {
    final base = stampsOf(_stroke('pencil', 20));
    final dense = stampsOf(_stroke('pencil', 20, brush: {'density': 0.2}));
    expect(dense.length, lessThan(base.length));
    expect(dense.first.alpha, base.first.alpha);
    final half = stampsOf(_stroke('pencil', 20, brush: {'opacity': 0.5}));
    expect(half.length, base.length);
    for (var i = 0; i < base.length; i++) {
      expect(half[i].x, base[i].x);
      expect(half[i].alpha, closeTo(base[i].alpha / 2, 1e-3));
    }
  });
}
