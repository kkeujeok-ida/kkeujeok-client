import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/drive/root_folder.dart' show RootStatus;
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/note_receiver.dart';
import 'package:kkeujeok/sync/upload_coordinator.dart';
import 'package:kkeujeok/ui/cannot_open_sheet.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/sync_banner.dart';
import 'package:kkeujeok/ui/sync_display.dart' show connectivityChangesProvider;

import 'fake_auth_gateway.dart';
import 'fake_receiver.dart';
import 'shell_test.dart' show pumpApp;
import 'sync_display_test.dart' show tick;
import 'upload_env.dart';

/// A store whose sync state is scripted and read without file IO.
class _Store extends NoteStore {
  _Store() : super(NoteData(() async => Directory.systemTemp));

  final states = <String, SyncInfo>{};
  final _c = StreamController<({String noteId, bool sync})>.broadcast(
    sync: true,
  );
  int writes = 0;

  @override
  Stream<({String noteId, bool sync})> get changes => _c.stream;

  void set(String id, SyncState s, {Map<String, Object?>? error}) {
    states[id] = SyncInfo(state: s, lastError: error);
    _c.add((noteId: id, sync: true));
  }

  @override
  Future<void> write(Note note) async => writes++;

  @override
  Future<SyncRead> readSync(String noteId) async {
    final i = states[noteId] ?? const SyncInfo(state: SyncState.synced);
    return (info: i, base: null, hasUnsent: false, state: i.state);
  }

  @override
  Future<List<String>> ids() async => states.keys.toList();
}

class _Coord implements UploadCoordinator {
  final calls = <String>[];

  @override
  Future<void> Function()? flushOpen;

