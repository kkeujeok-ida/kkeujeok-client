import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/drive/root_folder.dart' show RootStatus;
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'fake_auth_gateway.dart';
import 'fake_drive.dart';
import 'shell_test.dart' show pumpApp;

/// A fake whose listing waits for [gate], so "preparing" can be looked at.
class _GatedDrive extends FakeDrive {
  Completer<void> gate = Completer<void>();

  @override
  Future<DrivePage> list(String q, {String? fields, String? pageToken}) async {
    await gate.future;
    return super.list(q, fields: fields, pageToken: pageToken);
  }
}

Note _note() => createNote(
  title: 'Kept note',
  existingTitles: const [],
  background: 'plain',
  orientation: 'portrait',
  noteId: '01926f3a-0000-7000-8000-000000000900',
  pageId: '01926f3a-0000-7000-8000-000000000001',
  pageRev: '01926f3a-0000-7000-8000-000000000051',
  metaRev: '01926f3a-0000-7000-8000-000000000901',
  orderRev: '01926f3a-0000-7000-8000-000000000902',
  now: '2026-10-10T04:20:00.000Z',
  editedBy: 'Pixel 8',
).note!;

void main() {
  late Directory docs;
  late FakeAuthGateway auth;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-libdrive-');
    auth = FakeAuthGateway(restored: true)
      ..account = const AuthAccount(sub: 'sub-1', email: 'a@example.com');
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may hold a handle for a moment.
      }
    });
  });

  Future<ProviderContainer> open(WidgetTester t, FakeDrive drive) async {
    await pumpApp(
      t,
      auth: auth,
      noteData: NoteData(() async => docs),
      overrides: [
        driveClientProvider.overrideWithValue(drive),
        rootCheckThrottleProvider.overrideWithValue(Duration.zero),
      ],
      settle: false,
    );
    return ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
  }

  /// File IO runs outside the fake clock: wait in real time, pump, until
  /// [done] holds.
  Future<void> until(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
    }
    expect(done(), isTrue);
    await t.pump();
  }

  RootStatus status(ProviderContainer c) => c.read(rootFolderProvider).status;

  bool dialogOpen() => find.byType(AlertDialog).evaluate().isNotEmpty;

  testWidgets('first login: preparing shows, then one root exists', (t) async {
    final drive = _GatedDrive();
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.preparing);
    expect(find.text('Preparing Drive'), findsOneWidget);
    expect(c.read(uploadsAllowedProvider), isFalse);

    drive.gate.complete();
    await until(t, () => status(c) == RootStatus.ready);
    expect(find.text('Preparing Drive'), findsNothing);
    expect(drive.roots().length, 1);
    expect(drive.roots().single.parents, ['root']);
    expect(c.read(uploadsAllowedProvider), isTrue);
  });

  testWidgets('a failed call shows the retry card; retry runs once', (t) async {
    final drive = FakeDrive()..failures['list'] = [const DriveError('network')];
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.failed);
    expect(find.text('Check your connection and try again'), findsOneWidget);
    expect(dialogOpen(), isFalse);

    final before = drive.calls.length;
    await t.tap(find.text('Try again'));
    await until(t, () => status(c) == RootStatus.ready);
    expect(find.text('Check your connection and try again'), findsNothing);
    expect(drive.calls.skip(before).where((x) => x == 'create').length, 1);
  });

  testWidgets('offline notice floats at the top right, layout untouched', (
    t,
  ) async {
    final drive = FakeDrive()..failures['list'] = [const DriveError('network')];
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.failed);
    final notice = find.byKey(const Key('offlineNotice'));
    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    final r = t.getRect(notice);
    expect(r.right, greaterThan(screen.width - 24));
    expect(r.top, lessThan(48));
    expect(r.left, greaterThan(screen.width / 2));
    // Text and button live in it, with the 48 dp touch target kept.
    expect(
      find.descendant(
        of: notice,
        matching: find.text('Check your connection and try again'),
      ),
      findsOneWidget,
    );
    expect(
      t.getSize(find.widgetWithText(FilledButton, 'Try again')).height,
      greaterThanOrEqualTo(48),
    );
    final header = t.getTopLeft(find.text('Library'));

    await t.tap(find.text('Try again'));
    await until(t, () => status(c) == RootStatus.ready);
    expect(notice, findsNothing);
    expect(t.getTopLeft(find.text('Library')), header); // nothing was pushed
  });

  testWidgets('root moved: no dialog', (t) async {
    final drive = FakeDrive();
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.ready);
    drive.roots().single.parents = [drive.seed(kkeujeokId: 'f').id];
    final before = drive.calls.length;

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, () => drive.calls.length > before);
    await until(t, () => status(c) == RootStatus.ready);
    expect(dialogOpen(), isFalse);
  });

  testWidgets('a network error on foreground never asks about the folder', (
    t,
  ) async {
    final drive = FakeDrive();
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.ready);
    drive.roots().single.trashed = true;
    drive.failures['list'] = [const DriveError('http', status: 503)];

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, () => status(c) == RootStatus.failed);
    expect(dialogOpen(), isFalse);
  });

  testWidgets('trashed root: dialog, uploads stopped, later asks again, '
      'create makes a new root', (t) async {
    final drive = FakeDrive();
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.ready);
    final old = drive.roots().single;
    old.trashed = true;

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, dialogOpen);
    expect(status(c), RootStatus.missing);
    expect(c.read(uploadsAllowedProvider), isFalse);

    await t.tap(find.text('Later'));
    await t.pump(const Duration(milliseconds: 400));
    expect(dialogOpen(), isFalse);
    expect(c.read(uploadsAllowedProvider), isFalse);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, dialogOpen);

    await t.tap(find.text('Create new'));
    await until(t, () => status(c) == RootStatus.ready);
    await t.pump(const Duration(milliseconds: 400));
    expect(dialogOpen(), isFalse);
    expect(drive.roots().single.id, isNot(old.id));
    expect(c.read(uploadsAllowedProvider), isTrue);
  });

  testWidgets('log out from the dialog signs out', (t) async {
    final drive = FakeDrive();
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.ready);
    drive.roots().single.deleted = true;

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, dialogOpen);
    await t.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Log out'),
      ),
    );
    await until(t, () => auth.signOutCalls == 1);
  });

  Future<void> seedNote(WidgetTester t) => t.runAsync(() async {
    final c = ProviderContainer(
      overrides: [
        noteDataProvider.overrideWithValue(NoteData(() async => docs)),
      ],
    );
    await c.read(noteStoreProvider).write(_note());
    c.dispose();
  });

  testWidgets('editor on top: no dialog until it is popped, then one', (
    t,
  ) async {
    await seedNote(t);
    final drive = FakeDrive();
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.ready);
    await until(t, () => find.text('Kept note').evaluate().isNotEmpty);
    await t.tap(find.text('Kept note'));
    await until(t, () => find.byType(NoteEditor).evaluate().isNotEmpty);

    drive.roots().single.trashed = true;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, () => status(c) == RootStatus.missing);
    await t.pump(const Duration(milliseconds: 400));
    expect(dialogOpen(), isFalse);

    Navigator.of(t.element(find.byType(NoteEditor))).pop();
    await until(t, dialogOpen);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('settings on top: no dialog until it is popped, then one', (
    t,
  ) async {
    final drive = FakeDrive();
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.ready);
    await t.tap(find.text('Settings'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(NoteEditor), findsNothing);

    drive.roots().single.trashed = true;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, () => status(c) == RootStatus.missing);
    await t.pump(const Duration(milliseconds: 400));
    expect(dialogOpen(), isFalse);

    await t.pageBack();
    await until(t, dialogOpen);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('a run that outlives a sign-out stays idle', (t) async {
    final drive = _GatedDrive();
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.preparing);
    await c.read(authProvider.notifier).signOut();
    await t.pump();
    drive.gate.complete();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pump();
    expect(status(c), RootStatus.idle);
    expect(c.read(uploadsAllowedProvider), isFalse);
  });

  testWidgets('dialog: buttons in order, create has the focus', (t) async {
    final drive = FakeDrive();
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.ready);
    drive.roots().single.trashed = true;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, dialogOpen);
    await t.pump(const Duration(milliseconds: 400));

    final x = [
      for (final s in ['Create new', 'Later', 'Log out'])
        t.getTopLeft(find.text(s)).dx,
    ];
    expect(x[0] < x[1] && x[1] < x[2], isTrue);

    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await until(t, () => status(c) == RootStatus.ready);
    expect(drive.roots().length, 1);
    expect(drive.roots().single.id, isNot(drive.items.first.id));
  });

  testWidgets('foreground checks are throttled and do not flash preparing', (
    t,
  ) async {
    final drive = FakeDrive();
    await pumpApp(
      t,
      auth: auth,
      noteData: NoteData(() async => docs),
      overrides: [driveClientProvider.overrideWithValue(drive)],
      settle: false,
    );
    final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
    await until(t, () => status(c) == RootStatus.ready);
    final calls = drive.calls.length;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump();
    expect(drive.calls.length, calls); // inside the 30 s window: skipped
  });

  for (final (name, err, text, action) in [
    (
      'network',
      const DriveError('http', status: 503),
      'Check your connection and try again',
      'Try again',
    ),
    (
      'reauth',
      const DriveError('http', status: 401),
      'Please sign in again',
      'Sign in again',
    ),
    (
      'fatal',
      const DriveError('http', status: 400),
      "Couldn't prepare Drive",
      'Try again',
    ),
  ]) {
    testWidgets('failed card for $name', (t) async {
      final drive = FakeDrive()..failures['list'] = [err];
      final c = await open(t, drive);
      await until(t, () => status(c) == RootStatus.failed);
      expect(find.text(text), findsOneWidget);
      expect(find.text(action), findsOneWidget);
      if (name == 'reauth') {
        await t.tap(find.text(action));
        await until(t, () => auth.requestCalls == 1);
        await until(t, () => status(c) == RootStatus.ready);
      }
    });
  }

  testWidgets('notes open while Drive fails', (t) async {
    final drive = FakeDrive()
      ..failures['list'] = [const DriveError('http', status: 401)];
    await t.runAsync(() async {
      final c = ProviderContainer(
        overrides: [
          noteDataProvider.overrideWithValue(NoteData(() async => docs)),
        ],
      );
      await c.read(noteStoreProvider).write(_note());
      c.dispose();
    });
    final c = await open(t, drive);
    await until(t, () => status(c) == RootStatus.failed);
    await until(t, () => find.text('Kept note').evaluate().isNotEmpty);
    await t.tap(find.text('Kept note'));
    await t.pump(const Duration(milliseconds: 400));
    expect(dialogOpen(), isFalse);
    await until(t, () => find.byType(NoteEditor).evaluate().isNotEmpty);
  });
}
