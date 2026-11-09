import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/shape.dart';

void main() {
  test('unknown or incomplete shapes are not known and make no points', () {
    for (final s in <Object?>[
      {'kind': 'star'},
      {'kind': 'rect', 'x': 0},
      {'kind': 'triangle', 'vertices': []},
      'rect',
      null,
    ]) {
      expect(isKnownShape(s), isFalse);
      expect(shapePoints(s), isNull);
    }
  });

  test('move and scale follow the shape and points are made again', () {
    final s = shapeFromDrag('rect', [0, 0], [40, 20], false)!;
    transformShape(s, (x, y) => (x + 10, y + 5), 1, 1, 0);
    expect([s['x'], s['y'], s['width']], [10, 5, 40]);
    transformShape(s, (x, y) => (x, y), 2, 1, 90);
    expect([s['width'], s['rotation']], [80, 90]);
    expect(shapePoints(s)!.first.length, 4);
    final t = shapeFromDrag('triangle', [0, 0], [10, 10], false)!;
    transformShape(t, (x, y) => (x + 1, y), 1, 1, 0);
    expect((t['vertices'] as List).first, [6, 0]);
  });

  test('corners are stored, dense points stay for partial erase and legacy', () {
    final r = shapeFromDrag('rect', [0, 0], [40, 20], false)!;
    expect(shapeCorners(r)!.length, 5);
    final legacy = {'shape': r, 'points': shapePoints(r)};
    expect((denseOf(legacy) as List).length, shapePoints(r)!.length);
    // an old dense stroke draws from its shape: the same two rings
    expect(shapeRings(r, 2)![0].length, 4);
  });

  test('hold-resize keeps the anchor and does not jump', () {
    final r = shapeFromDrag('rect', [0, 0], [40, 20], false)!;
    expect(shapeHoldResize(r, [40, 20], [40, 20]), r);
    final g = shapeHoldResize(r, [40, 20], [60, 30])!;
    expect([g['x'], g['y'], g['width'], g['height']], [0, 0, 60, 30]);
  });
}
