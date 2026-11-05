import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:pdfium_dart/pdfium_dart.dart';

import '../model/pdf_rules.dart';

// What the PDF file says (spec/pdf.md `pdf.import` input): size, head, SHA-256
// and the page boxes PDFium reads. The work runs in an isolate: the UI never
// waits for a 100 MB file.

/// A refusal; [code] is a reason of `pdf.import`, or `failed` when PDFium
/// itself could not run (shown as the unreadable-file text).
class PdfImportException implements Exception {
  const PdfImportException(this.code);
  final String code;
  @override
  String toString() => 'PdfImportException($code)';
}

class PdfImportCancelled implements Exception {
  const PdfImportCancelled();
}

/// Lets the caller stop a running import.
class PdfCancel {
  bool cancelled = false;
  void Function()? _stop;

  void cancel() {
    cancelled = true;
    _stop?.call();
  }
}

class PdfProbe {
  const PdfProbe(this.size, this.head, this.sha256, this.parse);
  final int size;
  final String head;
  final String sha256;
  final Map<String, Object?> parse;

  Map<String, Object?> input(String fileName) => {
    'fileName': fileName,
    'size': size,
    'head': head,
    'sha256': sha256,
    'parse': parse,
  };
}

/// Reads [path]; reports `(done, total)` pages while PDFium goes through them.
Future<PdfProbe> probePdf(
  String path,
  PdfCancel cancel,
  void Function(int done, int total) onProgress,
) async {
  final rx = ReceivePort(), err = ReceivePort();
  final out = Completer<PdfProbe>();
  void close() {
    rx.close();
    err.close();
  }

  final iso = await Isolate.spawn(_probeMain, (
    rx.sendPort,
    path,
  ), onError: err.sendPort);
  cancel._stop = () {
    iso.kill(priority: Isolate.immediate);
    close();
    if (!out.isCompleted) out.completeError(const PdfImportCancelled());
  };
  if (cancel.cancelled) cancel._stop!();
  rx.listen((m) {
    if (m is (int, int)) {
      onProgress(m.$1, m.$2);
    } else if (m is Map) {
      close();
      iso.kill();
      out.complete(
        PdfProbe(
          m['size'] as int,
          m['head'] as String,
          m['sha256'] as String,
          (m['parse'] as Map).cast<String, Object?>(),
        ),
      );
    }
  });
  err.listen((_) {
    close();
    if (!out.isCompleted) out.completeError(const PdfImportException('failed'));
  });
  return out.future;
}

Future<void> _probeMain((SendPort, String) a) async {
  final (port, path) = a;
  final file = File(path);
  final size = await file.length();
  final raf = await file.open();
  final headBytes = await raf.read(5);
  await raf.close();
  final head = [for (final b in headBytes) b.toRadixString(16).padLeft(2, '0')]
      .join();
  var sha = '';
  var parse = <String, Object?>{'status': 'corrupt'};
  // Too big or not a PDF: refused by `pdf.import` before anything else is
  // looked at, so the hash and the pages are not worth the time.
  if (head == pdfHeadHex && size <= pdfMaxBytes) {
    sha = (await crypto.sha256.bind(file.openRead()).first).toString();
    parse = _parse(path, (d, t) => port.send((d, t)));
    final units = await _userUnits(file);
    // shortcut: PDFium does not give /UserUnit, so the file text is searched;
    // it counts only when every page has one and they are all equal (several
    // values, some pages only, or one inside a compressed object stream are
    // not matched to pages: 1 is used).
    final pages = parse['pages'];
    if (pages is List &&
        units.length == pages.length &&
        units.toSet().length == 1) {
      for (final p in pages) {
        (p as Map)['userUnit'] = units.first;
      }
    }
  }
  port.send({'size': size, 'head': head, 'sha256': sha, 'parse': parse});
}

