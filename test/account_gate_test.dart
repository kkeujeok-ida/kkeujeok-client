import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_device_store.dart';
import 'package:kkeujeok/ui/library.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/shell.dart';
import 'package:kkeujeok/ui/unsent_widgets.dart';

import 'fake_auth_gateway.dart';
import 'fake_receiver.dart';
import 'shell_test.dart' show pumpApp;

const acctA = AuthAccount(sub: 'sub-a', email: 'alice@example.com');
const acctB = AuthAccount(sub: 'sub-b', email: 'bob@example.com');

const body2 = "Account a@… has 2 changes that weren't sent.";
const goBack = 'Go back to the previous account';
const download = 'Save as files';
const discard2 = 'Discard 2 changes from the previous account';
const again = 'Press again to discard';

/// Device record without real IO, which does not finish under the fake clock.
class FakeDevice extends SyncDeviceStore {
  FakeDevice(this.device, Directory dir) : super(NoteData(() async => dir));
  SyncDevice device;
  Future<void>? hold;
  int reads = 0;

  @override
  Future<SyncDevice> read() async {
    reads++;
    await hold;
    return device;
  }
}

class FakeNotes extends NoteStore {
  FakeNotes(this.bytes) : super(NoteData(() async => Directory.systemTemp));
  final Map<String, List<int>?> bytes;
  @override
  Future<List<int>?> workingBytes(String noteId) async => bytes[noteId];
}

/// The shell behind the gate does no Drive work in these tests.
class IdleRoot extends RootFolderNotifier {
  @override
  Future<void> check() async {}
  @override
  Future<void> checkForeground() async {}
}

List<Override> idleShell() => [
  rootFolderProvider.overrideWith(IdleRoot.new),
  noteReceiverProvider.overrideWithValue(RecReceiver()),
];

/// The seams of the gate, recorded.
class Rec {
  List<String>? ids = ['n1', 'n2'];
  Completer<void>? hold; // the count waits for it
  int unsentCalls = 0;
  List<bool> discards = [true];
  int discardCalls = 0;
  Completer<void>? shareHold;
  bool shareFails = false;
  final shared = <Map<String, List<int>>>[];
}

Future<void> settleIo(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
  }
  await t.pumpAndSettle();
}

bool focused(WidgetTester t, Finder f) =>
    Focus.of(t.element(f)).hasPrimaryFocus;