  @override
  Future<void> syncNow(String id) async => calls.add('syncNow:$id');
  @override
  Future<void> noteClosed(String id) async => calls.add('closed:$id');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Root extends RootFolderNotifier {
  @override
  RootFolderState build() => const RootFolderState(RootStatus.ready);
}

void main() {
  const id = noteId;
  late _Store store;
  late _Coord coord;
  late RecReceiver recv;
  late int closes;

  setUp(() {
    store = _Store();
    coord = _Coord();
    recv = RecReceiver();
    closes = 0;
  });

  List<Override> overrides() => [
    noteStoreProvider.overrideWithValue(store),
    uploadCoordinatorProvider.overrideWithValue(coord),
    connectivityChangesProvider.overrideWithValue(const Stream<bool>.empty()),
    networkProbeProvider.overrideWithValue(() async => true),
    noteReceiverProvider.overrideWithValue(recv),
    rootFolderProvider.overrideWith(_Root.new),
  ];

  Future<void> pumpBanner(
    WidgetTester t, {
    bool higher = false,
    String lang = 'ko',
  }) async {
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
          home: Scaffold(
            body: SyncBanner(
              higherPriority: higher,
              noteId: id,
              onCloseNote: () => closes++,
            ),
          ),
        ),
      ),
    );
    await tick(t);
  }

  const deletedText = '다른 기기에서 지운 노트예요.';
  const newVersionText = '새 버전에서 만든 노트예요. 앱을 업데이트하면 편집할 수 있어요.';
  const reauthText = '로그인이 만료됐어요. 변경은 이 기기에 보관 중이에요.';
  const deleted = {'class': 'deleted', 'reason': 'trashed'};

  group('banner', () {
    testWidgets('deleted: text, [다시 살리기] revives then syncs, [닫기] closes', (
      t,
    ) async {
      final h = t.ensureSemantics();
      await pumpBanner(t);
      expect(find.text(deletedText), findsNothing);
      store.set(id, SyncState.error, error: deleted);
      await tick(t);
      expect(find.text(deletedText), findsOneWidget);
      final s = t.widget<Semantics>(
        find
            .ancestor(
              of: find.text(deletedText),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(s.properties.liveRegion, isTrue);
      expect(s.properties.sortKey, isA<OrdinalSortKey>());

      await t.tap(find.text('다시 살리기'));
      await tick(t);
      expect(recv.revived, [id]);
      expect(coord.calls, ['syncNow:$id']);
      await t.tap(find.text('닫기'));
      expect(closes, 1);
      h.dispose();
    });

    testWidgets('newer format: the banner has no action', (t) async {
      await pumpBanner(t);
      store.set(
        id,
        SyncState.error,
        error: {'class': 'unreadable', 'reason': 'unsupportedVersion'},
      );
      await tick(t);
      expect(find.text(newVersionText), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('newer format holds the slot over re-login', (t) async {
      await pumpBanner(t);
      store.set(
        id,
        SyncState.error,
        error: {'class': 'unreadable', 'reason': 'unsupportedVersion'},
      );
      store.set(
        '01926f3a-0000-7000-8000-000000000999',
        SyncState.error,
        error: {'class': 'reauth'},
      );
      await tick(t);
      expect(find.text(newVersionText), findsOneWidget);
      expect(find.text(reauthText), findsNothing);
    });

    testWidgets('a read-only conflict keeps the slot over both', (t) async {
      await pumpBanner(t, higher: true);
      store.set(id, SyncState.error, error: deleted);
      await tick(t);
      expect(find.text(deletedText), findsNothing);
    });

    testWidgets('deleted holds the slot over newer format and re-login', (
      t,
    ) async {
      await pumpBanner(t);
      store.set(id, SyncState.error, error: deleted);
      store.set(
        '01926f3a-0000-7000-8000-000000000999',
        SyncState.error,
        error: {'class': 'reauth'},
      );
      await tick(t);
      expect(find.text(deletedText), findsOneWidget);
      expect(find.text(reauthText), findsNothing);
      store.set(id, SyncState.pending); // the deleted state ends
      await tick(t);
      expect(find.text(deletedText), findsNothing);
      expect(find.text(reauthText), findsOneWidget);
    });
  });

  group('editor', () {
    Future<void> openEditor(WidgetTester t) async {
      t.view.physicalSize = const Size(900, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NoteEditor(note: makeNote(title: 'Alpha')),
          ),
        ),
      );
      await tick(t);
    }

    Future<void> scribble(WidgetTester t) async {
      final g = await t.startGesture(
        t.getCenter(find.byType(NoteEditor)),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(60, 30));
      await g.up();
      await t.pump(const Duration(milliseconds: 50));
    }

    testWidgets('a newer-format note is read-only and shows the banner', (
      t,
    ) async {
      store.set(
        id,
        SyncState.error,
        error: {'class': 'unreadable', 'reason': 'unsupportedVersion'},
      );
      await openEditor(t);
      expect(find.text(newVersionText), findsOneWidget);
      await scribble(t);
      expect(store.writes, 0);
    });

    testWidgets('the same note draws and saves when it is not read-only', (
      t,
    ) async {
      await openEditor(t);
      await scribble(t);
      expect(store.writes, greaterThan(0));
    });

    testWidgets('the deleted banner shows in the editor', (t) async {
      store.set(id, SyncState.error, error: deleted);
      await openEditor(t);
      expect(find.text(deletedText), findsOneWidget);
    });
  });

  group('library', () {
    late Directory docs;
    late NoteData data;
    late NoteStore real;
    late List<Uri> opened;
    late List<List<File>> shared;

    setUp(() {
      docs = Directory.systemTemp.createTempSync('kkj-ext-ui-');
      data = NoteData(() async => docs);
      real = NoteStore(data);
      opened = [];
      shared = [];
      addTearDown(() {
        try {
          docs.deleteSync(recursive: true);
        } on FileSystemException {
          // The OS cleans temp up later.
        }
      });
    });

    Future<void> until(WidgetTester t, String text) async {
      for (var i = 0; i < 200 && find.text(text).evaluate().isEmpty; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await t.pump();
      }
    }

    /// The sheet reads the note's files; real IO needs real time.
    Future<void> sheetLoaded(WidgetTester t) async {
      for (var i = 0; i < 80; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await t.pump();
      }
    }

    Future<void> open(WidgetTester t, String firstText) async {
      await pumpApp(
        t,
        auth: FakeAuthGateway(restored: true)
          ..account = const AuthAccount(sub: 's', email: 'e'),
        noteData: data,
        overrides: <Override>[
          noteReceiverProvider.overrideWithValue(recv),
          rootFolderProvider.overrideWith(_Root.new),
          urlOpenerProvider.overrideWithValue((u) async {
            opened.add(u);
            return true;
          }),
          noteFilesSharerProvider.overrideWithValue((files) async {
            shared.add([
              for (final f in files) File(f.path)..readAsBytesSync(),
            ]);
          }),
          exportDirProvider.overrideWithValue(() async => docs),
        ],
        settle: false,
      );
      await until(t, firstText);
    }

    /// A readable local note whose remote file cannot be read.
    Future<void> brokenRemote({required bool unsent}) async {
      final n = makeNote(title: 'Local');
      final info = const SyncInfo(
        fileId: 'FILE1',
        baseHeadRevisionId: 'R1',
        state: SyncState.error,
        lastError: {'class': 'unreadable', 'reason': 'parse', 'head': 'R2'},
      );
      await real.commitSync(n, n, info);
      if (unsent) await real.write(makeNote(rev: 3, title: 'Local'));
    }

    testWidgets('a readable note with an unreadable remote is the "열 수 없음" '
        'card and opens the sheet', (t) async {
      await t.runAsync(() => brokenRemote(unsent: false));
      await open(t, "Can't open");
      expect(find.text('Local'), findsNothing);
      await t.tap(find.text("Can't open"));
      await t.pumpAndSettle();
      await sheetLoaded(t);
      expect(
        find.text('This note file cannot be read. The file was left as it is.'),
        findsOneWidget,
      );
      expect(find.text('View in Drive'), findsOneWidget);
      expect(find.text('Export sync log'), findsOneWidget);
      expect(find.text('Download as file'), findsNothing); // nothing unsent
      expect(find.text('Retry'), findsNothing);
      await t.tap(find.text('View in Drive'));
      await t.pump();
      expect(opened.single, driveFileUri('FILE1'));
      expect(
        opened.single.toString(),
        'https://drive.google.com/file/d/FILE1/view',
      );
    });

    testWidgets('with unsent changes the sheet adds the device copy', (
      t,
    ) async {
      await t.runAsync(() => brokenRemote(unsent: true));
      await open(t, "Can't open");
      await t.tap(find.text("Can't open"));
      await t.pumpAndSettle();
      await sheetLoaded(t);
      expect(find.text('Download as file'), findsOneWidget);
      await t.tap(find.text('Download as file'));
      await sheetLoaded(t);
      expect(shared, hasLength(1));
      expect(shared.single.single.path, endsWith('$noteId.kkj'));
    });

    testWidgets('a card of a note that cannot be decoded here opens the '
        'sheet too, without a Drive link when it has no file', (t) async {
      final f = File('${docs.path}/$noteDataDirName/$noteId/working.kkj');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync([1, 2, 3]);
      await open(t, "Can't open");
      await t.tap(find.text("Can't open"));
      await t.pumpAndSettle();
      await sheetLoaded(t);
      expect(find.text('View in Drive'), findsNothing);
      expect(find.text('Download as file'), findsNothing); // not readable here
      expect(find.text('Export sync log'), findsOneWidget);
    });

    testWidgets('the revive snackbar shows once per revived note', (t) async {
      final n = makeNote(title: 'Local');
      await t.runAsync(
        () => real.commitSync(
          n,
          n,
          const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
        ),
      );
      await open(t, 'Local');
      const text =
          'This note was deleted on another device but had changes not sent '
          'yet, so it was brought back.';
      expect(find.text(text), findsNothing);
      recv.state.value = const ReceiveState(revived: 1);
      await t.pump();
      await t.pump();
      expect(find.text(text), findsOneWidget);
      recv.state.value = const ReceiveState(revived: 1, version: 2);
      await t.pump();
      expect(find.text(text), findsOneWidget); // still the one snackbar
    });

    testWidgets('leaving the editor asks the receiver, then the uploader', (
      t,
    ) async {
      final n = makeNote(title: 'Local');
      await t.runAsync(
        () => real.commitSync(
          n,
          n,
          const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
        ),
      );
      await open(t, 'Local');
      await t.tap(find.text('Local'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Back to library'));
      await t.pumpAndSettle();
      for (var i = 0; i < 20 && recv.closed.isEmpty; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
      }
      expect(recv.closed, [noteId]);
    });

    testWidgets('the sheet is a route with a name for the screen reader', (
      t,
    ) async {
      final h = t.ensureSemantics();
      await t.runAsync(() => brokenRemote(unsent: false));
      await open(t, "Can't open");
      await t.tap(find.text("Can't open"));
      await t.pumpAndSettle();
      await sheetLoaded(t);
      final s = t
          .widgetList<Semantics>(find.byType(Semantics))
          .where(
            (s) =>
                s.properties.namesRoute == true &&
                s.properties.scopesRoute == true,
          );
      expect(s.map((x) => x.properties.label), contains("Can't open"));
      h.dispose();
    });
  });
}
