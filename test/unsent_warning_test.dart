import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_device_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/unsent.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'account_gate_test.dart' show settleIo;
import 'fake_auth_gateway.dart';
import 'shell_test.dart' show pumpApp;

const logoutBody2 =
    "2 changes weren't sent. If you log out, they will be lost.";
const discardLogout = 'Discard and log out';
const discardDisconnect = 'Discard and disconnect';
const again = 'Press again to discard';

bool focused(WidgetTester t, Finder f) =>
    Focus.of(t.element(f)).hasPrimaryFocus;

const noteIdA = '01926f3a-0000-7000-8000-000000000900';
const noteIdB = '01926f3a-0000-7000-8000-000000000901';

Note _note(String id) => createNote(
  title: 'a',
  existingTitles: [],
  background: 'plain',
  orientation: 'portrait',
  noteId: id,
  pageId: '01926f3a-0000-7000-8000-000000000001',
  pageRev: '01926f3a-0000-7000-8000-000000000051',
  metaRev: '01926f3a-0000-7000-8000-000000000911',
  orderRev: '01926f3a-0000-7000-8000-000000000912',
  now: '2026-10-10T04:20:00.000Z',
  editedBy: 'Pixel 8',
).note!;

class _FailingList extends NoteStore {
  _FailingList(super.data);
  @override
  Future<List<String>> ids() => throw const FileSystemException('x');
}

/// The notes clear fine, but the device record stays (a delete that fails
/// is swallowed by the real store) or cannot be read back.
class _StuckDevice extends SyncDeviceStore {
  _StuckDevice(super.data, {this.readFails = false});
  final bool readFails;
  @override
  Future<void> clear() async {}
  @override
  Future<SyncDevice> read() =>
      readFails ? throw const FileSystemException('x') : super.read();
}

class _FailingClear extends NoteData {
  _FailingClear(super.documents);
  @override
  Future<void> clear() => throw const FileSystemException('busy');
}

