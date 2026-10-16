import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/storage/sync_device_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/note_chain.dart';
import 'package:kkeujeok/sync/note_receiver.dart';

import 'upload_env.dart';

const otherId = '01926f3a-0000-7000-8000-000000000902';

void main() {
  late UploadEnv env;
  late NoteChain chain;
  late AuthAccount? acct;
  late bool online;
  late List<ReceiveState> seen;

  Future<void> setUpEnv() async {
    env = await UploadEnv.create();
    chain = NoteChain();
    acct = const AuthAccount(sub: 's', email: 'e');
    online = true;
    seen = [];
  }

  NoteReceiver receiver() {
    final r = NoteReceiver(
      store: env.store,
      drive: env.drive,
      device: env.device,
      log: env.log,
      merge: env.merge,
      hosts: env.hosts,
      allowed: () async => env.allowed,
      online: () async => online,
      account: () => acct,
      sleep: (d) async => env.sleeps.add(d),
      jitter: () => 0.5,
      chain: chain,
    );
    r.state.addListener(() => seen.add(r.state.value));
    addTearDown(r.dispose);
    return r;
  }

  /// A synced local note that Drive has too.
  Future<void> localSynced() async {
    await env.save(makeNote());
    await env.uploader().upload(noteId);
    expect(env.info.state, SyncState.synced);
  }

  Future<String?> token() async => (await env.device.read()).pageToken;

  void foreignEdit(int rev) =>
      env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: rev)));

  int mediaCalls() => env.drive.calls.where((c) => c.startsWith('media')).length;

  setUp(setUpEnv);

  group('first check', () {
    test('a new note with a summary shows its card and badge before the '
        'download, then is stored synced; the token is saved last', () async {
      env.drive.foreignNote(makeNote(title: 'Elsewhere'), parent: env.root.id);
      final r = receiver();
      ReceiveState? during;
      env.drive.before = (c) {
        if (c.startsWith('media')) during = r.state.value;
      };
      await r.check();
      expect(during!.cards.single.title, 'Elsewhere');
      expect(during!.receiving, {noteId});
      expect(r.state.value.receiving, isEmpty);
      expect(r.state.value.cards, isEmpty);
      expect(r.state.value.scanning, isFalse);
      expect(seen.any((s) => s.scanning), isTrue);
      final n = (await env.store.read(noteId))!.note!;
      expect(n.title, 'Elsewhere');
      expect(env.info.state, SyncState.synced);
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      expect(env.info.fileId, env.note.id);
      expect(env.syncFile.existsSync(), isTrue);
      expect(File('${env.noteDir.path}/base.${env.note.headRevisionId}.kkj')
          .existsSync(), isTrue);
      expect(await token(), await env.drive.getStartPageToken());
      expect(r.state.value.version, greaterThan(0));
      // The start token was taken before the listing.
      final c = env.drive.calls;
      expect(c.indexOf('changes:start'), lessThan(c.indexOf('list')));
    });

    test('no summary: no card until the note is downloaded', () async {
      env.drive.foreignNote(
        makeNote(),
        parent: env.root.id,
        summary: false,
      );
      final r = receiver();
      ReceiveState? during;
      env.drive.before = (c) {
        if (c.startsWith('media')) during = r.state.value;
      };
      await r.check();
      expect(during!.cards, isEmpty);
      expect(during!.receiving, {noteId});
      expect(await env.store.read(noteId), isNotNull);
    });

    test('an unreadable download is kept byte for byte and never uploaded',
        () async {
      final junk = utf8.encode('junk');
      env.drive.foreignNote(makeNote(), parent: env.root.id, bytes: junk);
      await receiver().check();
      expect(env.working.readAsBytesSync(), junk);
      expect((await env.store.read(noteId))!.status, ReadStatus.unreadable);
      expect(env.info.state, SyncState.error);
      await receiver().check();
      expect(env.working.readAsBytesSync(), junk);
      expect(mediaCalls(), 1);
    });

    test('a newer-format file is kept and reported', () async {
      final json = makeNote().copyJson()..['formatVersion'] = 99;
      env.drive.foreignNote(
        makeNote(),
        parent: env.root.id,
        bytes: encodeKkj(Note.trusted(json)),
      );
      await receiver().check();
      expect((await env.store.read(noteId))!.status, isNot(ReadStatus.ok));
      expect(env.info.lastError?['class'], 'unreadable');
    });

    test('paged scan with two notes saves the token last', () async {
      env.drive.pageSize = 1;
      env.drive.foreignNote(makeNote(), parent: env.root.id);
      env.drive.foreignNote(
        makeNote(noteIdOverride: otherId),
        parent: env.root.id,
      );
      await receiver().check();
      expect(await env.store.read(noteId), isNotNull);
      expect(await env.store.read(otherId), isNotNull);
      expect(await token(), '2');
    });
  });

  group('changes', () {
    test('a changed synced note is replaced; badge shows before the download',
        () async {
      await localSynced();
      final r = receiver();
      await r.check(); // token
      foreignEdit(2);
      ReceiveState? during;
      env.drive.before = (c) {
        if (c.startsWith('media')) during = r.state.value;
      };
      await r.check();
      expect(during!.receiving, {noteId});
      expect(r.state.value.receiving, isEmpty);
      final head = env.note.headRevisionId;
      expect(env.info.baseHeadRevisionId, head);
      expect(env.info.state, SyncState.synced);
      expect(
        (await env.store.read(noteId))!.note!.pages.first['rev'],
        makeNote(rev: 2).pages.first['rev'],
      );
      final names = await env.eventNames();
      expect(names, contains('baseAdvanced'));
      expect(await env.stateChanges(), contains('syncing>synced'));
      expect(await token(), await env.drive.getStartPageToken());
    });

    test('a change whose head is our base downloads nothing', () async {
      await localSynced();
      final r = receiver();
      await r.check();
      await env.save(makeNote(rev: 4));
      await env.uploader().upload(noteId); // listed as a change, head == base
      final before = mediaCalls();
      final bytes = env.working.readAsBytesSync();
      await r.check();
      expect(mediaCalls(), before);
      expect(env.working.readAsBytesSync(), bytes);
    });

    test('unsent changes are merged, a conflict writes a sidecar and the '
        'base becomes the remote head', () async {
      await localSynced();
      final r = receiver();
      await r.check();
      await env.save(makeNote(rev: 5)); // edited here
      foreignEdit(2); // and there
      await r.check();
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      expect(env.info.state, SyncState.conflict);
      expect(env.info.conflicts, isNotEmpty);
      expect(env.info.unsentSidecars, isNotEmpty);
      expect(await env.eventNames(), containsAll(['merged', 'conflictFound']));
    });

    test('an edit that lands during the download is never overwritten',
        () async {
      await localSynced();
      final r = receiver();
      await r.check();
      foreignEdit(2);
      var done = false;
      env.drive.before = (c) {
        if (c.startsWith('media') && !done) {
          done = true;
          unawaited(env.store.write(makeNote(rev: 7)));
        }
      };
      await r.check();
      expect(env.info.state, isNot(SyncState.synced));
      final s = await env.store.readSync(noteId);
      expect(s.hasUnsent, isTrue);
    });

    test('an open note is merged through its editor host', () async {
      await localSynced();
      final r = receiver();
      await r.check();
      var calls = 0;
      env.hosts.register(noteId, (merge, record) async {
        calls++;
        final out = merge((await env.store.read(noteId))!.note!);
        await record();
        if (out != null) await env.store.write(out.note);
        return true;
      });
      foreignEdit(2);
      await r.check();
      expect(calls, 1);
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
    });

    test('a newer-format remote writes nothing and marks the note', () async {
      await localSynced();
      final r = receiver();
      await r.check();
      final bytes = env.working.readAsBytesSync();
      final json = makeNote(rev: 2).copyJson()..['formatVersion'] = 99;
      env.drive.foreignRevision(env.note, encodeKkj(Note.trusted(json)));
      await r.check();
      expect(env.working.readAsBytesSync(), bytes);
      expect(env.info.state, SyncState.error);
      expect(env.info.lastError?['reason'], 'unsupportedVersion');
    });

    test('a note in error or with pendingVerify is skipped', () async {
      await localSynced();
      final r = receiver();
      await r.check();
      await env.store.updateSync(
        noteId,
        (c) => c.copyWith(state: SyncState.error),
      );
      foreignEdit(2);
      final before = mediaCalls();
      await r.check();
      expect(mediaCalls(), before);
    });

    test('the receive waits for the note chain shared with uploads', () async {
      await localSynced();
      final r = receiver();
      await r.check();
      foreignEdit(2);
      final gate = Completer<void>();
      unawaited(chain.run(noteId, () => gate.future));
      final before = mediaCalls();
      final run = r.check();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mediaCalls(), before);
      gate.complete();
      await run;
      expect(mediaCalls(), before + 1);
    });
  });

  group('token and errors', () {
    test('a rejected token logs, rescans and saves a new token', () async {
      await localSynced();
      final r = receiver();
      await r.check();
      foreignEdit(2);
      env.drive.rejectChanges = 1;
      await r.check();
      expect(await env.eventNames(), contains('pageTokenRejected'));
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      expect(await token(), await env.drive.getStartPageToken());
    });

    for (final status in [400, 404, 410]) {
      test('status $status is a rejected token', () async {
        await receiver().check();
        env.drive.rejectStatus = status;
        env.drive.rejectChanges = 1;
        await receiver().check();
        expect(await env.eventNames(), contains('pageTokenRejected'));
      });
    }

    test('5xx backs off, the 7th failure ends the check without the token',
        () async {
      await localSynced();
      final r = receiver();
      await r.check();
      final saved = await token();
      foreignEdit(2);
      env.drive.failures['media'] = [
        for (var i = 0; i < 7; i++) const DriveError('http', status: 503),
      ];
      await r.check();
      expect(env.sleeps, hasLength(6));
      expect(await token(), saved);
      expect(env.info.state, SyncState.error);
      expect(env.info.lastError?['class'], 'backoff');
      expect(
        (await env.store.read(noteId))!.note!.pages.first['rev'],
        makeNote().pages.first['rev'],
      ); // device copy untouched
      expect(r.state.value.receiving, isEmpty);
    });

    test('an account change during the download writes nothing', () async {
      await localSynced();
      final r = receiver();
      await r.check();
      final saved = await token();
      final bytes = env.working.readAsBytesSync();
      foreignEdit(2);
      env.drive.before = (c) {
        if (c.startsWith('media')) {
          acct = const AuthAccount(sub: 'other', email: 'o');
        }
      };
      await r.check();
      expect(env.working.readAsBytesSync(), bytes);
      expect(await token(), saved);
      expect(r.state.value.receiving, isEmpty);
    });

    test('an unreadable device record: no Drive call, an error entry',
        () async {
      File('${env.docs.path}/$syncDeviceFileName').writeAsStringSync('{bad');
      await receiver().check();
      expect(env.drive.calls, isEmpty);
      final e = (await env.events()).last;
      expect(e['event'], 'error');
      expect(e['reason'], 'deviceUnreadable');
    });

    test('another account on the device makes no request', () async {
      acct = const AuthAccount(sub: 'x', email: 'x');
      await receiver().check();
      expect(env.drive.calls, isEmpty);
    });

    test('closed gate, offline or signed out: no request', () async {
      final r = receiver();
      env.allowed = false;
      await r.check();
      env.allowed = true;
      online = false;
      await r.check();
      online = true;
      acct = null;
      await r.check();
      expect(env.drive.calls, isEmpty);
    });

    test('a second check while one runs shares it', () async {
      final r = receiver();
      final a = r.check();
      final b = r.check();
      expect(identical(a, b), isTrue);
      await a;
      expect(env.drive.calls.where((c) => c == 'changes:start'), hasLength(1));
    });
  });

  group('noteOpened', () {
    test('a moved head is received; an equal head costs one get', () async {
      await localSynced();
      final r = receiver();
      env.drive.calls.clear();
      await r.noteOpened(noteId);
      expect(env.drive.calls.where((c) => c.startsWith('get')), hasLength(1));
      expect(mediaCalls(), 0);
      foreignEdit(2);
      await r.noteOpened(noteId);
      expect(mediaCalls(), 1);
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
    });

    test('offline: no call', () async {
      await localSynced();
      online = false;
      env.drive.calls.clear();
      await receiver().noteOpened(noteId);
      expect(env.drive.calls, isEmpty);
    });

    test('the note is marked receiving while it is received', () async {
      await localSynced();
      final r = receiver();
      foreignEdit(2);
      ReceiveState? during;
      env.drive.before = (c) {
        if (c.startsWith('media')) during = r.state.value;
      };
      await r.noteOpened(noteId);
      expect(during!.receiving, {noteId});
    });
  });

  test('after dispose a running check ends without touching the state',
      () async {
    await localSynced();
    final r = receiver();
    foreignEdit(2);
    env.drive.before = (c) {
      if (c.startsWith('media')) r.dispose();
    };
    await r.check(); // must not throw
    r.dispose(); // idempotent
  });
}
