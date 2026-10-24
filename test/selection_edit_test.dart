import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/history.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/render/selection_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/model/element_clipboard.dart';
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

  Future<void> undo(WidgetTester t) async {
    await t.tap(find.byTooltip('Undo'));
    await t.pump();
  }

  ProviderContainer cont(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(NoteEditor)));
  History hist(WidgetTester t) => cont(t).read(noteHistoriesProvider)[_id(1)]!;
  List els(WidgetTester t) =>
      hist(t).note.copyJson()['pages'][0]['elements'] as List;

  testWidgets('width and color: one op and one undo step each', (t) async {
    await select(t);
    await t.tap(find.byTooltip('Thickness'));
    await t.pumpAndSettle();
    await t.drag(find.byType(Slider), const Offset(60, 0));
    await t.pumpAndSettle();
    expect(els(t).single['width'], isNot(2));
    expect(hist(t).undoDepth, 1);
    await t.tap(find.byTooltip('Color'));
    await t.pumpAndSettle();
    await t.tap(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(InkWell))
          .first,
    );
    await t.pumpAndSettle();
    expect(hist(t).undoDepth, 2);
    await undo(t);
    await undo(t);
    expect(els(t).single['width'], 2);
  });

  testWidgets('copy, blank tap, paste; undo removes the copy', (t) async {
    await select(t);
    await t.tap(find.byTooltip('Copy'));
    await t.pump();
    expect(cont(t).read(elementClipboardProvider), hasLength(1));
    expect(hist(t).undoDepth, 0);
    await drag(t, [(400, 150)]);
    expect(find.text('Select all'), findsOneWidget);
    await t.tap(find.text('Paste'));
    await t.pump();
    expect(els(t), hasLength(2));
    expect(els(t).last['id'], isNot(_id(9)));
    expect(box(t), isNotNull);
    await undo(t);
    expect(els(t), hasLength(1));
  });

  testWidgets('blank menu: paste off without clipboard; select all', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, [(400, 150)]);
    final paste = t.widget<TextButton>(
      find.widgetWithText(TextButton, 'Paste'),
    );
    expect(paste.onPressed, isNull);
    await t.tap(find.text('Select all'));
    await t.pump();
    expect(box(t), const Rect.fromLTRB(100, 100, 200, 160));
  });

  testWidgets('cut and delete undo; clipboard stays after cut undo', (t) async {
    await select(t);
    await t.tap(find.byTooltip('Cut'));
    await t.pump();
    expect(els(t), isEmpty);
    expect(cont(t).read(elementClipboardProvider), hasLength(1));
    await undo(t);
    expect(els(t), hasLength(1));
    expect(cont(t).read(elementClipboardProvider), hasLength(1));
    await drag(t, around);
    await t.tap(find.byTooltip('Delete'));
    await t.pump();
    expect(els(t), isEmpty);
    await undo(t);
    expect(els(t).single['id'], _id(9));
  });

  testWidgets('read only page: copy only', (t) async {
    await select(t);
    hist(t).lockPages({_id(1001)});
    t.view.physicalSize = const Size(800, 900);
    addTearDown(t.view.resetPhysicalSize);
    await t.pump();
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Cut'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.byTooltip('Thickness'), findsNothing);
  });
}
