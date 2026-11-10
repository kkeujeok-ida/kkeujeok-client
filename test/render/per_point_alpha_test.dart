import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/render/page_painter.dart';

Map<String, dynamic> _stroke(
  List<List<num>> pts, {
  Object? brush,
  String tool = 'pen',
}) => {
  'type': 'stroke',
  'id': 's',
  'tool': tool,
  'color': '#000000',
  'width': 8,
  'usePressure': true,
  'brush': brush,
  'points': [
    for (var i = 0; i < pts.length; i++)
      pts[i].length > 3 ? pts[i] : [...pts[i], i * 10],
  ],
};

// Pressure 0.1 at the left to 0.9 at the right, a line at y = 30.
List<List<num>> _ramp() => [
  for (var i = 0; i <= 40; i++) [10 + i * 2.0, 30, 0.1 + 0.8 * i / 40],
];

// Constant pressure 0.5: with the curve below the alpha is 0.5 everywhere.
List<List<num>> _flat(List<List<num>> xy) => [
  for (final p in xy) [p[0], p[1], 0.5],
];

const _half = {
  'opacityPressureCurve': [
    [0, 0.5],
    [1, 0.5],
  ],
};
const _rise = {
  'opacityPressureCurve': [
    [0, 0.1],
    [1, 1],
  ],
};

/// Red channel (ink black over white paper) of a 100x60 render.
Future<List<int>> _render(WidgetTester t, Map<String, dynamic> s) async {
  final r = await t.runAsync(() async {
    final rec = ui.PictureRecorder();
    PagePainter(
      page: {
        'width': 100,
        'height': 60,
        'background': 'plain',
        'elements': [s],
      },
      cache: StrokePathCache(),
      invert: false,
    ).paint(ui.Canvas(rec), const Size(100, 60));
    final img = await rec.endRecording().toImage(100, 60);
    final px = (await img.toByteData())!.buffer.asUint8List();
    return [for (var i = 0; i < px.length; i += 4) px[i]];
  });
  return r!;
}

int _at(List<int> r, int x, int y) => r[y * 100 + x];

void main() {
  testWidgets('pressure curve: alpha follows the point, not the whole line', (
    t,
  ) async {
    final s = _stroke(_ramp(), brush: _rise);
    expect(perPointAlpha(s), isTrue);
    final r = await _render(t, s);
    expect(_at(r, 20, 30), greaterThan(_at(r, 80, 30) + 60));
  });

  testWidgets('tilt curve: alpha follows the point tilt', (t) async {
    final pts = [
      for (var i = 0; i <= 40; i++) [10 + i * 2.0, 30, 0.5, i * 10, 90 * i / 40, 0],
    ];
    final s = _stroke(pts, brush: {
      'opacityTiltCurve': [
        [0, 0.1],
        [1, 1],
      ],
    });
    expect(perPointAlpha(s), isTrue);
    final r = await _render(t, s);
    expect(_at(r, 20, 30), greaterThan(_at(r, 80, 30) + 60));
  });

  testWidgets('seams and ends are not darker than the alpha', (t) async {
    final s = _stroke(
      _flat([for (var i = 0; i <= 40; i++) [10 + i * 2.0, 30]]),
      brush: _half,
    );
    final r = await _render(t, s);
    for (var x = 12; x < 88; x++) {
      expect(_at(r, x, 30), inInclusiveRange(125, 130), reason: 'x=$x');
    }
  });

  testWidgets('a stroke crossing itself is not darker at the crossing', (
    t,
  ) async {
    final s = _stroke(
      _flat([
        for (var i = 0; i <= 30; i++) [10 + i * 2.0, 30],
        for (var i = 0; i <= 30; i++) [70 - i * 2.0, 30],
      ]),
      brush: _half,
    );
    final r = await _render(t, s);
    expect(_at(r, 40, 30), inInclusiveRange(125, 130));
  });

  testWidgets('no curve: the old single-layer path', (t) async {
    final s = _stroke(
      _flat([for (var i = 0; i <= 40; i++) [10 + i * 2.0, 30]]),
      brush: {'opacity': 0.5},
    );
    expect(perPointAlpha(s), isFalse);
    expect(perPointAlpha(_stroke(_ramp())), isFalse);
    expect(_at(await _render(t, s), 50, 30), inInclusiveRange(125, 130));
  });

  test('live: closed pieces keep their alpha when points are appended', () {
    List<List<num>> pts(int n) => [
      for (var i = 0; i < n; i++) [10 + i * 3.0, 30, 0.1 + 0.8 * i / 60],
    ];
    final c = LiveCache();
    c.pathOf(_stroke(pts(40), brush: _rise));
    final before = [...c.frozenAlpha];
    expect(before, isNotEmpty);
    c.pathOf(_stroke(pts(60), brush: _rise));
    expect(c.frozenAlpha.length, greaterThan(before.length));
    expect(c.frozenAlpha.sublist(0, before.length), before);
  });
}