Map<String, Object?> _parse(String path, void Function(int, int) progress) {
  final pdfium = getPdfium();
  pdfium.FPDF_InitLibrary();
  final native = path.toNativeUtf8();
  final doc = pdfium.FPDF_LoadDocument(native.cast(), nullptr);
  calloc.free(native);
  if (doc == nullptr) {
    // 4 password, 5 security handler
    final e = pdfium.FPDF_GetLastError();
    // A trailer that names /Encrypt but PDFium cannot read is still encrypted.
    final tail = _tail(path);
    return {
      'status': e == 4 || e == 5 || tail.contains('/Encrypt')
          ? 'encrypted'
          : 'corrupt',
    };
  }
  final box = calloc<Float>(4);
  try {
    // An owner-password file opens without a password but is still refused.
    if (pdfium.FPDF_GetSecurityHandlerRevision(doc) != -1) {
      return {'status': 'encrypted'};
    }
    final n = pdfium.FPDF_GetPageCount(doc);
    if (n > pdfMaxPages) {
      return {
        'status': 'ok',
        'encrypted': false,
        'pages': List.generate(n, (_) => <String, Object?>{}),
      };
    }
    List<double>? read(
      int Function(
        Pointer<Float>,
        Pointer<Float>,
        Pointer<Float>,
        Pointer<Float>,
      )
      get,
    ) => get(box, box + 1, box + 2, box + 3) == 0
        ? null
        : [for (var k = 0; k < 4; k++) box[k]];

    final pages = <Map<String, Object?>>[];
    for (var i = 0; i < n; i++) {
      final page = pdfium.FPDF_LoadPage(doc, i);
      if (page == nullptr) return {'status': 'corrupt'};
      try {
        final media = read(
          (a, b, c, d) => pdfium.FPDFPage_GetMediaBox(page, a, b, c, d),
        );
        // No MediaBox: nothing to take the size from (it is not guessed).
        if (media == null) return {'status': 'corrupt'};
        final crop = read(
          (a, b, c, d) => pdfium.FPDFPage_GetCropBox(page, a, b, c, d),
        );
        pages.add({
          'mediaBox': media,
          'cropBox': ?crop,
          'rotate': pdfium.FPDFPage_GetRotation(page).clamp(0, 3) * 90,
        });
      } finally {
        pdfium.FPDF_ClosePage(page);
      }
      progress(i + 1, n);
    }
    return {'status': 'ok', 'encrypted': false, 'pages': pages};
  } finally {
    calloc.free(box);
    pdfium.FPDF_CloseDocument(doc);
  }
}

String _tail(String path) {
  final f = File(path).openSync();
  try {
    final n = f.lengthSync();
    f.setPositionSync(n > 4096 ? n - 4096 : 0);
    return latin1.decode(f.readSync(4096));
  } finally {
    f.closeSync();
  }
}

final _unit = RegExp(r'^\s*([0-9]*\.?[0-9]+)');

/// Every `/UserUnit` value written in plain text in [f].
Future<List<double>> _userUnits(File f) async {
  final found = <double>[];
  var carry = '';
  await for (final chunk in f.openRead()) {
    final s = carry + latin1.decode(chunk);
    for (
      var i = s.indexOf('/UserUnit');
      i >= 0;
      i = s.indexOf('/UserUnit', i + 9)
    ) {
      if (i + 40 <= carry.length) continue; // seen whole in the last chunk
      final m = _unit.firstMatch(
        s.substring(i + 9, (i + 40).clamp(0, s.length)),
      );
      final v = m == null ? null : double.tryParse(m.group(1)!);
      if (v != null && v > 0) found.add(v);
    }
    carry = s.length > 40 ? s.substring(s.length - 40) : s;
  }
  return found;
}

/// A PDF another app opened or shared (Android intent): the copy in the cache
/// folder and the name of the file, once; null when there is none. Throws
/// [PdfImportException] when the copy failed.
Future<({String path, String name})?> takeSharedPdf() async {
  try {
    final m = await const MethodChannel('com.kkeujeok.app/pdf')
        .invokeMapMethod<String, String>('takePending');
    if (m == null) return null;
    return (path: m['path']!, name: m['name']!);
  } on PlatformException {
    throw const PdfImportException('failed'); // the copy failed: say so
  } on MissingPluginException {
    return null; // tests, other platforms
  }
}
