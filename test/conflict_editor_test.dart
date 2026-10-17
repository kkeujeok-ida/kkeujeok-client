// Story 3.19: the editor over a conflict. A real `NoteStore` on a temp folder,
// the real `QueueMergeStep` and the editor's own merge host.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/design_tokens/build/tokens.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/merge_step.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/sync_banner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// [base] with page [no] changed by the other device (lineage as synced).
Note _remoteChanging(Note base, int no) {
  final j = base.copyJson();
  final p = (j['pages'] as List)[no] as Map<String, dynamic>;
  p['lineage'] = [p['rev']];
  p['rev'] = _id(9000 + no);
  p['seq'] = (p['seq'] as int) + 1;
  return Note.trusted(j);
}

/// [base] without page [no]: the other device deleted it.
Note _remoteWithout(Note base, int no) {
  final j = base.copyJson();
  (j['pages'] as List).removeAt(no);
  return Note.trusted(j);
}

void main() {
  late Directory docs;
  late NoteData data;
  late NoteStore store;
  late File file;
  late List<Map> sent;

  setUp(() {
    resetStylusSeen();
    sent = [];
    docs = Directory.systemTemp.createTempSync('kkj-conflict-');
    data = NoteData(() async => docs);
    store = NoteStore(data);
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
    await pumpApp(t, noteData: data, noteStore: store, device: [device]);
    await settle(t);
    await t.tap(find.text('Lecture'));
    await settle(t);
    expect(find.byType(NoteEditor), findsOneWidget);
  }

  List<Map> announced() => [
    for (final m in sent)
      if (m['type'] == 'announce') m['data'] as Map,
  ];

  Iterable<Map> assertive(String text) =>
      announced().where((a) => a['message'] == text && a['assertiveness'] == 1);

  Map shownPage() {
    final w =
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
    return (w.painter as PagePainter).page;
  }

  Offset onScreen(WidgetTester t, double x, double y) {
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
    final vp = (paint.painter as PagePainter).viewport!;
    return vp.offset + Offset(x, y) * vp.scale;
  }

  Future<void> stroke(
    WidgetTester t, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
  }) async {
    final g = await t.startGesture(onScreen(t, 100, 100), kind: kind);
    await g.moveTo(onScreen(t, 200, 160));
    await g.up();
    await t.pump(const Duration(milliseconds: 50));
  }

  Future<MergeOutcome> mergeIn(WidgetTester t, Note base, Note remote) {
    final c = ProviderScope.containerOf(t.element(find.byType(NoteEditor)));
    return c
        .read(mergeStepProvider)
        .merge(localAtStart: base, base: base, remote: remote);
  }

  Future<SyncInfo> info() async => (await store.readSync(_id(1))).info;

  const bannerEn =
      'You edited this page on another device too. It is read-only until you choose.';
  const bannerDeletedEn =
      "A page was deleted on another device. This device's version is kept until you choose.";
  const foundEn =
      'Page 1 was edited on both devices. It is read-only until you choose.';
  const blockedEn = 'This page is read-only.';

  Color bannerColor(WidgetTester t) {
    final box = find.ancestor(
      of: find.text(bannerEn),
      matching: find.byType(ColoredBox),
    );
    return t.widget<ColoredBox>(box.first).color;
  }

  PenToolbar toolbar(WidgetTester t) =>
      t.widget<PenToolbar>(find.byType(PenToolbar));

  group('a conflict in an open editor', () {
    testWidgets('idle page: remote page shown, locked, banner, announcement', (
      t,
    ) async {
      final h = t.ensureSemantics();
      final base = _base();
      seed(base);
      await open(t);
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], hasLength(1));

      final out = await t.runAsync(
        () => mergeIn(t, base, _remoteChanging(base, 0)),
      );
      await settle(t);

      expect((out as Merged).conflicts, 1);
      // The sidecar is durable and listed before the page is the remote one.
      final i = await t.runAsync(info);
      expect(i!.unsentSidecars, hasLength(1));
      expect(i.conflicts.single['pageId'], _a);
      final sidecar = await t.runAsync(
        () => store.readSidecar(
          _id(1),
          _a,
          i.unsentSidecars.single['rev'] as String,
        ),
      );
      expect(((sidecar!['page'] as Map)['elements'] as List), hasLength(1));
      // The remote page is shown and saved.
      expect(shownPage()['rev'], _id(9000));
      expect(onDisk().pages[0]['rev'], _id(9000));
      // Banner and announcement.
      expect(find.text(bannerEn), findsOneWidget);
      expect(assertive(foundEn), hasLength(1));
      expect(find.text('Resolve'), findsOneWidget);
      // The hook is supplied by the editor (Story 3.21): the sheet opens.
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Resolve'))
            .onPressed,
        isNotNull,
      );
      // The page is read-only: no stroke, no op.
      await stroke(t);
      await stroke(t, kind: PointerDeviceKind.mouse);
      await settle(t);
      expect(onDisk().pages[0]['elements'], isEmpty);
      expect(shownPage()['elements'], isEmpty);
      expect(
        find.semantics.byValue(
          RegExp('Read-only, page edited on both devices'),
        ),
        findsOneWidget,
      );
      expect(toolbar(t).canUndo, isFalse);
      expect(toolbar(t).canRedo, isFalse);
      h.dispose();
    });

    testWidgets('a stroke in progress ends first and is in the sidecar; the '
        'screen keeps the local page', (t) async {
      final h = t.ensureSemantics();
      final base = _base();
      seed(base);
      await open(t);
      final g = await t.startGesture(
        onScreen(t, 100, 100),
        kind: PointerDeviceKind.stylus,
      );
      await g.moveTo(onScreen(t, 150, 130));
      await t.pump();

      var done = false;
      MergeOutcome? out;
      mergeIn(t, base, _remoteChanging(base, 0)).then((o) {
        out = o;
        done = true;
      });
      await settle(t);
      // Waiting: nothing applied while the pointer is down.
      expect(done, isFalse);
      expect(onDisk().pages[0]['rev'], _id(2001));
      expect(assertive(foundEn), isEmpty);

      await g.moveTo(onScreen(t, 200, 160));
      await g.up();
      await settle(t);
      await settle(t);
      expect(done, isTrue);

      expect((out! as Merged).conflicts, 1);
      final i = (await t.runAsync(info))!;
      final sidecar = await t.runAsync(
        () => store.readSidecar(
          _id(1),
          _a,
          i.unsentSidecars.single['rev'] as String,
        ),
      );
      // The finished stroke is in the sidecar page.
      expect(((sidecar!['page'] as Map)['elements'] as List), hasLength(1));
      // The stored note has the remote page; the screen keeps the local one.
      expect(onDisk().pages[0]['rev'], _id(9000));
      expect(onDisk().pages[0]['elements'], isEmpty);
      expect(shownPage()['elements'], hasLength(1));
      // Still read-only.
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], isEmpty);

      // Leaving and coming back shows the remote page.
      await t.tap(find.byTooltip('Back to library'));
      await settle(t);
      await t.tap(find.text('Lecture'));
      await settle(t);
      expect(shownPage()['rev'], _id(9000));
      expect(shownPage()['elements'], isEmpty);
      h.dispose();
    });

    testWidgets('a blocked write stresses the banner once and announces at '
        'most once a second', (t) async {
      final h = t.ensureSemantics();
      final base = _base();
      seed(base);
      await open(t);
      await stroke(t);
      await settle(t);
      await t.runAsync(() => mergeIn(t, base, _remoteChanging(base, 0)));
      await settle(t);
      expect(bannerColor(t), KkjLight.componentsBannerBackground);

      await stroke(t, kind: PointerDeviceKind.mouse);
      await stroke(t, kind: PointerDeviceKind.mouse);
      expect(bannerColor(t), KkjLight.colorAccentSoft);
      expect(assertive(blockedEn), hasLength(1));
      await t.pump(const Duration(milliseconds: 900));
      expect(bannerColor(t), KkjLight.componentsBannerBackground);

      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await stroke(t, kind: PointerDeviceKind.mouse);
      expect(assertive(blockedEn), hasLength(2));
      await t.pump(const Duration(milliseconds: 900));
      expect(onDisk().pages[0]['elements'], isEmpty);
      h.dispose();
    });

    testWidgets('no emphasis when animations are off, the notice stays', (
      t,
    ) async {
      final h = t.ensureSemantics();
      final base = _base();
      seed(base);
      await open(t);
      await stroke(t);
      await settle(t);
      await t.runAsync(() => mergeIn(t, base, _remoteChanging(base, 0)));
      await settle(t);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await t.pump();
      await stroke(t, kind: PointerDeviceKind.mouse);
      expect(bannerColor(t), KkjLight.componentsBannerBackground);
      expect(assertive(blockedEn), hasLength(1));
      h.dispose();
    });

    testWidgets('undo and redo on a locked page do nothing and say so', (
      t,
    ) async {
      final h = t.ensureSemantics();
      seed(_base());
      await open(t);
      await stroke(t);
      await settle(t);
      expect(toolbar(t).canUndo, isTrue);
      // The lock comes from the status alone (no merge dropped the records).
      await t.runAsync(
        () => store.updateSync(
          _id(1),
          (s) => s.copyWith(
            conflicts: [
              {
                'pageId': _a,
                'kind': 'bothEdited',
                'rev': _id(1),
                'theirsRev': _id(2),
                'detectedAt': '2026-10-17T00:00:00.000Z',
                'originalIndex': 0,
                'resolvedAt': null,
              },
            ],
          ),
        ),
      );
      await settle(t);
      expect(find.text(bannerEn), findsOneWidget);
      expect(toolbar(t).canUndo, isFalse);
      final before = file.readAsBytesSync();

      toolbar(t).onUndo!();
      await settle(t);
      toolbar(t).onRedo!();
      await settle(t);

      expect(file.readAsBytesSync(), before);
      expect(onDisk().pages[0]['elements'], hasLength(1));
      expect(assertive(blockedEn), hasLength(1));
      h.dispose();
    });

    testWidgets('remoteDeleted: the page is out of the note, banner text '
        'for deleted pages', (t) async {
      final h = t.ensureSemantics();
      final base = _base();
      seed(base);
      await open(t);
      await stroke(t);
      await settle(t);

      final out = await t.runAsync(
        () => mergeIn(t, base, _remoteWithout(base, 0)),
      );
      await settle(t);

      expect((out as Merged).conflicts, 1);
      expect(onDisk().pages.map((p) => p['id']), [_b]);
      expect(find.text(bannerDeletedEn), findsOneWidget);
      expect(find.text(bannerEn), findsNothing);
      expect(
        assertive(
          "Page 1 was deleted on another device. This device's version is kept until you choose.",
        ),
        hasLength(1),
      );
      final i = await t.runAsync(info);
      expect(i!.unsentSidecars, hasLength(1));
      // Page B is another page and edits normally.
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], hasLength(1));
      h.dispose();
    });

    testWidgets('a conflict on another page leaves this page editable', (
      t,
    ) async {
      final h = t.ensureSemantics();
      final base = _base();
      // This device changed page B before; the other device changed it too.
      final local = base.copyJson();
      final lb = (local['pages'] as List)[1] as Map<String, dynamic>;
      lb['rev'] = _id(5002);
      lb['seq'] = 2;
      seed(Note.trusted(local));
      await open(t);

      final out = await t.runAsync(
        () => mergeIn(t, base, _remoteChanging(base, 1)),
      );
      await settle(t);

      expect((out as Merged).conflicts, 1);
      expect(find.text(bannerEn), findsOneWidget);
      // Page A is the one on screen and it is not locked.
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], hasLength(1));
      expect(assertive(blockedEn), isEmpty);
      expect(toolbar(t).canUndo, isTrue);
      h.dispose();
    });

    testWidgets('a merge without a conflict: no lock, banner or notice', (
      t,
    ) async {
      final h = t.ensureSemantics();
      final base = _base();
      seed(base);
      await open(t);
      await stroke(t);
      await settle(t);

      final out = await t.runAsync(
        () => mergeIn(t, base, _remoteChanging(base, 1)),
      );
      await settle(t);

      expect((out as Merged).conflicts, 0);
      expect(find.byType(SyncBanner), findsOneWidget);
      expect(find.text(bannerEn), findsNothing);
      expect(announced().where((a) => a['assertiveness'] == 1), isEmpty);
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], hasLength(2));
      h.dispose();
    });
  });

  group('a conflict found while the note was closed', () {
    Future<void> record(WidgetTester t, {String kind = 'bothEdited'}) =>
        t.runAsync(() async {
          await store.updateSync(
            _id(1),
            (s) => s.copyWith(
              state: SyncState.conflict,
              conflicts: [
                {
                  'pageId': _a,
                  'kind': kind,
                  'rev': _id(1),
                  'theirsRev': _id(2),
                  'detectedAt': '2026-10-17T00:00:00.000Z',
                  'originalIndex': 0,
                  'resolvedAt': null,
                },
              ],
            ),
          );
        });

    testWidgets('on open: page locked, banner, no new-conflict notice', (
      t,
    ) async {
      final h = t.ensureSemantics();
      seed(_base());
      await t.runAsync(() => store.updateSync(_id(1), (s) => s));
      await record(t);
      await open(t);
      await settle(t);

      expect(find.text(bannerEn), findsOneWidget);
      expect(assertive(foundEn), isEmpty);
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], isEmpty);
      expect(assertive(blockedEn), hasLength(1));
      h.dispose();
    });

    testWidgets('a resolved conflict does not lock', (t) async {
      seed(_base());
      await t.runAsync(() => store.updateSync(_id(1), (s) => s));
      await t.runAsync(
        () => store.updateSync(
          _id(1),
          (s) => s.copyWith(
            conflicts: [
              {
                'pageId': _a,
                'kind': 'bothEdited',
                'rev': _id(1),
                'theirsRev': _id(2),
                'detectedAt': '2026-10-17T00:00:00.000Z',
                'originalIndex': 0,
                'resolvedAt': '2026-10-17T01:00:00.000Z',
              },
            ],
          ),
        ),
      );
      await open(t);
      expect(find.text(bannerEn), findsNothing);
      await stroke(t);
      await settle(t);
      expect(onDisk().pages[0]['elements'], hasLength(1));
    });

    testWidgets('the library card shows the two-versions badge', (t) async {
      seed(_base());
      await t.runAsync(() => store.updateSync(_id(1), (s) => s));
      await record(t);
      await pumpApp(t, noteData: data, noteStore: store);
      await settle(t);
      expect(find.text('Two versions'), findsOneWidget);
    });

    testWidgets('ko: banner, deleted banner and notice', (t) async {
      final h = t.ensureSemantics();
      seed(_base());
      await t.runAsync(() => store.updateSync(_id(1), (s) => s));
      await record(t);
      await open(t, device: const Locale('ko', 'KR'));
      expect(find.text('다른 기기에서도 고친 페이지예요. 고를 때까지는 읽기만 돼요.'), findsOneWidget);
      expect(find.text('해결하기'), findsOneWidget);
      await stroke(t);
      await settle(t);
      expect(assertive('읽기 전용 페이지예요'), hasLength(1));
      h.dispose();
    });

    testWidgets('ko: remoteDeleted banner', (t) async {
      seed(_base());
      await t.runAsync(() => store.updateSync(_id(1), (s) => s));
      await record(t, kind: 'remoteDeleted');
      await open(t, device: const Locale('ko', 'KR'));
      expect(
        find.text('다른 기기에서 지운 페이지가 있어요. 고를 때까지 이 기기 버전을 보관해요.'),
        findsOneWidget,
      );
    });
  });
}
