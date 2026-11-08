import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/render/pencil_texture.dart';
import 'package:kkeujeok/render/stroke_outline.dart';

Map<String, dynamic> _stroke(
  String id,
  List<List<num>> xy, {
  double pressure = 0.5,
  num width = 6,
}) => {
  'type': 'stroke',
  'id': id,
  'tool': 'pencil',
  'color': '#000000',
  'width': width,
  'usePressure': true,
  'points': [
    for (var i = 0; i < xy.length; i++) [xy[i][0], xy[i][1], pressure, i * 10],
  ],
};

PencilCells _cells(Map<String, dynamic> s, {int maxCells = 4000000}) {
  final pts = s['points'] as List;
  return buildPencilCells(
    strokeOutlineFor('pencil', 6, true, pts),
    strokeSamples(true, pts),
    pencilSeed(s['id'] as String),
    maxCells: maxCells,
  )!;
}

int _inked(PencilCells c) {
  var n = 0;
  for (var k = 3; k < c.pixels.length; k += 4) {
    if (c.pixels[k] != 0) n++;
  }
  return n;
}

double _ratio(double pressure) {
  final s = _stroke('r', [
    [10, 20],
    [190, 20],
  ], pressure: pressure);
  final c = _cells(s);
  // Interior only: a 4 pt band along the middle, away from the caps.
  var n = 0, total = 0;
  for (var i = 60; i < 340; i++) {
    for (var j = 38; j < 42; j++) {
      total++;
      if (c.inked(i, j)) n++;
    }
  }
  return n / total;
}

void main() {
  test('pressure sets how many cells are inked', () {
    expect(_ratio(1), closeTo(0.95, 0.04));
    expect(_ratio(0), closeTo(0.35, 0.04));
  });

  test('the cells depend only on the stroke id', () {
    final a = _cells(
      _stroke('m', [
        [10, 10],
        [60, 14],
      ]),
    );
    final b = _cells(
      _stroke('m', [
        [10, 10],
        [60, 14],
      ]),
    );
    expect(a.pixels, b.pixels);
    final other = _cells(
      _stroke('n', [
        [10, 10],
        [60, 14],
      ]),
    );
    expect(other.pixels, isNot(a.pixels));
  });

  test('one point gives cells; a box over the limit gives none', () {
    final dot = _stroke('d', [
      [30, 30],
    ]);
    expect(_inked(_cells(dot)), greaterThan(0));
    final line = _stroke('l', [
      [0, 0],
      [100, 100],
    ]);
    final pts = line['points'] as List;
    expect(
      buildPencilCells(
        strokeOutlineFor('pencil', 6, true, pts),
        strokeSamples(true, pts),
        1,
        maxCells: 1000,
      ),
      isNull,
    );
  });

  testWidgets('texture builds, paints, and follows a move', (t) async {
    await t.runAsync(() async {
      final tex = PencilTextures();
      final s = _stroke('t', [
        [10, 20],
        [60, 24],
        [90, 20],
      ]);
      expect(tex.lookup(s), isNull); // first frame: alpha polygon
      await tex.settled();
      final first = tex.lookup(s)!;
      expect(first.m, isNull);

      final moved = _stroke('t', [
        [20, 25],
        [70, 29],
        [100, 25],
      ]);
      final d = tex.lookup(moved)!;
      expect(identical(d.image, first.image), isTrue);
      expect(d.m, [1.0, 0.0, 10.0, 5.0]);

      // A shape change (not a similarity) rebuilds.
      final bent = _stroke('t', [
        [20, 25],
        [70, 49],
        [100, 25],
      ]);
      expect(tex.lookup(bent), isNull);
      expect(tex.lookup(bent), isNull);
      await tex.settled();
      expect(tex.lookup(bent), isNotNull);

      // Gone from the page: released.
      tex.keepOnly({});
      expect(tex.lookup(bent), isNull);
      await tex.settled();
    });
  });

  test('each cell takes the pressure of its nearest sample', () {
    final s = {
      ..._stroke('v', [
        for (var i = 0; i <= 18; i++) [10 + i * 10, 20],
      ]),
      'points': [
        for (var i = 0; i <= 18; i++) [10 + i * 10, 20, i / 18, i * 10],
      ],
    };
    final pts = s['points'] as List;
    final smp = strokeSamples(true, pts);
    final c = buildPencilCells(
      strokeOutlineFor('pencil', 6, true, pts),
      smp,
      pencilSeed('v'),
    )!;
    var checked = 0;
    for (var i = c.i0; i < c.i0 + c.w; i++) {
      for (var j = c.j0; j < c.j0 + c.h; j++) {
        final cx = (i + 0.5) * pencilCell, cy = (j + 0.5) * pencilCell;
        var best = double.infinity;
        var bi = 0;
        for (var k = 0; k < smp.x.length; k++) {
          final d =
              (smp.x[k] - cx) * (smp.x[k] - cx) +
              (smp.y[k] - cy) * (smp.y[k] - cy);
          if (d < best) {
            best = d;
            bi = k;
          }
        }
        if (best > 1.0)
          continue; // inside the polygon for sure only near a sample
        checked++;
        expect(
          c.inked(i, j),
          pencilGrain(pencilSeed('v'), i, j) <
              pencilDensity(smp.q[bi]).threshold,
          reason: 'cell $i,$j',
        );
      }
    }
    expect(checked, greaterThan(1000));
  });

  testWidgets('painter draws the cells, with gaps, once the texture is ready', (
    t,
  ) async {
    final stroke = _stroke('p', [
      [10, 30],
      [80, 30],
    ], pressure: 0);
    final page = {
      'width': 100,
      'height': 60,
      'background': 'plain',
      'elements': [stroke],
    };
    final cache = StrokePathCache();
    // Zoom 4: a cell is 2 px, so single cells show.
    Future<List<int>> paint() async {
      final rec = ui.PictureRecorder();
      PagePainter(
        page: page,
        cache: cache,
        invert: false,
        viewport: const PageViewport(4, Offset.zero),
      ).paint(ui.Canvas(rec), const Size(400, 240));
      final img = await rec.endRecording().toImage(400, 240);
      return (await img.toByteData())!.buffer.asUint8List().toList();
    }

    await t.runAsync(() async {
      await paint(); // queues the build
      await cache.textures.settled();
      expect(cache.textures.lookup(stroke), isNotNull);
      final px = await paint();
      var black = 0, white = 0;
      for (var y = 116; y < 124; y++) {
        for (var x = 80; x < 280; x++) {
          final v = px[(y * 400 + x) * 4];
          if (v < 10) black++;
          if (v > 245) white++;
        }
      }
      final ratio = black / (8 * 200);
      expect(white, greaterThan(0)); // gaps show the paper
      expect(ratio, closeTo(0.35, 0.1));
    });
    cache.dispose();
  });
}
