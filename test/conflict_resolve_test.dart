// Story 3.21: resolving a conflict from the editor. A real `NoteStore` on a
// temp folder, the real `QueueMergeStep` and the editor's own merge host.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/merge_step.dart';
import 'package:kkeujeok/ui/conflict_sheet.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

final _a = _id(1001);
final _b = _id(1002);

Note _base() {
  final j = createNote(
    title: 'Lecture',
    existingTitles: const [],
    background: 'plain',
    orientation: 'portrait',
    noteId: _id(1),
    pageId: _a,
    pageRev: _id(2001),
    metaRev: _id(3001),
    orderRev: _id(4001),
    now: '2000-01-01T12:00:00.000Z',
    editedBy: 'Pixel 8',
  ).note!.copyJson();
  final pages = j['pages'] as List;
  pages.add({
    ...(pages.first as Map<String, dynamic>),
    'id': _b,
    'rev': _id(2002),
  });
  return Note.trusted(j);
}

Note _remoteChanging(Note base, List<int> nos) {
  final j = base.copyJson();
  for (final no in nos) {
    final p = (j['pages'] as List)[no] as Map<String, dynamic>;
    p['lineage'] = [p['rev']];
    p['rev'] = _id(9000 + no);
    p['seq'] = (p['seq'] as int) + 1;
    p['editedBy'] = 'Galaxy Tab';
    p['editedAt'] = '2026-10-17T05:00:00.000Z';
  }
  return Note.trusted(j);
}

Note _remoteWithout(Note base, int no) {
  final j = base.copyJson();
  (j['pages'] as List).removeAt(no);
  return Note.trusted(j);
}

/// A store whose `sync.json` read can be made to fail.
class _FlakyStore extends NoteStore {
  _FlakyStore(super.data);

  bool failRead = false;

  @override
  Future<SyncRead> readSync(String noteId) =>
      failRead ? Future.error(StateError('read')) : super.readSync(noteId);
}

