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
}