void main() {
  late Rec rec;
  late FakeAuthGateway gate;
  late FakeDevice device;
  late Directory exportDir;

  setUp(() {
    rec = Rec();
    gate = FakeAuthGateway(restored: true)..account = acctB;
    exportDir = Directory.systemTemp.createTempSync('kkj-export-');
    addTearDown(() => exportDir.deleteSync(recursive: true));
    device = FakeDevice(
      const SyncDevice(sub: 'sub-a', email: 'alice@example.com'),
      exportDir,
    );
  });

  Future<void> pump(WidgetTester t, {NoteStore? notes}) => pumpApp(
    t,
    auth: gate,
    noteStore: notes,
    stubUnsent: false,
    overrides: [
      ...idleShell(),
      syncDeviceStoreProvider.overrideWithValue(device),
      unsentIdsProvider.overrideWithValue(() async {
        rec.unsentCalls++;
        await rec.hold?.future;
        return rec.ids;
      }),
      discardLocalDataProvider.overrideWithValue(() async {
        rec.discardCalls++;
        return rec.discards.length > 1
            ? rec.discards.removeAt(0)
            : rec.discards.first;
      }),
      exportDirProvider.overrideWithValue(() async => exportDir),
      noteFilesSharerProvider.overrideWithValue((files) async {
        rec.shared.add({
          for (final f in files) f.uri.pathSegments.last: f.readAsBytesSync(),
        });
        await rec.shareHold?.future;
        if (rec.shareFails) throw StateError('share failed');
      }),
    ],
  );

  void expectNoShell() {
    expect(find.byType(Shell), findsNothing);
    expect(find.byType(LibraryScreen), findsNothing);
  }

  group('mismatch dialog', () {
    testWidgets('names the old account and N, default focus is going back, '
        'and nothing runs behind it', (t) async {
      await pump(t);
      expect(find.text('Signed in with a different account'), findsOneWidget);
      expect(find.text(body2), findsOneWidget);
      expectNoShell();
      expect(focused(t, find.text(goBack)), isTrue);
      expect(focused(t, find.text(discard2)), isFalse);
      expect(rec.discardCalls, 0);
      for (final b in [
        find.widgetWithText(FilledButton, goBack),
        find.widgetWithText(OutlinedButton, download),
        find.widgetWithText(FilledButton, discard2),
      ]) {
        expect(t.getSize(b).height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('system Back does not close it', (t) async {
      await pump(t);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text(body2), findsOneWidget);
      expectNoShell();
    });

    testWidgets('going back signs out, once, and keeps the data', (t) async {
      gate = FakeAuthGateway(restored: true, signOutHangs: true)
        ..account = acctB;
      await pump(t);
      await t.tap(find.text(goBack));
      await t.pump();
      await t.tap(find.text(goBack)); // a second press while it runs
      await t.pump();
      expect(gate.signOutCalls, 1);
      await t.pump(const Duration(seconds: 11));
      await t.pumpAndSettle();
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(rec.discardCalls, 0);
    });

    testWidgets('the old account signing in again goes straight on', (t) async {
      gate = FakeAuthGateway(restored: false, signInAccount: acctA);
      await pump(t);
      await t.tap(find.text('Sign in with Google'));
      await t.pumpAndSettle();
      expect(find.byType(Shell), findsOneWidget);
      expect(rec.unsentCalls, 0);
      expect(rec.discardCalls, 0);
    });

    testWidgets('signing in as another account from the sign-in screen '
        'shows it', (t) async {
      gate = FakeAuthGateway(restored: false, signInAccount: acctB);
      await pump(t);
      expect(find.text('Sign in with Google'), findsOneWidget);
      await t.tap(find.text('Sign in with Google'));
      await t.pumpAndSettle();
      expect(find.text(body2), findsOneWidget);
      expectNoShell();
    });

    testWidgets('discard needs two presses, no new dialog, never focused', (
      t,
    ) async {
      await pump(t);
      await t.tap(find.text(discard2));
      await t.pumpAndSettle();
      expect(find.text(again), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(rec.discardCalls, 0);
      expect(focused(t, find.text(again)), isFalse);
      expect(focused(t, find.text(goBack)), isTrue);
      await t.tap(find.text(again));
      await t.pumpAndSettle();
      expect(rec.discardCalls, 1);
      expect(find.byType(Shell), findsOneWidget);
    });

    testWidgets('the discard button is in a live region', (t) async {
      await pump(t);
      expect(
        find.descendant(
          of: find.byType(TwoStepButton),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsWidgets,
      );
    });

    testWidgets('a failed discard keeps the dialog, the next press retries', (
      t,
    ) async {
      rec.discards = [false, true];
      await pump(t);
      await t.tap(find.text(discard2));
      await t.pumpAndSettle();
      await t.tap(find.text(again));
      await t.pumpAndSettle();
      expect(find.text(body2), findsOneWidget);
      expect(
        find.textContaining("Couldn't erase the previous account"),
        findsOneWidget,
      );
      expectNoShell();
      await t.tap(find.text(again));
      await t.pumpAndSettle();
      expect(rec.discardCalls, 2);
      expect(find.byType(Shell), findsOneWidget);
    });

    testWidgets('a second discard press while it runs is ignored', (t) async {
      final hold = Completer<bool>();
      await pumpApp(
        t,
        auth: gate,
        stubUnsent: false,
        overrides: [
          ...idleShell(),
          syncDeviceStoreProvider.overrideWithValue(device),
          unsentIdsProvider.overrideWithValue(() async => ['n1']),
          discardLocalDataProvider.overrideWithValue(() {
            rec.discardCalls++;
            return hold.future;
          }),
        ],
      );
      await t.tap(find.text('Discard 1 change from the previous account'));
      await t.pumpAndSettle();
      await t.tap(find.text(again));
      await t.pump();
      await t.tap(find.text(again));
      await t.pump();
      expect(rec.discardCalls, 1);
      hold.complete(true);
      await t.pumpAndSettle();
      expect(find.byType(Shell), findsOneWidget);
    });

    testWidgets('unknown count: unknown wording, nothing deleted', (t) async {
      rec.ids = null;
      await pump(t);
      expect(
        find.textContaining("Couldn't check whether account a@…"),
        findsOneWidget,
      );
      expect(
        find.text('Discard changes from the previous account'),
        findsOneWidget,
      );
      expect(rec.discardCalls, 0);
      expectNoShell();
    });
  });

  group('download', () {
    final notes = FakeNotes({
      'n1': [1, 2, 3],
      'n2': null,
      'n3': [9],
    });

    testWidgets('shares one .kkj per note with a working copy, keeps the '
        'dialog, removes the temp files', (t) async {
      rec.ids = ['n1', 'n2', 'n3'];
      await pump(t, notes: notes);
      await t.tap(find.text(download));
      await settleIo(t);
      expect(rec.shared, [
        {
          'n1.kkj': [1, 2, 3],
          'n3.kkj': [9],
        },
      ]);
      expect(find.text('Signed in with a different account'), findsOneWidget);
      expect(exportDir.listSync(), isEmpty);
      expect(rec.discardCalls, 0);
      expect(focused(t, find.textContaining('Discard')), isFalse);
    });

    testWidgets('a second press while it runs is ignored', (t) async {
      rec.ids = ['n1'];
      rec.shareHold = Completer<void>();
      await pump(t, notes: notes);
      await t.tap(find.text(download));
      await settleIo(t);
      await t.tap(find.text(download));
      await settleIo(t);
      expect(rec.shared.length, 1);
      rec.shareHold!.complete();
      await settleIo(t);
      await t.tap(find.text(download));
      await settleIo(t);
      expect(rec.shared.length, 2);
    });

    testWidgets('nothing to save shows an error line', (t) async {
      rec.ids = ['n2'];
      await pump(t, notes: notes);
      await t.tap(find.text(download));
      await settleIo(t);
      expect(find.text('There are no notes to save.'), findsOneWidget);
      expect(rec.shared, isEmpty);
    });

    testWidgets('a failed share shows an error line, dialog stays', (t) async {
      rec.shareFails = true;
      rec.ids = ['n1'];
      await pump(t, notes: notes);
      await t.tap(find.text(download));
      await settleIo(t);
      expect(
        find.text("Couldn't save the files. Please try again."),
        findsOneWidget,
      );
      expect(find.text('Signed in with a different account'), findsOneWidget);
      expect(exportDir.listSync(), isEmpty);
    });
  });

  group('no mismatch', () {
    testWidgets('same account', (t) async {
      device.device = const SyncDevice(sub: 'sub-b');
      await pump(t);
      expect(find.byType(Shell), findsOneWidget);
      expect(rec.unsentCalls, 0);
      expect(rec.discardCalls, 0);
    });

    testWidgets('no record or no tag', (t) async {
      device.device = const SyncDevice();
      await pump(t);
      expect(find.byType(Shell), findsOneWidget);
      expect(rec.discardCalls, 0);
      expect(rec.unsentCalls, 0);
    });

    testWidgets('account unknown: the device is not even read', (t) async {
      gate.account = null;
      await pump(t);
      expect(find.byType(Shell), findsOneWidget);
      expect(device.reads, 0);
      expect(rec.discardCalls, 0);
    });

    testWidgets('a garbage record file and a failing directory read as no '
        'tag', (t) async {
      for (final failing in [false, true]) {
        final docs = Directory.systemTemp.createTempSync('kkj-docs-');
        addTearDown(() => docs.deleteSync(recursive: true));
        File('${docs.path}/$syncDeviceFileName').writeAsStringSync('{ not');
        final data = NoteData(
          () async => failing ? throw const FileSystemException('x') : docs,
        );
        await pumpApp(
          t,
          auth: gate,
          settle: false,
          stubUnsent: false,
          overrides: [
            ...idleShell(),
            syncDeviceStoreProvider.overrideWithValue(SyncDeviceStore(data)),
            unsentIdsProvider.overrideWithValue(() async {
              rec.unsentCalls++;
              return ['n1'];
            }),
            discardLocalDataProvider.overrideWithValue(() async {
              rec.discardCalls++;
              return true;
            }),
          ],
        );
        await settleIo(t);
        expect(find.byType(Shell), findsOneWidget, reason: '$failing');
        expect(rec.discardCalls, 0);
        expect(rec.unsentCalls, 0);
        await t.pumpWidget(const SizedBox());
      }
    });
  });

  group('nothing unsent', () {
    testWidgets('clears silently and opens the shell', (t) async {
      rec.ids = [];
      await pump(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(rec.discardCalls, 1);
      expect(find.byType(Shell), findsOneWidget);
    });

    testWidgets('a failed clear blocks with retry and going back', (t) async {
      rec.ids = [];
      rec.discards = [false, true];
      await pump(t);
      expectNoShell();
      expect(
        find.textContaining("Couldn't erase the previous account"),
        findsOneWidget,
      );
      expect(focused(t, find.text(goBack)), isTrue);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(rec.discardCalls, 2);
      expect(find.byType(Shell), findsOneWidget);
    });
  });

  group('stale runs', () {
    testWidgets('the account changed while counting: no delete, no dialog', (
      t,
    ) async {
      rec.ids = [];
      rec.hold = Completer<void>();
      await pump(t);
      expect(rec.unsentCalls, 1);
      gate.account = acctA; // the session moved on
      rec.hold!.complete();
      await t.pumpAndSettle();
      expect(rec.discardCalls, 0);
      expectNoShell();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('signed out while the device record is read', (t) async {
      final hold = Completer<void>();
      device.hold = hold.future;
      await pump(t);
      gate.account = null;
      hold.complete();
      await t.pumpAndSettle();
      expect(rec.unsentCalls, 0);
      expectNoShell();
    });

    testWidgets('disposed while counting: nothing happens afterwards', (
      t,
    ) async {
      rec.ids = [];
      rec.hold = Completer<void>();
      await pump(t);
      await t.pumpWidget(const SizedBox());
      rec.hold!.complete();
      await t.pumpAndSettle();
      expect(rec.discardCalls, 0);
      expect(t.takeException(), isNull);
    });
  });

  test('maskEmail keeps the first character', () {
    expect(maskEmail('alice@example.com'), 'a@…');
    expect(maskEmail('  Zed@x.org'), 'Z@…');
    expect(maskEmail(''), '…');
    expect(maskEmail('가나@x.org'), '가@…');
  });
}
