import 'dart:ui' as ui;

import '../render/page_painter.dart';

/// The first page as a PNG of [width] x [height] pixels, with its background
/// and every element (spec `drive-layout` "Library list summary"). Null when
/// it cannot be drawn.
Future<List<int>?> renderThumbnail(
  Map<String, dynamic> page,
  int width,
  int height,
) async {
  try {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    PagePainter(
      page: page,
      cache: StrokePathCache(),
    ).paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
    final image = await recorder.endRecording().toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}
