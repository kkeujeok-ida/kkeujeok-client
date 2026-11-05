// The real PDFium reads the sample PDFs of the root repo; the page boxes must
// give the manifest's numbers through `pdf.import`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/image_rules.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/pdf_rules.dart';
import 'package:kkeujeok/storage/pdf_intake.dart';

void main() {
  final dir = '${Directory.current.parent.path}/test/pdf';
  final manifest = jsonDecode(
    File('$dir/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  for (final e in manifest.entries) {
    test('sample ${e.key}', () async {
      final m = e.value as Map<String, dynamic>;
      final probe = await probePdf('$dir/${e.key}', PdfCancel(), (_, _) {});
      final r = pdfImport(probe.input(e.key));
      if (m['status'] == 'ok') {
        expect(r['error'], isNull, reason: '${probe.parse}');
        expect(probe.sha256, m['sha256']);
        final pages = r['pages'] as List;
        final want = m['pages'] as List;
        expect(pages.length, want.length);
        for (var i = 0; i < want.length; i++) {
          final p = pages[i] as Map, w = want[i] as Map;
          final bg = p['background'] as Map;
          expect(p['width'], w['width']);
          expect(p['height'], w['height']);
          expect(bg['box'], w['box']);
          expect(bg['rotate'], w['rotate']);
          expect(bg['userUnit'], w['userUnit']);
        }
      } else {
        expect(r['error'], m['status'], reason: '${probe.parse}');
      }
    });
  }

  test('cancel before the result', () async {
    final cancel = PdfCancel();
    final f = probePdf('$dir/mixed.pdf', cancel, (_, _) {});
    cancel.cancel();
    await expectLater(f, throwsA(isA<PdfImportCancelled>()));
  });

  test('a note with a PDF background reads, keeps it and names its asset', () {
    final h = 'a' * 64;
    Map<String, dynamic> page(Object bg) => {
      'id': 'p',
      'width': 595,
      'height': 842,
      'background': bg,
      'rev': 'r',
      'seq': 1,
      'editedAt': 't',
      'editedBy': 'd',
      'elements': [],
    };
    final r = Note.parse({
      'formatVersion': 1,
      'noteId': 'n',
      'meta': {'title': 't'},
      'metaRev': 'm',
      'metaSeq': 1,
      'orderRev': 'o',
      'orderSeq': 1,
      'pages': [
        page({'type': 'pdf', 'asset': h, 'page': 0}), // malformed: kept
        page('plain'),
      ],
    });
    expect(r.status, ReadStatus.ok);
    expect(referencedAssets(r.note!), [h]);
    expect(isPdfBackground(r.note!.pages[0]['background']), isFalse);
  });
}
