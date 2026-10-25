import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/render/page_painter.dart';

Map<String, dynamic> _stroke(
  String id,
  String tool,
  String color,
  num width,
  List<List<num>> xy,
) => {
  'type': 'stroke',
  'id': id,
  'tool': tool,
  'color': color,
  'width': width,
  'usePressure': false,
  'points': [
    for (var i = 0; i < xy.length; i++) [xy[i][0], xy[i][1], 0.5, i * 10],
  ],
};

/// Renders [elements] on a 100x60 page and returns the RGBA bytes.
Future<List<int>> _render(
  WidgetTester t,
  List<Map<String, dynamic>> elements,
) async {
  final page = {
    'width': 100,
    'height': 60,
    'background': 'plain',
    'elements': elements,
  };
  final r = await t.runAsync(() async {
    final rec = ui.PictureRecorder();
    PagePainter(
      page: page,
      cache: StrokePathCache(),
    ).paint(ui.Canvas(rec), const Size(100, 60));
    final img = await rec.endRecording().toImage(100, 60);
    final data = await img.toByteData();
    return data!.buffer.asUint8List().toList();
  });
  return r!;
}

List<int> _px(List<int> rgba, int x, int y) {
  final i = (y * 100 + x) * 4;
  return rgba.sublist(i, i + 3);
}

void _near(List<int> a, List<int> b, [int tol = 2]) {
  for (var k = 0; k < 3; k++) {
    expect((a[k] - b[k]).abs() <= tol, isTrue, reason: '$a vs $b');
  }
}

List<int> _mult(List<int> below, int c0, int c1, int c2) => [
  for (final (i, c) in [c0, c1, c2].indexed)
    (below[i] * (1 - 0.4 * (1 - c / 255))).round(),
];

void main() {
  const yellow = '#ffe066';
  final bar = _stroke('h', 'highlighter', yellow, 14, [
    [10, 30],
    [60, 30],
  ]);

  testWidgets('ink below shows through, multiplied at 0.4', (t) async {
    final pen = _stroke('p', 'pen', '#e03131', 8, [
      [20, 30],
      [80, 30],
    ]);
    final under = await _render(t, [pen]);
    final both = await _render(t, [pen, bar]);
    _near(_px(both, 30, 30), _mult(_px(under, 30, 30), 0xff, 0xe0, 0x66));
    // Over paper only: paper * factor.
    final paper = await _render(t, []);
    _near(
      _px(await _render(t, [bar]), 30, 30),
      _mult(_px(paper, 30, 30), 0xff, 0xe0, 0x66),
    );
  });

  testWidgets('one stroke does not darken where it crosses itself', (t) async {
    final single = await _render(t, [bar]);
    final loop = _stroke('l', 'highlighter', yellow, 14, [
      [10, 30],
      [60, 30],
      [10, 30],
      [60, 30],
    ]);
    _near(_px(await _render(t, [loop]), 30, 30), _px(single, 30, 30), 1);
  });

  testWidgets('two strokes overlapping are darker than one', (t) async {
    final single = await _render(t, [bar]);
    final other = _stroke('h2', 'highlighter', yellow, 14, [
      [10, 30],
      [60, 30],
    ]);
    final two = await _render(t, [bar, other]);
    expect(_px(two, 30, 30)[2] < _px(single, 30, 30)[2] - 5, isTrue);
  });

  testWidgets('no points draws nothing; one point draws a small mark', (
    t,
  ) async {
    final paper = await _render(t, []);
    expect(
      await _render(t, [_stroke('e', 'highlighter', yellow, 14, [])]),
      paper,
    );
    final dot = await _render(t, [
      _stroke('d', 'highlighter', yellow, 14, [
        [50, 30],
      ]),
    ]);
    expect(dot, isNot(paper));
  });
}
