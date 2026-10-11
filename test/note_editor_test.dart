import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kkeujeok/design_tokens/build/tokens.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/render/stroke_outline.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> ptr(WidgetTester t, PointerEvent e) async {
    t.binding.handlePointerEvent(e);
    await t.pump();
  }

  PointerDownEvent down(
    int id,
    Offset p,
    int ms, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) => PointerDownEvent(
    pointer: id,
    kind: kind,
    position: p,
    pressureMin: 0,
    pressureMax: 1,
    pressure: 0.5,
    timeStamp: Duration(milliseconds: ms),
  );

  PointerMoveEvent move(
    int id,
    Offset p,
    int ms, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) => PointerMoveEvent(
    pointer: id,
    kind: kind,
    position: p,
    pressureMin: 0,
    pressureMax: 1,
    pressure: 0.5,
    timeStamp: Duration(milliseconds: ms),
  );

  PointerUpEvent up(
    int id,
    Offset p,
    int ms, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) => PointerUpEvent(
    pointer: id,
    kind: kind,
    position: p,
    timeStamp: Duration(milliseconds: ms),
  );

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
        (598, 400, 0.5), // right of the 595 pt page
        (600, 400, 0.5),
      ]);
      await settle(t);
      final pts = ((elements().single as Map)['points'] as List).cast<List>();
      expect(pts, hasLength(4));
      expect(pts.last[0], closeTo(600, 0.01));
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

    testWidgets('a late second finger is ignored while one draws', (t) async {
      seed(_note());
      await open(t);
      final a = onScreen(t, 100, 100), b = onScreen(t, 300, 300);
      await ptr(t, down(1, a, 0));
      await ptr(t, down(9, b, 400));
      await ptr(t, move(9, b + const Offset(20, 20), 410));
      await ptr(t, up(9, b + const Offset(20, 20), 420));
      await ptr(t, move(1, onScreen(t, 150, 150), 430));
      await ptr(t, up(1, onScreen(t, 150, 150), 440));
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

  group('zoom and pan', () {
    const gap = KkjTokens.spacing3;
    const a0 = Offset(300, 300), b0 = Offset(400, 300);

    /// Two fingers down 10 ms apart, then moved to [a1]/[b1].
    Future<void> pinch(
      WidgetTester t,
      Offset a1,
      Offset b1, {
      Offset a = a0,
      Offset b = b0,
      bool release = true,
    }) async {
      await ptr(t, down(31, a, 0));
      await ptr(t, down(32, b, 10));
      await ptr(t, move(31, a1, 20));
      await ptr(t, move(32, b1, 30));
      if (release) {
        await ptr(t, up(31, a1, 40));
        await ptr(t, up(32, b1, 40));
      }
    }

    Future<void> menu(WidgetTester t) async {
      await t.tap(find.byTooltip('More'));
      await t.pumpAndSettle();
    }

    IconButton iconButton(WidgetTester t, IconData icon) =>
        t.widget<IconButton>(
          find.ancestor(
            of: find.byIcon(icon),
            matching: find.byType(IconButton),
          ),
        );

    testWidgets('opens fit to width, page top under the toolbar', (t) async {
      seed(_note());
      await open(t);
      final vp = viewport(t);
      expect(vp.scale, closeTo((900 - 2 * gap) / 595, 1e-9));
      expect(
        vp.offset.dy,
        closeTo(t.getRect(find.byType(PenToolbar)).bottom + gap, 0.01),
      );
      expect(vp.offset.dx, closeTo(gap, 1e-9));
    });

    testWidgets('pinch keeps the point under the fingers, scale in range', (
      t,
    ) async {
      seed(_note());
      final before = file.readAsBytesSync();
      await open(t);
      final v0 = viewport(t);
      final p0 = v0.toPage((a0 + b0) / 2);
      await pinch(
        t,
        const Offset(300, 300),
        const Offset(500, 300),
        release: false,
      );
      final v1 = viewport(t);
      expect(v1.scale, closeTo(v0.scale * 2, 1e-9));
      // The fingers' center is now (400, 300).
      final p1 = v1.toPage(const Offset(400, 300));
      expect(p1.dx, closeTo(p0.dx, 1e-6));
      expect(p1.dy, closeTo(p0.dy, 1e-6));
      await ptr(t, up(31, const Offset(300, 300), 50));
      await ptr(t, up(32, const Offset(500, 300), 50));
      await settle(t);
      expect(file.readAsBytesSync(), before); // no stroke, no save
      expect(elements(), isEmpty);
    });

    testWidgets('scale is limited to 50%..400%', (t) async {
      seed(_note());
      await open(t);
      await pinch(t, const Offset(100, 300), const Offset(800, 300));
      expect(viewport(t).scale, PageViewport.zoomMax);
      await pinch(t, const Offset(400, 300), const Offset(402, 300));
      expect(viewport(t).scale, PageViewport.zoomMin);
      // A page smaller than the area is centered.
      expect(viewport(t).offset.dx, closeTo((900 - 595 * 0.5) / 2, 0.01));
    });

    testWidgets('second finger within 150 ms cancels the stroke', (t) async {
      seed(_note());
      final before = file.readAsBytesSync();
      await open(t);
      final s0 = viewport(t).scale;
      await ptr(t, down(1, onScreen(t, 100, 100), 0));
      await ptr(t, move(1, onScreen(t, 120, 110), 20));
      await ptr(t, down(2, onScreen(t, 300, 300), 150)); // exactly 150 ms
      await ptr(t, move(2, onScreen(t, 400, 300), 160)); // pinch
      expect(viewport(t).scale, isNot(s0));
      await ptr(t, up(1, onScreen(t, 120, 110), 170));
      await ptr(t, up(2, onScreen(t, 400, 300), 170));
      await settle(t);
      expect(elements(), isEmpty);
      expect(file.readAsBytesSync(), before);
      // Not in the undo history either.
      expect(iconButton(t, Icons.undo).onPressed, isNull);
    });

    testWidgets('a finger after 150 ms is ignored, the stroke is kept', (
      t,
    ) async {
      seed(_note());
      await open(t);
      final s0 = viewport(t).scale;
      await ptr(t, down(1, onScreen(t, 100, 100), 0));
      await ptr(t, down(2, onScreen(t, 300, 300), 151));
      await ptr(t, move(2, onScreen(t, 500, 300), 160));
      await ptr(t, move(1, onScreen(t, 140, 120), 170));
      await ptr(t, up(2, onScreen(t, 500, 300), 180));
      await ptr(t, up(1, onScreen(t, 140, 120), 190));
      await settle(t);
      expect(viewport(t).scale, s0);
      final pts = ((elements().single as Map)['points'] as List);
      expect(pts, hasLength(2));
    });

    testWidgets('a stylus takes over from a touch stroke', (t) async {
      seed(_note());
      await open(t);
      await ptr(t, down(1, onScreen(t, 100, 100), 0));
      await ptr(t, move(1, onScreen(t, 120, 110), 20));
      await draw(t, line); // stylus stroke while the finger is down
      await ptr(t, up(1, onScreen(t, 120, 110), 400));
      await settle(t);
      final els = elements();
      expect(els, hasLength(1)); // the touch stroke was dropped
      final pts = ((els.single as Map)['points'] as List).cast<List>();
      expect(pts.map((p) => p[2]), [0.2, 0.5, 0.9, 0.7]);
    });

    testWidgets('a stylus cancels a two-finger gesture', (t) async {
      seed(_note());
      await open(t);
      await pinch(
        t,
        const Offset(300, 300),
        const Offset(450, 300),
        release: false,
      );
      final scaled = viewport(t).scale;
      await draw(t, line);
      await ptr(t, move(32, const Offset(700, 300), 500)); // not a pinch now
      expect(viewport(t).scale, scaled);
      await ptr(t, up(31, const Offset(300, 300), 510));
      await ptr(t, up(32, const Offset(700, 300), 510));
      await settle(t);
      expect(elements(), hasLength(1));
    });

    testWidgets('one finger left after a gesture makes no input', (t) async {
      seed(_note());
      await open(t);
      await pinch(
        t,
        const Offset(300, 300),
        const Offset(450, 300),
        release: false,
      );
      await ptr(t, up(32, const Offset(450, 300), 100));
      final scaled = viewport(t);
      await ptr(t, move(31, const Offset(320, 330), 110));
      await ptr(t, move(31, const Offset(340, 360), 120));
      expect(viewport(t).scale, scaled.scale);
      expect(viewport(t).offset, scaled.offset);
      await ptr(t, up(31, const Offset(340, 360), 130));
      await settle(t);
      expect(elements(), isEmpty);
      // All contacts are up: a stroke works again.
      await draw(t, line, kind: PointerDeviceKind.touch);
      await settle(t);
      expect(elements(), hasLength(1));
    });

    testWidgets('pan stops at the page edge, with toolbar room below', (
      t,
    ) async {
      seed(_note());
      await open(t);
      // 2x first, so the page is larger than the area both ways.
      await pinch(t, const Offset(300, 300), const Offset(500, 300));
      final tb = t.getSize(find.byType(PenToolbar)).height;
      final top = t.getRect(find.byType(PenToolbar)).bottom + gap;

      await ptr(t, down(41, const Offset(300, 200), 0));
      await ptr(t, down(42, const Offset(400, 200), 5));
      // Drag far down: the page top stops under the toolbar.
      await ptr(t, move(41, const Offset(300, 5000), 10));
      await ptr(t, move(42, const Offset(400, 5000), 10));
      expect(viewport(t).offset.dy, closeTo(top, 0.01));
      // Drag far up: the page bottom stops a toolbar height above the edge.
      await ptr(t, move(41, const Offset(300, -9000), 20));
      await ptr(t, move(42, const Offset(400, -9000), 20));
      final vp = viewport(t);
      expect(
        vp.offset.dy + 842 * vp.scale,
        closeTo(700 - gap - (tb + gap), 0.01),
      );
      // Sideways, the page keeps its edge on screen.
      await ptr(t, move(41, const Offset(-9000, 200), 30));
      await ptr(t, move(42, const Offset(-8900, 200), 30));
      final vx = viewport(t);
      expect(vx.offset.dx + 595 * vx.scale, closeTo(900 - gap, 0.01));
      await ptr(t, up(41, const Offset(-9000, 200), 40));
      await ptr(t, up(42, const Offset(-8900, 200), 40));
    });

    testWidgets('menu: items, +/- about the center, % and limits', (t) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t);
      await menu(t);
      expect(find.text('Fit width'), findsOneWidget);
      expect(find.text('Fit page'), findsOneWidget);
      expect(find.byTooltip('Zoom out'), findsOneWidget);
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      final s0 = viewport(t).scale;
      expect(
        find.bySemanticsLabel('Zoom ${(s0 * 100).round()}%'),
        findsOneWidget,
      );
      expect(find.text('${(s0 * 100).round()}%'), findsOneWidget);

      // 48 dp everywhere.
      for (final f in [
        find.byTooltip('Zoom out'),
        find.byTooltip('Zoom in'),
        find.byTooltip('More'),
        find.widgetWithText(MenuItemButton, 'Fit width'),
        find.widgetWithText(MenuItemButton, 'Fit page'),
      ]) {
        expect(t.getSize(f).width, greaterThanOrEqualTo(48));
        expect(t.getSize(f).height, greaterThanOrEqualTo(48));
      }

      const center = Offset(450, 350);
      final p = viewport(t).toPage(center);
      await t.tap(find.byTooltip('Zoom in'));
      await t.pumpAndSettle();
      final v1 = viewport(t);
      expect(v1.scale, closeTo(s0 * 1.25, 1e-9));
      expect(find.byTooltip('Zoom in'), findsOneWidget); // menu stays open
      expect(
        find.bySemanticsLabel('Zoom ${(v1.scale * 100).round()}%'),
        findsOneWidget,
      );
      expect(v1.toPage(center).dx, closeTo(p.dx, 1e-6));
      expect(v1.toPage(center).dy, closeTo(p.dy, 1e-6));

      // Up to the top: + is disabled at 400%.
      for (
        var i = 0;
        i < 10 && iconButton(t, Icons.add).onPressed != null;
        i++
      ) {
        await t.tap(find.byTooltip('Zoom in'));
        await t.pumpAndSettle();
      }
      expect(viewport(t).scale, PageViewport.zoomMax);
      expect(find.text('400%'), findsOneWidget);
      expect(iconButton(t, Icons.add).onPressed, isNull);
      h.dispose();
    });

    testWidgets('minus disables at 50%', (t) async {
      seed(_note());
      await open(t);
      await pinch(t, const Offset(400, 300), const Offset(402, 300));
      await menu(t);
      expect(viewport(t).scale, PageViewport.zoomMin);
      expect(find.text('50%'), findsOneWidget);
      expect(iconButton(t, Icons.remove).onPressed, isNull);
    });

    testWidgets('fit width / fit page stay fit when the screen changes', (
      t,
    ) async {
      seed(_note());
      await open(t);
      await pinch(t, const Offset(400, 300), const Offset(402, 300));
      await menu(t);
      await t.tap(find.text('Fit page'));
      await t.pumpAndSettle();
      final vp = viewport(t);
      expect(vp.scale, lessThan(1.0)); // 842 pt in ~700 dp
      expect(
        vp.offset.dy + 842 * vp.scale,
        lessThanOrEqualTo(700 - gap + 1e-6),
      );

      t.view.physicalSize = const Size(600, 900);
      await t.pumpAndSettle();
      final fitted = viewport(t);
      expect(fitted.scale, isNot(vp.scale));
      expect(fitted.offset.dy + 842 * fitted.scale, lessThanOrEqualTo(900));

      await menu(t);
      await t.tap(find.text('Fit width'));
      await t.pumpAndSettle();
      expect(viewport(t).scale, closeTo((600 - 2 * gap) / 595, 1e-9));
      t.view.physicalSize = const Size(800, 900);
      await t.pumpAndSettle();
      expect(viewport(t).scale, closeTo((800 - 2 * gap) / 595, 1e-9));

      // After a zoom step the scale is not re-fitted.
      await menu(t);
      await t.tap(find.byTooltip('Zoom in'));
      await t.pumpAndSettle();
      final z = viewport(t).scale;
      t.view.physicalSize = const Size(700, 900);
      await t.pumpAndSettle();
      expect(viewport(t).scale, z);
    });

    testWidgets('writing at zoom stores page points', (t) async {
      seed(_note());
      await open(t);
      await pinch(t, const Offset(300, 300), const Offset(500, 300));
      expect(viewport(t).scale, greaterThan(2.5));
      await draw(t, const [(100, 100, 0.5), (130, 120, 0.5), (160, 100, 0.5)]);
      await settle(t);
      final st = elements().single as Map;
      final pts = (st['points'] as List).cast<List>();
      expect(pts.first[0], closeTo(100, 0.01));
      expect(pts[1][1], closeTo(120, 0.01));
      expect(st['width'], 2); // pt width; drawn at width * scale
    });

    testWidgets('no animation: the menu changes the zoom in one frame', (
      t,
    ) async {
      seed(_note());
      await open(t);
      await menu(t);
      final s0 = viewport(t).scale;
      // With animation the first frame has not reached the target.
      await t.tap(find.byTooltip('Zoom in'));
      await t.pump();
      expect(viewport(t).scale, closeTo(s0, 1e-6));
      await t.pumpAndSettle();
      final s1 = viewport(t).scale;
      expect(s1, closeTo(s0 * 1.25, 1e-9));

      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await t.pump();
      await t.tap(find.byTooltip('Zoom in'));
      await t.pump();
      expect(viewport(t).scale, closeTo(s1 * 1.25, 1e-9));
    });

    testWidgets('Korean names', (t) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t, device: const [Locale('ko', 'KR')]);
      await t.tap(find.byTooltip('더 보기'));
      await t.pumpAndSettle();
      expect(find.byTooltip('축소'), findsOneWidget);
      expect(find.byTooltip('확대'), findsOneWidget);
      expect(find.text('너비 맞춤'), findsOneWidget);
      expect(find.text('페이지 맞춤'), findsOneWidget);
      final pct = (viewport(t).scale * 100).round();
      expect(find.bySemanticsLabel('배율 $pct%'), findsOneWidget);
      h.dispose();
    });

    testWidgets('resize while free keeps the page inside the clamp', (t) async {
      seed(_note());
      await open(t);
      await pinch(t, const Offset(300, 300), const Offset(500, 300));
      // Drag the page to its far bottom, then shrink the screen.
      await ptr(t, down(41, const Offset(300, 200), 0));
      await ptr(t, down(42, const Offset(400, 200), 5));
      await ptr(t, move(41, const Offset(300, -9000), 10));
      await ptr(t, move(42, const Offset(400, -9000), 10));
      await ptr(t, up(41, const Offset(300, -9000), 20));
      await ptr(t, up(42, const Offset(400, -9000), 20));
      final s = viewport(t).scale;
      t.view.physicalSize = const Size(600, 500);
      await t.pumpAndSettle();
      final vp = viewport(t);
      final tb = t.getRect(find.byType(PenToolbar));
      expect(vp.scale, s);
      expect(vp.offset.dy, lessThanOrEqualTo(tb.bottom + gap + 1e-6));
      expect(
        vp.offset.dy + 842 * s,
        greaterThanOrEqualTo(500 - gap - (tb.height + gap) - 1e-6),
      );
      expect(vp.offset.dx, lessThanOrEqualTo(gap + 1e-6));
      expect(vp.offset.dx + 595 * s, greaterThanOrEqualTo(600 - gap - 1e-6));
    });

    testWidgets('cancel of a gesture pointer: no stroke, then input works', (
      t,
    ) async {
      seed(_note());
      await open(t);
      await pinch(
        t,
        const Offset(300, 300),
        const Offset(450, 300),
        release: false,
      );
      await ptr(
        t,
        PointerCancelEvent(
          pointer: 32,
          kind: PointerDeviceKind.touch,
          position: const Offset(450, 300),
          timeStamp: const Duration(milliseconds: 50),
        ),
      );
      await ptr(t, up(31, const Offset(300, 300), 60));
      await settle(t);
      expect(elements(), isEmpty);
      await draw(t, line, kind: PointerDeviceKind.touch);
      await settle(t);
      expect(elements(), hasLength(1));
    });

    testWidgets('first finger off the page, second within 150 ms: pinch', (
      t,
    ) async {
      seed(_note());
      await open(t);
      final s0 = viewport(t).scale;
      await ptr(t, down(1, const Offset(5, 400), 0)); // gray margin
      await ptr(t, down(2, const Offset(300, 400), 100));
      await ptr(t, move(2, const Offset(600, 400), 110));
      expect(viewport(t).scale, isNot(s0));
      await ptr(t, up(1, const Offset(5, 400), 120));
      await ptr(t, up(2, const Offset(600, 400), 120));
      await settle(t);
      expect(elements(), isEmpty);
    });

    testWidgets('two quick + taps end at 1.25 squared', (t) async {
      seed(_note());
      await open(t);
      await menu(t);
      final s0 = viewport(t).scale;
      await t.tap(find.byTooltip('Zoom in'));
      await t.pump();
      await t.tap(find.byTooltip('Zoom in'));
      await t.pumpAndSettle();
      expect(viewport(t).scale, closeTo(s0 * 1.25 * 1.25, 1e-9));
    });

    testWidgets('a touch during a zoom animation maps with the target', (
      t,
    ) async {
      seed(_note());
      await open(t);
      await menu(t);
      await t.tap(find.byTooltip('Zoom in'));
      await t.pump(); // animation running
      const at = Offset(200, 400);
      await ptr(t, down(1, at, 0));
      await ptr(t, up(1, at, 10));
      await settle(t);
      final want = viewport(t).toPage(at);
      final pts = ((elements().single as Map)['points'] as List).cast<List>();
      expect(pts, hasLength(1));
      expect(pts.first[0], closeTo(want.dx, 0.01));
      expect(pts.first[1], closeTo(want.dy, 0.01));
    });

    testWidgets('a finger left down is never ink after the stylus ends', (
      t,
    ) async {
      seed(_note());
      await open(t);
      await ptr(t, down(1, onScreen(t, 100, 100), 0));
      await draw(t, line); // stylus takes over, the finger stays down
      await settle(t);
      await ptr(t, down(2, onScreen(t, 300, 300), 1000));
      await ptr(t, move(2, onScreen(t, 340, 320), 1010));
      await ptr(t, up(2, onScreen(t, 340, 320), 1020));
      await ptr(t, up(1, onScreen(t, 100, 100), 1030));
      await settle(t);
      expect(elements(), hasLength(1)); // the stylus stroke only
    });

    test('PageViewport: fitWidth, clamped, zoomAbout', () {
      const size = Size(900, 700);
      const pad = EdgeInsets.fromLTRB(12, 80, 12, 12);
      final fw = PageViewport.fitWidth(size, 595, 842, pad);
      expect(fw.scale, closeTo(876 / 595, 1e-9));
      expect(fw.offset.dx, closeTo(12, 1e-9));
      expect(fw.offset.dy, 80);
      expect(
        PageViewport.fitWidth(const Size(60, 700), 595, 842, pad).scale,
        PageViewport.zoomMin,
      );
      expect(
        PageViewport.fitWidth(const Size(9000, 700), 100, 100, pad).scale,
        PageViewport.zoomMax,
      );

      // Large axis: edges stop at the padding; extra room below.
      const near = PageViewport(2, Offset(500, 500));
      final c = near.clamped(size, 595, 842, pad, extraBottom: 60);
      expect(c.offset.dx, closeTo(12, 1e-9));
      expect(c.offset.dy, 80);
      const farAway = PageViewport(2, Offset(-9000, -9000));
      final far = farAway.clamped(size, 595, 842, pad, extraBottom: 60);
      expect(far.offset.dx + 595 * 2, closeTo(900 - 12, 1e-9));
      expect(far.offset.dy + 842 * 2, closeTo(700 - 12 - 60, 1e-9));
      // Small axis: centered, whatever the offset.
      const tiny = PageViewport(0.5, Offset(-300, 700));
      final small = tiny.clamped(size, 595, 842, pad);
      expect(small.offset.dx, closeTo((900 - 595 * 0.5) / 2, 1e-9));
      expect(small.offset.dy, closeTo(80 + (608 - 842 * 0.5) / 2, 1e-9));

      // zoomAbout keeps the point under the focal; the scale is cut.
      const v = PageViewport(1.5, Offset(30, 60));
      const f = Offset(400, 300);
      final z = v.zoomAbout(f, 3);
      expect(z.scale, 3);
      final a = v.toPage(f), b = z.toPage(f);
      expect(b.dx, closeTo(a.dx, 1e-9));
      expect(b.dy, closeTo(a.dy, 1e-9));
      expect(v.zoomAbout(f, 99).scale, PageViewport.zoomMax);
      expect(v.zoomAbout(f, 0.01).scale, PageViewport.zoomMin);
    });
  });

  group('undo / redo', () {
    Map page() => decodeKkj(file.readAsBytesSync()).note!.pages.first;
    Finder btn(String tip) => find.byTooltip(tip);
    Map viewportPage(WidgetTester t) {
      final w =
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
      return (w.painter as PagePainter).page;
    }

    bool enabled(WidgetTester t, String tip) {
      final f = t.getSemantics(btn(tip)).getSemanticsData().flagsCollection;
      return f.isEnabled == Tristate.isTrue;
    }

    Future<void> tap(WidgetTester t, String tip) async {
      await t.tap(btn(tip));
      await settle(t);
    }

    testWidgets('buttons: after the pen slot, 48dp, disabled when empty', (
      t,
    ) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t);
      expect(enabled(t, 'Undo'), isFalse);
      expect(enabled(t, 'Redo'), isFalse);
      for (final tip in ['Undo', 'Redo']) {
        final s = t.getSize(btn(tip));
        expect(s.width, greaterThanOrEqualTo(48));
        expect(s.height, greaterThanOrEqualTo(48));
      }
      final slot = t.getRect(find.bySemanticsLabel('Pen, Black, width 2.0'));
      expect(t.getRect(btn('Undo')).left, greaterThan(slot.right));
      expect(
        t.getRect(btn('Redo')).left,
        greaterThan(t.getRect(btn('Undo')).left),
      );
      // Pressing a disabled button changes nothing.
      final before = file.readAsBytesSync();
      await tap(t, 'Undo');
      expect(file.readAsBytesSync(), before);
      h.dispose();
    });

    testWidgets('undo removes the stroke, redo brings it back', (t) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t);
      await draw(t, line);
      await draw(t, line.map((p) => (p.$1, p.$2 + 40, p.$3)).toList());
      await settle(t);
      final stroke2 = Map.of(elements().last as Map);
      final p0 = page();
      expect(enabled(t, 'Undo'), isTrue);
      expect(enabled(t, 'Redo'), isFalse);

      await tap(t, 'Undo');
      var p1 = page();
      expect(elements(), hasLength(1));
      expect(p1['rev'], isNot(p0['rev']));
      expect(p1['seq'], (p0['seq'] as int) + 1);
      expect(enabled(t, 'Redo'), isTrue);

      await tap(t, 'Redo');
      final p2 = page();
      expect(elements(), hasLength(2));
      expect(elements().last, stroke2);
      expect(p2['rev'], isNot(p1['rev']));
      expect(p2['seq'], (p1['seq'] as int) + 1);
      expect(enabled(t, 'Redo'), isFalse);
      h.dispose();
    });

    testWidgets('a new stroke clears redo', (t) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t);
      await draw(t, line);
      await settle(t);
      await tap(t, 'Undo');
      expect(enabled(t, 'Redo'), isTrue);
      await draw(t, line);
      await settle(t);
      expect(enabled(t, 'Redo'), isFalse);
      expect(enabled(t, 'Undo'), isTrue);
      h.dispose();
    });

    testWidgets('no effect while a stroke is in progress', (t) async {
      seed(_note());
      await open(t);
      await draw(t, line);
      await settle(t);
      final before = file.readAsBytesSync();
      await draw(t, line, up: false); // pen still down
      final id = pointer;
      final undo = t.getCenter(btn('Undo'));
      final finger = await t.startGesture(undo, kind: PointerDeviceKind.touch);
      await finger.up();
      await settle(t);
      expect(file.readAsBytesSync(), before);
      t.binding.handlePointerEvent(
        PointerUpEvent(
          pointer: id,
          kind: PointerDeviceKind.stylus,
          position: onScreen(t, 250, 200),
          timeStamp: const Duration(milliseconds: 100),
        ),
      );
      await settle(t);
      expect(elements(), hasLength(2)); // the stroke went on and was kept
    });

    testWidgets('queued saves end with the last state', (t) async {
      seed(_note());
      final gate = Completer<void>();
      var calls = 0, active = 0, maxActive = 0;
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
      await t.tap(btn('Undo'));
      await t.pump();
      await t.tap(btn('Undo'));
      await t.pump();
      await t.tap(btn('Redo'));
      await t.pump();
      gate.complete();
      await settle(t);
      expect(maxActive, 1);
      expect(elements(), hasLength(1)); // two undone, one redone
    });

    testWidgets('history survives library round trip, not a new process', (
      t,
    ) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t);
      await draw(t, line);
      await settle(t);
      await t.tap(find.byTooltip('Back to library'));
      await settle(t);
      await t.tap(find.text('Lecture'));
      await settle(t);
      expect(enabled(t, 'Undo'), isTrue);
      await tap(t, 'Undo');
      expect(elements(), isEmpty);

      // A new app process: empty history, the file is as it was saved.
      await t.pumpWidget(const SizedBox());
      await open(t);
      expect(enabled(t, 'Undo'), isFalse);
      expect(enabled(t, 'Redo'), isFalse);
      h.dispose();
    });

    testWidgets('a failed save leaves the screen undone, next save heals', (
      t,
    ) async {
      seed(_note());
      var fail = false;
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
      fail = true;
      await tap(t, 'Undo');
      expect(find.text("Couldn't save to this device."), findsOneWidget);
      expect(elements(), hasLength(1)); // file still has the stroke
      fail = false;
      await tap(t, 'Redo');
      expect(elements(), hasLength(1));
      await tap(t, 'Undo');
      expect(elements(), isEmpty);
    });

    testWidgets('reopening after a failed save starts a fresh history', (
      t,
    ) async {
      final h = t.ensureSemantics();
      seed(_note());
      final store = NoteStore(
        data,
        writeFile: (f, b) async => throw const FileSystemException('disk full'),
      );
      await open(t, store: store);
      await draw(t, line);
      await settle(t);
      await t.tap(find.byTooltip('Back to library'));
      await settle(t);
      expect(find.byType(NoteEditor), findsNothing);
      await t.tap(find.text('Lecture'));
      await settle(t);
      expect(enabled(t, 'Undo'), isFalse);
      expect(viewportPage(t)['elements'], isEmpty);
      expect(elements(), isEmpty);
      h.dispose();
    });

    testWidgets('history is dropped when the note meta differs', (t) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t);
      await draw(t, line);
      await settle(t);
      // Renamed on disk (as another writer would); leaving reloads the list.
      final j = decodeKkj(file.readAsBytesSync()).note!.copyJson();
      (j['meta'] as Map)['title'] = 'Renamed';
      file.writeAsBytesSync(encodeKkj(Note.trusted(j)));
      await t.tap(find.byTooltip('Back to library'));
      await settle(t);
      await t.tap(find.text('Renamed'));
      await settle(t);
      expect(find.byType(NoteEditor), findsOneWidget);
      expect(enabled(t, 'Undo'), isFalse);
      h.dispose();
    });

    testWidgets('undo while leaving does nothing', (t) async {
      seed(_note());
      final gate = Completer<void>();
      var calls = 0;
      final store = NoteStore(
        data,
        writeFile: (f, b) async {
          if (++calls == 1) await gate.future;
          await f.writeAsBytes(b);
        },
      );
      await open(t, store: store);
      await draw(t, line);
      await t.tap(find.byTooltip('Back to library'));
      await t.pump();
      await t.tap(btn('Undo'));
      await t.pump();
      gate.complete();
      await settle(t);
      expect(find.byType(NoteEditor), findsNothing);
      expect(elements(), hasLength(1));
    });

    testWidgets('Korean names', (t) async {
      seed(_note());
      await open(t, device: const [Locale('ko', 'KR')]);
      expect(find.byTooltip('실행 취소'), findsOneWidget);
      expect(find.byTooltip('다시 실행'), findsOneWidget);
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

  group('pen pressure toggle', () {
    final slot = find.descendant(
      of: find.byType(PenToolbar),
      matching: find.byType(InkResponse),
    );
    final off = jsonEncode([
      {'color': '#000000', 'width': 2.0, 'usePressure': false},
    ]);

    Future<void> openPopover(WidgetTester t) async {
      await t.tap(slot);
      await settle(t);
      expect(find.byType(PenEditDialog), findsOneWidget);
    }

    Future<String?> stored() async =>
        (await SharedPreferences.getInstance()).getString('penSlots');

    PenPreviewPainter preview(WidgetTester t) =>
        (t
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(PenEditDialog),
                        matching: find.byWidgetPredicate(
                          (w) => w is CustomPaint && w.painter is PenPreviewPainter,
                        ),
                      ),
                    )
                    .painter!
                as PenPreviewPainter);

    testWidgets('re-tap opens popover: title, switch on, preview', (t) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t);
      await openPopover(t);
      expect(find.text('Pen'), findsOneWidget);
      expect(find.text('Use pressure'), findsOneWidget);
      expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(preview(t).pen.usePressure, isTrue);
      final sw = t.getSemantics(find.bySemanticsLabel('Use pressure'));
      expect(sw.getSemanticsData().flagsCollection.isToggled, Tristate.isTrue);
      expect(
        t.getSize(find.bySemanticsLabel('Use pressure')).height,
        greaterThanOrEqualTo(48),
      );
      h.dispose();
    });

    testWidgets('off: saved at once, flat preview, next stroke false', (
      t,
    ) async {
      seed(_note());
      await open(t);
      await draw(t, line); // one stroke made with pressure on
      await settle(t);
      await openPopover(t);
      final pressureOnPoly = preview(t).polygon;
      await t.tap(find.text('Use pressure'));
      await t.pump();
      expect(jsonDecode((await stored())!)[0]['usePressure'], isFalse);
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
      final flat = preview(t);
      expect(flat.pen.usePressure, isFalse);
      expect(flat.polygon, isNot(pressureOnPoly));
      // Closing keeps the change.
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      expect(find.byType(PenEditDialog), findsNothing);
      await draw(t, line);
      await settle(t);
      final els = elements().cast<Map<String, dynamic>>();
      expect(els, hasLength(2));
      expect(els[0]['usePressure'], isTrue); // existing stroke unchanged
      expect(els[1]['usePressure'], isFalse);
      expect(
        (els[1]['points'] as List).map((p) => (p as List)[2]),
        [0.2, 0.5, 0.9, 0.7],
      );
    });

    testWidgets('a stored false applies to a new session', (t) async {
      seed(_note());
      await pumpApp(t, noteData: data, prefs: {'penSlots': off});
      await settle(t);
      await t.tap(find.text('Lecture'));
      await settle(t);
      await draw(t, line);
      await settle(t);
      expect((elements().single as Map)['usePressure'], isFalse);
      await openPopover(t);
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('a corrupt stored value falls back to the default pen', (
      t,
    ) async {
      seed(_note());
      await pumpApp(t, noteData: data, prefs: {'penSlots': '{"x":1}'});
      await settle(t);
      await t.tap(find.text('Lecture'));
      await settle(t);
      await draw(t, line);
      await settle(t);
      expect((elements().single as Map)['usePressure'], isTrue);
    });

    testWidgets('barrier tap closes, change kept, focus on the slot', (
      t,
    ) async {
      seed(_note());
      await open(t);
      await openPopover(t);
      await t.tap(find.text('Use pressure'));
      await t.pump();
      await t.tapAt(const Offset(5, 400));
      await settle(t);
      expect(find.byType(PenEditDialog), findsNothing);
      expect(jsonDecode((await stored())!)[0]['usePressure'], isFalse);
      final ink = t.widget<InkResponse>(
        find.descendant(
          of: find.byType(PenToolbar),
          matching: find.byType(InkResponse),
        ),
      );
      expect(ink.focusNode!.hasPrimaryFocus, isTrue);
    });

    testWidgets('no popover while a stylus is down', (t) async {
      seed(_note());
      await open(t);
      final id = ++pointer;
      await ptr(
        t,
        down(
          id,
          onScreen(t, 100, 100),
          0,
          kind: PointerDeviceKind.stylus,
        ),
      );
      await t.tap(slot);
      await t.pump();
      expect(find.byType(PenEditDialog), findsNothing);
      await ptr(
        t,
        up(id, onScreen(t, 100, 100), 10, kind: PointerDeviceKind.stylus),
      );
      await t.tap(slot);
      await settle(t);
      expect(find.byType(PenEditDialog), findsOneWidget);
    });

    testWidgets('Korean strings', (t) async {
      final h = t.ensureSemantics();
      seed(_note());
      await open(t, device: const [Locale('ko', 'KR')]);
      await t.tap(slot);
      await settle(t);
      expect(find.text('펜'), findsOneWidget);
      expect(find.bySemanticsLabel('필압 반영'), findsOneWidget);
      h.dispose();
    });
  });
}
