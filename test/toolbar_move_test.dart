import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/toolbar_pos.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/platform/gesture_exclusion.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Note _note() => createNote(
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
).note!;

void main() {
  late Directory docs;
  late NoteData data;
  final sent = <Map>[];

  setUp(() {
    resetStylusSeen();
    docs = Directory.systemTemp.createTempSync('kkj-toolbar-');
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

  Future<void> open(
    WidgetTester t, {
    Map<String, Object> prefs = const {},
    double width = 900,
  }) async {
    sent.clear();
    t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (m) async {
        sent.add(m as Map);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    await pumpApp(t, noteData: data, prefs: prefs, width: width);
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
  }

  Map<String, Object> stored(double x, double y, String dock, bool v) => {
    'toolbarPos': jsonEncode({'dock': dock, 'x': x, 'y': y, 'vertical': v}),
  };

  ProviderContainer box(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(NoteEditor)));

  ToolbarPos pos(WidgetTester t) => box(t).read(toolbarPosProvider);

  Rect bar(WidgetTester t) => t.getRect(find.byType(PenToolbar));

  PenToolbar tb(WidgetTester t) =>
      t.widget<PenToolbar>(find.byType(PenToolbar));

  // The handle, a point 25 dp in from the toolbar's corner.
  Offset handle(WidgetTester t) =>
      t.getTopLeft(find.byType(PenToolbar)) + const Offset(25, 17);

  // Long-press the handle; returns the finger's offset from the bar center.
  Future<(TestGesture, Offset)> grab(WidgetTester t) async {
    final at = handle(t);
    final g = await t.startGesture(at);
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    return (g, at - bar(t).center);
  }

  List<Map> announced() => [
    for (final m in sent)
      if (m['type'] == 'announce') m['data'] as Map,
  ];

  Future<void> dockVia(WidgetTester t, String name) async {
    await t.tapAt(handle(t));
    await t.pumpAndSettle();
    await t.tap(find.text(name), warnIfMissed: false);
    await t.pumpAndSettle();
  }

  group('drag', () {
    testWidgets('long press drag to the left edge docks it vertical', (
      t,
    ) async {
      await open(t);
      expect(pos(t), ToolbarPos.defaults);
      final (g, off) = await grab(t);
      expect(find.byType(SnapOutline), findsNWidgets(4));
      await g.moveTo(const Offset(40, 350) + off);
      await t.pump();
      final lit = t
          .widgetList<SnapOutline>(find.byType(SnapOutline))
          .where((o) => o.highlighted);
      expect(lit, hasLength(1));
      expect(
        t
            .widget<SnapOutline>(find.byKey(const ValueKey(ToolbarDock.left)))
            .highlighted,
        isTrue,
      );
      await g.up();
      await t.pumpAndSettle();
      expect(find.byType(SnapOutline), findsNothing);
      expect(pos(t).dock, ToolbarDock.left);
      expect(pos(t).vertical, isTrue);
      expect(tb(t).vertical, isTrue);
      expect(bar(t).left, 12);
      expect(bar(t).center.dy, closeTo(380, 1)); // under the corner buttons
      expect(bar(t).top, greaterThanOrEqualTo(12 + 48));
      expect(box(t).read(penSlotsStoreProvider).readToolbar(), pos(t));
    });

    testWidgets('dropped far from every outline it floats, same direction', (
      t,
    ) async {
      await open(t);
      final (g, off) = await grab(t);
      await g.moveTo(const Offset(450, 350) + off);
      await g.up();
      await t.pumpAndSettle();
      expect(pos(t).dock, ToolbarDock.float);
      expect(pos(t).vertical, isFalse);
      expect(pos(t).x, closeTo(0.5, 0.01));
      expect(pos(t).y, closeTo(0.5, 0.01));
      expect(bar(t).center.dy, closeTo(350, 1));
    });

    testWidgets('Esc during the drag puts it back and saves nothing', (
      t,
    ) async {
      await open(t);
      final before = bar(t);
      final (g, off) = await grab(t);
      await g.moveTo(const Offset(450, 350) + off);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(find.byType(SnapOutline), findsNothing);
      await g.up();
      await t.pumpAndSettle();
      expect(pos(t), ToolbarPos.defaults);
      expect(bar(t), before);
    });

    testWidgets('a pointer cancel does the same', (t) async {
      await open(t);
      final before = bar(t);
      final (g, off) = await grab(t);
      await g.moveTo(const Offset(450, 350) + off);
      await t.pump();
      await g.cancel();
      await t.pumpAndSettle();
      expect(find.byType(SnapOutline), findsNothing);
      expect(pos(t), ToolbarPos.defaults);
      expect(bar(t), before);
    });
  });

  group('menu', () {
    testWidgets('a tap opens it; choosing docks, saves, announces politely', (
      t,
    ) async {
      await open(t);
      await t.tapAt(handle(t));
      await t.pumpAndSettle();
      for (final s in ['Top', 'Left', 'Right', 'Bottom']) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.byType(SnapOutline), findsNothing); // a tap is not a drag
      await t.tap(find.text('Left'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(pos(t).dock, ToolbarDock.left);
      expect(pos(t).vertical, isTrue);
      final a = announced().where(
        (a) => a['message'] == 'Toolbar docked: Left',
      );
      expect(a, hasLength(1));
      expect(a.single['assertiveness'], isNot(1)); // polite
      await dockVia(t, 'Bottom');
      expect(pos(t).dock, ToolbarDock.bottom);
      expect(pos(t).vertical, isFalse);
      expect(bar(t).bottom, 700 - 12);
    });

    testWidgets('an outside tap closes it without a change', (t) async {
      await open(t);
      await t.tapAt(handle(t));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(450, 500));
      await t.pumpAndSettle();
      expect(find.text('Left'), findsNothing);
      expect(pos(t), ToolbarPos.defaults);
    });

    testWidgets('the TalkBack custom action opens the same menu', (t) async {
      final h = t.ensureSemantics();
      await open(t);
      final node = t.getSemantics(find.bySemanticsLabel('Move toolbar'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      final id = data.customSemanticsActionIds!.single;
      // ignore: deprecated_member_use
      t.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        id,
      );
      await t.pumpAndSettle();
      expect(find.text('Right'), findsOneWidget);
      h.dispose();
    });
  });

  group('layout', () {
    testWidgets('vertical bars keep the item order, top to bottom', (t) async {
      await open(t, prefs: stored(0.5, 0, 'left', true));
      expect(tb(t).vertical, isTrue);
      expect(bar(t).left, 12);
      expect(bar(t).width, PenToolbar.verticalWidth);
      final ys = [
        for (final tip in [
          'Add pen slot',
          'Undo',
          'Redo',
          'Eraser (Stroke)',
          'Lasso',
          'Text',
          'Image',
        ])
          t.getCenter(find.byTooltip(tip)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(ys.toSet(), hasLength(ys.length));
      await dockVia(t, 'Right');
      expect(bar(t).right, 900 - 12);
    });

    testWidgets('restart: the same position and direction', (t) async {
      await open(t, prefs: stored(0.25, 0.6, 'float', true));
      expect(tb(t).vertical, isTrue);
      expect(bar(t).center.dx, closeTo(225, 1));
      expect(bar(t).center.dy, closeTo(420, 1));
    });

    testWidgets('top, narrow: wraps under the corners', (t) async {
      await open(t, width: 400);
      expect(bar(t).top, 12 + 48);
      expect(bar(t).left, greaterThanOrEqualTo(12));
      expect(bar(t).right, lessThanOrEqualTo(400 - 12));
    });

    testWidgets('top, wide: in the corner row', (t) async {
      await open(t);
      expect(bar(t).top, 12);
      expect(bar(t).center.dx, closeTo(450, 1));
    });

    testWidgets('the pen popover steps aside for a vertical bar', (t) async {
      await open(t, prefs: stored(0.5, 0, 'left', true));
      await t.tap(find.byTooltip('Add pen slot'));
      await t.pumpAndSettle();
      expect(find.byType(PenEditDialog), findsOneWidget);
      expect(
        t
            .getRect(
              find.descendant(
                of: find.byType(PenEditDialog),
                matching: find.byType(SingleChildScrollView),
              ),
            )
            .left,
        greaterThanOrEqualTo(bar(t).right),
      );
    });

    testWidgets('a slot list taller than the screen scrolls', (t) async {
      await open(t, prefs: stored(0.5, 0, 'left', true));
      for (var i = 0; i < 9; i++) {
        box(t).read(penSlotsProvider.notifier).add();
      }
      await t.pumpAndSettle();
      expect(bar(t).height, lessThanOrEqualTo(700 - 24));
      expect(find.byTooltip('Show earlier slots'), findsOneWidget);
    });
  });

  group('rotation', () {
    testWidgets('a floating bar is pulled back; the stored value stays', (
      t,
    ) async {
      await open(t, prefs: stored(0.95, 0.5, 'float', false));
      expect(bar(t).right, lessThanOrEqualTo(900 - 12));
      t.view.physicalSize = const Size(500, 700);
      await t.pumpAndSettle();
      expect(bar(t).right, lessThanOrEqualTo(500 - 12));
      expect(bar(t).left, greaterThanOrEqualTo(12));
      expect(pos(t).x, 0.95);
      t.view.physicalSize = const Size(900, 700);
      await t.pumpAndSettle();
      expect(bar(t).right, lessThanOrEqualTo(900 - 12));
      expect(pos(t).dock, ToolbarDock.float);
    });

    testWidgets('pulled back next to an outline: it docks there, saved', (
      t,
    ) async {
      await open(t, prefs: stored(0.99, 0.5, 'float', true));
      expect(pos(t).dock, ToolbarDock.float); // not on the first layout
      t.view.physicalSize = const Size(700, 900);
      await t.pumpAndSettle();
      expect(pos(t).dock, ToolbarDock.right);
      expect(
        box(t).read(penSlotsStoreProvider).readToolbar().dock,
        ToolbarDock.right,
      );
    });
  });

  testWidgets('back gesture: a left bar sends its rect, moving removes it', (
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
    await open(t, prefs: stored(0.5, 0, 'left', true));
    await t.pump();
    final r = bar(t);
    // Android honors 200 dp per edge: clipped around the middle.
    expect(calls.last, [
      [r.left, r.center.dy - 100, r.right, r.center.dy + 100],
    ]);
    await dockVia(t, 'Right');
    expect(calls.last, isEmpty);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.kkeujeok.app/gesture'),
      null,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('animations off: the bar lands at once', (t) async {
    await open(t);
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.tapAt(handle(t));
    await t.pumpAndSettle();
    await t.tap(find.text('Bottom'), warnIfMissed: false);
    await t.pump(); // the menu closes and the bar is set
    await t.pump();
    expect(bar(t).bottom, 700 - 12);
  });
}
