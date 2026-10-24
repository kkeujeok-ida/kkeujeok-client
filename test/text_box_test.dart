import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/text_metrics.dart';
import 'package:kkeujeok/ops/history.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

// One text box "hello": x 100..300, y 100..122.4.
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
    'type': 'text',
    'x': 100,
    'y': 100,
    'width': 200,
    'rotation': 0,
    'text': 'hello',
    'runs': [],
    'size': 16,
    'color': '#000000',
    'bold': false,
    'italic': false,
  });
  return Note.parse(j).note!;
}

void main() {
  late Directory docs;
  late NoteData data;

  setUpAll(() {
    TextMetrics.install(
      File('assets/fonts/Pretendard-Regular.otf').readAsBytesSync(),
      File('assets/fonts/Pretendard-SemiBold.otf').readAsBytesSync(),
    );
  });

  setUp(() {
    resetStylusSeen();
    docs = Directory.systemTemp.createTempSync('kkj-text-');
    data = NoteData(() async => docs);
    File('${docs.path}/$noteDataDirName/${_id(1)}/working.kkj')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(encodeKkj(_note()));
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

  var ptr = 500;
  var clock = 0;
  // A tap (or a drag through [pts]) with the stylus, in page pt.
  Future<void> drag(WidgetTester t, List<(double, double)> pts) async {
    final p = ++ptr;
    for (var i = 0; i < pts.length; i++) {
      final pos = at(t, pts[i].$1, pts[i].$2);
      final ms = Duration(milliseconds: clock);
      clock += 10;
      t.binding.handlePointerEvent(
        i == 0
            ? PointerDownEvent(
                pointer: p,
                kind: PointerDeviceKind.stylus,
                position: pos,
                timeStamp: ms,
              )
            : PointerMoveEvent(
                pointer: p,
                kind: PointerDeviceKind.stylus,
                position: pos,
                timeStamp: ms,
              ),
      );
      await t.pump();
    }
    t.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: p,
        kind: PointerDeviceKind.stylus,
        position: at(t, pts.last.$1, pts.last.$2),
        timeStamp: Duration(milliseconds: clock),
      ),
    );
    clock += 10;
    await t.pump();
  }

  ProviderContainer cont(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(NoteEditor)));
  History hist(WidgetTester t) => cont(t).read(noteHistoriesProvider)[_id(1)]!;
  List els(WidgetTester t) =>
      hist(t).note.copyJson()['pages'][0]['elements'] as List;

  List<Map> texts(WidgetTester t) => [
    for (final e in els(t))
      if ((e as Map)['type'] == 'text') e,
  ];

  Future<void> textTool(WidgetTester t) async {
    await t.tap(find.byTooltip('Text'));
    await t.pump();
  }

  testWidgets('text tool: tap makes a half page box; confirm saves one op', (
    t,
  ) async {
    await open(t);
    await textTool(t);
    await drag(t, [(50, 250)]);
    expect(find.byType(TextField), findsOneWidget);
    await t.enterText(find.byType(TextField), 'new text');
    await drag(t, [(500, 150)]); // outside: confirms only
    expect(find.byType(TextField), findsNothing);
    expect(els(t), hasLength(2));
    final box = els(t).last as Map;
    expect(box['text'], 'new text');
    expect(box['width'], 297.5);
    expect([box['x'], box['y']], [50, 250]);
    expect(hist(t).undoDepth, 1);
    // The next tap makes a new box.
    await drag(t, [(300, 350)]);
    expect(find.byType(TextField), findsOneWidget);
    await t.tap(find.byTooltip('Undo'));
    await t.pump();
    expect(els(t), hasLength(1));
  });

  testWidgets('blank content leaves no box and no undo step', (t) async {
    await open(t);
    await textTool(t);
    await drag(t, [(50, 250)]);
    await t.enterText(find.byType(TextField), '  ');
    await t.tap(find.byTooltip('Lasso')); // another tool confirms
    await t.pump();
    expect(find.byType(TextField), findsNothing);
    expect(els(t), hasLength(1));
    expect(hist(t).undoDepth, 0);
  });

  testWidgets('format bar: order, names, bold goes to what is typed', (
    t,
  ) async {
    await open(t);
    await textTool(t);
    await drag(t, [(50, 250)]);
    final names = ['Font size 16', 'Text color', 'Bold, off', 'Italic, off'];
    final xs = [
      for (final n in names) t.getTopLeft(find.bySemanticsLabel(n)).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    for (final x in xs) {
      expect(x, isNot(xs.first - 1)); // distinct slots
    }
    expect(t.getSize(find.bySemanticsLabel('Bold, off')).height, 48);
    await t.tap(find.bySemanticsLabel('Bold, off'));
    await t.pump();
    expect(find.bySemanticsLabel('Bold, on'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'ab');
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    final box = els(t).last as Map;
    expect(box['runs'], [
      {'start': 0, 'end': 2, 'bold': true},
    ]);
  });

  testWidgets('double tap edits a box: one editText', (t) async {
    await open(t);
    await drag(t, [(150, 110)]);
    await drag(t, [(150, 110)]);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'hello world');
    await drag(t, [(500, 150)]);
    expect(texts(t).single['text'], 'hello world');
    expect(hist(t).undoDepth, greaterThanOrEqualTo(1));
    final depth = hist(t).undoDepth;
    // An unchanged edit saves nothing (lasso: its first tap draws no dot).
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, [(150, 110)]);
    await drag(t, [(150, 110)]);
    await drag(t, [(500, 150)]);
    expect(hist(t).undoDepth, depth);
  });

  testWidgets('side handle drag: setTextBoxWidth', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, [(90, 90), (310, 90), (310, 135), (90, 135), (90, 92)]);
    final before = hist(t).undoDepth;
    await drag(t, [(300, 111), (320, 111), (340, 111)]); // right handle
    expect((els(t).last as Map)['width'], greaterThan(200));
    expect(hist(t).undoDepth, before + 1);
    final w = (els(t).last as Map)['width'] as num;
    await t.tap(find.byTooltip('Undo'));
    await t.pump();
    expect((els(t).last as Map)['width'], 200);
    expect(w, isNot(200));
  });

  testWidgets('a corner press on a one-line box moves it, not a width drag', (
    t,
  ) async {
    await open(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, [(90, 90), (310, 90), (310, 135), (90, 135), (90, 92)]);
    await drag(t, [(300, 100), (310, 100), (320, 100)]); // top-right corner
    // A one-line box is small: its corner moves it, it never widens it.
    final box = texts(t).single;
    expect(box['width'], 200);
    expect(box['x'], isNot(100));
  });

  testWidgets('read only page: the text tool does nothing', (t) async {
    await open(t);
    hist(t).lockPages({_id(1001)});
    await textTool(t);
    await drag(t, [(50, 250)]);
    expect(find.byType(TextField), findsNothing);
    expect(els(t), hasLength(1));
  });

  testWidgets('keyboard open hides the toolbar', (t) async {
    await open(t);
    await textTool(t);
    await drag(t, [(50, 250)]);
    expect(find.byTooltip('Lasso'), findsOneWidget);
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(t.view.resetViewInsets);
    await t.pump();
    expect(find.byTooltip('Lasso'), findsNothing);
  });
}
