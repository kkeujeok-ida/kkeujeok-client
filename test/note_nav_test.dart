// Story 5.13 / 15.12: previous / next note by three fingers.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/element_clipboard.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/toolbar_pos.dart';
import 'package:kkeujeok/model/text_metrics.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Note _note(int n, String title) => createNote(
  title: title,
  existingTitles: const [],
  background: 'plain',
  orientation: 'portrait',
  noteId: _id(n),
  pageId: _id(1000 + n),
  pageRev: _id(2000 + n),
  metaRev: _id(3000 + n),
  orderRev: _id(4000 + n),
  now: '2000-01-01T12:00:00.000Z',
  editedBy: 'Pixel 8',
).note!;

void main() {
  late Directory docs;
  late NoteData data;
  late NoteStore store;

  setUpAll(() {
    TextMetrics.install(
      File('assets/fonts/Pretendard-Regular.otf').readAsBytesSync(),
      File('assets/fonts/Pretendard-SemiBold.otf').readAsBytesSync(),
    );
  });

  setUp(() {
    resetStylusSeen();
    docs = Directory.systemTemp.createTempSync('kkj-nav-');
    data = NoteData(() async => docs);
    store = NoteStore(data);
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // The OS cleans temp up later.
      }
    });
  });

  File fileOf(int n) =>
      File('${docs.path}/$noteDataDirName/${_id(n)}/working.kkj');

  void seed(Note n, int i) {
    fileOf(i)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(encodeKkj(n));
  }

  void seedAll() {
    seed(_note(1, 'Alpha'), 1);
    seed(_note(2, 'Beta'), 2);
    seed(_note(3, 'Gamma'), 3);
  }

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

  Future<void> open(WidgetTester t, String title) async {
    await pumpApp(t, noteData: data, noteStore: store);
    await settle(t);
    await t.tap(find.text(title));
    await settle(t);
    expect(find.byType(NoteEditor), findsOneWidget);
  }

  String shown(WidgetTester t) =>
      t.widget<NoteEditor>(find.byType(NoteEditor)).note.title;

  var ptr = 100;
  var clock = 10000; // ms; the test gestures all stamp zero, so stamp here

  Future<void> three(
    WidgetTester t,
    Offset delta, {
    int gapMs = 0, // the third finger lands this late
    bool wait = true,
  }) async {
    final ids = [for (var i = 0; i < 3; i++) ++ptr];
    clock += 1000;
    final from = [for (var i = 0; i < 3; i++) Offset(350 + i * 60.0, 400)];
    for (var i = 0; i < 3; i++) {
      t.binding.handlePointerEvent(
        PointerDownEvent(
          pointer: ids[i],
          kind: PointerDeviceKind.touch,
          position: from[i],
          timeStamp: Duration(milliseconds: clock + (i == 2 ? gapMs : i * 10)),
        ),
      );
    }
    for (var i = 0; i < 3; i++) {
      t.binding.handlePointerEvent(
        PointerMoveEvent(
          pointer: ids[i],
          kind: PointerDeviceKind.touch,
          position: from[i] + delta,
          delta: delta,
          timeStamp: Duration(milliseconds: clock + 400),
        ),
      );
    }
    for (var i = 0; i < 3; i++) {
      t.binding.handlePointerEvent(
        PointerUpEvent(
          pointer: ids[i],
          kind: PointerDeviceKind.touch,
          position: from[i] + delta,
          timeStamp: Duration(milliseconds: clock + 450),
        ),
      );
    }
    if (wait) await settle(t);
  }

  testWidgets('menu has no previous / next note', (t) async {
    seedAll();
    await open(t, 'Alpha');
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(find.text('Previous note'), findsNothing);
    expect(find.text('Next note'), findsNothing);
  });

  testWidgets('three fingers: chip, small back button bottom left, expiry', (
    t,
  ) async {
    seedAll();
    await open(t, 'Alpha');
    await three(t, const Offset(-80, 0));
    expect(shown(t), 'Beta');
    expect(find.text('Beta · 2/3'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final btn = find.widgetWithText(FilledButton, 'Back');
    expect(btn, findsOneWidget);
    final r = t.getRect(btn);
    expect(r.height, greaterThanOrEqualTo(48));
    expect(r.left, lessThan(200));
    expect(
      r.center.dy,
      greaterThan(t.view.physicalSize.height / t.view.devicePixelRatio / 2),
    );
    await t.pump(const Duration(seconds: 5));
    expect(find.text('Beta · 2/3'), findsNothing);
    expect(btn, findsNothing);
  });

  testWidgets('left-docked toolbar: back button does not overlap it', (
    t,
  ) async {
    seedAll();
    await open(t, 'Alpha');
    final c = ProviderScope.containerOf(t.element(find.byType(NoteEditor)));
    c
        .read(toolbarPosProvider.notifier)
        .set(const ToolbarPos().applyDock(ToolbarDock.left));
    await settle(t);
    await three(t, const Offset(-80, 0));
    final r = t.getRect(find.widgetWithText(FilledButton, 'Back'));
    final bar = t.getRect(find.byType(PenToolbar));
    expect(r.overlaps(bar), isFalse);
    expect(r.left, greaterThanOrEqualTo(bar.right));
  });

  testWidgets('bottom-docked toolbar: back button does not overlap it', (
    t,
  ) async {
    seedAll();
    await open(t, 'Alpha');
    final c = ProviderScope.containerOf(t.element(find.byType(NoteEditor)));
    c
        .read(toolbarPosProvider.notifier)
        .set(const ToolbarPos().applyDock(ToolbarDock.bottom));
    await settle(t);
    await three(t, const Offset(-80, 0));
    final r = t.getRect(find.widgetWithText(FilledButton, 'Back'));
    final bar = t.getRect(find.byType(PenToolbar));
    expect(r.overlaps(bar), isFalse);
  });

  testWidgets('three fingers: left is next, right is previous', (t) async {
    seedAll();
    await open(t, 'Alpha');
    await three(t, const Offset(-80, 0));
    expect(shown(t), 'Beta');
    await three(t, const Offset(80, 0));
    expect(shown(t), 'Alpha');
  });

  testWidgets('no hop: late third finger, vertical, or at the end', (t) async {
    seedAll();
    await open(t, 'Alpha');
    await three(t, const Offset(-80, 0), gapMs: 300);
    expect(shown(t), 'Alpha');
    await three(t, const Offset(0, -120));
    expect(shown(t), 'Alpha');
    await three(t, const Offset(60, 0)); // too short
    expect(shown(t), 'Alpha');
    await three(t, const Offset(90, 0)); // no previous note
    expect(shown(t), 'Alpha');
  });

  testWidgets('a text box being edited is saved before the hop', (t) async {
    seedAll();
    await open(t, 'Alpha');
    await t.tap(find.byTooltip('Text'));
    await t.pump();
    final s = await t.startGesture(
      const Offset(400, 250),
      kind: PointerDeviceKind.stylus,
    );
    await s.up();
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'kept');
    await t.pump(const Duration(seconds: 1)); // past the palm window
    final board = ProviderScope.containerOf(t.element(find.byType(NoteEditor)));
    board.read(elementClipboardProvider.notifier).set([
      {'id': 'x', 'type': 'text'},
    ]);
    await three(t, const Offset(-80, 0));
    expect(shown(t), 'Beta');
    final saved = decodeKkj(fileOf(1).readAsBytesSync()).note!;
    final els = (saved.pages.first['elements'] as List);
    expect(els.any((e) => (e as Map)['text'] == 'kept'), isTrue);
    expect(board.read(elementClipboardProvider), hasLength(1));
  });

  testWidgets('back button returns to Alpha with no chip or button', (t) async {
    seedAll();
    await open(t, 'Alpha');
    await three(t, const Offset(-80, 0));
    expect(shown(t), 'Beta');
    await t.tap(find.widgetWithText(FilledButton, 'Back'));
    await settle(t);
    expect(shown(t), 'Alpha');
    expect(find.textContaining(' · '), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Back'), findsNothing);
  });

  testWidgets('a note that cannot be read is skipped', (t) async {
    seedAll();
    fileOf(2).writeAsBytesSync([1, 2, 3]);
    await open(t, 'Alpha');
    await three(t, const Offset(-80, 0));
    expect(shown(t), 'Gamma');
    expect(find.text('Gamma · 2/2'), findsOneWidget);
  });

  testWidgets('animations off: a fade, not a slide', (t) async {
    seedAll();
    await open(t, 'Alpha');
    Finder slide() => find.ancestor(
      of: find.byType(NoteEditor).last,
      matching: find.byType(SlideTransition),
    );
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await three(t, const Offset(-80, 0), wait: false);
    for (
      var i = 0;
      i < 200 && find.byType(NoteEditor).evaluate().length < 2;
      i++
    ) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(find.byType(NoteEditor), findsNWidgets(2)); // mid-transition
    expect(slide(), findsNothing);
    await settle(t);
    expect(shown(t), 'Beta');
  });

  testWidgets('back from a hopped note lands on the library', (t) async {
    seedAll();
    await open(t, 'Alpha');
    await three(t, const Offset(-80, 0));
    await t.tap(find.byTooltip('Back to library'));
    await settle(t);
    expect(find.byType(NoteEditor), findsNothing);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('no readable target: nothing is touched', (t) async {
    seedAll();
    await open(t, 'Alpha');
    fileOf(2).writeAsBytesSync([1, 2, 3]);
    fileOf(3).writeAsBytesSync([1, 2, 3]);
    await three(t, const Offset(-80, 0));
    expect(shown(t), 'Alpha');
    expect(find.byType(NoteEditor), findsOneWidget);
    // Still usable: a second try does not hang on a stuck flag.
    await three(t, const Offset(-80, 0));
    expect(shown(t), 'Alpha');
  });
}
