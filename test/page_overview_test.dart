// Story 6.2: the page overview screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/render/selection_painter.dart';
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

  int onDisk() => decodeKkj(file.readAsBytesSync()).note!.pages.length;

  testWidgets('[+] adds after the current page; the snackbar undoes it', (
    t,
  ) async {
    seed(_note(3));
    await open(t);
    await t.tap(find.byTooltip('Pages'));
    await settle(t);
    await t.tap(find.byTooltip('Add page'));
    await settle(t);
    expect(find.text('Page 2 added'), findsOneWidget);
    expect(find.byTooltip('Page menu'), findsNWidgets(4));
    expect(onDisk(), 4);
    await t.tap(find.text('Undo'));
    await settle(t);
    expect(find.byTooltip('Page menu'), findsNWidgets(3));
    expect(onDisk(), 3);
  });

  testWidgets('menu: duplicate, delete with undo, current page falls back', (
    t,
  ) async {
    seed(_note(3));
    await open(t);
    await t.tap(find.byTooltip('Pages'));
    await settle(t);
    await t.tap(find.byTooltip('Page menu').at(1));
    await settle(t);
    await t.tap(find.text('Duplicate'));
    await settle(t);
    expect(find.text('Page 2 duplicated'), findsOneWidget);
    expect(onDisk(), 4);
    // The current page (1) is deleted: the next one (2) becomes current.
    await t.tap(find.byTooltip('Page menu').at(0));
    await settle(t);
    await t.tap(find.text('Delete'));
    await settle(t);
    expect(find.text('Page 1 deleted'), findsOneWidget);
    expect(onDisk(), 3);
    expect(find.text('1 · Current'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await settle(t);
    expect(onDisk(), 4);
  });

  testWidgets('the last page left cannot be deleted', (t) async {
    seed(_note(1));
    await open(t);
    await t.tap(find.byTooltip('Pages'));
    await settle(t);
    await t.tap(find.byTooltip('Page menu'));
    await settle(t);
    final item = t.widget<PopupMenuItem<VoidCallback>>(
      find.widgetWithText(PopupMenuItem<VoidCallback>, 'Delete'),
    );
    expect(item.enabled, isFalse);
  });

  testWidgets('a two-finger pull past the end adds a page, a short one not', (
    t,
  ) async {
    seed(_note(2));
    await open(t);
    Future<void> pull(double dy) async {
      final a = await t.startGesture(const Offset(300, 300), pointer: 1);
      final b = await t.startGesture(const Offset(400, 300), pointer: 2);
      for (var k = 1; k <= 10; k++) {
        await a.moveBy(Offset(0, dy / 10));
        await b.moveBy(Offset(0, dy / 10));
      }
      await a.up();
      await b.up();
      await settle(t);
    }

    await pull(-50); // a short scroll, nowhere near the end
    expect(onDisk(), 2);
    await pull(-4000); // far past the end, released
    expect(onDisk(), 3);
    expect(find.text('Page 3 added'), findsOneWidget);
  });

  testWidgets('a cancelled pull adds no page', (t) async {
    seed(_note(2));
    await open(t);
    final a = await t.startGesture(const Offset(300, 300), pointer: 1);
    final b = await t.startGesture(const Offset(400, 300), pointer: 2);
    for (var k = 1; k <= 10; k++) {
      await a.moveBy(const Offset(0, -400));
      await b.moveBy(const Offset(0, -400));
    }
    await a.cancel();
    await b.cancel();
    await settle(t);
    expect(onDisk(), 2);
  });

  List<String> order() => [
    for (final p in decodeKkj(file.readAsBytesSync()).note!.pages)
      p['id'] as String,
  ];

  Future<void> openOverview(WidgetTester t) async {
    await t.tap(find.byTooltip('Pages'));
    await settle(t);
  }

  // The thumbnail of page [n] sits above its number.
  Offset thumb(WidgetTester t, int n) =>
      t.getCenter(
        find.descendant(
          of: find.byType(PageOverview),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data == '$n' || w.data == '$n · Current'),
          ),
        ),
      ) -
      const Offset(0, 40);

  testWidgets('menu moves a page; undo is one step', (t) async {
    seed(_note(3));
    await open(t);
    await openOverview(t);
    await t.tap(find.byTooltip('Page menu').at(0));
    await settle(t);
    await t.tap(find.text('Move later'));
    await settle(t);
    expect(find.text('Page 1 moved to position 2'), findsOneWidget);
    expect(order(), [_b, _a, _c]);
    await t.tap(find.text('Undo'));
    await settle(t);
    expect(order(), [_a, _b, _c]);
    // The first page cannot go earlier.
    await t.tap(find.byTooltip('Page menu').at(0));
    await settle(t);
    final item = t.widget<PopupMenuItem<VoidCallback>>(
      find.widgetWithText(PopupMenuItem<VoidCallback>, 'Move to start'),
    );
    expect(item.enabled, isFalse);
  });

  testWidgets('long press and drag puts a page where it is dropped', (t) async {
    seed(_note(3));
    await open(t);
    await openOverview(t);
    final g = await t.startGesture(thumb(t, 1));
    await t.pump(const Duration(milliseconds: 700));
    await g.moveTo(thumb(t, 2));
    await t.pump();
    await g.moveTo(thumb(t, 3));
    await t.pump();
    await g.up();
    await settle(t);
    expect(order(), [_b, _c, _a]);
    expect(find.text('Page 1 moved to position 3'), findsOneWidget);
  });

  testWidgets('select mode: header, multi delete with undo, no delete of all', (
    t,
  ) async {
    seed(_note(3));
    await open(t);
    await openOverview(t);
    await t.tap(find.text('Select'));
    await settle(t);
    expect(find.text('0 selected'), findsOneWidget);
    await t.tapAt(thumb(t, 1));
    await t.tapAt(thumb(t, 3));
    await settle(t);
    expect(find.text('2 selected'), findsOneWidget);
    // Dragging a chosen page moves both, in their old relative order.
    final g = await t.startGesture(thumb(t, 3));
    await t.pump(const Duration(milliseconds: 700));
    await g.moveTo(thumb(t, 2));
    await t.pump();
    await g.up();
    await settle(t);
    expect(order(), [_a, _c, _b]);
    expect(find.text('2 pages moved'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await settle(t);
    expect(find.text('2 pages deleted'), findsOneWidget);
    expect(order().length, 1);
    await t.tap(find.text('Undo'));
    await settle(t);
    expect(order().length, 3);
    // Every page chosen: [삭제] is off.
    await t.tap(find.text('Select'));
    await settle(t);
    for (var n = 1; n <= 3; n++) {
      await t.tapAt(thumb(t, n));
    }
    await settle(t);
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, 'Delete')).onPressed,
      isNull,
    );
  });

  List<String> backgrounds() => [
    for (final p in decodeKkj(file.readAsBytesSync()).note!.pages)
      p['background'] as String,
  ];

  testWidgets('background: one page from the menu, two from the header', (
    t,
  ) async {
    seed(_note(3));
    await open(t);
    await openOverview(t);
    await t.tap(find.byTooltip('Page menu').at(1));
    await settle(t);
    await t.tap(find.text('Change background'));
    await settle(t);
    await t.tap(find.text('Grid'));
    await settle(t);
    expect(find.text('Page 2 background changed'), findsOneWidget);
    expect(backgrounds(), ['plain', 'grid', 'plain']);
    await t.tap(find.text('Select'));
    await settle(t);
    await t.tapAt(thumb(t, 1));
    await t.tapAt(thumb(t, 2));
    await settle(t);
    await t.tap(find.text('Background'));
    await settle(t);
    await t.tap(find.text('Dot'));
    await settle(t);
    expect(backgrounds(), ['dot', 'dot', 'plain']);
    await t.tap(find.text('Undo'));
    await settle(t);
    expect(backgrounds(), ['plain', 'grid', 'plain']); // one step
  });

  testWidgets('turning a page leaves elements; badge selects them', (t) async {
    final n = _note(2).copyJson();
    ((n['pages'] as List).first as Map)['elements'] = [
      {
        'id': _id(9001),
        'type': 'stroke',
        'tool': 'pen',
        'color': '#000000',
        'width': 2,
        'usePressure': false,
        'points': [
          [500, 700, 0.5, 0],
          [510, 710, 0.5, 10],
        ],
      },
    ];
    seed(Note.trusted(n));
    await open(t);
    await openOverview(t);
    await t.tap(find.byTooltip('Page menu').at(0));
    await settle(t);
    await t.tap(find.text('Make landscape'));
    await settle(t);
    expect(find.text('Page 1 is now landscape'), findsOneWidget);
    final page = decodeKkj(file.readAsBytesSync()).note!.pages.first;
    expect([page['width'], page['height']], [842, 595]);
    expect((page['elements'] as List).length, 1); // not moved, not removed
    // The badge on the thumbnail; the menu now offers the way back.
    expect(find.text('1 elements outside the page'), findsOneWidget);
    await t.tap(find.byTooltip('Page menu').at(0));
    await settle(t);
    expect(find.text('Make portrait'), findsOneWidget);
    await t.tapAt(const Offset(1, 1)); // closes the menu
    await settle(t);
    await t.tap(find.text('1 elements outside the page'));
    await settle(t);
    expect(find.byType(PageOverview), findsNothing);
    // The editor shows the frame text and the element is selected.
    expect(find.text('1 elements outside the page'), findsOneWidget);
    final sel = find
        .descendant(
          of: find.byType(NoteEditor),
          matching: find.byType(CustomPaint),
        )
        .evaluate()
        .map((e) => (e.widget as CustomPaint).painter)
        .whereType<SelectionPainter>();
    expect(sel.single.box, isNotNull);
  });

  test('TalkBack label in Korean', () {
    final l = AppLocalizationsKo();
    expect(
      '${l.pageSemantics(3, 5, l.pageLandscape)}, ${l.pageCurrent}',
      '3페이지 / 5, 가로, 현재',
    );
  });
}
