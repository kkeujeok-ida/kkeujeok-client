// Story 9.6: original PDF pages + the overlay of the elements, joined by the
// real PDFium; the result is read back (page count, size, original text, the
// elements drawn over the original).
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' show min, max;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/export/pdf_export.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/pdf_rules.dart';
import 'package:kkeujeok/model/text_metrics.dart';
import 'package:kkeujeok/render/pdf_pages.dart';
import 'package:kkeujeok/storage/asset_store.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:pdfium_dart/pdfium_dart.dart';

final _dir = '${Directory.current.parent.path}/test/pdf';

Map<String, dynamic> _ref(Map m, int page) {
  final g = m['pages'][page] as Map;
  return {
    'type': 'pdf',
    'asset': m['sha256'],
    'page': page,
    'box': g['box'],
    'rotate': g['rotate'],
    'userUnit': g['userUnit'],
  };
}

Map<String, dynamic> _page(String id, num w, num h, Object bg) => {
  'id': id,
  'width': w,
  'height': h,
  'background': bg,
  'rev': 'r',
  'seq': 1,
  'editedAt': 'x',
  'editedBy': 'y',
  'elements': [
    {
      'id': '$id-pen',
      'type': 'stroke',
      'tool': 'pen',
      'color': '#ff0000',
      'width': 6,
      'usePressure': false,
      'points': [
        [10, 10, 0.5, 0],
        [100, 80, 0.5, 10],
        [160, 20, 0.5, 20],
      ],
    },
    {
      'id': '$id-hl',
      'type': 'stroke',
      'tool': 'highlighter',
      'color': '#fdd55d',
      'width': 14,
      'usePressure': false,
      'points': [
        [20, 120, 0.5, 0],
        [200, 120, 0.5, 10],
      ],
    },
    {
      'id': '$id-t',
      'type': 'text',
      'x': 30,
      'y': 200,
      'width': 200,
      'text': '필기 Hello',
      'size': 20,
    },
  ],
};

Note _note(List<Map<String, dynamic>> pages) => Note.parse({
  'formatVersion': 1,
  'noteId': 'n',
  'meta': {'title': 't'},
  'metaRev': 'm',
  'metaSeq': 1,
  'orderRev': 'o',
  'orderSeq': 1,
  'pages': pages,
}).note!;

/// (width, height, text) of every page of [path].
List<(double, double, String)> _read(String path) {
  final p = getPdfium();
  p.FPDF_InitLibrary();
  final np = path.toNativeUtf8();
  final doc = p.FPDF_LoadDocument(np.cast(), nullptr);
  calloc.free(np);
  expect(doc, isNot(nullptr));
  final out = <(double, double, String)>[];
  for (var i = 0; i < p.FPDF_GetPageCount(doc); i++) {
    final page = p.FPDF_LoadPage(doc, i);
    final tp = p.FPDFText_LoadPage(page);
    final n = p.FPDFText_CountChars(tp);
    final buf = calloc<UnsignedShort>(n + 1);
    p.FPDFText_GetText(tp, 0, n, buf);
    out.add((
      p.FPDF_GetPageWidthF(page),
      p.FPDF_GetPageHeightF(page),
      String.fromCharCodes(buf.cast<Uint16>().asTypedList(n)),
    ));
    calloc.free(buf);
    p.FPDFText_ClosePage(tp);
    p.FPDF_ClosePage(page);
  }
  p.FPDF_CloseDocument(doc);
  return out;
}

/// [left, right, bottom, top] of the first character of page 1.
List<double> _firstChar(String path) {
  final p = getPdfium();
  p.FPDF_InitLibrary();
  final np = path.toNativeUtf8();
  final doc = p.FPDF_LoadDocument(np.cast(), nullptr);
  calloc.free(np);
  final page = p.FPDF_LoadPage(doc, 0);
  final tp = p.FPDFText_LoadPage(page);
  final b = calloc<Double>(4);
  p.FPDFText_GetCharBox(tp, 0, b, b + 1, b + 2, b + 3);
  final r = [for (var i = 0; i < 4; i++) b[i]];
  calloc.free(b);
  p.FPDFText_ClosePage(tp);
  p.FPDF_ClosePage(page);
  p.FPDF_CloseDocument(doc);
  return r;
}

