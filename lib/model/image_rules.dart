import 'dart:math' as math;

import 'note.dart';
import 'number.dart';

// Spec rules of spec/image.md: image.accept, image.initialSize,
// image.referencedAssets, image.uploadPlan, image.assetState. Pure.

/// The least width or height of an image, pt.
const imageSizeMin = 1.0;

/// Largest stored asset, bytes (10 MB).
const imageMaxBytes = 10485760;

final _hash = RegExp(r'^[0-9a-f]{64}$');

/// True for 64 lowercase hex characters.
bool isAssetHash(Object? v) => v is String && _hash.hasMatch(v);

/// `image.accept`: [head] is the first 12 bytes as lowercase hex.
Map<String, Object?> imageAccept(String head, int size) {
  const heic = {'heic', 'heix', 'heim', 'heis', 'hevc', 'hevx', 'mif1', 'msf1'};
  String ascii(int from, int to) => head.length < to * 2
      ? ''
      : String.fromCharCodes([
          for (var i = from; i < to; i++)
            int.parse(head.substring(i * 2, i * 2 + 2), radix: 16),
        ]);
  String? ext;
  if (head.startsWith('ffd8ff')) {
    ext = 'jpg';
  } else if (head.startsWith('89504e470d0a1a0a')) {
    ext = 'png';
  } else if (head.length == 24 &&
      ascii(0, 4) == 'RIFF' &&
      ascii(8, 12) == 'WEBP') {
    ext = 'webp';
  } else if (head.length == 24 &&
      ascii(4, 8) == 'ftyp' &&
      heic.contains(ascii(8, 12))) {
    return {'accept': 'convert', 'ext': 'jpg'};
  }
  if (ext == null) return {'error': 'unsupported'};
  if (size > imageMaxBytes) return {'error': 'tooLarge'};
  return {'accept': 'as-is', 'ext': ext};
}

/// `image.initialSize`: `{width, height, x, y}`.
Map<String, num> imageInitialSize(
  num pxWidth,
  num pxHeight,
  num pageWidth,
  num pageHeight,
) {
  final maxW = pageWidth * 4 / 5, maxH = pageHeight * 4 / 5;
  final scale = math.min(1.0, math.min(maxW / pxWidth, maxH / pxHeight));
  final w = math.max(imageSizeMin, pxWidth * scale);
  final h = math.max(imageSizeMin, pxHeight * scale);
  return {
    'width': round2(w.toDouble()),
    'height': round2(h.toDouble()),
    'x': round2((pageWidth - w) / 2),
    'y': round2((pageHeight - h) / 2),
  };
}

/// `image.referencedAssets`: the `asset` of every image element, sorted,
/// without duplicates; a malformed one is kept (as `""` when not a string).
List<String> referencedAssets(Note note) {
  final out = <String>{};
  for (final p in note.pages) {
    for (final e in p['elements'] as List) {
      if (e is Map && e['type'] == 'image') {
        final a = e['asset'];
        out.add(a is String ? a : '');
      }
    }
  }
  return out.toList()..sort();
}

/// `image.uploadPlan`: what goes to Drive before the note.
Map<String, Object?> imageUploadPlan(
  Iterable<String> referenced,
  Iterable<String> confirmed,
  Iterable<String> onDevice,
) {
  final conf = confirmed.toSet(), dev = onDevice.toSet();
  final upload = <String>{}, missing = <String>{};
  for (final h in referenced) {
    if (conf.contains(h)) continue;
    (dev.contains(h) ? upload : missing).add(h);
  }
  return {
    'upload': upload.toList()..sort(),
    'missing': missing.toList()..sort(),
    'blocked': missing.isNotEmpty,
  };
}

enum AssetState { ready, downloading, failed }

/// `image.assetState`.
AssetState assetState(String asset, Set<String> local, Set<String> failed) {
  if (!isAssetHash(asset)) return AssetState.failed;
  if (local.contains(asset)) return AssetState.ready;
  return failed.contains(asset) ? AssetState.failed : AssetState.downloading;
}
