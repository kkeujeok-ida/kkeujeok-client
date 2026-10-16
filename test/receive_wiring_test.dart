import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/drive/root_folder.dart' show RootStatus;
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/sync/note_receiver.dart';
import 'package:kkeujeok/sync/receive_scheduler.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'fake_auth_gateway.dart';
import 'fake_receiver.dart';
import 'shell_test.dart' show pumpApp;
import 'upload_env.dart' show makeNote, noteId;

class _ReadyRoot extends RootFolderNotifier {
  @override
  RootFolderState build() => const RootFolderState(RootStatus.ready);
}

const _other = '01926f3a-0000-7000-8000-000000000902';

void main() {
  group('ReceiveScheduler', () {
    testWidgets('ticks every 20,000 ms while resumed, not after pause', (
      t,
    ) async {
      var n = 0;
      final s = ReceiveScheduler(check: () async => n++);
      s.resume();
      await t.pump(const Duration(milliseconds: 19999));
      expect(n, 0);
      await t.pump(const Duration(milliseconds: 1));
      expect(n, 1);
      await t.pump(const Duration(seconds: 40));
      expect(n, 3);
      s.pause();
      await t.pump(const Duration(seconds: 60));
      expect(n, 3);
      s.resume();
      await t.pump(const Duration(seconds: 20));
      expect(n, 4);
      s.dispose();
      await t.pump(const Duration(seconds: 60));
      expect(n, 4);
    });

    testWidgets('kicks closer than 5,000 ms are skipped, force is not', (
      t,
    ) async {
      var n = 0;
      var now = DateTime.utc(2026, 10, 16);
      final s = ReceiveScheduler(check: () async => n++, clock: () => now);
      s.kick();
      expect(n, 1);
      now = now.add(const Duration(milliseconds: 4999));
      s.kick();
      expect(n, 1);
      s.kick(force: true);
      expect(n, 2);
      now = now.add(const Duration(milliseconds: 5000));
      s.kick();
      expect(n, 3);
      s.dispose();
      s.kick(force: true);
      expect(n, 3);
    });

    testWidgets('a check that throws is swallowed', (t) async {
      final s = ReceiveScheduler(check: () async => throw StateError('x'));
      s.kick();
      await t.pump();
      s.dispose();
    });
  });

  group('library', () {
    late Directory docs;
    late NoteData data;
    late RecReceiver rec;

    setUp(() {
      docs = Directory.systemTemp.createTempSync('kkj-recv-ui-');
      data = NoteData(() async => docs);
      rec = RecReceiver();
      final f = File('${docs.path}/$noteDataDirName/$noteId/working.kkj');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(encodeKkj(makeNote(title: 'Local')));
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

    Future<void> open(
      WidgetTester t, {
      bool ready = true,
      List<Locale> device = const [Locale('en', 'US')],
    }) async {
      await pumpApp(
        t,
        device: device,
        auth: FakeAuthGateway(restored: true)
          ..account = const AuthAccount(sub: 's', email: 'e'),
        noteData: data,
        overrides: <Override>[
          noteReceiverProvider.overrideWithValue(rec),
          if (ready) rootFolderProvider.overrideWith(_ReadyRoot.new),
        ],
        settle: false,
      );
      await until(t, 'Local');
    }

    testWidgets('start with a ready root checks once; 20 s polls; pause '
        'stops', (t) async {
      await open(t);
      expect(rec.checks, 1);
      await t.pump(const Duration(seconds: 20));
      expect(rec.checks, 2);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump(const Duration(seconds: 60));
      expect(rec.checks, 2);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(rec.checks, 2, reason: 'a kick within 5,000 ms is skipped');
      await t.pump(const Duration(seconds: 20));
      expect(rec.checks, 3);
    });

    testWidgets('foreground after a while checks at once', (t) async {
      await open(t);
      await t.pump(const Duration(seconds: 20));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump(const Duration(seconds: 1));
      final before = rec.checks;
      // The throttle reads the real clock: wait it out in real time.
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5100)),
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(rec.checks, before + 1);
    });

    testWidgets('no root, no check at start', (t) async {
      await open(t, ready: false);
      expect(rec.checks, 0);
    });

    testWidgets('the badge follows the receiving set', (t) async {
      await open(t);
      expect(find.text('Receiving'), findsNothing);
      rec.state.value = ReceiveState(receiving: {noteId});
      await t.pump();
      expect(find.text('Receiving'), findsOneWidget);
      rec.state.value = const ReceiveState();
      await t.pump();
      expect(find.text('Receiving'), findsNothing);
    });

    testWidgets('a summary card with a badge, the placeholder only after '
        '1,000 ms of scanning', (t) async {
      await open(t);
      rec.state.value = const ReceiveState(
        scanning: true,
        receiving: {_other},
        cards: [
          RemoteCard(
            noteId: _other,
            fileId: 'F2',
            title: 'Elsewhere',
            modifiedAt: '2026-10-10T04:20:00.000Z',
          ),
        ],
      );
      await t.pump(const Duration(milliseconds: 900));
      final cards = find.byType(AspectRatio).evaluate().length;
      expect(find.text('Elsewhere'), findsOneWidget);
      expect(find.text('Receiving'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byType(AspectRatio), findsNWidgets(cards + 2));
      rec.state.value = const ReceiveState();
      await t.pump();
      expect(find.byType(AspectRatio), findsNWidgets(cards - 1));
      expect(find.text('Elsewhere'), findsNothing);
    });

    testWidgets('a scan under 1,000 ms never shows the placeholder', (
      t,
    ) async {
      await open(t);
      final cards = find.byType(AspectRatio).evaluate().length;
      rec.state.value = const ReceiveState(scanning: true);
      await t.pump(const Duration(milliseconds: 500));
      rec.state.value = const ReceiveState();
      await t.pump(const Duration(seconds: 2));
      expect(find.byType(AspectRatio), findsNWidgets(cards));
    });

    testWidgets('a new version reloads the list', (t) async {
      await open(t);
      final f = File('${docs.path}/$noteDataDirName/$_other/working.kkj');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(
        encodeKkj(makeNote(title: 'Arrived', noteIdOverride: _other)),
      );
      rec.state.value = const ReceiveState(version: 1);
      await until(t, 'Arrived');
      expect(find.text('Arrived'), findsOneWidget);
    });

    testWidgets('Korean badge text', (t) async {
      await open(t, device: const [Locale('ko', 'KR')]);
      rec.state.value = ReceiveState(receiving: {noteId});
      await t.pump();
      expect(find.text('받는 중'), findsOneWidget);
    });

    testWidgets('leaving the library cancels the timer and later state is '
        'ignored', (t) async {
      await open(t);
      await t.pumpWidget(const SizedBox());
      final before = rec.checks;
      await t.pump(const Duration(seconds: 60));
      expect(rec.checks, before);
      rec.state.value = ReceiveState(receiving: {noteId});
      await t.pump();
    });
  });
}
