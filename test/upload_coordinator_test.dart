import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/open_note.dart';
import 'package:kkeujeok/sync/upload_coordinator.dart';

import 'upload_env.dart';

void main() {
  late UploadEnv env;
  late OpenNote open;
  late int scheduled;
  late DateTime now;
  late UploadCoordinator coordinator;

  setUp(() async {
    env = await UploadEnv.create();
    open = OpenNote(env.data.rootDir);
    scheduled = 0;
    now = DateTime.utc(2026, 10, 11, 9);
    coordinator = UploadCoordinator(
      store: env.store,
      uploader: env.uploader(),
      openNote: open,
      lease: UploadLease(env.data, () => now),
      log: env.log,
      allowed: () async => env.allowed,
      online: () async => env.online,
      schedule: () async => scheduled++,
    );
  });

  test(
    'a closed note with changes is uploaded: pending, syncing, synced',
    () async {
      await env.save(makeNote());
      await coordinator.noteClosed(noteId);
      expect(env.info.state, SyncState.synced);
      expect(await env.stateChanges(), ['pending>syncing', 'syncing>synced']);
      expect(env.drive.uploads, hasLength(1));
    },
  );

  test('a note with nothing unsent makes no request', () async {
    await env.save(makeNote());
    await coordinator.noteClosed(noteId);
    env.drive.calls.clear();
    await coordinator.noteClosed(noteId);
    await coordinator.appStarted();
    expect(env.drive.calls, isEmpty);
  });

  test(
    'the open note is not uploaded while idle, but is on background',
    () async {
      await env.save(makeNote());
      await open.set(noteId);
      await coordinator.uploadUnsent(); // connectivity, WorkManager
      await coordinator.foreground();
      expect(env.drive.calls, isEmpty);

      var flushed = false;
      coordinator.flushOpen = () async => flushed = true;
      await coordinator.appBackgrounded();
      expect(flushed, isTrue);
      expect(env.drive.uploads, hasLength(1));
    },
  );

  test('background flushes the editor queue before it uploads', () async {
    await env.save(makeNote());
    await open.set(noteId);
    coordinator.flushOpen = () async {
      await env.save(makeNote(rev: 2)); // the queue reaches the disk
    };
    await coordinator.appBackgrounded();
    final up = noteOf(env.note.bytes)!;
    expect(up.pages.first['rev'], endsWith('52'));
  });

  test(
    'offline or gate closed: no request, WorkManager is scheduled',
    () async {
      await env.save(makeNote());
      env.online = false;
      await coordinator.noteClosed(noteId);
      expect(env.drive.calls, isEmpty);
      expect(scheduled, 1);

      env.online = true;
      env.allowed = false;
      await coordinator.noteClosed(noteId);
      expect(env.drive.calls, isEmpty);
      expect(scheduled, 2);
      expect((await env.store.readSync(noteId)).state, SyncState.pending);
    },
  );

  test('a note with no changes does not schedule anything', () async {
    env.online = false;
    await coordinator.appBackgrounded();
    expect(scheduled, 0);
  });

  test(
    'app start finishes an interrupted upload before anything new',
    () async {
      await env.save(makeNote());
      env.drive.before = (c) {
        if (c.startsWith('get:')) throw Crash();
      };
      await coordinator.noteClosed(noteId); // swallowed: a crash
      expect(env.info.pendingVerify?['oursRevisionId'], isNotNull);
      await open.set(noteId); // a stale marker of the dead process

      env.drive.before = null;
      env.drive.calls.clear();
      await open.clear(); // what `main` does once at process start
      await coordinator.appStarted();

      expect(env.drive.uploads, hasLength(1)); // not uploaded again
      expect(env.info.state, SyncState.synced);
    },
  );

  test('foreground retries quota, reauth and fatal; never deleted', () async {
    await env.save(makeNote());
    env.drive.failures['upload'] = [
      const DriveError('http', status: 403, reason: 'storageQuotaExceeded'),
    ];
    await coordinator.noteClosed(noteId);
    expect(env.info.state, SyncState.error);

    await coordinator.foreground(); // quota: retried at the foreground
    expect(env.info.state, SyncState.synced);

    // deleted: stays
    await env.save(makeNote(rev: 2));
    env.note.trashed = true;
    await coordinator.noteClosed(noteId);
    expect(env.info.lastError?['class'], 'deleted');
    env.drive.calls.clear();
    await coordinator.foreground();
    expect(env.info.state, SyncState.error);
    expect(env.drive.calls, isEmpty);
  });

  test('an old unreadable/parse note waiting for verify recovers', () async {
    await env.save(makeNote());
    env.drive.failures['revisions'] = [const DriveError('parse')];
    await coordinator.noteClosed(noteId);
    // What 11.1 builds before the fix wrote:
    await env.store.updateSync(
      noteId,
      (c) => c.copyWith(lastError: {'class': 'unreadable', 'reason': 'parse'}),
    );
    final local = env.working.readAsBytesSync();

    await coordinator.syncNow(noteId);

    expect(env.info.state, SyncState.synced);
    expect(env.drive.uploads, hasLength(1)); // verified, not uploaded again
    expect(env.working.readAsBytesSync(), local);
  });

  test('another holder of the lease: the note is left alone', () async {
    await env.save(makeNote());
    final other = UploadLease(env.data, () => now);
    expect(await other.acquire(noteId), isTrue);
    await coordinator.noteClosed(noteId);
    expect(env.drive.calls, isEmpty);

    // Stale after 10 minutes: taken over.
    now = now.add(const Duration(minutes: 11));
    await coordinator.noteClosed(noteId);
    expect(env.drive.uploads, hasLength(1));
    // Released afterwards.
    expect(await other.acquire(noteId), isTrue);
  });

  test('lease: exclusive, fresh holds, release frees', () async {
    await env.save(makeNote());
    final a = UploadLease(env.data, () => now);
    final b = UploadLease(env.data, () => now);
    expect(await a.acquire(noteId), isTrue);
    expect(await b.acquire(noteId), isFalse);
    await a.release(noteId);
    expect(await b.acquire(noteId), isTrue);
    expect(await b.acquire('01926f3a-0000-7000-8000-0000000000aa'), isFalse);
  });

  test('app start does not clear the mark and skips the open note', () async {
    await env.save(makeNote());
    await open.set(noteId);
    await coordinator.appStarted();
    expect(await open.read(), noteId);
    expect(env.drive.calls, isEmpty);
    expect(env.drive.uploads, isEmpty);
  });

  test(
    'md5Mismatch is retried once per process, not at every trigger',
    () async {
      await env.save(makeNote());
      await env.store.updateSync(
        noteId,
        (c) => c.copyWith(
          state: SyncState.error,
          lastError: {'class': 'fatal', 'reason': 'md5Mismatch'},
        ),
      );
      await coordinator.foreground(); // the one retry
      final first = env.drive.uploads.length;
      expect(first, 1);
      await env.save(makeNote(rev: 2));
      await env.store.updateSync(
        noteId,
        (c) => c.copyWith(
          state: SyncState.error,
          lastError: {'class': 'fatal', 'reason': 'md5Mismatch'},
        ),
      );
      await coordinator.foreground(); // not again
      expect(env.drive.uploads.length, first);
      expect(env.info.state, SyncState.error);
    },
  );

  test('OpenNote clears only its own note', () async {
    await open.set(noteId);
    await open.clear('01926f3a-0000-7000-8000-0000000000aa');
    expect(await open.read(), noteId);
    await open.clear(noteId);
    expect(await open.read(), isNull);
  });

  test(
    'rootReady: the first call is app start, later calls only upload',
    () async {
      await env.save(makeNote());
      await coordinator.rootReady(); // first: app start
      expect(env.info.state, SyncState.synced);

      await open.set(noteId);
      await env.save(makeNote(rev: 2));
      await coordinator.rootReady(); // later: the open note is left alone
      expect(await open.read(), noteId);
      expect(env.drive.uploads, hasLength(1));
    },
  );

  group('Story 11.2: syncing never stays', () {
    test('syncing with nothing to send settles at app start, logged', () async {
      await env.save(makeNote());
      await coordinator.noteClosed(noteId);
      // A killed receive left `syncing`; the working copy equals the base.
      await env.store.updateSync(
        noteId,
        (c) => c.copyWith(state: SyncState.syncing),
      );
      env.drive.calls.clear();
      await coordinator.appStarted();
      expect(env.info.state, SyncState.synced);
      expect((await env.stateChanges()).last, 'syncing>synced');
      expect(env.drive.uploads, hasLength(1)); // nothing uploaded again
    });

    test(
      'an upload killed before its request ends when online again',
      () async {
        await env.save(makeNote());
        env.drive.before = (c) {
          if (c == 'upload:new') throw Crash();
        };
        await coordinator.noteClosed(noteId); // swallowed: a crash
        expect(env.info.state, SyncState.syncing);

        env.drive.before = null;
        env.online = false;
        await coordinator.appStarted(); // offline: still honest, not dropped
        expect(env.info.state, SyncState.syncing);

        env.online = true;
        await coordinator.reconnected();
        expect(env.info.state, SyncState.synced);
        expect(env.drive.uploads, hasLength(1));
      },
    );

    test('an offline edit uploads when the connection returns', () async {
      await env.save(makeNote());
      await coordinator.noteClosed(noteId);
      env.online = false;
      await env.save(makeNote(rev: 2));
      await coordinator.noteClosed(noteId);
      expect((await env.store.readSync(noteId)).state, SyncState.pending);
      expect(scheduled, greaterThan(0));

      env.online = true;
      await coordinator.reconnected();
      expect(env.info.state, SyncState.synced);
      expect(env.drive.uploads, hasLength(2));
    });

    test('an offline edit of the open note uploads when the connection '
        'returns', () async {
      await env.save(makeNote());
      await coordinator.noteClosed(noteId);
      env.online = false;
      await open.set(noteId);
      await env.save(makeNote(rev: 2));
      await coordinator.appBackgrounded(); // offline: stays pending
      expect((await env.store.readSync(noteId)).state, SyncState.pending);

      env.online = true;
      await coordinator.reconnected();
      expect(env.info.state, SyncState.synced);
      expect(env.drive.uploads, hasLength(2));
    });
  });
}
