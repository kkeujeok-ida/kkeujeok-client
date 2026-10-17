// Story 3.21: a note of several pages shows them all, one under the other.
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
import 'package:kkeujeok/ui/pen_toolbar.dart';

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

  testWidgets('a one-page note is one painter, as before', (t) async {
    seed(_note(1));
    await open(t);
    expect(painters(), hasLength(1));
    final vp = painters().single.viewport!;
    expect(vp.offset.dy, greaterThan(0));
    await stroke(t, 0);
    await settle(t);
    expect(onDisk().pages.single['elements'], hasLength(1));
  });

  testWidgets('every page is shown, each named "N / M"', (t) async {
    final h = t.ensureSemantics();
    seed(_note(3));
    await open(t);
    expect(painters(), hasLength(3));
    for (var i = 1; i <= 3; i++) {
      expect(
        find.bySemanticsLabel('Page $i of 3, Portrait'),
        findsOneWidget,
        reason: 'page $i',
      );
    }
    // One under the other, in order, with a gap.
    final top = [for (final p in painters()) p.viewport!.offset.dy];
    expect(top[0], lessThan(top[1]));
    expect(top[1], lessThan(top[2]));
    h.dispose();
  });

  testWidgets('ko labels', (t) async {
    final h = t.ensureSemantics();
    seed(_note(2));
    await pumpApp(
      t,
      noteData: data,
      noteStore: store,
      device: const [Locale('ko', 'KR')],
    );
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
    expect(find.bySemanticsLabel('1페이지 / 2, 세로'), findsOneWidget);
    expect(find.bySemanticsLabel('2페이지 / 2, 세로'), findsOneWidget);
    h.dispose();
  });

  testWidgets('scrolling brings page 2 up; the stroke lands on it in its own '
      'coordinates', (t) async {
    seed(_note(2));
    await open(t);
    final before = painters()[1].viewport!.offset.dy;
    expect(before, greaterThan(700)); // below the screen
    await scroll(t, 900);
    final after = painters()[1].viewport!.offset.dy;
    expect(after, lessThan(before));
    expect(after, lessThan(500));

    await stroke(t, 1);
    await settle(t);
    final pages = onDisk().pages;
    expect(pages[0]['elements'], isEmpty);
    final els = pages[1]['elements'] as List;
    expect(els, hasLength(1));
    final first = (els.single['points'] as List).first as List;
    expect(first[0], closeTo(100, 1.5));
    expect(first[1], closeTo(100, 1.5));
  });

  testWidgets('a stroke on page 1 stays on page 1', (t) async {
    seed(_note(2));
    await open(t);
    await stroke(t, 0);
    await settle(t);
    final pages = onDisk().pages;
    expect(pages[0]['elements'], hasLength(1));
    expect(pages[1]['elements'], isEmpty);
  });

  testWidgets('a stroke between two pages is not drawn', (t) async {
    seed(_note(2));
    await open(t);
    await scroll(t, 400);
    final vp0 = painters()[0].viewport!;
    final vp1 = painters()[1].viewport!;
    final gap = Offset(
      (vp0.offset.dx + 100),
      (vp0.offset.dy + 842 * vp0.scale + vp1.offset.dy) / 2,
    );
    final g = await t.startGesture(gap, kind: PointerDeviceKind.stylus);
    await g.moveBy(const Offset(20, 5));
    await g.up();
    await settle(t);
    expect(onDisk().pages[0]['elements'], isEmpty);
    expect(onDisk().pages[1]['elements'], isEmpty);
  });

  testWidgets('undo takes back the stroke of the page it was drawn on', (
    t,
  ) async {
    seed(_note(2));
    await open(t);
    await stroke(t, 0);
    await scroll(t, 900);
    await stroke(t, 1);
    await settle(t);
    expect(onDisk().pages[0]['elements'], hasLength(1));
    expect(onDisk().pages[1]['elements'], hasLength(1));
    t.widget<PenToolbar>(find.byType(PenToolbar)).onUndo!();
    await settle(t);
    expect(onDisk().pages[1]['elements'], isEmpty);
    expect(onDisk().pages[0]['elements'], hasLength(1));
  });

  testWidgets('a conflict locks its page only; the others edit', (t) async {
    final h = t.ensureSemantics();
    seed(_note(2));
    await t.runAsync(() => store.updateSync(_id(1), (s) => s));
    await t.runAsync(
      () => store.updateSync(
        _id(1),
        (s) => s.copyWith(
          conflicts: [
            {
              'pageId': _a,
              'kind': 'bothEdited',
              'rev': _id(1),
              'theirsRev': _id(2),
              'detectedAt': '2026-10-17T00:00:00.000Z',
              'originalIndex': 0,
              'resolvedAt': null,
            },
          ],
        ),
      ),
    );
    await open(t);
    await stroke(t, 0);
    await settle(t);
    expect(onDisk().pages[0]['elements'], isEmpty);
    await scroll(t, 900);
    await stroke(t, 1);
    await settle(t);
    expect(onDisk().pages[1]['elements'], hasLength(1));
    // Only the locked page says so.
    expect(
      find.semantics.byValue(RegExp('Read-only, page edited on both devices')),
      findsOneWidget,
    );
    h.dispose();
  });

  testWidgets('a finger that is not drawing scrolls the note', (t) async {
    seed(_note(2));
    await open(t);
    // A stylus was seen: fingers only move the view.
    final pen = TestPointer(3, PointerDeviceKind.stylus);
    await t.sendEventToBinding(pen.hover(const Offset(10, 10)));
    final before = painters()[1].viewport!.offset.dy;
    await t.dragFrom(const Offset(450, 500), const Offset(0, -300));
    await t.pump();
    expect(painters()[1].viewport!.offset.dy, lessThan(before));
    expect(onDisk().pages[0]['elements'], isEmpty);
  });

  testWidgets('fit page fits the page on screen', (t) async {
    seed(_note(2));
    await open(t);
    await scroll(t, 1500); // page 2 is the one in the middle now
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Fit page'));
    await t.pumpAndSettle();
    final v1 = painters()[1].viewport!;
    // Page 2 is the one that is whole on screen now.
    expect(v1.offset.dy, greaterThanOrEqualTo(0));
    expect(v1.offset.dy + 842 * v1.scale, lessThanOrEqualTo(700.5));
  });

  group('paints', () {
    const white = Color(0xFFFFFFFF);
    Finder page(int i) => find
        .descendant(
          of: find.byType(NoteEditor),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is PagePainter,
          ),
        )
        .at(i);

    testWidgets('on screen it paints its paper; off screen it paints nothing', (
      t,
    ) async {
      seed(_note(3));
      await open(t);
      expect(
        t.renderObject(page(0)),
        paints
          ..clipRect()
          ..rect(color: white),
      );
      expect(t.renderObject(page(1)), paintsNothing);
      expect(t.renderObject(page(2)), paintsNothing);

      await scroll(t, 1500);
      expect(t.renderObject(page(0)), paintsNothing);
      expect(
        t.renderObject(page(1)),
        paints
          ..clipRect()
          ..rect(color: white),
      );
      expect(t.renderObject(page(2)), paintsNothing);
    });

    testWidgets('a page that is only partly in view still paints', (t) async {
      seed(_note(3));
      await open(t);
      final vp = painters()[0].viewport!;
      // Page 1's bottom edge 10 px inside the screen.
      await scroll(t, vp.offset.dy + 842 * vp.scale - 10);
      final bottom = painters()[0].viewport!.offset.dy + 842 * vp.scale;
      expect(bottom, closeTo(10, 0.5));
      expect(
        t.renderObject(page(0)),
        paints
          ..clipRect()
          ..rect(color: white),
      );
      // And page 2's top edge is below the screen: nothing.
      expect(t.renderObject(page(2)), paintsNothing);
      // Just past the edge it is gone.
      await scroll(t, 20);
      expect(t.renderObject(page(0)), paintsNothing);
    });
  });
}