void main() {
  group('settings', () {
    late FakeAuthGateway gate;
    late List<String> events;
    var counts = 0;
    List<String>? ids = ['n1', 'n2'];
    Completer<void>? hold;
    var discards = <bool>[true];

    setUp(() {
      events = [];
      counts = 0;
      ids = ['n1', 'n2'];
      hold = null;
      discards = [true];
      gate = FakeAuthGateway(restored: true);
    });

    Future<void> pump(WidgetTester t) => pumpApp(
      t,
      auth: gate,
      stubUnsent: false,
      overrides: [
        unsentIdsProvider.overrideWithValue(() async {
          counts++;
          await hold?.future;
          return ids;
        }),
        discardLocalDataProvider.overrideWithValue(() async {
          events.add('discard:signOut=${gate.signOutCalls}');
          return discards.length > 1 ? discards.removeAt(0) : discards.first;
        }),
      ],
    );

    Future<void> openSettings(WidgetTester t) async {
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
    }

    group('log out', () {
      testWidgets('with unsent changes only the warning and cancel show, '
          'cancel is focused', (t) async {
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        expect(find.text('Changes weren\'t sent'), findsOneWidget);
        expect(find.text('Log out?'), findsNothing); // replaced, not stacked
        expect(find.text(logoutBody2), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(TextButton), findsOneWidget);
        expect(find.text(discardLogout), findsOneWidget);
        expect(focused(t, find.text('Cancel')), isTrue);
        expect(focused(t, find.text(discardLogout)), isFalse);
        expect(
          t.getSize(find.widgetWithText(FilledButton, discardLogout)).height,
          greaterThanOrEqualTo(48),
        );
        expect(gate.signOutCalls, 0);
      });

      testWidgets('the first press only arms, the second signs out and then '
          'erases', (t) async {
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        await t.tap(find.text(discardLogout));
        await t.pumpAndSettle();
        expect(find.text(again), findsOneWidget);
        expect(find.text(discardLogout), findsNothing);
        expect(focused(t, find.text('Cancel')), isTrue);
        expect(gate.signOutCalls, 0);
        expect(events, isEmpty);
        await t.tap(find.text(again));
        await t.pumpAndSettle();
        expect(gate.signOutCalls, 1);
        expect(events, ['discard:signOut=1']);
        expect(find.text('Sign in with Google'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      });

      testWidgets('a double tap on the armed button runs once', (t) async {
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        await t.tap(find.text(discardLogout));
        await t.pumpAndSettle();
        await t.tap(find.text(again));
        await t.tap(find.text(again)); // no frame in between
        await t.pumpAndSettle();
        expect(gate.signOutCalls, 1);
        expect(events.length, 1);
      });

      testWidgets('Back and Cancel change nothing', (t) async {
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Privacy policy'), findsOneWidget);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(gate.signOutCalls, 0);
        expect(events, isEmpty);
      });

      testWidgets('a failed erase shows the error and retries', (t) async {
        discards = [false, true];
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        await t.tap(find.text(discardLogout));
        await t.pumpAndSettle();
        await t.tap(find.text(again));
        await t.pumpAndSettle();
        expect(
          find.textContaining("Couldn't erase the note copies"),
          findsOneWidget,
        );
        await t.tap(find.text('Try again'));
        await t.pumpAndSettle();
        expect(events.length, 2);
        expect(gate.signOutCalls, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Sign in with Google'), findsOneWidget);
      });

      testWidgets('could not check: unknown wording, still a warning', (
        t,
      ) async {
        ids = null;
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        expect(
          find.textContaining("Couldn't check for changes that weren't sent"),
          findsOneWidget,
        );
        expect(find.text(discardLogout), findsOneWidget);
        expect(gate.signOutCalls, 0);
      });

      testWidgets('nothing unsent: only the "Log out?" confirm (Story 11.9), '
          'no unsent warning', (t) async {
        ids = [];
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        expect(find.text('Log out?'), findsOneWidget);
        expect(find.text("Changes weren't sent"), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(gate.signOutCalls, 0);
        await t.tap(find.widgetWithText(FilledButton, 'Log out'));
        await t.pumpAndSettle();
        expect(gate.signOutCalls, 1);
        expect(events, isEmpty);
        expect(find.text('Sign in with Google'), findsOneWidget);
      });

      testWidgets('edited while the plain confirm is open: the confirm press '
          'counts again and returns to the warning', (t) async {
        ids = [];
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        ids = ['n1'];
        await t.tap(find.widgetWithText(FilledButton, 'Log out'));
        await t.pumpAndSettle();
        expect(gate.signOutCalls, 0);
        expect(find.text("Changes weren't sent"), findsOneWidget);
        expect(find.text('Log out?'), findsNothing);
      });

      testWidgets('the armed discard button relaxes after about 5 s', (
        t,
      ) async {
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pumpAndSettle();
        await t.tap(find.text(discardLogout));
        await t.pumpAndSettle();
        expect(find.text(again), findsOneWidget);
        await t.pump(const Duration(seconds: 6));
        expect(find.text(again), findsNothing);
        expect(find.text(discardLogout), findsOneWidget);
      });

      testWidgets('two presses while counting count once and open one '
          'dialog', (t) async {
        hold = Completer<void>();
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pump();
        await t.tap(find.text('Log out'));
        await t.pump();
        expect(counts, 1);
        hold!.complete();
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('leaving Settings while counting opens nothing', (t) async {
        hold = Completer<void>();
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Log out'));
        await t.pump();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('Privacy policy'), findsNothing);
        hold!.complete();
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(gate.signOutCalls, 0);
        expect(t.takeException(), isNull);
      });
    });

    group('disconnect', () {
      testWidgets('with unsent changes: count line, only the two-step '
          'discard and cancel', (t) async {
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Disconnect'));
        await t.pumpAndSettle();
        expect(find.textContaining("2 changes weren't sent."), findsOneWidget);
        expect(
          find.textContaining(
            'The note copies and sign-in info on this device will be erased.',
          ),
          findsOneWidget,
        );
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.text(discardDisconnect), findsOneWidget);
        expect(focused(t, find.text('Cancel')), isTrue);
        await t.tap(find.text(discardDisconnect));
        await t.pumpAndSettle();
        expect(find.text(again), findsOneWidget);
        expect(gate.disconnectCalls, 0);
        expect(focused(t, find.text(again)), isFalse);
        await t.tap(find.text(again));
        await settleIo(t);
        expect(gate.disconnectCalls, 1);
      });

      testWidgets('Cancel and Back revoke nothing', (t) async {
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Disconnect'));
        await t.pumpAndSettle();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(gate.disconnectCalls, 0);
      });

      testWidgets('nothing unsent: the plain Story 3.5 confirmation', (
        t,
      ) async {
        ids = [];
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Disconnect'));
        await t.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Disconnect'), findsOneWidget);
        expect(find.text(discardDisconnect), findsNothing);
        expect(find.textContaining('weren\'t sent'), findsNothing);
        await t.tap(find.widgetWithText(FilledButton, 'Disconnect'));
        await settleIo(t);
        expect(gate.disconnectCalls, 1);
      });

      testWidgets('edited while the plain confirm is open: the confirm press '
          'counts again and returns to the warning', (t) async {
        ids = [];
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Disconnect'));
        await t.pumpAndSettle();
        ids = ['n1'];
        await t.tap(find.widgetWithText(FilledButton, 'Disconnect'));
        await t.pumpAndSettle();
        expect(gate.disconnectCalls, 0);
        expect(find.text(discardDisconnect), findsOneWidget);
        expect(find.textContaining("1 change wasn't sent"), findsOneWidget);
      });

      testWidgets('two presses while counting count once', (t) async {
        hold = Completer<void>();
        await pump(t);
        await openSettings(t);
        await t.tap(find.text('Disconnect'));
        await t.pump();
        await t.tap(find.text('Disconnect'));
        await t.pump();
        expect(counts, 1);
        hold!.complete();
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    });
  });

  group('unsentNoteIds with real files', () {
    late Directory docs;
    late NoteData data;

    setUp(() {
      docs = Directory.systemTemp.createTempSync('kkj-unsent-');
      data = NoteData(() async => docs);
      addTearDown(() => docs.deleteSync(recursive: true));
    });

    test('lists only notes with changes Drive does not have', () async {
      final store = NoteStore(data);
      await store.commitSync(
        _note(noteIdA),
        _note(noteIdA),
        const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
      );
      await store.write(_note(noteIdB)); // never uploaded
      expect(await unsentNoteIds(store), [noteIdB]);
    });

    test('a listing failure is unknown, not none', () async {
      expect(await unsentNoteIds(_FailingList(data)), isNull);
      expect(await unsentNoteIds(NoteStore(data)), isEmpty);
    });

    test('workingBytes is the raw file, also when it is not a note', () async {
      final store = NoteStore(data);
      expect(await store.workingBytes(noteIdA), isNull);
      await store.write(_note(noteIdA));
      final file = File('${docs.path}/$noteDataDirName/$noteIdA/working.kkj');
      expect(await store.workingBytes(noteIdA), file.readAsBytesSync());
      file.writeAsBytesSync([1, 2, 3]);
      expect(await store.workingBytes(noteIdA), [1, 2, 3]);
    });

    ProviderContainer container(NoteData d, SyncDeviceStore device) {
      final c = ProviderContainer(
        overrides: [
          noteDataProvider.overrideWithValue(d),
          syncDeviceStoreProvider.overrideWithValue(device),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('discarding erases the notes, the device record and histories, '
        'not the log', () async {
      final device = SyncDeviceStore(data);
      await device.adoptAccount('sub-a', 'a@example.com');
      await NoteStore(data).write(_note(noteIdA));
      final log = File('${docs.path}/sync-log.jsonl')..writeAsStringSync('x');
      final c = container(data, device);
      expect(await c.read(discardLocalDataProvider)(), isTrue);
      expect(Directory('${docs.path}/$noteDataDirName').existsSync(), isFalse);
      expect(File('${docs.path}/$syncDeviceFileName').existsSync(), isFalse);
      expect(log.existsSync(), isTrue);
      // The same account can be adopted again after the erase.
      expect(await device.adoptAccount('sub-b', 'b@example.com'), isTrue);
    });

    test('the device record surviving clear(), or unreadable after it, is '
        'a failed discard', () async {
      final stuck = _StuckDevice(data);
      await stuck.adoptAccount('sub-a', 'a@example.com');
      expect(await container(data, stuck).read(discardLocalDataProvider)(), isFalse);
      expect((await stuck.read()).sub, 'sub-a');
      final broken = _StuckDevice(data, readFails: true);
      expect(await container(data, broken).read(discardLocalDataProvider)(), isFalse);
    });

    test(
      'a notes folder that cannot be deleted keeps the device record',
      () async {
        final failing = _FailingClear(() async => docs);
        final device = SyncDeviceStore(failing);
        await device.adoptAccount('sub-a', 'a@example.com');
        final c = container(failing, device);
        expect(await c.read(discardLocalDataProvider)(), isFalse);
        expect((await device.read()).sub, 'sub-a');
      },
    );
  });
}
