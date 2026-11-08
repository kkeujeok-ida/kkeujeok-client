import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/render/page_painter.dart';

Map<String, dynamic> _stroke(String id) => {
  'type': 'stroke',
  'id': id,
  'tool': 'pencil',
  'color': '#000000',
  'width': 6,
  'usePressure': true,
  'points': [
    [10, 30, 1.0, 0],
    [80, 30, 1.0, 10],
  ],
};

void main() {
  testWidgets('pencil shows the grain tile: gaps and ink, live and finished', (
    t,
  ) async {
    final stroke = _stroke('p');
    final page = {
      'width': 100,
      'height': 60,
      'background': 'plain',
      'elements': [stroke],
    };
    final cache = StrokePathCache();
    Future<Set<int>> shades({required bool live}) async {
      final rec = ui.PictureRecorder();
      PagePainter(
        page: live ? {...page, 'elements': []} : page,
        cache: cache,
        invert: false,
        live: live ? () => stroke : null,
        viewport: const PageViewport(4, Offset.zero),
      ).paint(ui.Canvas(rec), const Size(400, 240));
      final img = await rec.endRecording().toImage(400, 240);
      final px = (await img.toByteData())!.buffer.asUint8List();
      return {
        for (var y = 116; y < 124; y++)
          for (var x = 80; x < 280; x++) px[(y * 400 + x) * 4] ~/ 16,
      };
    }

    await t.runAsync(() async {
      await cache.textures.settled();
      expect(cache.textures.image, isNotNull);
      // A flat polygon has 2 shades (ink, paper); the grain gives many.
      expect((await shades(live: false)).length, greaterThan(4));
      expect((await shades(live: true)).length, greaterThan(4));
    });
    cache.dispose();
  });
}
