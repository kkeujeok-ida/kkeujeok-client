// Story 5.13: previous / next note from the menu and by three fingers.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/element_clipboard.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/text_metrics.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/ui/note_editor.dart';

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

  Future<void> menuHop(WidgetTester t, String label) async {
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text(label));
    await settle(t);
  }

  bool enabled(WidgetTester t, String label) =>
      t
          .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, label))
          .onPressed !=
      null;

  var ptr = 100;
  var clock = 10000; // ms; the test gestures all stamp zero, so stamp here

  Future<void> three(
    WidgetTester t,
    Offset delta, {
    int gapMs = 0, // the third finger lands this late
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
    await settle(t);
  }

  testWidgets('menu: next opens Beta with chip, snackbar and ends disabled', (
    t,
  ) async {
    seedAll();
    await open(t, 'Alpha');
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(enabled(t, 'Previous note'), isFalse);
    expect(enabled(t, 'Next note'), isTrue);
    await t.tap(find.text('Next note'));
    await settle(t);
    expect(shown(t), 'Beta');
    expect(find.text('Beta · 2/3'), findsOneWidget);
    expect(find.text('Back to ‘Alpha’'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
    // The chip goes after three seconds.
    await t.pump(const Duration(seconds: 4));
    expect(find.text('Beta · 2/3'), findsNothing);
    await menuHop(t, 'Next note');
    expect(shown(t), 'Gamma');
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(enabled(t, 'Next note'), isFalse);
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

  testWidgets('undo goes back to Alpha with no chip or snackbar', (t) async {
    seedAll();
    await open(t, 'Alpha');
    await menuHop(t, 'Next note');
    expect(shown(t), 'Beta');
    await t.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await settle(t);
    expect(shown(t), 'Alpha');
    expect(find.textContaining(' · '), findsNothing);
    expect(find.byType(SnackBarAction), findsNothing);
  });

  testWidgets('a note that cannot be read is skipped', (t) async {
    seedAll();
    fileOf(2).writeAsBytesSync([1, 2, 3]);
    await open(t, 'Alpha');
    await menuHop(t, 'Next note');
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
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Next note'));
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
    await menuHop(t, 'Next note');
    await t.tap(find.byTooltip('Back to library'));
    await settle(t);
    expect(find.byType(NoteEditor), findsNothing);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('no readable target: nothing is touched, menu stays', (t) async {
    seedAll();
    await open(t, 'Alpha');
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    fileOf(2).writeAsBytesSync([1, 2, 3]);
    fileOf(3).writeAsBytesSync([1, 2, 3]);
    await t.tap(find.text('Next note'));
    await settle(t);
    expect(shown(t), 'Alpha');
    expect(find.byType(NoteEditor), findsOneWidget);
    // Still usable: a second try does not hang on a stuck flag.
    await menuHop(t, 'Next note');
    expect(shown(t), 'Alpha');
  });
}
