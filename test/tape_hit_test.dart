import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/eraser.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/model/tape_hit.dart';

Map<String, dynamic> tape(String id, double y, [String tool = 'tape']) => {
  'type': 'stroke',
  'id': id,
  'tool': tool,
  'width': 20,
  'usePressure': false,
  'color': '#000000',
  'points': [
    [0, y, 0.5, 0],
    [100, y, 0.5, 10],
  ],
};

void main() {
  test('topmost tape wins; non-tapes and misses give null', () {
    final els = [tape('a', 50), tape('b', 55), tape('p', 200, 'pen')];
    expect(tapeAt(els, (50, 52)), 'b');
    expect(tapeAt(els, (50, 41)), 'a');
    expect(tapeAt(els, (50, 200)), isNull);
    expect(tapeAt(els, (50, 100)), isNull);
  });
  test('tap needs < 400 ms and < 6 dp', () {
    expect(isTapeTap(399, 5.9), isTrue);
    expect(isTapeTap(400, 1), isFalse);
    expect(isTapeTap(100, 6), isFalse);
  });

  test('partial erase removes the whole tape by its band, no pieces', () {
    final els = [tape('a', 50)];
    // 8 pt above the center line: inside the 10 pt half width, off the line.
    final r = eraseTargets(els, [(50.0, 42.0)], 1, true);
    expect(r.fade, {'a'});
    expect(r.elements, [els.first]); // no '~' pieces
    expect(eraseTargets(els, [(50.0, 30.0)], 1, true).fade, isEmpty);
  });

  test('open tape is an outline, closed is opaque', () async {
    final page = {
      'width': 100,
      'height': 100,
      'background': 'plain',
      'elements': [tape('a', 50)],
    };
    Future<List<int>> px(Set<String> open) async {
      final rec = ui.PictureRecorder();
      PagePainter(
        page: page,
        cache: StrokePathCache(),
        openTapes: open,
        invert: false,
      ).paint(ui.Canvas(rec), const ui.Size(100, 100));
      final img = await rec.endRecording().toImage(100, 100);
      final d = (await img.toByteData())!;
      final o = (50 * 100 + 50) * 4;
      return [d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2)];
    }

    final closed = await px({});
    final open = await px({'a'});
    expect(closed, isNot(open));
    expect(open, [255, 255, 255]); // paper shows through the middle
  });
}
