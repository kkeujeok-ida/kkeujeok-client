import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/pen_only.dart';
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

  // A finger (or other kind) at page pt: down, optional moves, up/cancel.
  var tid = 900;
  Future<void> finger(
    WidgetTester t,
    List<(double, double)> pts, {
    int startMs = 1000,
    PointerDeviceKind kind = PointerDeviceKind.touch,
    double radius = 0,
    bool cancel = false,
  }) async {
    final p = ++tid;
    for (var i = 0; i < pts.length; i++) {
      final pos = at(t, pts[i].$1, pts[i].$2);
      final ms = Duration(milliseconds: startMs + 10 * i);
      t.binding.handlePointerEvent(
        i == 0
            ? PointerDownEvent(
                pointer: p,
                kind: kind,
                position: pos,
                radiusMajor: radius,
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
    final last = at(t, pts.last.$1, pts.last.$2);
    final ms = Duration(milliseconds: startMs + 10 * pts.length);
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

  Future<void> hover(WidgetTester t, int ms, [double x = 150]) async {
    t.binding.handlePointerEvent(
      PointerHoverEvent(
        kind: PointerDeviceKind.stylus,
        position: at(t, x, 300),
        timeStamp: Duration(milliseconds: ms),
      ),
    );
    await t.pump();
  }

  const line = <(double, double)>[(150, 300), (250, 300), (350, 300)];

  testWidgets('no record, auto: a finger draws', (t) async {
    await open(t);
    await finger(t, line);
    expect(strokes(t).length, 2);
  });

  testWidgets('first hover is stored; then a finger leaves no ink', (t) async {
    await open(t);
    await hover(t, 0);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('stylusSeen'), true);
    await finger(t, line);
    expect(strokes(t).length, 1);
  });

  testWidgets('restart: the stored record makes the first finger pen only', (
    t,
  ) async {
    await open(t);
    await hover(t, 0);
    resetStylusSeen();
    await t.pumpWidget(const SizedBox());
    await open(t, {'stylusSeen': true});
    await finger(t, line);
    expect(strokes(t).length, 1);
  });

  testWidgets('off keeps the record and draws', (t) async {
    await open(t, {'stylusSeen': true, 'penOnlyMode': 'off'});
    await finger(t, line);
    expect(strokes(t).length, 2);
  });

  testWidgets('on needs no record', (t) async {
    await open(t, {'penOnlyMode': 'on'});
    await finger(t, line);
    expect(strokes(t).length, 1);
  });

  testWidgets('a bad stored mode or record is the default', (t) async {
    await open(t, {'stylusSeen': 'yes', 'penOnlyMode': 'maybe'});
    await finger(t, line);
    expect(strokes(t).length, 2);
  });

  testWidgets('touch is ignored within 500 ms of the pen, then normal', (
    t,
  ) async {
    await open(t, {'penOnlyMode': 'off'});
    await hover(t, 1000);
    await finger(t, line, startMs: 1400);
    expect(strokes(t).length, 1);
    await finger(t, line, startMs: 1600);
    expect(strokes(t).length, 2);
  });

  testWidgets('wide contact and unknown kind leave no ink', (t) async {
    await open(t, {'penOnlyMode': 'off'});
    await finger(t, line, radius: 50);
    await finger(t, line, kind: PointerDeviceKind.unknown);
    expect(strokes(t).length, 1);
    await finger(t, line, radius: 30);
    expect(strokes(t).length, 2);
  });

  testWidgets('a cancelled finger leaves no ink', (t) async {
    await open(t, {'penOnlyMode': 'off'});
    await finger(t, line, cancel: true);
    expect(strokes(t).length, 1);
  });

  testWidgets('a pen landing drops the finger stroke, then writes', (t) async {
    await open(t, {'penOnlyMode': 'off'});
    final pos = at(t, 150, 300);
    t.binding.handlePointerEvent(
      PointerDownEvent(
        pointer: 700,
        position: pos,
        timeStamp: const Duration(milliseconds: 1000),
      ),
    );
    await t.pump();
    t.binding.handlePointerEvent(
      PointerMoveEvent(
        pointer: 700,
        position: pos + const Offset(40, 0),
        timeStamp: const Duration(milliseconds: 1020),
      ),
    );
    await t.pump();
    await drag(t, [(150, 400), (250, 400)]);
    expect(strokes(t).length, 2); // the pen stroke only
    t.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: 700,
        position: pos,
        timeStamp: const Duration(milliseconds: 1100),
      ),
    );
    await t.pump();
    expect(strokes(t).length, 2);
  });

  testWidgets('second finger within 150 ms drops the stroke; later keeps it', (
    t,
  ) async {
    await open(t, {'penOnlyMode': 'off'});
    Future<void> two(int gap) async {
      final a = ++tid, b = ++tid;
      t.binding.handlePointerEvent(
        PointerDownEvent(
          pointer: a,
          position: at(t, 150, 300),
          timeStamp: const Duration(milliseconds: 5000),
        ),
      );
      await t.pump();
      t.binding.handlePointerEvent(
        PointerMoveEvent(
          pointer: a,
          position: at(t, 200, 300),
          timeStamp: const Duration(milliseconds: 5010),
        ),
      );
      await t.pump();
      t.binding.handlePointerEvent(
        PointerDownEvent(
          pointer: b,
          position: at(t, 300, 300),
          timeStamp: Duration(milliseconds: 5000 + gap),
        ),
      );
      await t.pump();
      for (final id in [a, b]) {
        t.binding.handlePointerEvent(
          PointerUpEvent(
            pointer: id,
            position: at(t, 200, 300),
            timeStamp: const Duration(milliseconds: 5300),
          ),
        );
        await t.pump();
      }
    }

    await two(100);
    expect(strokes(t).length, 1);
    await two(200);
    expect(strokes(t).length, 2);
  });

  testWidgets('settings: segmented button, stored, none on the editor', (
    t,
  ) async {
    final sh = t.ensureSemantics();
    await pumpApp(t, noteData: data);
    await settle(t);
    await t.tap(find.text('Settings'));
    await settle(t);
    await t.scrollUntilVisible(find.text('Write with pen only'), 100);
    await t.scrollUntilVisible(find.text('On'), 100);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.byType(SegmentedButton<PenOnlyMode>), findsOneWidget);
    expect(
      t.getSize(find.widgetWithText(TextButton, 'On')).height,
      greaterThanOrEqualTo(48),
    );
    final sem = t.getSemantics(find.text('Auto'));
    expect(find.bySemanticsLabel('Auto'), findsOneWidget);
    expect(sem.hasFlag(SemanticsFlag.isSelected), isTrue);
    SegmentedButton<PenOnlyMode> seg() =>
        t.widget(find.byType(SegmentedButton<PenOnlyMode>));
    expect(seg().style!.animationDuration, isNot(Duration.zero));
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pump();
    expect(seg().style!.animationDuration, Duration.zero);
    await t.tap(find.text('Off'));
    await t.pump();
    final p = await SharedPreferences.getInstance();
    expect(p.getString('penOnlyMode'), 'off');
    await t.tap(find.text('On'));
    await t.pump();
    expect(p.getString('penOnlyMode'), 'on');
    await t.pageBack();
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
    expect(find.text('Write with pen only'), findsNothing);
    sh.dispose();
  });
}
