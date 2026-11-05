import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../model/note.dart';
import '../storage/asset_store.dart';
import '../model/pdf_rules.dart' show isPdfBackground;
import 'export_rules.dart';
import 'pdf_compose.dart';
import 'pdf_writer.dart';

/// Why an export did not produce a file: [code] is a range error, or
/// `assetMissing` (then [assets] lists the hashes), or `failed`.
class ExportFailure implements Exception {
  ExportFailure(this.code, [this.assets = const [], this.pdfAssets = const []]);
  final String code;
  final List<String> assets, pdfAssets;
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
    // A PDF is checked by its file (it may be 100 MB: never read whole).
    final pdfPaths = <String, String>{};
    for (final p in note.pages) {
      final bg = p['background'];
      if (!isPdfBackground(bg)) continue;
      final h = (bg as Map)['asset'] as String;
      final path = await store.pdfPath(h);
      if (path != null) pdfPaths[h] = path;
    }
    final plan = exportPlan(note, range, [
      ...await store.local(hashes),
      ...pdfPaths.keys,
    ]);
    if (plan['error'] == 'assetMissing') {
      throw ExportFailure(
        'assetMissing',
        (plan['assets'] as List).cast(),
        ((plan['pdfAssets'] as List?) ?? const []).cast(),
      );
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
    if (pdfPaths.isEmpty) {
      await file.writeAsBytes(pdf, flush: true);
      return file;
    }
    // PDF pages: the overlay is joined with the original pages by PDFium.
    final tmp = File('${file.path}.overlay');
    final part = File('${file.path}.part');
    try {
      await tmp.writeAsBytes(pdf, flush: true);
      await composePdf(tmp.path, part.path, [
        for (final pp in (plan['pages'] as List).cast<Map>())
          _composePage(pp, note, pdfPaths),
      ]);
      if (cancelled?.call() ?? false) throw ExportCancelled();
      await part.rename(file.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
      if (await part.exists()) await part.delete();
    }
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

ComposePage _composePage(Map pp, Note note, Map<String, String> paths) {
  final w = (pp['width'] as num).toDouble(),
      h = (pp['height'] as num).toDouble();
  final pdf = pp['pdf'] as Map?;
  if (pdf == null) {
    return (
      src: null,
      page: 0,
      userUnit: 1,
      width: w,
      height: h,
      overlay: false,
    );
  }
  final bg =
      note.pages.firstWhere((p) => p['id'] == pp['id'])['background'] as Map;
  return (
    src: paths[pdf['asset']],
    page: pdf['page'] as int,
    userUnit: (bg['userUnit'] as num).toDouble(),
    width: w,
    height: h,
    overlay: (pp['elements'] as List).isNotEmpty,
  );
}
