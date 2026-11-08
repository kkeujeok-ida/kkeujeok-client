import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

// spec rule `stroke.texture.pencil` (spec/pen-kinds.md): density only. The
// grain is the tile image `assets/pencil_grain.png`, never stored in a note.
const pencilGrainAsset = 'assets/pencil_grain.png';

/// Page units per tile pixel: the tile is a 512 px paper-tooth grain.
const pencilGrainScale = 0.6;

/// `density(q)` and `threshold(q)`; [q] is clamped to 0..1.
({double density, int threshold}) pencilDensity(double q) {
  final c = q.isNaN ? 0.5 : q.clamp(0.0, 1.0);
  final d = 0.35 + 0.6 * c;
  return (density: d, threshold: (d * 65536 + 1e-6).floor());
}

/// The grain tile, loaded once. [image] is null until it is ready (strokes then
/// show the plain alpha polygon) and stays null if the asset cannot load.
class PencilTextures extends ChangeNotifier {
  PencilTextures({Future<Uint8List> Function()? load}) {
    _ready = _load(
      load ??
          () async =>
              (await rootBundle.load(pencilGrainAsset)).buffer.asUint8List(),
    );
  }

  ui.Image? image;
  late final Future<void> _ready;
  var _disposed = false;

  /// Completes when the tile is loaded (tests, export).
  Future<void> settled() => _ready;

  Future<void> _load(Future<Uint8List> Function() read) async {
    try {
      final codec = await ui.instantiateImageCodec(await read());
      final img = (await codec.getNextFrame()).image;
      codec.dispose();
      if (_disposed) {
        img.dispose();
        return;
      }
      image = img;
      notifyListeners();
    } catch (_) {
      // alpha polygon stays
    }
  }

  @override
  void dispose() {
    _disposed = true;
    image?.dispose();
    image = null;
    super.dispose();
  }
}
