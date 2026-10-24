import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/select.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/render/selection_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/ui/note_editor.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

// One stroke across the page's upper left.
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
      [150, 100, 0.5, 10],
      [200, 100, 0.5, 20],
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
    (230, 140),
    (80, 140),
    (80, 62),
  ];

  testWidgets('lasso button semantics, 48 dp, selected state', (t) async {
    final h = t.ensureSemantics();
    await open(t);
    final b = find.byTooltip('Lasso');
    expect(b, findsOneWidget);
    expect(t.getSize(find.byTooltip('Lasso')).height, greaterThanOrEqualTo(48));
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    expect(
      t.getSemantics(b).getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    h.dispose();
  });

  testWidgets('lasso around the stroke selects it; blank tap clears', (
    t,
  ) async {
    await open(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, around);
    expect(box(t), const Rect.fromLTRB(100, 100, 200, 100));
    await drag(t, [(400, 250)]);
    expect(box(t), isNull);
  });

  testWidgets('tap selects one element; switching tool clears', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, [(150, 102)]);
    expect(box(t), isNotNull);
    await t.tap(find.bySemanticsLabel(RegExp('^Pen')));
    await t.pump();
    expect(box(t), isNull);
  });

  testWidgets('pen tool: tap does not select; lasso is not drawn', (t) async {
    await open(t);
    await drag(t, [(150, 102)]);
    expect(box(t), isNull);
  });

  // Finger 1 lands at [first], finger 2 far from it; they move apart. The
  // scale after the move.
  Future<double> pinchAfter(WidgetTester t, Offset first) async {
    final a = ++id, b = ++id;
    final second = at(t, 400, 300);
    t.binding.handlePointerEvent(
      PointerDownEvent(pointer: a, position: first, timeStamp: Duration.zero),
    );
    await t.pump();
    t.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: b,
        position: second,
        timeStamp: const Duration(milliseconds: 500),
      ),
    );
    await t.pump();
    t.binding.handlePointerEvent(
      PointerMoveEvent(
        pointer: b,
        position: second + const Offset(120, 120),
        timeStamp: const Duration(milliseconds: 600),
      ),
    );
    await t.pump();
    final scale = vp(t).scale;
    for (final p in [a, b]) {
      t.binding.handlePointerEvent(PointerUpEvent(pointer: p));
      await t.pump();
    }
    return scale;
  }

  testWidgets('pen-only finger on the box is consumed, not a pinch', (t) async {
    await open(t);
    final s0 = vp(t).scale;
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, around); // a stylus: pen-only from now on
    expect(box(t), isNotNull);
    // Off the box a second finger pinches (control) ...
    expect(await pinchAfter(t, at(t, 400, 150)), isNot(s0));
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, around);
    final s1 = vp(t).scale;
    // ... on the box the touch is a selection gesture: no pinch, no change.
    expect(await pinchAfter(t, at(t, 150, 100)), s1);
    expect(box(t), isNotNull);
  });

  testWidgets('undo of the selected stroke prunes the selection', (t) async {
    await open(t);
    await drag(t, [(100, 300), (150, 300), (200, 300)]); // pen tool: a stroke
    await settle(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, [(150, 300)]);
    expect(box(t), isNotNull);
    await t.tap(find.byTooltip('Undo'));
    await t.pump();
    expect(box(t), isNull);
  });

  testWidgets('a tap in the margin clears the selection', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, around);
    expect(box(t), isNotNull);
    final top = at(t, 300, 0) - const Offset(0, 6); // above the page
    const kind = PointerDeviceKind.stylus;
    t.binding.handlePointerEvent(
      PointerDownEvent(pointer: ++id, kind: kind, position: top),
    );
    await t.pump();
    t.binding.handlePointerEvent(
      PointerUpEvent(pointer: id, kind: kind, position: top),
    );
    await t.pump();
    expect(box(t), isNull);
  });

  test('selectionBounds: rotated box, empty stroke and invalid elements', () {
    final els = <Map<String, dynamic>>[
      {
        'id': 'a',
        'type': 'text',
        'x': 0,
        'y': 0,
        'width': 100,
        'height': 50,
        'rotation': 90,
      },
      {'id': 'b', 'type': 'stroke', 'points': []},
      {'id': 'c', 'type': 'text'},
    ];
    final r = selectionBounds(els)!;
    expect(r.left, closeTo(25, 1e-9));
    expect(r.top, closeTo(-25, 1e-9));
    expect(r.right, closeTo(75, 1e-9));
    expect(r.bottom, closeTo(75, 1e-9));
    expect(selectLasso(els, [(-100, -100), (200, -100), (200, 200)]), ['a']);
    expect(selectTap(els, (50, 25)), 'a');
    expect(selectionBounds([els[1], els[2]]), isNull);
  });
}
