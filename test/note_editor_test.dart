import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/render/stroke_outline.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Note _note({
  String title = 'Lecture',
  String background = 'plain',
  String orientation = 'portrait',
}) => createNote(
  title: title,
  existingTitles: const [],
  background: background,
  orientation: orientation,
  noteId: _id(1),
  pageId: _id(1001),
  pageRev: _id(2001),
  metaRev: _id(3001),
  orderRev: _id(4001),
  now: '2000-01-01T12:00:00.000Z',
  editedBy: 'Pixel 8',
).note!;

void main() {
  late Directory docs;
  late NoteData data;
  late File file;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-edit-');
    data = NoteData(() async => docs);
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

  List elements() =>
      (decodeKkj(file.readAsBytesSync()).note!.pages.first['elements']) as List;

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

  Future<void> open(
    WidgetTester t, {
    NoteStore? store,
    List<Locale> device = const [Locale('en', 'US')],
  }) async {
    await pumpApp(t, noteData: data, noteStore: store, device: device);
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
    expect(find.byType(NoteEditor), findsOneWidget);
  }

  PageViewport viewport(WidgetTester t) {
    final paint =
        find
                .descendant(
                  of: find.byType(NoteEditor),
                  matching: find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is PagePainter,
                  ),
                )
                .evaluate()
                .single
                .widget
            as CustomPaint;
    return (paint.painter as PagePainter).viewport!;
  }

  Offset onScreen(WidgetTester t, double x, double y) {
    final vp = viewport(t);
    return vp.offset + Offset(x, y) * vp.scale;
  }

  var pointer = 100;

  /// One stroke: down, moves, up. Each point is (x, y, pressure) in page pt.
  Future<void> draw(
    WidgetTester t,
    List<(double, double, double)> pts, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    bool cancel = false,
    bool up = true,
  }) async {
    final id = ++pointer;
    PointerEvent ev(int i, {bool last = false}) {
      final (x, y, p) = pts[i];
      final pos = onScreen(t, x, y);
      final stamp = Duration(milliseconds: 10 * i);
      if (i == 0) {
        return PointerDownEvent(
          pointer: id,
          kind: kind,
          position: pos,
          pressure: p,
          pressureMin: 0,
          pressureMax: 1,
          timeStamp: stamp,
        );
      }
      if (last && up) {
        return cancel
            ? PointerCancelEvent(
                pointer: id,
                kind: kind,
                position: pos,
                timeStamp: stamp,
              )
            : PointerUpEvent(
                pointer: id,
                kind: kind,
                position: pos,
                pressure: p,
                pressureMin: 0,
                pressureMax: 1,
                timeStamp: stamp,
              );
      }
      return PointerMoveEvent(
        pointer: id,
        kind: kind,
        position: pos,
        pressure: p,
        pressureMin: 0,
        pressureMax: 1,
        timeStamp: stamp,
      );
    }

    for (var i = 0; i < pts.length; i++) {
      t.binding.handlePointerEvent(ev(i, last: i == pts.length - 1 && i > 0));
      await t.pump();
    }
    if (pts.length == 1 && up) {
      final pos = onScreen(t, pts[0].$1, pts[0].$2);
      t.binding.handlePointerEvent(
        cancel
            ? PointerCancelEvent(pointer: id, kind: kind, position: pos)
            : PointerUpEvent(pointer: id, kind: kind, position: pos),
      );
      await t.pump();
    }
  }

  const line = <(double, double, double)>[
    (100, 100, 0.2),
    (150, 120, 0.5),
    (200, 160, 0.9),
    (250, 200, 0.7),
  ];

  group('writing screen', () {
    testWidgets('corner, one pen slot, page; grip is not in the tree', (
      t,
    ) async {
      final h = t.ensureSemantics();
      seed(_note(background: 'lined'));
      await open(t);
      expect(find.text('Lecture'), findsOneWidget);
      expect(find.byTooltip('Back to library'), findsOneWidget);
      expect(find.bySemanticsLabel('Pen, Black, width 2.0'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ExcludeSemantics),
          matching: find.byIcon(Icons.more_vert),
        ),
        findsOneWidget,
      );
      // The page is clear of the corner and the toolbar.
      final pageTop = viewport(t).offset.dy;
      expect(
        pageTop,
        greaterThanOrEqualTo(
          t.getRect(find.byTooltip('Back to library')).bottom,
        ),
      );
      expect(
        pageTop,
        greaterThanOrEqualTo(t.getRect(find.byType(PenToolbar)).bottom),
      );
      h.dispose();
    });

    testWidgets('semantics: back, title, selected pen, page', (t) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t);
      final pen = t
          .getSemantics(find.bySemanticsLabel('Pen, Black, width 2.0'))
          .getSemanticsData();
      expect(pen.flagsCollection.isSelected, Tristate.isTrue);
      expect(pen.flagsCollection.isButton, isTrue);
      final page = t
          .getSemantics(find.bySemanticsLabel('Page 1 of 1, Portrait'))
          .getSemanticsData();
      expect(page.value, 'Handwriting');
      h.dispose();
    });

    testWidgets('Korean names', (t) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t, device: const [Locale('ko', 'KR')]);
      expect(find.byTooltip('서재로'), findsOneWidget);
      expect(find.bySemanticsLabel('펜, 검정, 두께 2.0'), findsOneWidget);
      expect(find.bySemanticsLabel('1페이지 / 1, 세로'), findsOneWidget);
      h.dispose();
    });

    testWidgets('touch targets are at least 48dp', (t) async {
      seed(_note());
      await open(t);
      final back = t.getSize(find.byTooltip('Back to library'));
      expect(back.width, greaterThanOrEqualTo(48));
      expect(back.height, greaterThanOrEqualTo(48));
      final slot = t.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.arrow_drop_down),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(slot.width, greaterThanOrEqualTo(48));
      expect(slot.height, greaterThanOrEqualTo(48));
    });

    testWidgets('a long title keeps to one line', (t) async {
      seed(_note(title: 'Long ' * 20));
      await pumpApp(t, noteData: data, width: 400);
      await settle(t);
      await t.tap(find.textContaining('Long').first);
      await settle(t);
      final text = t.widget<Text>(
        find.descendant(
          of: find.byType(NoteEditor),
          matching: find.textContaining('Long'),
        ),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(t.takeException(), isNull);
    });
  });

  group('input', () {
    testWidgets('stylus: pressure 0..1, default pen, saved at once', (t) async {
      seed(_note());
      await open(t);
      await draw(t, line);
      await settle(t);
      final els = elements();
      expect(els, hasLength(1));
      final s = els.single as Map<String, dynamic>;
      expect(s['type'], 'stroke');
      expect(s['tool'], 'pen');
      expect(s['color'], '#000000');
      expect(s['width'], 2);
      expect(s['usePressure'], isTrue);
      final pts = (s['points'] as List).cast<List>();
      expect(pts.map((p) => p[2]), [0.2, 0.5, 0.9, 0.7]);
      expect(pts.map((p) => p[3]), [0, 10, 20, 30]);
      expect(pts.first[0], closeTo(100, 0.01));
      expect(pts.first[1], closeTo(100, 0.01));
    });

    testWidgets('finger: every pressure is 0.5', (t) async {
      seed(_note());
      await open(t);
      await draw(t, line, kind: PointerDeviceKind.touch);
      await settle(t);
      final s = elements().single as Map<String, dynamic>;
      expect((s['points'] as List).map((p) => (p as List)[2]).toSet(), {0.5});
      expect(s['width'], 2);
    });

    testWidgets('start outside the page: no stroke, no save', (t) async {
      seed(_note());
      final before = file.readAsBytesSync();
      await open(t);
      final vp = viewport(t);
      // The sunken margin left of the page.
      final gray = Offset(vp.offset.dx / 2, vp.offset.dy + 100);
      final g = await t.startGesture(gray, kind: PointerDeviceKind.touch);
      await g.moveTo(onScreen(t, 100, 100));
      await g.up();
      await settle(t);
      expect(elements(), isEmpty);
      expect(file.readAsBytesSync(), before);
    });

    testWidgets('leaving the page keeps every point', (t) async {
      seed(_note());
      await open(t);
      await draw(t, const [
        (500, 400, 0.5),
        (580, 400, 0.5),
        (650, 400, 0.5), // right of the 595 pt page
        (700, 400, 0.5),
      ]);
      await settle(t);
      final pts = ((elements().single as Map)['points'] as List).cast<List>();
      expect(pts, hasLength(4));
      expect(pts.last[0], closeTo(700, 0.01));
    });

    testWidgets('a tap is a one-point stroke', (t) async {
      seed(_note());
      await open(t);
      await draw(t, const [(300, 300, 0.5)], kind: PointerDeviceKind.touch);
      await settle(t);
      final pts = ((elements().single as Map)['points'] as List);
      expect(pts, hasLength(1));
    });

    testWidgets('cancel finishes the stroke with the points so far', (t) async {
      seed(_note());
      await open(t);
      await draw(t, line, cancel: true);
      await settle(t);
      final pts = ((elements().single as Map)['points'] as List);
      expect(pts, hasLength(3)); // the cancel adds no point
    });

    testWidgets('inverted stylus makes no stroke', (t) async {
      seed(_note());
      await open(t);
      await draw(t, line, kind: PointerDeviceKind.invertedStylus);
      await settle(t);
      expect(elements(), isEmpty);
    });

    testWidgets('a second pointer is ignored while one draws', (t) async {
      seed(_note());
      await open(t);
      final a = await t.startGesture(
        onScreen(t, 100, 100),
        kind: PointerDeviceKind.touch,
      );
      final b = await t.startGesture(
        onScreen(t, 300, 300),
        kind: PointerDeviceKind.touch,
        pointer: 9,
      );
      await b.moveTo(onScreen(t, 320, 320));
      await b.up();
      await a.moveTo(onScreen(t, 150, 150));
      await a.up();
      await settle(t);
      final els = elements();
      expect(els, hasLength(1)); // the second pointer made no stroke
      final pts = ((els.single as Map)['points'] as List).cast<List>();
      expect(pts, hasLength(2)); // and left no point in the first
      expect(pts.every((p) => (p[0] as num) < 200), isTrue);
    });
  });

  group('saving', () {
    testWidgets('a failed save keeps the stroke; the next one saves both', (
      t,
    ) async {
      seed(_note());
      var fail = true;
      final store = NoteStore(
        data,
        writeFile: (f, b) async {
          if (fail) throw const FileSystemException('disk full');
          await f.writeAsBytes(b);
        },
      );
      await open(t, store: store);
      await draw(t, line);
      await settle(t);
      expect(find.text("Couldn't save to this device."), findsOneWidget);
      expect(elements(), isEmpty); // file unchanged

      fail = false;
      await draw(t, line.map((p) => (p.$1 + 10, p.$2 + 10, p.$3)).toList());
      await settle(t);
      expect(elements(), hasLength(2)); // the first stroke is saved too
    });

    testWidgets('back retries a failed save once, then leaves', (t) async {
      seed(_note());
      var fail = true;
      final store = NoteStore(
        data,
        writeFile: (f, b) async {
          if (fail) throw const FileSystemException('disk full');
          await f.writeAsBytes(b);
        },
      );
      await open(t, store: store);
      await draw(t, line);
      await settle(t);
      expect(elements(), isEmpty);
      fail = false;
      await t.tap(find.byTooltip('Back to library'));
      await settle(t);
      expect(find.byType(NoteEditor), findsNothing);
      expect(elements(), hasLength(1));
    });

    testWidgets('saves run one at a time and back waits for them', (t) async {
      seed(_note());
      final gate = Completer<void>();
      var active = 0, maxActive = 0, calls = 0;
      final store = NoteStore(
        data,
        writeFile: (f, b) async {
          calls++;
          active++;
          if (active > maxActive) maxActive = active;
          if (calls == 1) await gate.future;
          await f.writeAsBytes(b);
          active--;
        },
      );
      await open(t, store: store);
      await draw(t, line);
      await draw(t, line.map((p) => (p.$1, p.$2 + 40, p.$3)).toList());
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.tap(find.byTooltip('Back to library'));
      await t.pump();
      expect(find.byType(NoteEditor), findsOneWidget); // still saving
      gate.complete();
      await settle(t);
      expect(maxActive, 1);
      expect(find.byType(NoteEditor), findsNothing);
      expect(elements(), hasLength(2));
    });

    testWidgets('back returns to a library card showing the new stroke', (
      t,
    ) async {
      seed(_note());
      await open(t);
      final old = DateFormat.yMd('en')
          .format(DateTime.parse('2000-01-01T12:00:00.000Z').toLocal());
      await draw(t, line);
      await t.binding.handlePopRoute(); // system back
      await settle(t);
      expect(find.byType(NoteEditor), findsNothing);
      expect(find.text(old), findsNothing); // modified date moved on
      final painters = find
          .byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is PagePainter,
          )
          .evaluate()
          .map((e) => ((e.widget as CustomPaint).painter as PagePainter));
      expect(painters, hasLength(1));
      expect(painters.single.page['elements'], hasLength(1));
    });
  });

  group('paint', () {
    const white = Color(0xFFFFFFFF);
    const lineColor = Color(0xFFC5CED8);
    const dotColor = Color(0xFFA0AAB5);
    const black = Color(0xFF000000);

    Note withStroke(String background) {
      final r = applyOp(
        _note(background: background),
        {
          'op': 'addStroke',
          'pageId': _id(1001),
          'stroke': {
            'id': _id(9),
            'type': 'stroke',
            'tool': 'pen',
            'color': '#000000',
            'width': 2,
            'usePressure': true,
            'points': [
              [100, 100, 0.5, 0],
              [200, 150, 0.5, 10],
            ],
          },
        },
        const Ctx(
          rev: '01926f3a-0000-7000-8000-000000009999',
          now: '2000-01-02T00:00:00.000Z',
          editedBy: 'x',
        ),
      );
      return r.note!;
    }

    Finder painted(bool inEditor) => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PagePainter,
    );

    testWidgets('editor: clip, paper, lines and a stroke path', (t) async {
      seed(withStroke('lined'));
      await open(t);
      final ro = t.renderObject(
        find.descendant(of: find.byType(NoteEditor), matching: painted(true)),
      );
      expect(
        ro,
        paints
          ..clipRect()
          ..rect(color: white)
          ..line(color: lineColor)
          ..path(color: black),
      );
    });

    testWidgets('editor: grid has lines, dot has dots', (t) async {
      seed(_note(background: 'grid'));
      await open(t);
      expect(
        t.renderObject(painted(true)),
        paints
          ..clipRect()
          ..rect(color: white)
          ..line(color: lineColor),
      );
    });

    testWidgets('editor: dot background', (t) async {
      seed(_note(background: 'dot'));
      await open(t);
      expect(
        t.renderObject(painted(true)),
        paints
          ..clipRect()
          ..rect(color: white)
          ..circle(color: dotColor),
      );
    });

    testWidgets('library thumbnail: same painter, no viewport', (t) async {
      seed(withStroke('lined'));
      await pumpApp(t, noteData: data);
      await settle(t);
      final f = painted(false);
      final painter =
          (f.evaluate().single.widget as CustomPaint).painter as PagePainter;
      expect(painter.viewport, isNull);
      expect(
        t.renderObject(f),
        paints
          ..clipRect()
          ..rect(color: white)
          ..line(color: lineColor)
          ..path(color: black),
      );
    });

    test('parseColor', () {
      expect(parseColor('#000000'), const Color(0xFF000000));
      expect(parseColor('#c5ced8'), const Color(0xFFC5CED8));
      expect(parseColor('#11223380'), const Color(0x80112233));
      expect(parseColor('red'), black);
      expect(parseColor(null), black);
      expect(parseColor('#12345'), black);
    });

    test('PageViewport fit and toPage round trip', () {
      final vp = PageViewport.fit(
        const Size(900, 700),
        595,
        842,
        const EdgeInsets.fromLTRB(12, 80, 12, 12),
      );
      for (final p in const [Offset(0, 0), Offset(595, 842), Offset(100, 50)]) {
        final back = vp.toPage(vp.offset + p * vp.scale);
        expect(back.dx, closeTo(p.dx, 1e-9));
        expect(back.dy, closeTo(p.dy, 1e-9));
      }
      // Whole page inside the padded area.
      expect(vp.offset.dy, greaterThanOrEqualTo(80));
      expect(vp.offset.dy + 842 * vp.scale, lessThanOrEqualTo(700 - 12 + 1e-9));
    });

    test('PageViewport.fit survives a bad page or area', () {
      for (final (w, h) in const [
        (0.0, 842.0),
        (595.0, -1.0),
        (double.nan, 10.0),
        (double.infinity, 10.0),
      ]) {
        final vp = PageViewport.fit(
          const Size(900, 700),
          w,
          h,
          EdgeInsets.zero,
        );
        expect(vp.scale, 1);
        expect(vp.offset.dx.isNaN || vp.offset.dy.isNaN, isFalse);
      }
      final tiny = PageViewport.fit(
        const Size(10, 10),
        595,
        842,
        const EdgeInsets.all(20),
      );
      expect(tiny.scale, 1);
    });

    test('the cache sees an edit with the same id and length', () {
      Map<String, dynamic> stroke(num lastX) => {
        'id': 'a',
        'width': 2,
        'usePressure': true,
        'points': [
          [10, 10, 0.5, 0],
          [lastX, 30, 0.5, 10],
        ],
      };
      final c = StrokePathCache();
      final a = c.pathOf(stroke(50));
      expect(identical(c.pathOf(stroke(50)), a), isTrue);
      expect(identical(c.pathOf(stroke(80)), a), isFalse);
    });

    testWidgets('malformed elements are skipped, not thrown', (t) async {
      final j = _note().copyJson();
      ((j['pages'] as List).first as Map)['elements'] = [
        {'id': 5, 'type': 'stroke'},
        {'id': 'x', 'type': 'stroke', 'points': 'no', 'width': 2},
        {'type': 'text', 'id': 'y'},
      ];
      final page = (j['pages'] as List).first as Map<String, dynamic>;
      await t.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            size: const Size(100, 140),
            painter: PagePainter(page: page, cache: StrokePathCache()),
          ),
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('render cache', () {
    test('a finished stroke reuses its path, equal to the outline', () {
      final s = {
        'id': 'a',
        'width': 2,
        'usePressure': true,
        'points': [
          [10, 10, 0.5, 0],
          [40, 30, 0.8, 10],
          [90, 20, 0.3, 20],
        ],
      };
      final c = StrokePathCache();
      final p = c.pathOf(s);
      expect(identical(c.pathOf(s), p), isTrue);
      final want = outlinePath(strokeOutline(2, true, s['points'] as List));
      expect(p.getBounds(), want.getBounds());
      c.keepOnly({});
      expect(identical(c.pathOf(s), p), isFalse);
    });
  });
}
