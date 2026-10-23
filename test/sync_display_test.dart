import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/design_tokens/build/tokens.dart';
import 'package:kkeujeok/drive/root_folder.dart' show RootStatus;
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/note_receiver.dart';
import 'package:kkeujeok/sync/open_note.dart';
import 'package:kkeujeok/sync/upload_coordinator.dart';
import 'package:kkeujeok/ui/library.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/sync_banner.dart';
import 'package:kkeujeok/ui/sync_display.dart';
import 'package:kkeujeok/ui/sync_indicator.dart';

import 'fake_receiver.dart';
import 'upload_env.dart';

/// A store whose sync state is scripted and read without file IO.
class _Store extends NoteStore {
  _Store(this.notes) : super(NoteData(() async => Directory.systemTemp));

  final List<Note> notes;
  final states = <String, SyncState>{};
  final errors = <String, Map<String, Object?>?>{};
  final _c = StreamController<({String noteId, bool sync})>.broadcast(
    sync: true,
  );
  int reads = 0;

  @override
  Stream<({String noteId, bool sync})> get changes => _c.stream;

  void set(String id, SyncState s, {Map<String, Object?>? error}) {
    states[id] = s;
    errors[id] = error;
    _c.add((noteId: id, sync: true));
  }

  void edit(String id) => _c.add((noteId: id, sync: false));

  @override
  Future<SyncRead> readSync(String noteId) async {
    reads++;
    final s = states[noteId] ?? SyncState.synced;
    return (
      info: SyncInfo(state: s, lastError: errors[noteId]),
      base: null,
      hasUnsent: s != SyncState.synced,
      state: s,
    );
  }

  @override
  Future<List<String>> ids() async => states.keys.toList();

  @override
  Future<List<({String noteId, NoteReadResult result})>> list() async => [
    for (final n in notes) (noteId: n.noteId, result: decodeKkj(encodeKkj(n))),
  ];
}

class _Coord implements UploadCoordinator {
  final calls = <String>[];

  @override
  Future<void> Function()? flushOpen;

  @override
  Future<void> syncNow(String id) async => calls.add('syncNow:$id');
  @override
  Future<void> retry(String id) async => calls.add('retry:$id');
  @override
  Future<void> retryAll() async => calls.add('retryAll');
  @override
  Future<void> reconnected() async => calls.add('reconnected');
  @override
  Future<void> foreground() async => calls.add('foreground');
  @override
  Future<void> rootReady() async => calls.add('rootReady');
  @override
  Future<void> noteClosed(String id) async => calls.add('closed:$id');
  @override
  Future<void> appBackgrounded() async => calls.add('background');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Root extends RootFolderNotifier {
  static int signIns = 0;

  @override
  RootFolderState build() => const RootFolderState(RootStatus.ready);

  @override
  Future<bool> signInAgain() async {
    signIns++;
    return true;
  }
}

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Note _note(int n, String title) =>
    makeNote(title: title, noteIdOverride: _id(n));

/// A widget test with semantics on, off again before the end-of-test check.
void semTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (t) async {
      final h = t.ensureSemantics();
      try {
        await body(t);
      } finally {
        h.dispose();
      }
    });

