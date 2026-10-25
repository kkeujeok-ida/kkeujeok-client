import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kkeujeok/platform/gesture_exclusion.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/ui/note_editor.dart';

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

  IconButton btn(WidgetTester t, String tip) => t.widget<IconButton>(
    find
        .ancestor(of: find.byTooltip(tip), matching: find.byType(IconButton))
        .first,
  );

  bool toolSelected(WidgetTester t, String tip) =>
      btn(t, tip).isSelected ?? false;

  ProviderContainer box(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(NoteEditor)));

  int slot(WidgetTester t) => box(t).read(selectedPenSlotProvider);

  Future<void> key(
    WidgetTester t,
    LogicalKeyboardKey k, {
    bool ctrl = false,
    bool shift = false,
    bool meta = false,
  }) async {
    if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (meta) await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(k);
    if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (meta) await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
  }

  const line = <(double, double)>[(150, 300), (250, 300), (350, 300)];

  testWidgets('undo and redo: Ctrl+Z, Ctrl+Shift+Z, Ctrl+Y, Cmd+Shift+Z', (
    t,
  ) async {
    await open(t);
    await drag(t, line);
    expect(strokes(t).length, 2);
    await key(t, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(strokes(t).length, 1);
    await key(t, LogicalKeyboardKey.keyZ, ctrl: true, shift: true);
    expect(strokes(t).length, 2);
    await key(t, LogicalKeyboardKey.keyZ, ctrl: true);
    await key(t, LogicalKeyboardKey.keyY, ctrl: true);
    expect(strokes(t).length, 2);
    await key(t, LogicalKeyboardKey.keyZ, meta: true);
    await key(t, LogicalKeyboardKey.keyY, meta: true); // no Cmd+Y
    expect(strokes(t).length, 1);
    await key(t, LogicalKeyboardKey.keyZ, meta: true, shift: true);
    expect(strokes(t).length, 2);
  });

  testWidgets('digits pick slots (out of range ignored); P and H', (t) async {
    await open(t);
    await key(t, LogicalKeyboardKey.digit2);
    expect(slot(t), 1);
    await key(t, LogicalKeyboardKey.digit9);
    expect(slot(t), 1);
    await key(t, LogicalKeyboardKey.keyH);
    expect(slot(t), 2);
    await key(t, LogicalKeyboardKey.keyP);
    expect(slot(t), 1); // the last picked pen
    await key(t, LogicalKeyboardKey.digit3, shift: true);
    expect(slot(t), 1);
  });

  testWidgets('L, E and T pick tools; a digit leaves them', (t) async {
    await open(t);
    await key(t, LogicalKeyboardKey.keyL);
    expect(toolSelected(t, 'Lasso'), isTrue);
    await key(t, LogicalKeyboardKey.keyE);
    expect(toolSelected(t, 'Eraser (Stroke)'), isTrue);
    await key(t, LogicalKeyboardKey.keyT);
    expect(toolSelected(t, 'Text'), isTrue);
    await key(t, LogicalKeyboardKey.digit1);
    expect(toolSelected(t, 'Text'), isFalse);
  });

  testWidgets('arrows scroll the view by 40 pt', (t) async {
    await open(t);
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Zoom in'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.tapAt(const Offset(450, 650));
    await t.pumpAndSettle();
    final before = painter(t).viewport!.offset;
    await key(t, LogicalKeyboardKey.arrowLeft);
    expect(painter(t).viewport!.offset.dx, before.dx + 40);
    await key(t, LogicalKeyboardKey.arrowUp);
    expect(painter(t).viewport!.offset.dy, before.dy + 40);
  });

  testWidgets('keys do nothing while drawing', (t) async {
    await open(t);
    final p = ++id;
    t.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: p,
        kind: PointerDeviceKind.stylus,
        position: at(t, 150, 300),
      ),
    );
    await t.pump();
    await key(t, LogicalKeyboardKey.keyL);
    expect(toolSelected(t, 'Lasso'), isFalse);
    t.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: p,
        kind: PointerDeviceKind.stylus,
        position: at(t, 150, 300),
      ),
    );
    await t.pump();
  });

  testWidgets('left edge hover sends a strip; lift and dispose clear it', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    resetGestureExclusion();
    final calls = <List<Object?>>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.kkeujeok.app/gesture'),
      (c) async {
        calls.add(c.arguments as List<Object?>);
        return null;
      },
    );
    await open(t);
    t.binding.handlePointerEvent(
      const PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        position: Offset(10, 300),
      ),
    );
    await t.pump();
    expect(calls.last, [
      [0.0, 200.0, 32.0, 400.0],
    ]);
    await t.pump(const Duration(milliseconds: 600));
    expect(calls.last, isEmpty);
    t.binding.handlePointerEvent(
      const PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        position: Offset(10, 300),
      ),
    );
    await t.pump();
    expect(calls.last, isNotEmpty);
    await t.pumpWidget(const SizedBox());
    expect(calls.last, isEmpty);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.kkeujeok.app/gesture'),
      null,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
