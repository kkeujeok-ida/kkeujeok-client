import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/render/page_painter.dart';

Map<String, dynamic> _stroke(String id, {Object? brush}) => {
  'type': 'stroke',
  'id': id,
  'tool': 'pencil',
  'color': '#000000',
  'width': 6,
  'usePressure': true,
  'brush': brush,
  'points': [
    [10, 30, 1.0, 0],
    [80, 30, 1.0, 10],
  ],
};

void main() {
  testWidgets(
    'pencil stamps: grainy edge, live is the finished stroke without its end stamp, none is flat',
    (t) async {
      // Made inside runAsync: its three image loads need the real event loop.
      late final StrokePathCache cache;
      Future<List<int>> render(
        Map<String, dynamic> stroke, {
        required bool live,
      }) async {
        final rec = ui.PictureRecorder();
        PagePainter(
          page: {
            'width': 100,
            'height': 60,
            'background': 'plain',
            'elements': live ? [] : [stroke],
          },
          cache: cache,
          invert: false,
          live: live ? () => stroke : null,
          viewport: const PageViewport(4, Offset.zero),
        ).paint(ui.Canvas(rec), const Size(400, 240));
        final img = await rec.endRecording().toImage(400, 240);
        return (await img.toByteData())!.buffer.asUint8List().toList();
      }

      await t.runAsync(() async {
        cache = StrokePathCache();
        await cache.textures.settled();
        expect(cache.textures.images, isNotNull);
        final done = await render(_stroke('p'), live: false);
        final live = await render(_stroke('p'), live: true);
        // The live list has no stamp at the end of the path (stamps v2).
        final all = stampsOf(_stroke('p'));
        final part = stampsOf(_stroke('p'), live: true);
        expect(part, isNotEmpty);
        expect(all.length, greaterThan(part.length));
        expect(all.sublist(0, part.length), part);
        expect(live.any((b) => b != live.first), isTrue);
        // Stamps give many shades; the plain polygon (texture none) only a few.
        Set<int> shades(List<int> px) => {
          for (var y = 100; y < 140; y++)
            for (var x = 40; x < 320; x++) px[(y * 400 + x) * 4] ~/ 16,
        };
        expect(shades(done).length, greaterThan(4));
        final flat = await render(
          _stroke('p', brush: {'texture': 'none'}),
          live: false,
        );
        expect(shades(flat).length, lessThan(shades(done).length));
      });
      cache.dispose();
    },
  );
}
