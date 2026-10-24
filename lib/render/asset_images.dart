import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../model/image_rules.dart';
import '../storage/asset_store.dart';
import '../sync/asset_sync.dart';

/// What the page painter needs to draw image elements.
abstract class PageImages {
  /// The decoded image of an asset, or null while it is not ready.
  ui.Image? image(Map<String, dynamic> element);

  AssetState state(String asset);

  /// True while Drive is not known to hold the asset.
  bool pending(String asset);

  String get downloadingLabel;
  String get failedLabel;
  String get imageLabel;
  String get pendingLabel;
}

/// Decodes the stored bytes of an asset once and keeps the result. A decode
/// target keeps the longest side to [maxSide] px so a large photo does not
/// hold full resolution in memory.
class AssetImages extends ChangeNotifier implements PageImages {
  AssetImages(
    this.store,
    this.sync, {
    this.downloadingLabel = '',
    this.failedLabel = '',
    this.imageLabel = '',
    this.pendingLabel = '',
  }) {
    sync.addListener(notifyListeners);
  }

  final AssetStore store;
  final AssetSync sync;
  static const maxSide = 2048;

  @override
  String downloadingLabel, failedLabel, imageLabel, pendingLabel;

  final _images = <String, ui.Image>{};
  final _loading = <String>{};
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    sync.removeListener(notifyListeners);
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
    super.dispose();
  }

  @override
  AssetState state(String asset) => assetState(asset, sync.local, sync.failed);

  @override
  bool pending(String asset) => !sync.confirmed.contains(asset);

  @override
  ui.Image? image(Map<String, dynamic> e) {
    final h = e['asset'];
    if (h is! String || !sync.local.contains(h)) return null;
    final img = _images[h];
    if (img == null && _loading.add(h)) _load(h, e);
    return img;
  }

  Future<void> _load(String hash, Map<String, dynamic> e) async {
    try {
      final bytes = await store.read(hash);
      if (bytes == null || _disposed) return;
      final pw = (e['pxWidth'] as num?)?.toInt() ?? 0;
      final ph = (e['pxHeight'] as num?)?.toInt() ?? 0;
      final big = math.max(pw, ph) > maxSide;
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
        targetWidth: big && pw >= ph ? maxSide : null,
        targetHeight: big && ph > pw ? maxSide : null,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _images[hash] = frame.image;
    } catch (_) {
      // undecodable: stays a placeholder
    } finally {
      _loading.remove(hash);
      if (!_disposed) notifyListeners();
    }
  }
}

const _placeholder = Color(0xFFE0E0E0);
const _placeholderInk = Color(0xFF555555);

/// Draws image element [e] (rotation about its center) in page coordinates:
/// the image, or a grey placeholder at the stored size with its state text.
void paintImageElement(
  Canvas canvas,
  Map<String, dynamic> e,
  PageImages? source,
  double zoom,
) {
  final x = (e['x'] as num).toDouble(), y = (e['y'] as num).toDouble();
  final w = (e['width'] as num).toDouble(), h = (e['height'] as num).toDouble();
  final rot = ((e['rotation'] as num?) ?? 0).toDouble();
  final box = Rect.fromLTWH(x, y, w, h);
  final asset = '${e['asset']}';
  canvas.save();
  if (rot != 0) {
    canvas
      ..translate(box.center.dx, box.center.dy)
      ..rotate(rot * math.pi / 180)
      ..translate(-box.center.dx, -box.center.dy);
  }
  final img = source?.image(e);
  if (img != null) {
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      box,
      Paint()..filterQuality = FilterQuality.medium,
    );
  } else {
    canvas.drawRect(box, Paint()..color = _placeholder);
    final st = source?.state(asset);
    final text = switch (st) {
      AssetState.downloading => source!.downloadingLabel,
      AssetState.failed => source!.failedLabel,
      _ => '',
    };
    if (text.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 12, color: _placeholderInk),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: math.max(1, w - 4));
      tp.paint(canvas, Offset(x + (w - tp.width) / 2, y + (h - tp.height) / 2));
    }
  }
  if (source != null && source.pending(asset) && img != null) {
    // A small clock on the corner, the same size on screen at any zoom.
    final s = 18 / zoom;
    final c = Offset(x + w - s, y + 2 / zoom);
    canvas
      ..drawCircle(
        c + Offset(s / 2, s / 2),
        s / 2,
        Paint()..color = const Color(0xCCFFFFFF),
      )
      ..drawCircle(
        c + Offset(s / 2, s / 2),
        s / 2 - 1.5 / zoom,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / zoom
          ..color = _placeholderInk,
      )
      ..drawLine(
        c + Offset(s / 2, s / 2),
        c + Offset(s / 2, s * 0.25),
        Paint()
          ..strokeWidth = 1.5 / zoom
          ..color = _placeholderInk,
      )
      ..drawLine(
        c + Offset(s / 2, s / 2),
        c + Offset(s * 0.7, s / 2),
        Paint()
          ..strokeWidth = 1.5 / zoom
          ..color = _placeholderInk,
      );
  }
  canvas.restore();
}

/// True for an image element the painter can draw.
bool drawableImage(Object? e) =>
    e is Map<String, dynamic> &&
    e['type'] == 'image' &&
    e['id'] is String &&
    e['x'] is num &&
    e['y'] is num &&
    e['width'] is num &&
    e['height'] is num;
