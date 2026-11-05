import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/storage/theme_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<List<int>> _pixels(bool invert, Object background) async {
  final page = {
    'width': 4,
    'height': 4,
    'background': background,
    'elements': <Object>[],
  };
  final rec = ui.PictureRecorder();
  PagePainter(
    page: page,
    cache: StrokePathCache(),
    invert: invert,
  ).paint(ui.Canvas(rec), const ui.Size(4, 4));
  final img = await rec.endRecording().toImage(4, 4);
  final d = (await img.toByteData())!;
  return [for (var i = 0; i < 3; i++) d.getUint8(i)];
}

void main() {
  test('theme choice defaults to Light and is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ThemeStore(await SharedPreferences.getInstance());
    expect(store.read(), ThemeChoice.light);
    await store.write(ThemeChoice.allDark);
    expect(store.read(), ThemeChoice.allDark);
  });

  testWidgets('All Dark paints the dark paper; a PDF page stays white', (
    tester,
  ) async {
    await tester.runAsync(() async {
      expect(await _pixels(false, 'plain'), [255, 255, 255]);
      expect(await _pixels(true, 'plain'), [27, 28, 31]);
      final pdf = {
        'type': 'pdf',
        'asset': 'a' * 64,
        'page': 0,
        'box': [0, 0, 595, 842],
        'rotate': 0,
        'userUnit': 1,
      };
      expect(await _pixels(true, pdf), [255, 255, 255]);
    });
  });
}
