import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/brush.dart';
import 'package:kkeujeok/model/pressure_curve.dart';
import 'package:kkeujeok/render/stroke_outline.dart';

double _h(List<List<double>> poly) {
  final ys = [for (final p in poly) p[1]];
  return ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
}

void main() {
  final pts = [
    [0, 0, 0.5, 0, 45, 0],
    [10, 0, 0.5, 5, 45, 0],
    [20, 0, 0.5, 10, 45, 0],
  ];
  const lin = [1 / 3, 1 / 3, 2 / 3, 2 / 3];
  test('no sizeOf = same outline', () {
    expect(
      strokeOutlineFor('pen', 4, true, pts, PressureCurve.normal),
      strokeOutlineFor('pen', 4, true, pts, PressureCurve.normal, null),
    );
  });
  test('tilt size narrows an upright pen; unknown tilt keeps width', () {
    final up = [for (final p in pts) [p[0], p[1], p[2], p[3], 0, 0]];
    final narrow = strokeOutlineFor('pen', 4, true, up, PressureCurve.normal,
        (p) => tiltSizeFactor(p, lin));
    final plain = strokeOutlineFor('pen', 4, true, up, PressureCurve.normal);
    expect(_h(narrow), closeTo(_h(plain) * 0.5, 0.5));
    final none = strokeOutlineFor('pen', 4, true,
        [for (final p in pts) p.sublist(0, 4)], PressureCurve.normal,
        (p) => tiltSizeFactor(p, lin));
    expect(_h(none), closeTo(_h(plain), 1e-6));
  });
  test('alpha factor', () {
    expect(brushAlphaFactor('pen', null, pts), 1);
    expect(brushAlphaFactor('pen', {'opacity': 0.5}, pts), 0.5);
    expect(brushAlphaFactor('highlighter', {'opacity': 0.2}, pts), closeTo(0.5, 1e-9));
    expect(brushAlphaFactor('tape', {'opacity': 0.2}, pts), 1);
    expect(brushAlphaFactor('pen', {'tiltTarget': 'opacity'}, pts), closeTo(0.5, 1e-5));
  });
  test('pressure to opacity: mean q, inverse flips, usePressure off is 0.5', () {
    final hi = [[0, 0, 1.0, 0], [1, 0, 1.0, 1]];
    final inv = {'opacityPressureCurve': [[0, 1], [1, 0]]};
    final lin = {'opacityPressureCurve': [[0, 0], [1, 1]]};
    expect(brushAlphaFactor('pen', lin, hi), closeTo(1, 1e-9));
    expect(brushAlphaFactor('pen', inv, hi), closeTo(0, 1e-9));
    expect(brushAlphaFactor('pen', inv, hi, false), closeTo(0.5, 1e-9));
    expect(brushAlphaFactor('tape', inv, hi), 1);
  });
  test('point-list pressureCurve draws; legacy stays Butland', () {
    final c = PressureCurve.fromCurve([[0, 1], [1, 0]]);
    expect(c.q(0.25), closeTo(0.75, 1e-9));
    expect(PressureCurve.fromCurve([0.2, 0.4, 0.5, 0.8]),
        PressureCurve.fromValues([0.2, 0.4, 0.5, 0.8]));
  });
}
