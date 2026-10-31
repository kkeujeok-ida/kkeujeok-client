// Story 6.2: the page overview screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/l10n/app_localizations_ko.dart';
import 'package:kkeujeok/ui/page_overview.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

final _a = _id(1001);
final _b = _id(1002);
final _c = _id(1003);

Note _note(int pages) {
  final j = createNote(
    title: 'Lecture',
    existingTitles: const [],
    background: 'plain',
    orientation: 'portrait',
    noteId: _id(1),
    pageId: _a,
    pageRev: _id(2001),
    metaRev: _id(3001),
    orderRev: _id(4001),
    now: '2000-01-01T12:00:00.000Z',
    editedBy: 'Pixel 8',
  ).note!.copyJson();
  final list = j['pages'] as List;
  for (var i = 1; i < pages; i++) {
    list.add({
      ...(list.first as Map<String, dynamic>),
      'id': [_a, _b, _c][i],
      'rev': _id(2001 + i),
    });
  }
  return Note.trusted(j);
}

void main() {
  late Directory docs;
  late NoteData data;
  late NoteStore store;
  late File file;

  setUp(() {
    resetStylusSeen();
    docs = Directory.systemTemp.createTempSync('kkj-multi-');
    data = NoteData(() async => docs);
    store = NoteStore(data);
    file = File('${docs.path}/$noteDataDirName/${_id(1)}/working.kkj');
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // The OS cleans temp up later.
      }
    });
  });

  void seed(Note n) {
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(encodeKkj(n));
  }

  Future<void> settle(WidgetTester t) async {
    var idle = 0;
    for (var i = 0; i < 1000 && idle < 30; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
      idle = t.binding.hasScheduledFrame ? 0 : idle + 1;
    }
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t) async {
    await pumpApp(t, noteData: data, noteStore: store);
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
    expect(find.byType(NoteEditor), findsOneWidget);
  }

  List<PagePainter> painters() => [
    for (final w
        in find
            .descendant(
              of: find.byType(NoteEditor),
              matching: find.byType(CustomPaint),
            )
            .evaluate()
            .map((e) => e.widget as CustomPaint))
      if (w.painter is PagePainter) w.painter as PagePainter,
  ];

  testWidgets('header, current ring, semantics, tap navigates and closes', (
    t,
  ) async {
    final sem = t.ensureSemantics();
    seed(_note(3));
    await open(t);
    await t.tap(find.byTooltip('Pages'));
    await settle(t);
    expect(find.byType(PageOverview), findsOneWidget);
    expect(find.text('Pages'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Page menu'), findsNWidgets(3)); // always visible
    expect(find.text('1 · Current'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 1 of 3, portrait, Current'), findsOne);
    expect(find.bySemanticsLabel('Page 3 of 3, portrait'), findsOne);

    await t.tap(find.bySemanticsLabel('Page 3 of 3, portrait'));
    await settle(t);
    expect(find.byType(PageOverview), findsNothing);
    expect(painters()[2].viewport!.offset.dy, lessThan(150));
    sem.dispose();
  });

  testWidgets('close button returns to the same page', (t) async {
    seed(_note(3));
    await open(t);
    final before = painters()[0].viewport!.offset;
    await t.tap(find.byTooltip('Pages'));
    await settle(t);
    await t.tap(find.byTooltip('Close'));
    await settle(t);
    expect(find.byType(PageOverview), findsNothing);
    expect(painters()[0].viewport!.offset, before);
  });

  test('TalkBack label in Korean', () {
    final l = AppLocalizationsKo();
    expect(
      '${l.pageSemantics(3, 5, l.pageLandscape)}, ${l.pageCurrent}',
      '3페이지 / 5, 가로, 현재',
    );
  });
}
