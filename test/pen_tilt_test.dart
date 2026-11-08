import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/smooth.dart';

void main() {
  test('smoothPoints keeps tilt, shorter-arc azimuth, mixed rows finite', () {
    final six = smoothPoints([
      [0, 0, 1, 0, 10, 350],
      [1, 0, 1, 1, 20, 10],
      [2, 0, 1, 2, 30, 20],
    ], 2);
    for (final p in six) {
      expect(p.length, 6);
    }
    expect(six[1][5] as num, closeTo(0, 1e-6));
    final mixed = smoothPoints([
      [0, 0, 1, 0],
      [1, 0, 1, 1, 20, 10],
      [2, 0, 1, 2],
    ], 2);
    for (final p in mixed) {
      for (final v in p) {
        expect((v as num).isFinite, true);
      }
    }
  });
}