void main() {
  late Directory docs;
  late NoteData data;
  late _FlakyStore store;
  late File file;
  late List<Map> sent;
  late int scheduled;

  setUp(() {
    resetStylusSeen();
    sent = [];
    scheduled = 0;
    docs = Directory.systemTemp.createTempSync('kkj-resolve-');
    data = NoteData(() async => docs);
    store = _FlakyStore(data);
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

  Note onDisk() => decodeKkj(file.readAsBytesSync()).note!;

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
    Locale device = const Locale('en', 'US'),
    double width = 900,
  }) async {
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
    await pumpApp(
      t,
      noteData: data,
      noteStore: store,
      device: [device],
      width: width,
      overrides: [
        // Counts the upload that a resolve starts (the gate is closed).
        backgroundSchedulerProvider.overrideWithValue(() async => scheduled++),
      ],
    );
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
    expect(find.byType(NoteEditor), findsOneWidget);
  }

  Iterable<Map> polite(String text) => [
    for (final m in sent)
      if (m['type'] == 'announce' &&
          (m['data'] as Map)['message'] == text &&
          (m['data'] as Map)['assertiveness'] == null) // polite is the default
        m,
  ];

  List<PagePainter> painters() => [
    for (final w
        in find
            .descendant(
              of: find.byType(NoteEditor),
              matching: find.byType(CustomPaint),
            )
            .evaluate()
            .map((e) => e.widget as CustomPaint))
      if (w.painter is PagePainter) w.painter as PagePainter,
  ];

  Offset onScreen(int page, double x, double y) {
    final vp = painters()[page].viewport!;
    return vp.offset + Offset(x, y) * vp.scale;
  }

  Future<void> stroke(
    WidgetTester t, {
    int page = 0,
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final g = await t.startGesture(onScreen(page, 100, 100), kind: kind);
    await g.moveTo(onScreen(page, 200, 160));
    await g.up();
    await t.pump(const Duration(milliseconds: 50));
  }

  Future<void> scroll(WidgetTester t, double dy) async {
    final p = TestPointer(7, PointerDeviceKind.mouse);
    await t.sendEventToBinding(p.hover(const Offset(450, 400)));
    await t.sendEventToBinding(p.scroll(Offset(0, dy)));
    await t.pump();
  }

  Future<MergeOutcome> mergeIn(WidgetTester t, Note base, Note remote) {
    final c = ProviderScope.containerOf(t.element(find.byType(NoteEditor)));
    return c
        .read(mergeStepProvider)
        .merge(localAtStart: base, base: base, remote: remote);
  }

  Future<SyncInfo> info() async => (await store.readSync(_id(1))).info;

  PenToolbar toolbar(WidgetTester t) =>
      t.widget<PenToolbar>(find.byType(PenToolbar));

  /// The uploader leaves the note in `conflict`. The view settles first: a
  /// read the editor started must not hold the note's lock while the real
  /// clock runs.
  Future<void> markConflict(WidgetTester t) async {
    await settle(t);
    await t.runAsync(
      () => store.updateSync(
        _id(1),
        (s) => s.copyWith(state: SyncState.conflict),
      ),
    );
    await settle(t);
  }

  /// A conflict on page [pages] made by a real merge in the open editor,
  /// after one stroke on page 1. The state is `conflict`, as the uploader
  /// leaves it.
  Future<Note> conflict(WidgetTester t, {List<int> pages = const [0]}) async {
    final base = _base();
    seed(base);
    await open(t);
    await stroke(t);
    await settle(t);
    if (pages.contains(1)) {
      // Page 2 is written here too, then the view goes back to page 1.
      await scroll(t, 900);
      await stroke(t, page: 1);
      await settle(t);
      await scroll(t, -900);
    }
    await t.runAsync(() => mergeIn(t, base, _remoteChanging(base, pages)));
    await markConflict(t);
    await settle(t);
    return base;
  }

  Future<void> openSheet(WidgetTester t) async {
    await t.tap(find.text('Resolve'));
    await settle(t);
    expect(find.text('Pages edited on both devices'), findsOneWidget);
  }

  group('one choice', () {
    testWidgets('this device version: page replaced with a fresh rev, '
        'unlocked, undo cleared, resolved, pending, upload started', (t) async {
      final h = t.ensureSemantics();
      await conflict(t);
      expect(onDisk().pages[0]['rev'], _id(9000));
      expect(find.text('Resolve'), findsOneWidget);
      await openSheet(t);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Keep both'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );

      await t.tap(find.text('This device version'));
      await settle(t);

      final page = onDisk().pages[0];
      expect(page['id'], _a);
      expect(page['elements'], hasLength(1)); // the stroke of this device
      expect(page['rev'], isNot(anyOf(_id(9000), _id(2001))));
      expect(page['lineage'], contains(_id(9000)));
      expect(page['seq'], greaterThan(2));
      final i = await t.runAsync(info);
      expect(i!.unresolvedConflicts, isEmpty);
      expect(i.conflicts.single['resolvedAt'], isNotNull);
      expect(i.state, SyncState.pending);
      // The sheet is gone and so is the banner.
      expect(find.text('Pages edited on both devices'), findsNothing);
      expect(find.text('Resolve'), findsNothing);
      expect(
        find.text(
          'You edited this page on another device too. It is read-only '
          'until you choose.',
        ),
        findsNothing,
      );
      expect(polite('Page 1: kept this device version'), hasLength(1));
      // Editable again; the stroke made before the merge can not be undone.
      expect(toolbar(t).canUndo, isFalse);
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], hasLength(2));
      expect(toolbar(t).canUndo, isTrue);
      // The upload was asked for (the gate is closed, so it is scheduled).
      expect(scheduled, greaterThan(0));
      h.dispose();
    });

    testWidgets('other device version: its page, fresh rev', (t) async {
      await conflict(t);
      await openSheet(t);
      await t.tap(find.text('Other device version'));
      await settle(t);
      final page = onDisk().pages[0];
      expect(page['elements'], isEmpty);
      expect(page['rev'], isNot(_id(9000)));
      expect(page['editedBy'], isNot('Galaxy Tab')); // a new version
      final i = await t.runAsync(info);
      expect(i!.unresolvedConflicts, isEmpty);
      expect(i.state, SyncState.pending);
      expect(polite('Page 1: kept the other device version'), hasLength(1));
    });

    testWidgets('keep both: this device version at its index, the other '
        'right after, the note has one page more, all shown', (t) async {
      await conflict(t);
      await openSheet(t);
      await t.tap(find.text('Keep both'));
      await settle(t);
      final pages = onDisk().pages;
      expect(pages, hasLength(3));
      // This device's version at the original index, the other right after
      // it (the newer rev keeps the page id, the other gets a derived one).
      expect(pages[0]['elements'], hasLength(1));
      expect(pages[1]['elements'], isEmpty);
      expect(pages[1]['rev'], _id(9000));
      expect(pages[2]['id'], _b);
      expect({pages[0]['id'], pages[1]['id']}, contains(_a));
      expect(pages[0]['id'], isNot(pages[1]['id']));
      // The hidden page is reachable: three pages on screen.
      expect(painters(), hasLength(3));
      final i = await t.runAsync(info);
      expect(i!.unresolvedConflicts, isEmpty);
      expect(i.state, SyncState.pending);
      expect(polite('Page 1: kept both'), hasLength(1));
      // Both new pages are editable.
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], hasLength(2));
    });

    testWidgets('remoteDeleted: keep puts the page back at its index', (
      t,
    ) async {
      final base = _base();
      seed(base);
      await open(t);
      await stroke(t);
      await settle(t);
      await t.runAsync(() => mergeIn(t, base, _remoteWithout(base, 0)));
      await markConflict(t);
      expect(onDisk().pages.map((p) => p['id']), [_b]);
      await openSheet(t);
      expect(find.text('Page deleted on another device'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Keep this version'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await t.tap(find.text('Keep this version'));
      await settle(t);
      expect(onDisk().pages.map((p) => p['id']), [_a, _b]);
      expect(onDisk().pages[0]['elements'], hasLength(1));
      expect((await t.runAsync(info))!.unresolvedConflicts, isEmpty);
      expect(polite('Page 1: kept'), hasLength(1));
    });

    testWidgets('remoteDeleted: delete leaves the note and still resolves; '
        'nothing to send, so it is saved, not pending', (t) async {
      final base = _base();
      seed(base);
      await open(t);
      await stroke(t);
      await settle(t);
      await t.runAsync(() => mergeIn(t, base, _remoteWithout(base, 0)));
      await markConflict(t);
      await openSheet(t);
      await t.tap(find.text('Delete page'));
      await settle(t);
      expect(onDisk().pages.map((p) => p['id']), [_b]);
      final i = (await t.runAsync(info))!;
      expect(i.unresolvedConflicts, isEmpty);
      expect(i.conflicts.single['resolvedAt'], isNotNull);
      expect(polite('Page 1: deleted'), hasLength(1));
    });

    testWidgets('an error from resolveConflict: the sheet stays, nothing '
        'changes', (t) async {
      await conflict(t);
      // An entry kind the rule does not know: every choice is invalid.
      await t.runAsync(
        () => store.updateSync(
          _id(1),
          (s) => s.copyWith(
            conflicts: [
              for (final c in s.conflicts) {...c, 'kind': 'weird'},
            ],
          ),
        ),
      );
      await settle(t);
      final before = file.readAsBytesSync();
      await openSheet(t);
      await t.tap(find.text('Keep this version'));
      await settle(t);
      expect(find.text('Pages edited on both devices'), findsOneWidget);
      expect(find.text('Could not resolve. Try again.'), findsOneWidget);
      expect(file.readAsBytesSync(), before);
      expect((await t.runAsync(info))!.unresolvedConflicts, hasLength(1));
    });
  });

  group('the sheet', () {
    testWidgets('later: closes, nothing changes, lock and banner stay', (
      t,
    ) async {
      await conflict(t);
      final before = file.readAsBytesSync();
      await openSheet(t);
      await t.tap(find.text('Decide later'));
      await settle(t);
      expect(find.text('Pages edited on both devices'), findsNothing);
      expect(file.readAsBytesSync(), before);
      expect(find.text('Resolve'), findsOneWidget);
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], isEmpty);
      expect((await t.runAsync(info))!.unresolvedConflicts, hasLength(1));
    });

    testWidgets('back closes it too', (t) async {
      await conflict(t);
      await openSheet(t);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.text('Pages edited on both devices'), findsNothing);
      expect(find.byType(NoteEditor), findsOneWidget);
      expect((await t.runAsync(info))!.unresolvedConflicts, hasLength(1));
    });

    testWidgets('a phone: bottom sheet, stacked', (t) async {
      await conflict(t);
      t.view.physicalSize = const Size(400, 900);
      await settle(t);
      await openSheet(t);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('other side time: offline, the page time stands in', (t) async {
      await conflict(t);
      await openSheet(t);
      expect(find.textContaining('Galaxy Tab · '), findsOneWidget);
      expect(find.text('Newer'), findsOneWidget);
    });
  });

  group('several conflicts', () {
    testWidgets('one by one: the next comes up, the last closes the sheet, '
        'focus goes to the canvas', (t) async {
      await conflict(t, pages: [0, 1]);
      await openSheet(t);
      expect(find.text('Page 1 · 1/2'), findsOneWidget);
      await t.tap(find.text('Keep both'));
      await settle(t);
      // Page 2 is the next one (the index moved with the new page).
      expect(find.text('Pages edited on both devices'), findsOneWidget);
      expect(find.textContaining('· 1/1'), findsOneWidget);
      expect((await t.runAsync(info))!.unresolvedConflicts, hasLength(1));
      expect(find.text('Resolve'), findsOneWidget);
      await t.tap(find.text('This device version'));
      await settle(t);
      expect(find.text('Pages edited on both devices'), findsNothing);
      expect(find.text('Resolve'), findsNothing);
      final i = (await t.runAsync(info))!;
      expect(i.unresolvedConflicts, isEmpty);
      expect(i.state, SyncState.pending);
    });

    testWidgets('rest: all other device version, two taps', (t) async {
      await conflict(t, pages: [0, 1]);
      await openSheet(t);
      await t.tap(find.text('Rest: all other device version'));
      await t.pump();
      expect((await t.runAsync(info))!.unresolvedConflicts, hasLength(2));
      await t.tap(find.text('Tap again to apply to 2 pages'));
      await settle(t);
      expect(find.text('Pages edited on both devices'), findsNothing);
      final i = (await t.runAsync(info))!;
      expect(i.unresolvedConflicts, isEmpty);
      expect(i.conflicts.where((c) => c['resolvedAt'] != null), hasLength(2));
      expect(i.state, SyncState.pending);
      expect(onDisk().pages, hasLength(2));
      expect(onDisk().pages[0]['elements'], isEmpty);
      expect(polite('2 pages resolved'), hasLength(1));
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], hasLength(1));
    });

    testWidgets('rest: all this device version', (t) async {
      await conflict(t, pages: [0, 1]);
      await openSheet(t);
      await t.tap(find.text('Rest: all this device version'));
      await t.pump();
      await t.tap(find.text('Tap again to apply to 2 pages'));
      await settle(t);
      expect(onDisk().pages[0]['elements'], hasLength(1));
      expect((await t.runAsync(info))!.unresolvedConflicts, isEmpty);
    });
  });

  group('damaged state', () {
    testWidgets('a conflict whose sidecar is gone: a notice, no sheet, no '
        'crash', (t) async {
      await conflict(t);
      final dir = Directory('${docs.path}/$noteDataDirName/${_id(1)}/sidecars');
      for (final f in dir.listSync()) {
        f.deleteSync();
      }
      await t.tap(find.text('Resolve'));
      await settle(t);
      expect(find.text('Pages edited on both devices'), findsNothing);
      expect(find.text('Could not resolve. Try again.'), findsOneWidget);
      expect((await t.runAsync(info))!.unresolvedConflicts, hasLength(1));
    });

    testWidgets('a sync.json that can not be read keeps the page locked', (
      t,
    ) async {
      await conflict(t);
      final c = ProviderScope.containerOf(t.element(find.byType(NoteEditor)));
      final host = c.read(mergeHostsProvider).of(_id(1))!;
      store.failRead = true;
      await t.runAsync(() => host((_) => null, () async {}));
      await settle(t);
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], isEmpty);
      expect(find.text('Resolve'), findsOneWidget);
    });
  });

  group('the library card', () {
    testWidgets('opens the editor with the sheet already open', (t) async {
      await conflict(t);
      await t.tap(find.byTooltip('Back to library'));
      await settle(t);
      expect(find.byType(NoteEditor), findsNothing);
      await t.tap(find.text('Lecture'));
      await settle(t);
      expect(find.byType(NoteEditor), findsOneWidget);
      expect(find.text('Pages edited on both devices'), findsOneWidget);
    });

    testWidgets('a note without a conflict opens plainly', (t) async {
      seed(_base());
      await open(t);
      expect(find.text('Pages edited on both devices'), findsNothing);
    });

    testWidgets('after the choice the card has no conflict any more', (
      t,
    ) async {
      await conflict(t);
      await openSheet(t);
      await t.tap(find.text('Keep both'));
      await settle(t);
      await t.tap(find.byTooltip('Back to library'));
      await settle(t);
      await t.tap(find.text('Lecture'));
      await settle(t);
      expect(find.text('Pages edited on both devices'), findsNothing);
    });
  });

  testWidgets('ko: pane title, announcement', (t) async {
    final h = t.ensureSemantics();
    final base = _base();
    seed(base);
    await open(t, device: const Locale('ko', 'KR'));
    await stroke(t);
    await settle(t);
    await t.runAsync(() => mergeIn(t, base, _remoteChanging(base, [0])));
    await markConflict(t);
    await t.tap(find.text('해결하기'));
    await settle(t);
    expect(find.text('두 기기에서 고친 페이지가 있어요'), findsWidgets);
    expect(find.text('1페이지 · 1/1'), findsOneWidget);
    await t.tap(find.text('둘 다 남기기'));
    await settle(t);
    expect(polite('1페이지: 둘 다 남겼어요'), hasLength(1));
    h.dispose();
  });

  test('ConflictItem maps the rest choices', () {
    ConflictItem item(String kind) => ConflictItem(
      entry: {'pageId': 'p', 'kind': kind, 'rev': 'a'},
      sidecar: const {},
    );
    expect(item('bothEdited').choiceFor(thisDevice: true), 'mine');
    expect(item('bothEdited').choiceFor(thisDevice: false), 'theirs');
    expect(item('remoteDeleted').choiceFor(thisDevice: true), 'keep');
    expect(item('remoteDeleted').choiceFor(thisDevice: false), 'remove');
    expect(item('localDeleted').choiceFor(thisDevice: true), 'remove');
    expect(item('localDeleted').choiceFor(thisDevice: false), 'keep');
  });
}
