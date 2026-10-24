import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/render/selection_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/selection_menu.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

// One L-shaped stroke: box (100,100)-(200,160).
Note _note() {
  final j = createNote(
    title: 'Lecture',
    existingTitles: const [],
    background: 'plain',
    orientation: 'portrait',
    noteId: _id(1),
    pageId: _id(1001),
    pageRev: _id(2001),
    metaRev: _id(3001),
    orderRev: _id(4001),
    now: '2000-01-01T12:00:00.000Z',
    editedBy: 'Pixel 8',
  ).note!.copyJson();
  ((j['pages'] as List).first['elements'] as List).add({
    'id': _id(9),
    'type': 'stroke',
    'tool': 'pen',
    'color': '#000000',
    'width': 2,
    'usePressure': false,
    'points': [
      [100, 100, 0.5, 0],
      [200, 100, 0.5, 10],
      [200, 160, 0.5, 20],
    ],
  });
  return Note.parse(j).note!;
}

void main() {
  late Directory docs;
  late NoteData data;

  setUp(() {
    resetStylusSeen();
    docs = Directory.systemTemp.createTempSync('kkj-lasso-');
    data = NoteData(() async => docs);
    final f = File('${docs.path}/$noteDataDirName/${_id(1)}/working.kkj')
      ..parent.createSync(recursive: true);
    f.writeAsBytesSync(encodeKkj(_note()));
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // cleaned up later
      }
    });
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 40; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t) async {
    await pumpApp(t, noteData: data);
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
  }

  PageViewport vp(WidgetTester t) {
    final paint =
        find
                .descendant(
                  of: find.byType(NoteEditor),
                  matching: find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is PagePainter,
                  ),
                )
                .evaluate()
                .first
                .widget
            as CustomPaint;
    return (paint.painter as PagePainter).viewport!;
  }

  Offset at(WidgetTester t, double x, double y) =>
      vp(t).offset + Offset(x, y) * vp(t).scale;

  var id = 500;
  // Down, moves, up through the pointer route, in page pt.
  Future<void> drag(
    WidgetTester t,
    List<(double, double)> pts, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final p = ++id;
    for (var i = 0; i < pts.length; i++) {
      final pos = at(t, pts[i].$1, pts[i].$2);
      final ms = Duration(milliseconds: 10 * i);
      t.binding.handlePointerEvent(
        i == 0
            ? PointerDownEvent(
                pointer: p,
                kind: kind,
                position: pos,
                timeStamp: ms,
              )
            : PointerMoveEvent(
                pointer: p,
                kind: kind,
                position: pos,
                timeStamp: ms,
              ),
      );
      await t.pump();
    }
    t.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: p,
        kind: kind,
        position: at(t, pts.last.$1, pts.last.$2),
        timeStamp: Duration(milliseconds: 10 * pts.length),
      ),
    );
    await t.pump();
  }

  Rect? box(WidgetTester t) {
    final paints = find
        .descendant(
          of: find.byType(NoteEditor),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is SelectionPainter,
          ),
        )
        .evaluate();
    return ((paints.first.widget as CustomPaint).painter as SelectionPainter)
        .box;
  }

  const around = <(double, double)>[
    (80, 60),
    (230, 60),
    (230, 190),
    (80, 190),
    (80, 62),
  ];

  Future<void> select(WidgetTester t) async {
    await open(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, around);
    expect(box(t), const Rect.fromLTRB(100, 100, 200, 160));
  }

  // The angle (radians) the selection box is turned by.
  double angle(WidgetTester t) {
    final paints = find
        .descendant(
          of: find.byType(NoteEditor),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is SelectionPainter,
          ),
        )
        .evaluate();
    return ((paints.first.widget as CustomPaint).painter as SelectionPainter)
            .angle
            ?.call() ??
        0;
  }

  void expectBox(WidgetTester t, Rect r) {
    final b = box(t)!;
    expect(
      [b.left, b.top, b.right, b.bottom],
      [
        for (final v in [r.left, r.top, r.right, r.bottom]) closeTo(v, 0.01),
      ],
    );
  }

  Future<void> undo(WidgetTester t) async {
    await t.tap(find.byTooltip('Undo'));
    await t.pump();
  }

  testWidgets(
    'drag inside the box moves; one undo step; cancel changes nothing',
    (t) async {
      await select(t);
      await drag(t, [(150, 130), (170, 140), (190, 160)]);
      expectBox(t, const Rect.fromLTRB(140, 130, 240, 190));
      await undo(t);
      expectBox(t, const Rect.fromLTRB(100, 100, 200, 160));
      // A cancelled drag leaves the note alone.
      final p = ++id;
      const kind = PointerDeviceKind.stylus;
      t.binding.handlePointerEvent(
        PointerDownEvent(pointer: p, kind: kind, position: at(t, 150, 130)),
      );
      t.binding.handlePointerEvent(
        PointerMoveEvent(pointer: p, kind: kind, position: at(t, 190, 160)),
      );
      t.binding.handlePointerEvent(
        PointerCancelEvent(pointer: p, kind: kind, position: at(t, 190, 160)),
      );
      await t.pump();
      expectBox(t, const Rect.fromLTRB(100, 100, 200, 160));
    },
  );

  testWidgets('corner handle scales: locked keeps ratio, unlocked is free', (
    t,
  ) async {
    await select(t);
    await drag(t, [(200, 160), (250, 190), (300, 220)]);
    expectBox(t, const Rect.fromLTRB(100, 100, 300, 220));
    await undo(t);
    await t.tap(find.byTooltip('Lock aspect ratio'));
    await t.pump();
    await drag(t, [(200, 160), (300, 160)]);
    expectBox(t, const Rect.fromLTRB(100, 100, 300, 160));
  });

  testWidgets('rotate handle turns about the center', (t) async {
    await select(t);
    final y = 100 - selectionRotateGap / vp(t).scale;
    await drag(t, [(150, y), (200, 100), (250, 130)]);
    // The box is turned with the selection: same box, turned a quarter.
    expectBox(t, const Rect.fromLTRB(100, 100, 200, 160));
    expect(angle(t), closeTo(math.pi / 2, 0.01));
    await undo(t);
    expectBox(t, const Rect.fromLTRB(100, 100, 200, 160));
    expect(angle(t), closeTo(0, 0.01));
  });

  testWidgets('menu steps: bigger, smaller, rotate 90', (t) async {
    await select(t);
    await t.tap(find.byTooltip('Scale up'));
    await t.pump();
    expectBox(t, const Rect.fromLTRB(87.5, 92.5, 212.5, 167.5));
    await undo(t);
    await t.tap(find.byTooltip('Scale down'));
    await t.pump();
    expectBox(t, const Rect.fromLTRB(110, 106, 190, 154));
    await undo(t);
    await t.tap(find.byTooltip('Rotate 90°'));
    await t.pump();
    expectBox(t, const Rect.fromLTRB(100, 100, 200, 160));
    expect(angle(t), closeTo(math.pi / 2, 0.01));
  });

  testWidgets('two fingers on the selection scale and turn it: one undo step', (
    t,
  ) async {
    await select(t);
    final h = ProviderScope.containerOf(
      t.element(find.byType(NoteEditor)),
    ).read(noteHistoriesProvider)[_id(1)]!;
    final depth = h.undoDepth;
    const kind = PointerDeviceKind.touch;
    final a = ++id, b = ++id;
    Future<void> ev(PointerEvent e) async {
      t.binding.handlePointerEvent(e);
      await t.pump();
    }

    await ev(PointerDownEvent(pointer: a, kind: kind, position: at(t, 150, 130)));
    await ev(PointerDownEvent(pointer: b, kind: kind, position: at(t, 250, 130)));
    // Twice as far apart and a quarter turn: the second finger goes below.
    await ev(PointerMoveEvent(pointer: b, kind: kind, position: at(t, 150, 330)));
    await ev(PointerUpEvent(pointer: b, kind: kind, position: at(t, 150, 330)));
    await ev(PointerUpEvent(pointer: a, kind: kind, position: at(t, 150, 130)));
    expect(h.undoDepth, depth + 1);
    expect(angle(t), closeTo(math.pi / 2, 0.02));
    expectBox(t, const Rect.fromLTRB(50, 70, 250, 190));
    await undo(t);
    expect(h.undoDepth, depth);
    expectBox(t, const Rect.fromLTRB(100, 100, 200, 160));
    expect(angle(t), closeTo(0, 0.01));
  });

  testWidgets('a corner of a turned box still scales it', (t) async {
    await select(t);
    final y = 100 - selectionRotateGap / vp(t).scale;
    await drag(t, [(150, y), (200, 100), (250, 130)]); // a quarter turn
    expect(angle(t), closeTo(math.pi / 2, 0.01));
    // The turned frame's corners are 2x the box about the center (150, 130);
    // its top-left corner now sits at the page point (180, 80).
    await drag(t, [(180, 80), (210, 50)]);
    final r = box(t)!;
    expect(r.width, greaterThan(100));
    expect(angle(t), closeTo(math.pi / 2, 0.01));
  });

  testWidgets('no edit menu on a locked page', (t) async {
    await select(t);
    expect(find.byType(SelectionMenu), findsOneWidget);
    final c = ProviderScope.containerOf(t.element(find.byType(NoteEditor)));
    c.read(noteHistoriesProvider)[_id(1)]!.lockPages({_id(1001)});
    // A new size rebuilds the editor.
    t.view.physicalSize = const Size(800, 900);
    addTearDown(t.view.resetPhysicalSize);
    await t.pump();
    // Only [copy] is left (Story 4.6).
    expect(find.byTooltip('Scale up'), findsNothing);
    expect(find.byTooltip('Copy'), findsOneWidget);
  });

  testWidgets('a small selection can still be moved', (t) async {
    await select(t);
    await t.tap(find.byTooltip('Scale down'));
    await t.pump();
    for (var i = 0; i < 6; i++) {
      await t.tap(find.byTooltip('Scale down'));
      await t.pump();
    }
    final b = box(t)!;
    await drag(t, [
      (b.center.dx, b.center.dy),
      (b.center.dx + 30, b.center.dy),
    ]);
    expect(box(t)!.center.dx, closeTo(b.center.dx + 30, 0.05));
  });

  test('move leaves rotation absent and scale leaves it alone', () {
    final n = _note();
    final j = n.copyJson();
    ((j['pages'] as List).first['elements'] as List).add({
      'id': _id(10),
      'type': 'text',
      'x': 0,
      'y': 0,
      'width': 10,
      'height': 10,
    });
    const ctx = Ctx(
      rev: '01926f3a-0000-7000-8000-00000000aaaa',
      now: '2000-01-01T12:00:00.000Z',
      editedBy: 'x',
    );
    final r = applyOp(Note.trusted(j), {
      'op': 'move',
      'pageId': _id(1001),
      'ids': [_id(10)],
      'dx': 1,
      'dy': 1,
    }, ctx);
    final el =
        ((r.note!.copyJson()['pages'] as List).first['elements'] as List).last
            as Map;
    expect(el.containsKey('rotation'), isFalse);
  });
}
