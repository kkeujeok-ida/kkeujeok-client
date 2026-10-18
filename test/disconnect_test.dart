import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/storage/language_store.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_gateway.dart';
import 'shell_test.dart' show pumpApp;

const body =
    'The note copies and sign-in info on this device will be erased. '
    'The note files in your Drive stay as they are.';
const retryText = 'Check your connection and try again';

void main() {
  late Directory docs;
  late File note;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-docs-');
    final dir = Directory('${docs.path}/$noteDataDirName/sub')
      ..createSync(recursive: true);
    note = File('${dir.path}/a.kkj')..writeAsStringSync('note');
    addTearDown(() => docs.deleteSync(recursive: true));
  });

  Directory notesDir() => Directory('${docs.path}/$noteDataDirName');

  Future<void> openSettings(WidgetTester t) async {
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
  }

  void expectSignIn() {
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Log out'), findsNothing);
  }

  Future<void> pump(WidgetTester t, FakeAuthGateway g, {NoteData? noteData}) =>
      pumpApp(
        t,
        auth: g,
        prefs: {'language': 'en'},
        noteData: noteData ?? NoteData(() async => docs),
        // The library reads the folder too; keep it off the NoteData whose
        // calls these tests count.
        noteStore: NoteStore(NoteData(() async => docs)),
      );

  // Real file IO does not advance under the fake clock: let it finish first.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 3; i++) {
      await t.pump(); // run queued microtasks, start the next IO call
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await t.pumpAndSettle();
  }

  // Settings row, then the "Log out?" confirm (Story 11.9).
  Future<void> logOut(WidgetTester t) async {
    await t.tap(find.text('Log out'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Log out'));
  }

  Future<void> confirmDisconnect(WidgetTester t) async {
    await t.tap(find.text('Disconnect'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Disconnect'));
  }

  group('log out', () {
    testWidgets('always asks "Log out?" first; cancel changes nothing', (
      t,
    ) async {
      final h = t.ensureSemantics();
      final g = FakeAuthGateway(restored: true);
      await pump(t, g);
      await openSettings(t);
      await t.tap(find.text('Log out'));
      await t.pumpAndSettle();
      expect(find.text('Log out?'), findsOneWidget);
      expect(find.bySemanticsLabel('Log out?'), findsWidgets);
      expect(g.signOutCalls, 0);
      // Cancel has the focus; all buttons reach 48 dp.
      for (final b in [
        find.widgetWithText(TextButton, 'Cancel'),
        find.widgetWithText(FilledButton, 'Log out'),
      ]) {
        expect(t.getSize(b).height, greaterThanOrEqualTo(48));
      }
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
      expect(g.signOutCalls, 0);
      // Back is the same as Cancel.
      await t.tap(find.text('Log out'));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(g.signOutCalls, 0);
      h.dispose();
    });

    testWidgets('the confirm is in Korean too', (t) async {
      final g = FakeAuthGateway(restored: true);
      await pumpApp(
        t,
        auth: g,
        prefs: {'language': 'ko'},
        noteData: NoteData(() async => docs),
        noteStore: NoteStore(NoteData(() async => docs)),
      );
      await t.tap(find.text('설정'));
      await t.pumpAndSettle();
      await t.tap(find.text('로그아웃'));
      await t.pumpAndSettle();
      expect(find.text('로그아웃할까요?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, '로그아웃'));
      await t.pumpAndSettle();
      expect(g.signOutCalls, 1);
    });

    testWidgets('goes to sign-in after the confirm and keeps the notes', (
      t,
    ) async {
      final g = FakeAuthGateway(restored: true);
      await pump(t, g);
      await openSettings(t);
      await logOut(t);
      await t.pumpAndSettle();
      expectSignIn();
      expect(find.byType(AlertDialog), findsNothing);
      expect(g.signOutCalls, 1);
      expect(g.disconnectCalls, 0);
      expect(note.existsSync(), isTrue);
    });

    testWidgets('a plugin error still ends the session', (t) async {
      final g = FakeAuthGateway(restored: true, signOutFails: true);
      await pump(t, g);
      await openSettings(t);
      await logOut(t);
      await t.pumpAndSettle();
      expectSignIn();
      expect(note.existsSync(), isTrue);
    });

    testWidgets('a plugin that never answers still ends it after 10s', (
      t,
    ) async {
      final g = FakeAuthGateway(restored: true, signOutHangs: true);
      await pump(t, g);
      await openSettings(t);
      await logOut(t);
      await t.pump();
      expect(find.text('Sign in with Google'), findsNothing);
      await t.pump(const Duration(seconds: 11));
      await t.pumpAndSettle();
      expectSignIn();
      expect(note.existsSync(), isTrue);
    });

    testWidgets('signing in again opens the shell', (t) async {
      await pump(t, FakeAuthGateway(restored: true));
      await openSettings(t);
      await logOut(t);
      await t.pumpAndSettle();
      await t.tap(find.text('Sign in with Google'));
      await t.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('disconnect', () {
    testWidgets('cancel and back change nothing', (t) async {
      final g = FakeAuthGateway(restored: true);
      await pump(t, g);
      await openSettings(t);
      await t.tap(find.text('Disconnect'));
      await t.pumpAndSettle();
      expect(find.text(body), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Privacy policy'), findsOneWidget);

      await t.tap(find.text('Disconnect'));
      await t.pumpAndSettle();
      await t.binding.handlePopRoute(); // system back
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(g.disconnectCalls, 0);
      expect(note.existsSync(), isTrue);
    });

    testWidgets('success empties the note dir, keeps settings', (t) async {
      final g = FakeAuthGateway(restored: true);
      final store = await pumpApp(
        t,
        auth: g,
        prefs: {'language': 'ko'},
        noteData: NoteData(() async => docs),
      );
      await t.tap(find.text('설정'));
      await t.pumpAndSettle();
      await t.tap(find.text('연결 해제'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '연결 해제'));
      await settle(t);
      expect(g.disconnectCalls, 1);
      expect(notesDir().existsSync(), isFalse);
      expect(store.read(), LanguageChoice.ko);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('language'), 'ko');
      expect(find.text('Google로 로그인'), findsOneWidget);
    });

    testWidgets('revocation failure keeps data; retry revokes again', (
      t,
    ) async {
      final g = FakeAuthGateway(restored: true, disconnects: [false, true]);
      await pump(t, g);
      await openSettings(t);
      await confirmDisconnect(t);
      await settle(t);
      expect(find.text(retryText), findsOneWidget);
      expect(note.existsSync(), isTrue);

      await t.tap(find.widgetWithText(FilledButton, 'Try again'));
      await settle(t);
      expect(g.disconnectCalls, 2);
      expect(notesDir().existsSync(), isFalse);
      expectSignIn();
    });

    testWidgets('no answer in 10s counts as a failure', (t) async {
      final g = FakeAuthGateway(restored: true, disconnectHangs: true);
      await pump(t, g);
      await openSettings(t);
      await confirmDisconnect(t);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pump(const Duration(seconds: 9));
      expect(find.text(retryText), findsNothing);
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(find.text(retryText), findsOneWidget);
      expect(note.existsSync(), isTrue);
    });

    testWidgets('no note directory is not an error', (t) async {
      notesDir().deleteSync(recursive: true);
      await pump(t, FakeAuthGateway(restored: true));
      await openSettings(t);
      await confirmDisconnect(t);
      await settle(t);
      expectSignIn();
    });

    testWidgets('a failed delete is retried without revoking again', (t) async {
      var calls = 0;
      final g = FakeAuthGateway(restored: true);
      await pump(
        t,
        g,
        noteData: NoteData(() async {
          if (calls++ == 0) throw const FileSystemException('busy');
          return docs;
        }),
      );
      await openSettings(t);
      await confirmDisconnect(t);
      await settle(t);
      expect(find.textContaining('erase the note copies'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Try again'));
      await settle(t);
      expect(g.disconnectCalls, 1);
      expect(notesDir().existsSync(), isFalse);
      expectSignIn();
    });

    testWidgets('a revoke that was followed by a failed delete does not '
        'carry over to the next session', (t) async {
      var calls = 0;
      final g = FakeAuthGateway(restored: true);
      await pump(
        t,
        g,
        noteData: NoteData(() async {
          if (calls++ == 0) throw const FileSystemException('busy');
          return docs;
        }),
      );
      await openSettings(t);
      await confirmDisconnect(t);
      await settle(t);
      expect(g.disconnectCalls, 1);
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await t.pumpAndSettle();
      await logOut(t);
      await t.pumpAndSettle();
      expectSignIn();
      await t.tap(find.text('Sign in with Google'));
      await t.pumpAndSettle();
      await openSettings(t);
      await confirmDisconnect(t);
      await settle(t);
      expect(g.disconnectCalls, 2); // revoked again for the new session
      expectSignIn();
    });

    testWidgets('title and buttons are announced, cancel is focused', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await pump(t, FakeAuthGateway(restored: true));
      await openSettings(t);
      expect(find.bySemanticsLabel('Log out'), findsOneWidget);
      expect(find.bySemanticsLabel('Disconnect'), findsOneWidget);
      await t.tap(find.text('Disconnect'));
      await t.pumpAndSettle();
      expect(find.text('Disconnect?'), findsOneWidget);
      expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      expect(t.widget<TextButton>(cancel).autofocus, isTrue);
      expect(t.getSize(cancel).height, greaterThanOrEqualTo(48));
      expect(
        t.getSize(find.widgetWithText(FilledButton, 'Disconnect')).height,
        greaterThanOrEqualTo(48),
      );
      handle.dispose();
    });
  });

  group('note data', () {
    test('clear removes the directory and tolerates a missing one', () async {
      final data = NoteData(() async => docs);
      await data.clear();
      expect(notesDir().existsSync(), isFalse);
      await data.clear();
    });
  });
}
