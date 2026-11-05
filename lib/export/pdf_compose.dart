import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart';

// Joins the overlay PDF (the elements, drawn by the `pdf` package) with the
// original PDF pages (spec/export.md "PDF pages"): each PDF-background page is
// the original page as a form XObject (never an image, so its text stays
// extractable) onto a page of the stored width x height (`pdf.pageMatrix`), with the overlay page of the same number over it.
// A plain page is the overlay page as it is. Runs in an isolate.

/// One output page. [src] is the original PDF's path (null: a plain page).
/// [page] and [userUnit] come from the background reference.
typedef ComposePage = ({
  String? src,
  int page,
  double userUnit,
  double width,
  double height,
  bool overlay,
});

/// Writes the joined PDF to [outPath]; throws [StateError] when PDFium fails
/// (the caller removes the partial file).
Future<void> composePdf(
  String overlayPath,
  String outPath,
  List<ComposePage> pages,
) => Isolate.run(() => composePdfSync(overlayPath, outPath, pages));

void composePdfSync(
  String overlayPath,
  String outPath,
  List<ComposePage> pages,
) {
  final p = getPdfium();
  p.FPDF_InitLibrary();
  final docs = <String, FPDF_DOCUMENT>{};
  final natives = <Pointer>[];
  FPDF_DOCUMENT out = nullptr;
  RandomAccessFile? file;
  NativeCallable<
    Int Function(Pointer<FPDF_FILEWRITE>, Pointer<Void>, UnsignedLong)
  >?
  writer;
  FPDF_DOCUMENT open(String path) => docs[path] ??= () {
    final np = path.toNativeUtf8();
    final d = p.FPDF_LoadDocument(np.cast(), nullptr);
    calloc.free(np);
    if (d == nullptr) throw StateError('cannot open $path');
    return d;
  }();
  // An overlay page (or a plain page) goes in as a page copy.
  void importPage(FPDF_DOCUMENT from, int n, int at) {
    final r = '${n + 1}'.toNativeUtf8();
    final ok = p.FPDF_ImportPages(out, from, r.cast(), at);
    calloc.free(r);
    if (ok == 0) throw StateError('import page $n failed');
  }

  try {
    out = p.FPDF_CreateNewDocument();
    if (out == nullptr) throw StateError('cannot create the document');
    final ov = open(overlayPath);
    final m = calloc<FS_MATRIX>();
    natives.add(m);
    for (var i = 0; i < pages.length; i++) {
      final pg = pages[i];
      if (pg.src == null) {
        importPage(ov, i, i);
        continue;
      }
      final page = p.FPDFPage_New(out, i, pg.width, pg.height);
      if (page == nullptr) throw StateError('new page $i failed');
      final xobjects = <FPDF_XOBJECT>[];
      try {
        void put(FPDF_DOCUMENT from, int n, List<double> t) {
          final xo = p.FPDF_NewXObjectFromPage(out, from, n);
          if (xo == nullptr) throw StateError('xobject $n failed');
          xobjects.add(xo);
          final fo = p.FPDF_NewFormObjectFromXObject(xo);
          if (fo == nullptr) throw StateError('form object $n failed');
          m.ref
            ..a = t[0]
            ..b = t[1]
            ..c = t[2]
            ..d = t[3]
            ..e = t[4]
            ..f = t[5];
          if (p.FPDFPageObj_SetMatrix(fo, m) == 0 ||
              p.FPDFPage_InsertObject(page, fo) == 0) {
            p.FPDFPageObj_Destroy(fo);
            throw StateError('place $n failed');
          }
        }

        // PDFium's form already has /Rotate and the box origin applied (page
        // space, y up): what is left of the inverse `pdf.pageMatrix` is
        // the UserUnit.
        final u = pg.userUnit;
        put(open(pg.src!), pg.page, [u, 0, 0, u, 0, 0]);
        if (pg.overlay) put(ov, i, const [1, 0, 0, 1, 0, 0]);
        if (p.FPDFPage_GenerateContent(page) == 0) {
          throw StateError('content $i failed');
        }
      } finally {
        p.FPDF_ClosePage(page);
        for (final x in xobjects) {
          p.FPDF_CloseXObject(x);
        }
      }
    }
    file = File(outPath).openSync(mode: FileMode.write);
    final f = file;
    var failed = false;
    writer =
        NativeCallable<
          Int Function(Pointer<FPDF_FILEWRITE>, Pointer<Void>, UnsignedLong)
        >.isolateLocal((
          Pointer<FPDF_FILEWRITE> _,
          Pointer<Void> data,
          int size,
        ) {
          try {
            f.writeFromSync(data.cast<Uint8>().asTypedList(size));
            return 1;
          } catch (_) {
            failed = true;
            return 0;
          }
        }, exceptionalReturn: 0);
    final fw = calloc<FPDF_FILEWRITE>();
    natives.add(fw);
    fw.ref
      ..version = 1
      ..WriteBlock = writer.nativeFunction;
    if (p.FPDF_SaveAsCopy(out, fw, 0) == 0 || failed) {
      throw StateError('save failed');
    }
  } finally {
    writer?.close();
    file?.closeSync();
    for (final n in natives) {
      calloc.free(n);
    }
    if (out != nullptr) p.FPDF_CloseDocument(out);
    for (final d in docs.values) {
      p.FPDF_CloseDocument(d);
    }
  }
}