void main() {
  late _Store store;
  late _Coord coord;
  late RecReceiver recv;
  late StreamController<bool> conn;
  late List<Uri> opened;
  late List<Map> sent;
  var probe = true;
  const id = noteId;

  setUp(() {
    store = _Store([_note(0x900, 'Alpha')])..states[id] = SyncState.synced;
    coord = _Coord();
    recv = RecReceiver();
    conn = StreamController<bool>.broadcast();
    opened = [];
    sent = [];
    probe = true;
    _Root.signIns = 0;
    addTearDown(conn.close);
  });

  List<Override> overrides() => [
    noteStoreProvider.overrideWithValue(store),
    uploadCoordinatorProvider.overrideWithValue(coord),
    connectivityChangesProvider.overrideWithValue(conn.stream),
    networkProbeProvider.overrideWithValue(() async => probe),
    noteReceiverProvider.overrideWithValue(recv),
    rootFolderProvider.overrideWith(_Root.new),
    urlOpenerProvider.overrideWithValue((u) async {
      opened.add(u);
      return true;
    }),
  ];

  Future<void> pumpWith(
    WidgetTester t,
    Widget home, {
    String lang = 'ko',
    bool reduce = false,
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
    t.view.physicalSize = const Size(900, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: reduce
              ? (c, w) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(disableAnimations: true),
                  child: w!,
                )
              : null,
          home: home,
        ),
      ),
    );
    await tick(t);
  }

  Widget indicator({bool higher = false}) => Scaffold(
    body: Column(
      children: [
        SyncBanner(higherPriority: higher),
        const SyncIndicator(noteId: id),
      ],
    ),
  );

  List<Map> announcements() => [
    for (final m in sent)
      if (m['type'] == 'announce') m['data'] as Map,
  ];

  Finder icon(IconData i) =>
      find.descendant(of: find.byType(SyncIndicator), matching: find.byIcon(i));

  Finder named(String label) => find.bySemanticsLabel(label);

  group('indicator by state', () {
    for (final lang in ['ko', 'en']) {
      semTest('icon and access name per state ($lang)', (t) async {
        final ko = lang == 'ko';
        String sync(String s) =>
            ko ? '동기화 상태: $s. 자세히 보기' : 'Sync status: $s. More details';
        await pumpWith(t, indicator(), lang: lang);
        expect(icon(Icons.check), findsOneWidget);
        expect(named(sync(ko ? '저장됨' : 'Saved')), findsOneWidget);

        store.set(id, SyncState.pending);
        await tick(t);
        expect(icon(Icons.schedule), findsOneWidget);
        expect(named(sync(ko ? '저장 대기' : 'Waiting to save')), findsOneWidget);

        store.set(id, SyncState.conflict);
        await tick(t);
        expect(icon(Icons.warning_amber_rounded), findsOneWidget);
        expect(named(sync(ko ? '두 버전' : 'Two versions')), findsOneWidget);
        expect(
          t.widget<Icon>(icon(Icons.warning_amber_rounded)).color,
          KkjLight.colorStatusWarning,
        );

        store.set(id, SyncState.error, error: {'class': 'fatal'});
        await tick(t);
        expect(icon(Icons.error_outline), findsOneWidget);
        expect(named(sync(ko ? '저장 안 됨' : 'Not saved')), findsOneWidget);
        expect(
          t.widget<Icon>(icon(Icons.error_outline)).color,
          KkjLight.colorStatusError,
        );
      });
    }

    semTest('receiving shows after 1 s as a down arrow', (t) async {
      await pumpWith(t, indicator());
      recv.state.value = const ReceiveState(receiving: {id});
      await tick(t, 500);
      expect(icon(Icons.arrow_downward), findsNothing);
      await tick(t, 600);
      expect(icon(Icons.arrow_downward), findsOneWidget);
      expect(named('동기화 상태: 최신 내용 받는 중. 자세히 보기'), findsOneWidget);
      recv.state.value = const ReceiveState();
      await tick(t);
      expect(icon(Icons.check), findsOneWidget);
    });

    semTest('the target is at least 48 dp', (t) async {
      await pumpWith(t, indicator());
      final s = t.getSize(find.byType(IconButton));
      expect(s.width, greaterThanOrEqualTo(48));
      expect(s.height, greaterThanOrEqualTo(48));
    });
  });

  group('saving timing', () {
    semTest('under 1 s still reads as pending; from 1 s it turns, >= 600 ms', (
      t,
    ) async {
      await pumpWith(t, indicator());
      store.set(id, SyncState.syncing);
      await tick(t, 500);
      expect(icon(Icons.schedule), findsOneWidget);
      expect(icon(Icons.sync), findsNothing);

      await tick(t, 600); // 1,100 ms
      expect(icon(Icons.sync), findsOneWidget);

      store.set(id, SyncState.synced);
      await tick(t, 100); // shown for 100 ms only so far
      expect(icon(Icons.sync), findsOneWidget);
      await tick(t, 300);
      expect(icon(Icons.sync), findsOneWidget);
      await tick(t, 300); // 700 ms after it appeared
      expect(icon(Icons.check), findsOneWidget);
    });

    semTest('an upload under 1 s never shows saving', (t) async {
      await pumpWith(t, indicator());
      store.set(id, SyncState.syncing);
      await tick(t, 400);
      store.set(id, SyncState.synced);
      await tick(t, 1500);
      expect(icon(Icons.sync), findsNothing);
      expect(icon(Icons.check), findsOneWidget);
    });

    semTest('reduce motion: the arrows stand still', (t) async {
      await pumpWith(t, indicator(), reduce: true);
      store.set(id, SyncState.syncing);
      await tick(t, 1100);
      expect(icon(Icons.sync), findsOneWidget);
      await t.pumpAndSettle(); // would never end with a running animation
    });

    semTest('without reduce motion the arrows turn', (t) async {
      await pumpWith(t, indicator());
      store.set(id, SyncState.syncing);
      await tick(t, 1100);
      expect(
        find.ancestor(
          of: icon(Icons.sync),
          matching: find.byType(RotationTransition),
        ),
        findsWidgets,
      );
      expect(t.binding.hasScheduledFrame, isTrue);
      store.set(id, SyncState.synced);
      await tick(t, 700);
    });
  });

  group('offline', () {
    semTest('pending offline: label, no banner, upload on reconnect', (
      t,
    ) async {
      probe = false;
      store.states[id] = SyncState.pending;
      await pumpWith(t, indicator());
      expect(icon(Icons.cloud_off), findsOneWidget);
      expect(named('동기화 상태: 오프라인 · 이 기기에 보관 중. 자세히 보기'), findsOneWidget);
      expect(find.text('로그인이 만료됐어요. 변경은 이 기기에 보관 중이에요.'), findsNothing);

      conn.add(true);
      await tick(t);
      expect(coord.calls, ['reconnected']);
      expect(icon(Icons.schedule), findsOneWidget);

      conn.add(false);
      await tick(t);
      expect(icon(Icons.cloud_off), findsOneWidget);
      expect(coord.calls, ['reconnected']); // going offline uploads nothing
    });
  });

  group('error', () {
    semTest('error is assertive; the popover retries and exports', (t) async {
      await pumpWith(t, indicator());
      store.set(id, SyncState.error, error: {'class': 'backoff'});
      await tick(t);
      final a = announcements().single;
      expect(a['message'], '저장 안 됨');
      expect(a['assertiveness'], 1);

      await t.tap(find.byType(IconButton));
      await tick(t);
      expect(
        find.text('변경은 이 기기에 보관 중이에요. 다시 시도하거나 동기화 로그 내보내기를 해 주세요.'),
        findsOneWidget,
      );
      expect(find.text('동기화 로그 내보내기'), findsOneWidget);
      expect(find.text('지금 동기화'), findsNothing);
      await t.tap(find.text('다시 시도'));
      await tick(t);
      expect(coord.calls, ['retry:$id']);
    });

    semTest('[지금 동기화] syncs the open note', (t) async {
      await pumpWith(t, indicator());
      await t.tap(find.byType(IconButton));
      await tick(t);
      expect(find.text('모든 변경이 Drive에 저장됐어요.'), findsOneWidget);
      await t.tap(find.text('지금 동기화'));
      await tick(t);
      expect(coord.calls, ['syncNow:$id']);
    });

    semTest('saved-state announcements are polite, once per 10 s, '
        'never per stroke', (t) async {
      await pumpWith(t, indicator());
      store.set(id, SyncState.pending);
      await tick(t);
      final reads = store.reads;
      for (var i = 0; i < 20; i++) {
        store.edit(id); // strokes
      }
      await tick(t);
      expect(store.reads, reads); // no reread per stroke
      store.set(id, SyncState.synced);
      await tick(t);
      store.set(id, SyncState.pending);
      await tick(t);
      final polite = announcements().where((a) => a['assertiveness'] == null);
      expect(polite.map((a) => a['message']), ['저장 대기']);
    });

    semTest('a first edit of a saved note flips it to pending', (t) async {
      await pumpWith(t, indicator());
      store.states[id] = SyncState.pending; // what readSync derives
      store.edit(id);
      await tick(t);
      expect(icon(Icons.schedule), findsOneWidget);
    });
  });

  group('quota', () {
    semTest('one notice per run, popover with [Drive 공간 관리], no retry', (
      t,
    ) async {
      await pumpWith(t, indicator());
      store.set(id, SyncState.error, error: {'class': 'quota'});
      await tick(t);
      const text = 'Drive 저장 공간이 부족해요. 이 기기에 보관 중이에요.';
      expect(find.text(text), findsOneWidget); // the snack bar
      expect(announcements().where((a) => a['message'] == text), hasLength(1));
      expect(
        announcements().firstWhere(
          (a) => a['message'] == text,
        )['assertiveness'],
        1,
      );
      expect(icon(Icons.error_outline), findsOneWidget);

      // Again: no second notice.
      store.set(id, SyncState.synced);
      await tick(t);
      ScaffoldMessenger.of(t.element(find.byType(Scaffold))).clearSnackBars();
      await tick(t, 500);
      store.set(id, SyncState.error, error: {'class': 'quota'});
      await tick(t);
      expect(find.text(text), findsNothing);
      expect(announcements().where((a) => a['message'] == text), hasLength(1));

      await t.tap(find.byType(IconButton));
      await tick(t);
      expect(find.text(text), findsOneWidget); // the popover
      await t.tap(find.text('Drive 공간 관리'));
      await tick(t);
      expect(opened, [driveStorageUri]);
      expect(coord.calls, isEmpty); // nothing retried by itself
    });
  });

  group('re-login banner', () {
    const banner = '로그인이 만료됐어요. 변경은 이 기기에 보관 중이에요.';

    semTest('shows, forces error, re-login resumes all notes', (t) async {
      await pumpWith(t, indicator());
      expect(find.text(banner), findsNothing);
      store.set(id, SyncState.error, error: {'class': 'reauth'});
      await tick(t);
      expect(find.text(banner), findsOneWidget);
      expect(icon(Icons.error_outline), findsOneWidget);
      expect(
        t
            .getSize(
              find
                  .ancestor(
                    of: find.text(banner),
                    matching: find.byType(ColoredBox),
                  )
                  .first,
            )
            .width,
        900, // the screen's width
      );

      await t.tap(find.text('다시 로그인'));
      await tick(t);
      expect(_Root.signIns, 1);
      expect(coord.calls, ['retryAll']);

      // After the retry the notes are pending again: the banner goes.
      store.set(id, SyncState.pending);
      await tick(t);
      expect(find.text(banner), findsNothing);
    });

    semTest('a higher priority banner keeps the slot', (t) async {
      await pumpWith(t, indicator(higher: true));
      store.set(id, SyncState.error, error: {'class': 'reauth'});
      await tick(t);
      expect(find.text(banner), findsNothing);
      expect(icon(Icons.error_outline), findsOneWidget);
    });

    semTest('the banner appears first in reading order', (t) async {
      await pumpWith(t, indicator());
      store.set(id, SyncState.error, error: {'class': 'reauth'});
      await tick(t);
      final s = t.widget<Semantics>(
        find
            .ancestor(of: find.text(banner), matching: find.byType(Semantics))
            .first,
      );
      expect(s.properties.liveRegion, isTrue);
      expect(s.properties.sortKey, isA<OrdinalSortKey>());
    });
  });

  group('library card badges', () {
    semTest('badge per state, none for synced, state in the value', (t) async {
      store = _Store([
        _note(0x901, 'Synced'),
        _note(0x902, 'Waiting'),
        _note(0x903, 'Conflicted'),
        _note(0x904, 'Broken'),
      ]);
      store.states[_id(0x901)] = SyncState.synced;
      store.states[_id(0x902)] = SyncState.pending;
      store.states[_id(0x903)] = SyncState.conflict;
      store.states[_id(0x904)] = SyncState.error;
      store.errors[_id(0x904)] = {'class': 'fatal'};
      await pumpWith(t, const Scaffold(body: LibraryScreen()));
      await tick(t);

      expect(find.text('저장 대기'), findsOneWidget);
      expect(find.text('두 버전'), findsOneWidget);
      expect(find.text('저장 안 됨'), findsOneWidget);
      expect(find.text('저장됨'), findsNothing);

      Color? fill(String text) =>
          (t
                      .widget<DecoratedBox>(
                        find
                            .ancestor(
                              of: find.text(text),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      expect(fill('두 버전'), KkjLight.componentsBadgeConflictBackground);
      expect(fill('저장 안 됨'), KkjLight.componentsBadgeErrorBackground);
      expect(fill('저장 대기'), KkjLight.componentsBadgeNeutralBackground);
      expect(
        t.widget<Text>(find.text('두 버전')).style?.color,
        KkjLight.componentsBadgeConflictText,
      );

      String? value(String title) => t
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.label == title)
          .map((s) => s.properties.value)
          .firstOrNull;
      expect(value('Conflicted'), startsWith('두 버전'));
      expect(value('Waiting'), startsWith('저장 대기'));
      expect(value('Broken'), startsWith('저장 안 됨'));
      expect(value('Synced'), isNot(contains('저장')));
      await t.pumpWidget(const SizedBox());
    });

    semTest('the banner sits above the library header', (t) async {
      store = _Store([_note(0x901, 'Synced')]);
      store.set(_id(0x901), SyncState.error, error: {'class': 'reauth'});
      await pumpWith(t, const Scaffold(body: LibraryScreen()));
      await tick(t);
      expect(find.text('로그인이 만료됐어요. 변경은 이 기기에 보관 중이에요.'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('로그인이 만료됐어요. 변경은 이 기기에 보관 중이에요.')).dy,
        lessThan(t.getTopLeft(find.text('Notes')).dy),
      );
      await t.pumpWidget(const SizedBox());
    });
  });

  group('editor', () {
    semTest('the indicator sits in the corner and the banner pushes the '
        'page down', (t) async {
      await pumpWith(t, NoteEditor(note: makeNote(title: 'Alpha')));
      await tick(t);
      expect(find.byType(SyncIndicator), findsOneWidget);
      final before = t.getTopLeft(find.byType(SyncIndicator)).dy;

      store.set(id, SyncState.error, error: {'class': 'reauth'});
      await tick(t);
      final banner = find.text('로그인이 만료됐어요. 변경은 이 기기에 보관 중이에요.');
      expect(banner, findsOneWidget);
      expect(t.getTopLeft(find.byType(SyncIndicator)).dy, greaterThan(before));
      expect(
        t.getTopLeft(find.byType(SyncIndicator)).dy,
        greaterThan(t.getBottomLeft(banner).dy - 1),
      );
      await t.pumpWidget(const SizedBox());
    });
  });

  group('store and coordinator', () {
    test('NoteStore.changes: write is not sync, updateSync is', () async {
      final docs = Directory.systemTemp.createTempSync('kkj-chg-');
      addTearDown(() => docs.deleteSync(recursive: true));
      final s = NoteStore(NoteData(() async => docs));
      final seen = <bool>[];
      final sub = s.changes.listen((e) => seen.add(e.sync));
      addTearDown(sub.cancel);
      await s.write(makeNote());
      await s.updateSync(noteId, (c) => c.copyWith(state: SyncState.pending));
      final n = makeNote();
      await s.commitSync(n, n, const SyncInfo(baseHeadRevisionId: 'R1'));
      await s.commitReceive(
        noteId,
        expected: n,
        guard: const SyncInfo(baseHeadRevisionId: 'R1'),
        working: n,
        base: n,
        change: (c) => c.copyWith(baseHeadRevisionId: 'R1'),
      );
      await s.mergeWorking<int>(
        noteId,
        (cur, info) => (value: 1, note: null, sync: (i) => i, sidecars: []),
      );
      await s.storeUnreadable('01926f3a-0000-7000-8000-000000000901', [
        1,
        2,
        3,
      ], const SyncInfo());
      await Future<void>.delayed(Duration.zero);
      expect(seen, [false, true, true, true, true, true]);
    });

    late UploadEnv env;
    late OpenNote open;
    late UploadCoordinator coordinator;
    var received = 0;

    Future<void> setUpCoordinator() async {
      env = await UploadEnv.create();
      open = OpenNote(env.data.rootDir);
      received = 0;
      coordinator = UploadCoordinator(
        store: env.store,
        uploader: env.uploader(),
        openNote: open,
        lease: UploadLease(env.data, () => DateTime.utc(2026, 10, 17)),
        log: env.log,
        allowed: () async => env.allowed,
        online: () async => env.online,
        schedule: () async {},
        receive: () async => received++,
      );
    }

    Future<void> failWith(DriveError e) async {
      await env.save(makeNote());
      env.drive.failures['upload'] = [e];
      await coordinator.noteClosed(noteId);
      expect(env.info.state, SyncState.error);
    }

    test('syncNow uploads the open note without closing it, then asks for '
        'changes', () async {
      await setUpCoordinator();
      await env.save(makeNote());
      await open.set(noteId);
      var flushed = false;
      coordinator.flushOpen = () async => flushed = true;
      await coordinator.syncNow(noteId);
      expect(flushed, isTrue);
      expect(env.drive.uploads, hasLength(1));
      expect(env.info.state, SyncState.synced);
      expect(await open.read(), noteId); // still open
      expect(received, 1);
    });

    test('retry moves error to pending and uploads, even for a class the '
        'once-per-run rule stopped', () async {
      await setUpCoordinator();
      await failWith(
        const DriveError('http', status: 403, reason: 'storageQuotaExceeded'),
      );
      await coordinator.retry(noteId);
      expect(env.info.state, SyncState.synced);
    });

    test('quota is not retried by a reconnect, but by a foreground', () async {
      await setUpCoordinator();
      await failWith(
        const DriveError('http', status: 403, reason: 'storageQuotaExceeded'),
      );
      env.drive.calls.clear();
      await coordinator.reconnected();
      expect(env.info.state, SyncState.error);
      expect(env.drive.calls, isEmpty);
      await coordinator.foreground();
      expect(env.info.state, SyncState.synced);
    });

    test(
      'foreground clears the error of the open note, without uploading it',
      () async {
        await setUpCoordinator();
        await failWith(
          const DriveError('http', status: 403, reason: 'storageQuotaExceeded'),
        );
        await open.set(noteId);
        env.drive.calls.clear();
        await coordinator.foreground();
        expect(env.info.state, SyncState.pending);
        expect(env.drive.calls, isEmpty);
      },
    );

    test('retryAll after sign-in: reauth notes upload again', () async {
      await setUpCoordinator();
      await failWith(const DriveError('http', status: 401));
      expect(env.info.lastError?['class'], 'reauth');
      await coordinator.retryAll();
      expect(env.info.state, SyncState.synced);
    });

    test('a deleted note is not retried by hand either', () async {
      await setUpCoordinator();
      await failWith(const DriveError('http', status: 404));
      await coordinator.retry(noteId);
      expect(env.info.state, SyncState.error);
    });
  });
}

/// Real time never passes in a widget test: [ms] of fake time and the
/// microtasks the async reads need.
Future<void> tick(WidgetTester t, [int ms = 0]) async {
  await t.pump(Duration(milliseconds: ms));
  await t.pump();
}
