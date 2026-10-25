// Story 5.11: page view modes (vertical, horizontal, two pages).
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/model/page_view_mode.dart';

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

  Note onDisk() => decodeKkj(file.readAsBytesSync()).note!;

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

  Offset onPage(WidgetTester t, int i, double x, double y) {
    final vp = painters()[i].viewport!;
    return vp.offset + Offset(x, y) * vp.scale;
  }

  Future<void> scroll(WidgetTester t, double dy) async {
    final p = TestPointer(7, PointerDeviceKind.mouse);
    await t.sendEventToBinding(p.hover(const Offset(450, 400)));
    await t.sendEventToBinding(p.scroll(Offset(0, dy)));
    await t.pump();
  }

  Future<void> stroke(
    WidgetTester t,
    int page, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final g = await t.startGesture(onPage(t, page, 100, 100), kind: kind);
    await g.moveTo(onPage(t, page, 200, 160));
    await g.up();
    await t.pump(const Duration(milliseconds: 50));
  }

  Future<void> pick(WidgetTester t, String label) async {
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }

  Rect screenRect(WidgetTester t, int i) {
    final vp = painters()[i].viewport!;
    final pg = (painters()[i].page);
    return vp.offset &
        Size((pg['width'] as num) * vp.scale, (pg['height'] as num) * vp.scale);
  }

  testWidgets('menu has three modes, vertical selected by default', (t) async {
    seed(_note(3));
    await open(t);
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(find.text('Vertical scroll'), findsOneWidget);
    expect(find.text('Horizontal scroll'), findsOneWidget);
    expect(find.text('Two pages'), findsOneWidget);
    final r = t.widget<RadioMenuButton<PageViewMode>>(
      find.widgetWithText(RadioMenuButton<PageViewMode>, 'Vertical scroll'),
    );
    expect(r.groupValue, PageViewMode.vertical);
  });

  testWidgets('horizontal: one row fitted to the height, stroke on page 2', (
    t,
  ) async {
    seed(_note(3));
    await open(t);
    await pick(t, 'Horizontal scroll');
    final r0 = screenRect(t, 0), r1 = screenRect(t, 1);
    expect(r1.left, greaterThan(r0.right));
    expect(r1.top, closeTo(r0.top, 0.01));
    expect(r0.height, lessThanOrEqualTo(700));
    await stroke(t, 1);
    await settle(t);
    final pages = onDisk().pages;
    expect((pages[0]['elements'] as List), isEmpty);
    final pt = ((pages[1]['elements'] as List).single['points'] as List).first;
    expect(pt[0], closeTo(100, 0.5));
    expect(pt[1], closeTo(100, 0.5));
  });

  testWidgets('two pages: (1,2)(3) with a 4 spine gap', (t) async {
    seed(_note(3));
    await open(t);
    await pick(t, 'Two pages');
    final s = painters()[0].viewport!.scale;
    final a = screenRect(t, 0), b = screenRect(t, 1), c = screenRect(t, 2);
    expect(b.left - a.right, closeTo(4 * s, 0.01));
    expect(c.left - b.right, closeTo(24 * s, 0.01));
  });

  testWidgets('the page being looked at stays on a mode change', (t) async {
    seed(_note(3));
    await open(t);
    await scroll(t, 1500); // page 2 is on screen
    await pick(t, 'Horizontal scroll');
    final screen = Offset.zero & const Size(900, 700);
    expect(screen.overlaps(screenRect(t, 1)), isTrue);
  });

  testWidgets('rotation keeps the page in view', (t) async {
    seed(_note(3));
    await open(t);
    await pick(t, 'Horizontal scroll');
    await scroll(t, 400);
    final before = painters().length;
    expect(before, 3);
    t.view.physicalSize = const Size(700, 900);
    await t.pumpAndSettle();
    expect(
      (Offset.zero & const Size(700, 900)).overlaps(screenRect(t, 0)),
      isTrue,
    );
  });

  testWidgets('phone: no Two pages; stored twoPage shows vertical', (t) async {
    seed(_note(3));
    await pumpApp(
      t,
      width: 500,
      prefs: {'pageViewMode': 'twoPage'},
      noteData: data,
      noteStore: store,
    );
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
    expect(screenRect(t, 1).top, greaterThan(screenRect(t, 0).bottom));
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(find.text('Two pages'), findsNothing);
    expect(find.text('Horizontal scroll'), findsOneWidget);
  });

  testWidgets('the mode is restored from the same prefs', (t) async {
    seed(_note(3));
    await pumpApp(
      t,
      prefs: {'pageViewMode': 'horizontal'},
      noteData: data,
      noteStore: store,
    );
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
    expect(screenRect(t, 1).left, greaterThan(screenRect(t, 0).right));
  });

  testWidgets('horizontal: a lone landscape page fits the width too', (
    t,
  ) async {
    final n = _note(1).copyJson();
    final pg = (n['pages'] as List).single as Map<String, dynamic>;
    final w = pg['width'], h = pg['height'];
    pg['width'] = h;
    pg['height'] = w;
    seed(Note.trusted(n));
    await open(t);
    await pick(t, 'Horizontal scroll');
    final r = screenRect(t, 0);
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(900));
    expect(r.center.dx, closeTo(450, 1));
  });

  testWidgets('two pages: the anchor centers its pair, not the page', (
    t,
  ) async {
    seed(_note(3));
    await open(t);
    await scroll(t, 1500); // page 2 (right half of the pair) is on screen
    await pick(t, 'Two pages');
    final screen = Offset.zero & const Size(900, 700);
    expect(screen.contains(screenRect(t, 0).topLeft), isTrue);
    expect(screen.contains(screenRect(t, 1).bottomRight), isTrue);
  });
}
