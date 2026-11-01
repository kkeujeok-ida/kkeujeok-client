// Story 8.2: the PDF built from an export plan (structure, not pixels), the
// range, cancel and missing-asset paths.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/ui/export_screen.dart';
import 'package:kkeujeok/export/export_rules.dart';
import 'package:kkeujeok/export/pdf_writer.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/text_metrics.dart';
import 'package:kkeujeok/storage/asset_store.dart';

// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);
final _hash = AssetStore.sha256Hex(_png);

Map<String, dynamic> _page(
  String id,
  num w,
  num h,
  String bg,
  List<Map<String, dynamic>> els,
) => {
  'id': id,
  'width': w,
  'height': h,
  'background': bg,
  'rev': 'r',
  'seq': 1,
  'editedAt': 'x',
  'editedBy': 'y',
  'elements': els,
};

Note _note() => Note.parse({
  'formatVersion': 1,
  'noteId': 'n',
  'meta': {'title': '수학 노트'},
  'metaRev': 'm',
  'metaSeq': 1,
  'orderRev': 'o',
  'orderSeq': 1,
  'pages': [
    _page('p1', 595, 842, 'lined', [
      {
        'id': 't',
        'type': 'text',
        'x': 40,
        'y': 60,
        'width': 300,
        'text': 'Hello 안녕',
        'size': 20,
        'runs': [
          {'start': 6, 'end': 8, 'bold': true, 'color': '#ff0000'},
        ],
      },
      {
        'id': 'pen',
        'type': 'stroke',
        'tool': 'pen',
        'color': '#ffffff',
        'width': 3,
        'usePressure': false,
        'points': [
          [10, 10, 0.5, 0],
          [100, 80, 0.5, 10],
          [160, 20, 0.5, 20],
        ],
      },
      {
        'id': 'hl',
        'type': 'stroke',
        'tool': 'highlighter',
        'color': '#fdd55d',
        'width': 14,
        'usePressure': false,
        'points': [
          [20, 200, 0.5, 0],
          [200, 200, 0.5, 10],
        ],
      },
      {
        'id': 'img',
        'type': 'image',
        'x': 50,
        'y': 300,
        'width': 100,
        'height': 80,
        'rotation': 30,
        'asset': _hash,
        'ext': 'png',
      },
    ]),
    _page('p2', 842, 595, 'plain', []),
    _page('p3', 595, 842, 'dot', []),
  ],
}).note!;

Future<Uint8List> _pdf(
  Note note,
  Map<String, dynamic> range, {
  Set<String>? local,
  void Function(int, int)? onProgress,
  bool Function()? cancelled,
}) {
  final plan = exportPlan(note, range, local ?? {_hash});
  if (plan['error'] != null) throw StateError('${plan['error']}');
  return buildPdf(
    plan: plan,
    note: note,
    readAsset: (h) async => h == _hash ? Uint8List.fromList(_png) : null,
    regularFont: File('assets/fonts/Pretendard-Regular.ttf').readAsBytesSync(),
    semiBoldFont: File('assets/fonts/Pretendard-SemiBold.ttf')
        .readAsBytesSync(),
    onProgress: onProgress,
    cancelled: cancelled,
    compress: false,
  );
}

String _text(Uint8List b) => latin1.decode(b);

void main() {
  setUpAll(() {
    TextMetrics.install(
      File('assets/fonts/Pretendard-Regular.otf').readAsBytesSync(),
      File('assets/fonts/Pretendard-SemiBold.otf').readAsBytesSync(),
    );
  });

  test('all pages: count, sizes, vector page parts, fonts, image', () async {
    final progress = <int>[];
    final s = _text(
      await _pdf(_note(), {
        'mode': 'all',
        'current': 1,
      }, onProgress: (d, t) => progress.add(d * 10 + t)),
    );
    expect(RegExp(r'/Type/Page\b').allMatches(s).length, 3);
    expect(s, contains('/MediaBox[0 0 595 842]'));
    expect(s, contains('/MediaBox[0 0 842 595]'));
    expect(progress, [3, 13, 23, 33]);
    // Highlighter: constant alpha 0.4, Multiply.
    expect(s, contains('/BM/Multiply'));
    expect(s, contains('/ca 0.4'));
    expect(s, contains('/Subtype/Image')); // plus its alpha mask
    // Both Pretendard faces embedded; the text maps back to characters.
    expect(s, contains('/BaseFont/Pretendard-Regular'));
    expect(s, contains('/BaseFont/Pretendard-SemiBold'));
    final cmap = s.substring(s.indexOf('begincmap'));
    for (final cp in ['0048', 'C548', 'B155']) {
      expect(cmap.toUpperCase(), contains('<$cp>'));
    }
  });

  test('a range makes only those pages; dark theme changes nothing', () async {
    final s = _text(
      await _pdf(_note(), {'mode': 'custom', 'text': '2-3', 'current': 1}),
    );
    expect(RegExp(r'/Type/Page\b').allMatches(s).length, 2);
    expect(s, isNot(contains('/Subtype/Image')));
    expect(s, isNot(contains('/BaseFont/Pretendard')));
  });

  test('current page is one page', () async {
    final s = _text(await _pdf(_note(), {'mode': 'current', 'current': 2}));
    expect(RegExp(r'/Type/Page\b').allMatches(s).length, 1);
    expect(s, contains('/MediaBox[0 0 842 595]'));
  });

  test('cancel stops the build', () async {
    var pages = 0;
    await expectLater(
      _pdf(
        _note(),
        {'mode': 'all', 'current': 1},
        onProgress: (d, _) => pages = d,
        cancelled: () => pages >= 1,
      ),
      throwsA(isA<ExportCancelled>()),
    );
  });

  test('an asset not on the device is assetMissing, nothing is built', () {
    final plan = exportPlan(_note(), {'mode': 'all', 'current': 1}, <String>{});
    expect(plan, {
      'error': 'assetMissing',
      'assets': [_hash],
    });
    // Out of the range, the image does not matter.
    expect(
      exportPlan(_note(), {
        'mode': 'current',
        'current': 2,
      }, <String>{})['error'],
      isNull,
    );
  });

  test('a bad range is an error of export.range', () {
    expect(
      exportPlan(_note(), {
        'mode': 'custom',
        'text': '3-9',
        'current': 1,
      }, {})['error'],
      'outOfRange',
    );
  });

  testWidgets('a wrong range shows the error and disables Export', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ExportScreen(note: _note(), currentIndex: 0),
        ),
      ),
    );
    FilledButton button() => t.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNotNull);
    await t.tap(find.text('페이지 범위'));
    await t.pump();
    expect(button().onPressed, isNull); // empty
    await t.enterText(find.byType(TextField), '2-9');
    await t.pump();
    expect(find.text('페이지는 1부터 3 사이여야 해요.'), findsOneWidget);
    expect(button().onPressed, isNull);
    await t.enterText(find.byType(TextField), '2-3');
    await t.pump();
    expect(button().onPressed, isNotNull);
  });
}