void main() {
  late Directory tmp;
  late AssetStore store;
  final manifest = jsonDecode(
    File('$_dir/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  Map m(String f) => manifest[f] as Map;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TextMetrics.install(
      File('assets/fonts/Pretendard-Regular.otf').readAsBytesSync(),
      File('assets/fonts/Pretendard-SemiBold.otf').readAsBytesSync(),
    );
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('compose');
    store = AssetStore(NoteData(() async => tmp));
    for (final f in [
      'a4.pdf',
      'rotated90.pdf',
      'rotated270.pdf',
      'cropOffset.pdf',
      'userUnit2.pdf',
      'mixed.pdf',
    ]) {
      await store.writeFile(File('$_dir/$f'), m(f)['sha256'] as String, 'pdf');
    }
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<File> run(Note n, Map<String, dynamic> range) => exportNotePdf(
    note: n,
    range: range,
    store: store,
    dir: Directory('${tmp.path}/out'),
  );

  test('samples: size, original text, elements over it', () async {
    for (final f in [
      'a4.pdf',
      'rotated90.pdf',
      'rotated270.pdf',
      'cropOffset.pdf',
      'userUnit2.pdf',
    ]) {
      final g = (m(f)['pages'] as List).first as Map;
      final note = _note([_page('p', g['width'], g['height'], _ref(m(f), 0))]);
      final file = await run(note, {'mode': 'all', 'current': 1});
      final r = _read(file.path);
      expect(r.length, 1, reason: f);
      expect(r[0].$1, closeTo(g['width'] as num, 0.01), reason: f);
      expect(r[0].$2, closeTo(g['height'] as num, 0.01), reason: f);
      expect(r[0].$3, contains(g['text'] as String), reason: f);
      expect(r[0].$3, contains('Hello'), reason: f); // the element too
      // The original sits where `pdf.pageMatrix` puts it.
      final ref = _ref(m(f), 0);
      final o = _firstChar('$_dir/$f');
      final pts = [
        for (final (x, y) in [(o[0], o[2]), (o[1], o[3])])
          pdfPagePoint(ref['box'], ref['rotate'], ref['userUnit'], [x, y]),
      ];
      final h = (g['height'] as num).toDouble();
      final out = _firstChar(file.path);
      expect(out[0], closeTo(min(pts[0][0], pts[1][0]), 0.1), reason: f);
      expect(out[1], closeTo(max(pts[0][0], pts[1][0]), 0.1), reason: f);
      expect(out[2], closeTo(h - max(pts[0][1], pts[1][1]), 0.1), reason: f);
      expect(out[3], closeTo(h - min(pts[0][1], pts[1][1]), 0.1), reason: f);
      // Elements are drawn: the render differs from the bare original.
      final s = pdfRenderSize((g['width'] as num).toDouble(), h, null, 1);
      expect(
        renderPdfPage(file.path, 0, s),
        isNot(renderPdfPage('$_dir/$f', 0, s)),
        reason: f,
      );
    }
  });

  test('mixed note: order, plain page, range, no other pages', () async {
    final mx = m('mixed.pdf');
    final pg = mx['pages'] as List;
    num w(int i) => (pg[i] as Map)['width'];
    num h(int i) => (pg[i] as Map)['height'];
    final note = _note([
      _page('a', w(2), h(2), _ref(mx, 2)),
      _page('b', 400, 300, 'lined'),
      _page('c', w(0), h(0), _ref(mx, 0)),
    ]);
    final all = _read((await run(note, {'mode': 'all', 'current': 1})).path);
    expect(all.length, 3);
    expect(all[0].$3, contains('mixed page 3'));
    expect(all[1].$3, isNot(contains('mixed page')));
    expect(all[1].$1, 400);
    expect(all[2].$3, contains('mixed page 1'));
    expect(all[2].$1, closeTo(w(0), 0.01));
    final one = await run(note, {'mode': 'current', 'current': 3});
    final r = _read(one.path);
    expect(r.length, 1);
    expect(r[0].$3, contains('mixed page 1'));
    expect(r[0].$3, isNot(contains('mixed page 2')));
    expect(r[0].$3, isNot(contains('mixed page 3')));
    expect(one.parent.listSync().length, 1); // temp files gone
  });

  test('PDF not on the device: nothing is made', () async {
    final h = m('a4.pdf')['sha256'];
    await File('${tmp.path}/assets/$h.pdf').delete();
    final g = (m('a4.pdf')['pages'] as List).first as Map;
    final note = _note([
      _page('p', g['width'], g['height'], _ref(m('a4.pdf'), 0)),
    ]);
    await expectLater(
      run(note, {'mode': 'all', 'current': 1}),
      throwsA(
        isA<ExportFailure>()
            .having((e) => e.code, 'code', 'assetMissing')
            .having((e) => e.pdfAssets, 'pdfAssets', [h]),
      ),
    );
  });
}
