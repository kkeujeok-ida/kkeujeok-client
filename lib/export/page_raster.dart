import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/image_rules.dart' show AssetState;
import '../model/pdf_rules.dart' show isPdfBackground;
import '../render/asset_images.dart' show PageImages;
import '../render/page_painter.dart';
import '../render/pdf_pages.dart' show renderPdfPage;

// The flat picture of a page with an answer tape (spec/export.md "Answer
// tape"): the screen drawing in original colors, tapes closed, at 2.5 px/pt.

class _Images implements PageImages {
  _Images(this.byAsset);
  final Map<String, ui.Image> byAsset;
  @override
  ui.Image? image(Map<String, dynamic> e) => byAsset[e['asset']];
  @override
  AssetState state(String asset) => AssetState.ready;
  @override
  bool pending(String asset) => false;
  @override
  String get downloadingLabel => '';
  @override
  String get failedLabel => '';
  @override
  String get imageLabel => '';
  @override
  String get pendingLabel => '';
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// RGBA pixels (opaque) of [page] at [wPx] x [hPx], or null when it cannot be
/// drawn. [readAsset] gives image bytes, [pdfPath] the file of a PDF ground
/// (null draws white).
Future<Uint8List?> renderPageRaster(
  Map<String, dynamic> page,
  int wPx,
  int hPx, {
  required Future<Uint8List?> Function(String hash) readAsset,
  String? Function(Map background)? pdfPath,
}) async {
  final owned = <ui.Image>[];
  final cache = StrokePathCache();
  try {
    final images = <String, ui.Image>{};
    for (final e in page['elements'] as List) {
      if (e is! Map || e['type'] != 'image' || e['asset'] is! String) continue;
      final hash = e['asset'] as String;
      if (images.containsKey(hash)) continue;
      try {
        final b = await readAsset(hash);
        if (b != null) owned.add(images[hash] = await _decode(b));
      } catch (_) {} // undecodable: the grey placeholder, as on screen
    }
    ui.Image? ground;
    final bg = page['background'];
    final path = isPdfBackground(bg) ? pdfPath?.call(bg as Map) : null;
    if (path != null) {
      final bgm = bg as Map;
      final px = await Future.sync(
        () => renderPdfPage(path, bgm['page'] as int, (
          bw: wPx,
          bh: hPx,
          sx: 0,
          sy: 0,
          fw: wPx,
          fh: hPx,
        )),
      );
      if (px != null) {
        owned.add(ground = await _fromBgra(px, wPx, hPx));
      }
    }
    final size = ui.Size(wPx.toDouble(), hPx.toDouble());
    final vp = PageViewport(2.5, ui.Offset.zero);
    ui.Picture draw() {
      final rec = ui.PictureRecorder();
      PagePainter(
        page: page,
        cache: cache,
        viewport: vp,
        images: _Images(images),
        pdfImage: ground,
        invert: false,
      ).paint(ui.Canvas(rec), size);
      return rec.endRecording();
    }

    draw().dispose(); // queues the pencil textures
    await cache.textures.settled();
    final pic = draw();
    final img = await pic.toImage(wPx, hPx);
    pic.dispose();
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      img.dispose();
    }
  } catch (_) {
    return null;
  } finally {
    cache.dispose();
    for (final i in owned) {
      i.dispose();
    }
  }
}

Future<ui.Image> _fromBgra(Uint8List px, int w, int h) async {
  final buf = await ui.ImmutableBuffer.fromUint8List(px);
  final d = ui.ImageDescriptor.raw(
    buf,
    width: w,
    height: h,
    pixelFormat: ui.PixelFormat.bgra8888,
  );
  final codec = await d.instantiateCodec();
  final img = (await codec.getNextFrame()).image;
  codec.dispose();
  d.dispose();
  buf.dispose();
  return img;
}
