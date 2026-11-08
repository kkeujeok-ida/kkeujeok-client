import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/shape.dart';
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

Note _note(Map<String, dynamic> stroke) {
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
    ...stroke,
  });
  return Note.parse(j).note!;
}

void main() {
  late Directory docs;
  late NoteData data;

  void seed(Map<String, dynamic> stroke) =>
      File('${docs.path}/$noteDataDirName/${_id(1)}/working.kkj')
          .writeAsBytesSync(encodeKkj(_note(stroke)));

  setUp(() {
    resetStylusSeen();
    docs = Directory.systemTemp.createTempSync('kkj-shape-edit-');
    data = NoteData(() async => docs);
    File('${docs.path}/$noteDataDirName/${_id(1)}/working.kkj').parent
        .createSync(recursive: true);
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

  Future<void> select(WidgetTester t, Map<String, dynamic> stroke) async {
    seed(stroke);
    await open(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, [(80, 60), (330, 60), (330, 240), (80, 240), (80, 62)]);
  }

  void expectBox(WidgetTester t, double l, double tp, double r, double b) {
    final x = box(t)!;
    expect(
      [x.left, x.top, x.right, x.bottom],
      [closeTo(l, 0.05), closeTo(tp, 0.05), closeTo(r, 0.05), closeTo(b, 0.05)],
    );
  }

  Future<void> undo(WidgetTester t) async {
    await t.tap(find.byTooltip('Undo'));
    await t.pump();
  }

  final rect = {
    'kind': 'rect',
    'x': 100,
    'y': 100,
    'width': 100,
    'height': 60,
    'rotation': 0,
  };

  testWidgets('shape: corner resizes (one undo), top handle rotates with snap', (
    t,
  ) async {
    await select(t, {'points': shapePoints(rect), 'shape': rect});
    expectBox(t, 100, 100, 200, 160);
    // Ratio lock is on: 100:60 kept, the larger scale (160/100... 100/60) wins.
    await drag(t, [(200, 160), (230, 180), (260, 200)]);
    expectBox(t, 100, 100, 100 + 100 * (100 / 60), 200);
    await undo(t);
    expectBox(t, 100, 100, 200, 160);
    // Rotation handle is 22 above the top middle; drag it to the right of the
    // center: 90 degrees.
    await drag(t, [(150, 100 - 28 / vp(t).scale), (200, 110), (250, 130)]);
    final deg = angle(t) * 180 / math.pi;
    expect(deg, closeTo(90, 0.01));
    await undo(t);
    expect(angle(t), 0);
  });

  testWidgets('line: an end handle moves the end, snapped, one undo', (
    t,
  ) async {
    await select(t, {
      'points': [
        [100, 100, 0.5, 0],
        [200, 160, 0.5, 10],
      ],
    });
    await drag(t, [(200, 160), (230, 120), (260, 102)]);
    expectBox(t, 100, 100, 260, 100); // within 3 degrees: horizontal
    await undo(t);
    expectBox(t, 100, 100, 200, 160);
  });

  testWidgets('line: moving the body repaints without error', (t) async {
    await select(t, {
      'points': [
        [100, 100, 0.5, 0],
        [200, 160, 0.5, 10],
      ],
    });
    await drag(t, [(150, 130), (170, 140), (190, 160)]);
    expectBox(t, 140, 130, 240, 190);
  });
}
