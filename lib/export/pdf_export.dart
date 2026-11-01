import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../model/note.dart';
import '../storage/asset_store.dart';
import 'export_rules.dart';
import 'pdf_writer.dart';

/// Why an export did not produce a file: [code] is a range error, or
/// `assetMissing` (then [assets] lists the hashes), or `failed`.
class ExportFailure implements Exception {
  ExportFailure(this.code, [this.assets = const []]);
  final String code;
  final List<String> assets;
}

/// Writes the PDF of [note] for [range] (the input of `export.range` without
/// `pageCount`) into [dir] and returns the file. Reads the note and the asset
/// store only; nothing is changed. Throws [ExportCancelled] (no file is left)
/// or [ExportFailure].
Future<File> exportNotePdf({
  required Note note,
  required Map<String, dynamic> range,
  required AssetStore store,
  required Directory dir,
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  try {
    final hashes = {
      for (final p in note.pages)
        for (final e in (p['elements'] as List))
          if (e is Map && e['type'] == 'image' && e['asset'] is String)
            e['asset'] as String,
    };
    final plan = exportPlan(note, range, await store.local(hashes));
    if (plan['error'] == 'assetMissing') {
      throw ExportFailure('assetMissing', (plan['assets'] as List).cast());
    }
    if (plan['error'] != null) throw ExportFailure(plan['error'] as String);
    Future<Uint8List> font(String name) async =>
        (await rootBundle.load('assets/fonts/$name.ttf')).buffer.asUint8List();
    final pdf = await buildPdf(
      plan: plan,
      note: note,
      readAsset: (h) async {
        final b = await store.read(h);
        return b == null ? null : Uint8List.fromList(b);
      },
      regularFont: await font('Pretendard-Regular'),
      semiBoldFont: await font('Pretendard-SemiBold'),
      onProgress: onProgress,
      cancelled: cancelled,
    );
    if (cancelled?.call() ?? false) throw ExportCancelled();
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}${plan['fileName']}',
    );
    await file.writeAsBytes(pdf, flush: true);
    return file;
  } on ExportAssetMissing catch (e) {
    throw ExportFailure('assetMissing', e.assets);
  } on ExportFailure {
    rethrow;
  } on ExportCancelled {
    rethrow;
  } catch (_) {
    throw ExportFailure('failed');
  }
}
