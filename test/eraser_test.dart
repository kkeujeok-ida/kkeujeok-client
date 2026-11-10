import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/eraser.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

// A six-point stroke along y=100 and a text box over it.
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
  final els = (j['pages'] as List).first['elements'] as List;
  els.add({
    'id': _id(9),
    'type': 'stroke',
    'tool': 'pen',
    'color': '#000000',
    'width': 2,
    'usePressure': false,
    'points': [
      for (var i = 0; i < 6; i++) [100 + 20 * i, 100, 0.5, 10 * i],
    ],
    'foo': 1,
  });
  els.add({
    'id': _id(10),
    'type': 'text',
    'x': 100,
    'y': 90,
    'width': 100,
    'rotation': 0,
    'text': 'hi',
    'runs': <Object?>[],
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

  setUp(() {
    resetStylusSeen();
    docs = Directory.systemTemp.createTempSync('kkj-erase-');
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

  Future<void> open(
    WidgetTester t, [
    Map<String, Object> prefs = const {},
  ]) async {
    await pumpApp(t, noteData: data, prefs: prefs);
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
  }

  PagePainter painter(WidgetTester t) =>
      (find
                      .descendant(
                        of: find.byType(NoteEditor),
                        matching: find.byWidgetPredicate(
                          (w) => w is CustomPaint && w.painter is PagePainter,
                        ),
                      )
                      .evaluate()
                      .first
                      .widget
                  as CustomPaint)
              .painter
          as PagePainter;

  List<Map> els(WidgetTester t) => [
    for (final e in painter(t).page['elements'] as List) e as Map,
  ];

  List<Map> strokes(WidgetTester t) => [
    for (final e in els(t))
      if (e['type'] == 'stroke') e,
  ];

  Offset at(WidgetTester t, double x, double y) =>
      painter(t).viewport!.offset + Offset(x, y) * painter(t).viewport!.scale;

  var id = 500;
  // Down (with [buttons]), moves, then up or cancel, in page pt.
  Future<void> drag(
    WidgetTester t,
    List<(double, double)> pts, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    int buttons = 0,
    bool cancel = false,
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
                buttons: buttons,
                timeStamp: ms,
              )
            : PointerMoveEvent(
                pointer: p,
                kind: kind,
                position: pos,
                buttons: buttons,
                timeStamp: ms,
              ),
      );
      await t.pump();
    }
    final last = at(t, pts.last.$1, pts.last.$2);
    final ms = Duration(milliseconds: 10 * pts.length);
    t.binding.handlePointerEvent(
      cancel
          ? PointerCancelEvent(
              pointer: p,
              kind: kind,
              position: last,
              timeStamp: ms,
            )
          : PointerUpEvent(
              pointer: p,
              kind: kind,
              position: last,
              timeStamp: ms,
            ),
    );
    await t.pump();
  }

  const cross = <(double, double)>[(150, 60), (150, 140)];

  IconButton btn(WidgetTester t, String tip) => t.widget<IconButton>(
    find
        .ancestor(of: find.byTooltip(tip), matching: find.byType(IconButton))
        .first,
  );

  bool toolSelected(WidgetTester t, String tip) =>
      btn(t, tip).isSelected ?? false;

  testWidgets('stroke mode: whole stroke goes, text stays, one undo step', (
    t,
  ) async {
    await open(t);
    await t.tap(find.byTooltip('Eraser (Stroke)'));
    await t.pump();
    await drag(t, cross);
    expect(strokes(t), isEmpty);
    expect(els(t).single['type'], 'text');
    await t.tap(find.byTooltip('Undo'));
    await t.pump();
    expect(strokes(t).single['id'], _id(9));
    expect(strokes(t).single['foo'], 1);
    expect(els(t).map((e) => e['id']), [_id(9), _id(10)]);
  });

  testWidgets('partial mode: pieces keep points; undo/redo same ids', (
    t,
  ) async {
    await open(t, {'eraserMode': 'partial'});
    await t.tap(find.byTooltip('Eraser (Partial)'));
    await t.pump();
    await drag(t, cross);
    final s = strokes(t);
    expect(s.length, 2);
    expect(s.map((e) => (e['points'] as List).length), [3, 3]);
    expect((s[1]['points'] as List).first, [160, 100, 0.5, 30]);
    expect(s.any((e) => e['id'] == _id(9)), isFalse);
    expect(s[0]['foo'], 1);
    final ids = s.map((e) => e['id']).toList();
    await t.tap(find.byTooltip('Undo'));
    await t.pump();
    expect(strokes(t).single['id'], _id(9));
    await t.tap(find.byTooltip('Redo'));
    await t.pump();
    expect(strokes(t).map((e) => e['id']).toList(), ids);
  });

  testWidgets('a miss changes nothing and records no step', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Eraser (Stroke)'));
    await t.pump();
    final rev = painter(t).page['rev'];
    await drag(t, [(150, 300), (150, 340)]);
    expect(strokes(t).length, 1);
    expect(painter(t).page['rev'], rev);
    expect(btn(t, 'Undo').onPressed, isNull);
  });

  testWidgets('cancel erases nothing', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Eraser (Stroke)'));
    await t.pump();
    await drag(t, cross, cancel: true);
    expect(strokes(t).length, 1);
  });

  testWidgets('side button erases on the pen tool; toolbar unchanged', (
    t,
  ) async {
    await open(t);
    await drag(t, cross, buttons: kSecondaryStylusButton);
    expect(strokes(t), isEmpty);
    expect(toolSelected(t, 'Eraser (Stroke)'), isFalse);
    // Without the button the same drag writes.
    await drag(t, cross);
    expect(strokes(t).length, 1);
  });

  testWidgets('eraser end erases on the pen tool; ignored with the lasso', (
    t,
  ) async {
    await open(t);
    await t.tap(find.byTooltip('Lasso'));
    await t.pump();
    await drag(t, cross, kind: PointerDeviceKind.invertedStylus);
    expect(strokes(t).length, 1);
    await t.tap(find.byTooltip('Eraser (Stroke)'));
    await t.pump();
    await t.tap(find.byTooltip('Eraser (Stroke)'));
    await settle(t);
    await t.tapAt(const Offset(5, 5));
    await settle(t);
    await drag(t, cross, kind: PointerDeviceKind.invertedStylus);
    expect(strokes(t), isEmpty);
  });

  testWidgets('return to pen: stylus yes, finger no', (t) async {
    await open(t, {'eraserReturnToPen': true});
    await t.tap(find.byTooltip('Eraser (Stroke)'));
    await t.pump();
    await drag(t, [(150, 300), (150, 340)], kind: PointerDeviceKind.touch);
    expect(toolSelected(t, 'Eraser (Stroke)'), isTrue);
    // A stylus gesture over empty space erased nothing: the eraser stays.
    await drag(t, [(150, 300), (150, 340)]);
    expect(toolSelected(t, 'Eraser (Stroke)'), isTrue);
    await drag(t, cross);
    expect(strokes(t), isEmpty);
    expect(toolSelected(t, 'Eraser (Stroke)'), isFalse);
  });

  testWidgets('popover: defaults, mode and toggle are stored and shown', (
    t,
  ) async {
    await open(t);
    await t.tap(find.byTooltip('Eraser (Stroke)'));
    await t.pump();
    await t.tap(find.byTooltip('Eraser (Stroke)'));
    await settle(t);
    expect(find.text('Eraser options'), findsOneWidget);
    expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
    await t.tap(find.text('Partial'));
    await settle(t);
    await t.tap(find.byType(Switch));
    await settle(t);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('eraserMode'), 'partial');
    expect(p.getBool('eraserReturnToPen'), true);
    await t.tapAt(const Offset(5, 5)); // outside: closes, keeps changes
    await settle(t);
    expect(find.text('Eraser options'), findsNothing);
    expect(find.byTooltip('Eraser (Partial)'), findsOneWidget);
  });

  group('eraseTargets (15.7 translucent preview)', () {
    Map<String, dynamic> stroke(String id, double y) => {
      'id': id,
      'type': 'stroke',
      'width': 2,
      'usePressure': false,
      'points': [
        for (var i = 0; i <= 10; i++) [i * 10.0, y, 0.5, i * 10],
      ],
    };
    final text = {'id': 'tx', 'type': 'text', 'x': 20, 'y': 40};
    final els = [stroke('a', 40), text, stroke('b', 150)];
    final path = <Pt>[(50, 30), (50, 50)];

    test('stroke mode: touched stroke kept and faded; text/far stroke not', () {
      final t = eraseTargets(els, path, 6, false);
      expect(t.fade, {'a'});
      expect(t.elements, els);
    });
    test('partial mode: original faded, opaque pieces follow it', () {
      final t = eraseTargets(els, path, 6, true);
      expect(t.fade, {'a'});
      expect([for (final e in t.elements) (e as Map)['id']], [
        'a',
        'a~0',
        'a~1',
        'tx',
        'b',
      ]);
    });
    test('partial pieces are drawable strokes; only the touched part is cut', () {
      final t = eraseTargets(els, path, 6, true);
      final pieces = [
        for (final e in t.elements)
          if (e is Map && '${e['id']}'.startsWith('a~')) e,
      ];
      expect(pieces.length, 2);
      expect(pieces.every(drawableStroke), isTrue);
      // untouched stroke 'b' is not faded; pieces match the saved split.
      expect(t.fade.contains('b'), isFalse);
      final kept = splitPieces([
        for (var i = 0; i <= 10; i++) (i * 10.0, 40.0),
      ], path, 6);
      expect([for (final p in pieces) (p['points'] as List).length], [
        for (final k in kept) k.length,
      ]);
    });
    test('shape piece is a plain drawable stroke', () {
      final sh = {
        ...stroke('s', 40),
        'shape': {'kind': 'rect', 'x': 0, 'y': 40, 'width': 100, 'height': 1, 'rotation': 0},
      };
      final t = eraseTargets([sh], path, 6, true);
      final ps = t.elements.whereType<Map>().where((e) => e['id'] != 's');
      expect(ps, isNotEmpty);
      expect(ps.every((e) => drawableStroke(e) && !e.containsKey('shape')), isTrue);
    });
    test('path that touches nothing fades nothing (cancel restores)', () {
      expect(eraseTargets(els, [(150, 100)], 6, true).fade, isEmpty);
      expect(eraseTargets(els, const [], 6, true).fade, isEmpty);
    });
  });
}
