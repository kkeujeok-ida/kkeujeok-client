import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/render/pdf_pages.dart';

void main() {
  test('render size: whole page and a zoomed region', () {
    final w = pdfRenderSize(600, 800, null, 0.5);
    expect((w.bw, w.bh, w.sx, w.sy), (300, 400, 0, 0));
    final t = pdfRenderSize(
      600,
      800,
      const Rect.fromLTWH(100, 200, 200, 100),
      2,
    );
    expect(
      (t.bw, t.bh, t.sx, t.sy, t.fw, t.fh),
      (400, 200, -200, -400, 1200, 1600),
    );
  });

  test('PDFium renders a sample page to a non-blank bitmap of that size', () {
    final path = '${Directory.current.parent.path}/test/pdf/mixed.pdf';
    final s = pdfRenderSize(200, 300, null, 1);
    final px = renderPdfPage(path, 0, s)!;
    expect(px.length, s.bw * s.bh * 4);
    expect(px.any((b) => b != 255), isTrue);
    expect(renderPdfPage(path, 99, s), isNull);
  });
}
