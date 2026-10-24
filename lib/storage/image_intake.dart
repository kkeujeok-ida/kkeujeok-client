import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../model/image_rules.dart';

enum IntakeSource { gallery, camera }

enum IntakeFailure {
  /// The user chose nothing: ignored without a word.
  cancelled,

  /// Permission refused (also a permanent refusal): reason and [설정 열기].
  denied,
  tooLarge,
  unsupported,
  convertFailed,
}

/// Bytes ready to store: accepted by `image.accept` (after a conversion when
/// [converted]).
class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.ext,
    required this.pxWidth,
    required this.pxHeight,
    required this.converted,
  });

  final List<int> bytes;
  final String ext;
  final int pxWidth, pxHeight;
  final bool converted;
}

class IntakeResult {
  const IntakeResult.ok(PickedImage this.image) : failure = null;
  const IntakeResult.fail(IntakeFailure this.failure) : image = null;

  final PickedImage? image;
  final IntakeFailure? failure;
}

/// Where the editor gets an image from (gallery or camera); a test replaces it.
abstract interface class ImageIntake {
  Future<IntakeResult> pick(IntakeSource source);

  /// Opens the app's system settings page.
  Future<void> openSettings();
}

String _hex(List<int> b) =>
    [for (final x in b.take(12)) x.toRadixString(16).padLeft(2, '0')].join();

/// The two-step check of spec `image.accept`: the file, and for a format that
/// must be converted, the converted bytes again.
Future<IntakeResult> acceptImage(
  List<int> bytes, {
  required Future<List<int>?> Function(List<int>) toJpeg,
  required Future<(int, int)?> Function(List<int>) dimensions,
}) async {
  if (bytes.isEmpty) return const IntakeResult.fail(IntakeFailure.unsupported);
  var r = imageAccept(_hex(bytes), bytes.length);
  var out = bytes;
  var converted = false;
  if (r['accept'] == 'convert') {
    List<int>? jpeg;
    try {
      jpeg = await toJpeg(bytes);
    } catch (_) {}
    if (jpeg == null || jpeg.isEmpty) {
      return const IntakeResult.fail(IntakeFailure.convertFailed);
    }
    out = jpeg;
    converted = true;
    r = imageAccept(_hex(out), out.length);
    if (r['error'] == 'unsupported') {
      return const IntakeResult.fail(IntakeFailure.convertFailed);
    }
  }
  if (r['error'] == 'tooLarge') {
    return const IntakeResult.fail(IntakeFailure.tooLarge);
  }
  if (r['error'] != null) {
    return const IntakeResult.fail(IntakeFailure.unsupported);
  }
  final d = await dimensions(out);
  if (d == null) return const IntakeResult.fail(IntakeFailure.unsupported);
  return IntakeResult.ok(
    PickedImage(
      bytes: out,
      ext: r['ext'] as String,
      pxWidth: d.$1,
      pxHeight: d.$2,
      converted: converted,
    ),
  );
}

Future<(int, int)?> _decodeSize(List<int> bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final f = await codec.getNextFrame();
    final size = (f.image.width, f.image.height);
    f.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

Future<List<int>?> _toJpeg(List<int> bytes) =>
    FlutterImageCompress.compressWithList(
      Uint8List.fromList(bytes),
      format: CompressFormat.jpeg,
      quality: 92,
      // The default scales a large photo down to 1920 x 1080.
      minWidth: 100000,
      minHeight: 100000,
    );

/// image_picker for the file, permission_handler for the camera, the
/// platform codecs for HEIC.
class PluginImageIntake implements ImageIntake {
  @override
  Future<IntakeResult> pick(IntakeSource source) async {
    try {
      if (source == IntakeSource.camera) {
        var s = await Permission.camera.status;
        if (!s.isGranted) s = await Permission.camera.request();
        if (!s.isGranted) return const IntakeResult.fail(IntakeFailure.denied);
      }
      final file = await ImagePicker().pickImage(
        source: source == IntakeSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
      if (file == null) return const IntakeResult.fail(IntakeFailure.cancelled);
      return await acceptImage(
        await file.readAsBytes(),
        toJpeg: _toJpeg,
        dimensions: _decodeSize,
      );
    } on PlatformException catch (e) {
      return IntakeResult.fail(
        e.code.endsWith('access_denied')
            ? IntakeFailure.denied
            : IntakeFailure.unsupported,
      );
    }
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
