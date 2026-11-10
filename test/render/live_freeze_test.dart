import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/smooth.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/render/stroke_outline.dart';
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

  // Distance from (x, y) to the nearest edge of [polys].
  double edgeDist(List<List<List<double>>> polys, double x, double y) {
    var best = double.infinity;
    for (final poly in polys) {
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        final dx = b[0] - a[0], dy = b[1] - a[1];
        final l2 = dx * dx + dy * dy;
        final t = l2 == 0
            ? 0.0
            : (((x - a[0]) * dx + (y - a[1]) * dy) / l2).clamp(0.0, 1.0);
        best = math.min(
          best,
          math.sqrt(
            math.pow(x - a[0] - t * dx, 2) + math.pow(y - a[1] - t * dy, 2),
          ),
        );
      }
    }
    return best;
  }

  Map<String, dynamic> curvy(String tool) => {
    ..._stroke(tool, 0),
    'points': [
      for (var i = 0; i < 70; i++)
        [
          10 + i * 3.0,
          40 + 15 * math.sin(i / 6),
          0.3 + 0.5 * (i % 7) / 7,
          i * 10,
        ],
    ],
  };

  test('live shape (kept pieces + open piece) equals the pen-up shape', () {
    for (final level in [0, 4]) {
      smoothInUse = level;
      for (final tool in ['pen', 'fountain', 'highlighter']) {
        final s = curvy(tool);
        final c = LiveCache()..pathOf(s);
        expect(c.polygons, isNotEmpty);
        final live = [...c.polygons, ...c.openPolygons];
        final done = piecePolygons(s, s['points'] as List);
        final a = tool == 'highlighter'
                ? polygonsPath(tool, live)
                : (Path()..fillType = PathFillType.nonZero),
            b = polygonsPath(tool, done);
        if (tool != 'highlighter') {
          for (final poly in live) {
            a.addPath(outlinePath(poly), ui.Offset.zero);
          }
        }
        final box = b.getBounds().inflate(2);
        var worst = 0.0;
        for (var x = box.left; x < box.right; x += 0.25) {
          for (var y = box.top; y < box.bottom; y += 0.25) {
            if (a.contains(ui.Offset(x, y)) != b.contains(ui.Offset(x, y))) {
              worst = math.max(worst, edgeDist(done, x, y));
            }
          }
        }
        expect(worst, lessThanOrEqualTo(0.5), reason: '$tool smooth $level');
      }
    }
    smoothInUse = 0;
  });

  testWidgets('a highlighter drawn in pieces is not darker at overlaps', (
    t,
  ) async {
    final s = {
      ..._stroke('highlighter', 0),
      'width': 12,
      'points': curvy('pen')['points'],
    };
    Future<int> darkest(bool split) async {
      final rec = ui.PictureRecorder();
      final cache = StrokePathCache();
      PagePainter(
        page: {
          'width': 240,
          'height': 100,
          'background': 'plain',
          'elements': split ? [] : [s],
        },
        cache: cache,
        invert: false,
        live: split ? () => s : null,
        viewport: const PageViewport(2, ui.Offset.zero),
      ).paint(ui.Canvas(rec), const ui.Size(480, 200));
      final img = await rec.endRecording().toImage(480, 200);
      final px = (await img.toByteData())!.buffer.asUint8List();
      var m = 255;
      for (var i = 0; i < px.length; i += 4) {
        m = math.min(m, px[i]);
      }
      cache.dispose();
      return m;
    }

    await t.runAsync(() async {
      final live = await darkest(true), done = await darkest(false);
      expect(live, greaterThanOrEqualTo(done));
    });
  });
}
