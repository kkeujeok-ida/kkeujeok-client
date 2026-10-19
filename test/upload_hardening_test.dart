import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_device_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/background_upload.dart';
import 'package:kkeujeok/sync/note_uploader.dart';
import 'package:kkeujeok/sync/open_note.dart';
import 'package:kkeujeok/sync/thumbnail.dart';
import 'package:kkeujeok/sync/upload_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_drive.dart';
import 'upload_env.dart';

class _BadMd5 extends FakeDrive {
  @override
  Future<DriveFile> uploadSimple({
    String? fileId,
    required Map<String, Object?> metadata,
    required List<int> bytes,
  }) async {
    final f = await super.uploadSimple(
      fileId: fileId,
      metadata: metadata,
      bytes: bytes,
    );
    return DriveFile(
      id: f.id,
      headRevisionId: f.headRevisionId,
      md5Checksum: '0' * 32,
    );
  }
}

void main() {
  late UploadEnv env;

  setUp(() async {
    env = await UploadEnv.create();
  });

  Future<UploadOutcome> up() => env.uploader().upload(noteId);

  group('a create whose answer was lost', () {
    test('is not repeated: the file is found and adopted', () async {
      await env.save(makeNote());
      var lost = false;
      env.drive.after = (c) {
        if (c == 'upload:new' && !lost) {
          lost = true;
          throw const DriveError('network');
        }
      };
      expect(await up(), UploadOutcome.uploaded);
      expect(env.drive.uploads, hasLength(1)); // never created twice
      expect(env.drive.items.where((i) => i.name == 'a.kkj'), hasLength(1));
      expect(env.info.fileId, env.note.id);
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      expect(env.sleeps, hasLength(1));
    });

    test('a duplicate found on the way is folded into the kept file, then '
        'trashed; its other version of the page is a sidecar', () async {
      await env.save(makeNote());
      var lost = false;
      late FakeItem dup;
      env.drive.after = (c) {
        if (c == 'upload:new' && !lost) {
          lost = true;
          dup = env.drive.seed(name: 'a.kkj', kkeujeokId: noteId);
          env.drive.foreignRevision(dup, encodeKkj(makeNote(rev: 5)));
          throw const DriveError('network');
        }
      };
      await up();
      final log = await env.events();
      expect(
        log.where((e) => e['event'] == 'duplicatesCleaned').single['count'],
        1,
      );
      expect(dup.trashed, isTrue);
      expect(env.info.conflicts, hasLength(1));
      expect(env.info.conflicts.single['kind'], 'bothEdited');
      expect(env.info.unsentSidecars, isEmpty); // uploaded before the note
      expect(
        env.drive.byKkeujeokId(
          'sc:$noteId:$pageId:01926f3a-0000-7000-8000-000000000055',
        ),
        isNotNull,
      );
    });

    test(
      'a duplicate that cannot be parsed is neither folded nor trashed',
      () async {
        await env.save(makeNote());
        var lost = false;
        late FakeItem dup;
        env.drive.after = (c) {
          if (c == 'upload:new' && !lost) {
            lost = true;
            dup = env.drive.seed(name: 'a.kkj', kkeujeokId: noteId);
            env.drive.foreignRevision(dup, [1]);
            throw const DriveError('network');
          }
        };
        await up();
        expect(dup.trashed, isFalse);
        expect(
          (await env.events()).where((e) => e['event'] == 'duplicatesCleaned'),
          isEmpty,
        );
        expect(env.info.conflicts, isEmpty);
      },
    );
  });

  group('resumable offsets', () {
    test(
      'a lost chunk answer asks where Drive is and continues there',
      () async {
        await env.save(bigNote(megabytes: 8.5));
        var lost = false;
        env.drive.after = (c) {
          if (c.startsWith('resumable:put') && c.endsWith(':0') && !lost) {
            lost = true; // the chunk arrived, the answer did not
            throw const DriveError('network');
          }
        };
        expect(await up(), UploadOutcome.uploaded);
        final puts = env.drive.calls.where(
          (c) => c.startsWith('resumable:put'),
        );
        expect(puts.where((c) => c.endsWith(':0')), hasLength(1));
        expect(puts.last, endsWith(':8388608'));
        expect(
          env.drive.calls.any((c) => c.startsWith('resumable:query')),
          isTrue,
        );
        expect(env.note.bytes.length, env.drive.uploads.single.size);
      },
    );

    test('a chunk that never arrived is sent again from 0', () async {
      await env.save(bigNote(megabytes: 5.6));
      env.drive.failures['resumable:put'] = [const DriveError('network')];
      expect(await up(), UploadOutcome.uploaded);
      final puts = env.drive.calls.where((c) => c.startsWith('resumable:put'));
      expect(puts.where((c) => c.endsWith(':0')), hasLength(2));
    });

    test(
      '308 after all bytes is a new session, never a thrown error',
      () async {
        await env.save(bigNote(megabytes: 5.6));
        env.drive.withholdFinishes = 1;
        expect(await up(), UploadOutcome.uploaded);
        expect(env.drive.uploads, hasLength(2));
      },
    );

    test(
      'a session that never finishes ends in a failure with a state',
      () async {
        await env.save(bigNote(megabytes: 5.6));
        env.drive.withholdFinishes = 99;
        expect(await up(), UploadOutcome.failed);
        expect(env.info.state, SyncState.error);
        expect(env.info.lastError?['reason'], 'sessionLost');
        expect(env.drive.uploads, hasLength(3));
      },
    );
  });

  group('upload integrity and summary', () {
    test('an answer whose md5 differs from ours is a failure', () async {
      final bad = _BadMd5();
      env = await UploadEnv.create(drive: bad);
      await env.save(makeNote());
      expect(await up(), UploadOutcome.failed);
      expect(env.info.lastError?['reason'], 'md5Mismatch');
      expect(env.info.baseHeadRevisionId, isNull);
    });

    test('the thumbnail is written when it can be drawn', () async {
      await env.save(makeNote());
      final png = [137, 80, 78, 71, 13, 10, 26, 10, 7, 7];
      int? w, h;
      env.thumbnail = (page, width, height) async {
        w = width;
        h = height;
        return png;
      };
      await up();
      expect(base64Url.decode(env.note.thumbnailHint!['image'] as String), png);
      expect((w, h), (300, 425));
    });

    test('a render that throws, or a PNG over 2 MiB, writes none', () async {
      await env.save(makeNote());
      env.thumbnail = (p, w, h) async => throw StateError('no engine');
      expect(await up(), UploadOutcome.uploaded);
      expect(env.note.thumbnailHint, isNull);

      await env.save(makeNote(rev: 2));
      env.thumbnail = (p, w, h) async => List.filled(maxThumbnailBytes + 1, 1);
      expect(await up(), UploadOutcome.uploaded);
      expect(env.note.thumbnailHint, isNull);

      await env.save(makeNote(rev: 3));
      env.thumbnail = (p, w, h) async => List.filled(maxThumbnailBytes, 1);
      expect(await up(), UploadOutcome.uploaded);
      expect(env.note.thumbnailHint, isNotNull);
    });
  });

  group('sync.json that cannot be read', () {
    test('is never replaced by an empty one; the failure is logged', () async {
      await env.save(makeNote());
      await up();
      await env.save(makeNote(rev: 2));
      env.syncFile.writeAsStringSync('{ not json');
      env.drive.calls.clear();

      expect(await up(), UploadOutcome.failed);

      expect(env.syncFile.readAsStringSync(), '{ not json'); // not dropped
      final err = (await env.events()).where((e) => e['event'] == 'error');
      expect(err.last['reason'], 'syncUnreadable');
    });

    test(
      'updateSync refuses it and forgets a base file that is gone',
      () async {
        await env.save(makeNote());
        await env.store.updateSync(
          noteId,
          (c) => c.copyWith(baseHeadRevisionId: 'R1'),
          base: makeNote(),
        );
        File('${env.noteDir.path}/base.R1.kkj').deleteSync();
        final done = await env.store.updateSync(
          noteId,
          (c) => c.copyWith(state: SyncState.pending),
        );
        expect(done.baseHeadRevisionId, isNull); // recovered, no exception

        env.syncFile.writeAsStringSync('[]');
        await expectLater(
          env.store.updateSync(noteId, (c) => c),
          throwsA(
            isA<NoteSaveException>().having(
              (e) => e.message,
              'message',
              syncUnreadableMessage,
            ),
          ),
        );
        expect(env.syncFile.readAsStringSync(), '[]');
      },
    );

    test('a failed write leaves no .tmp behind', () async {
      final store = NoteStore(
        env.data,
        writeFile: (f, b) async {
          await f.writeAsBytes(b);
          throw const FileSystemException('disk full');
        },
      );
      await env.save(makeNote());
      await expectLater(
        store.updateSync(noteId, (c) => c.copyWith(fileId: 'F')),
        throwsA(isA<NoteSaveException>()),
      );
      expect(
        env.noteDir.listSync().where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );
    });
  });

  group('UploadLease', () {
    late DateTime now;
    setUp(() async {
      now = DateTime.utc(2026, 10, 11, 9);
      await env.save(makeNote());
    });
    UploadLease lease() => UploadLease(env.data, () => now);
    File file() => File('${env.noteDir.path}/upload.lease');

    test(
      'an empty file (the moment between create and write) is fresh',
      () async {
        file().writeAsStringSync('');
        expect(await lease().acquire(noteId), isFalse);
        expect(file().existsSync(), isTrue); // not deleted
      },
    );

    test('an empty file that is old by its file time is taken over', () async {
      file().writeAsStringSync('');
      file().setLastModifiedSync(
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(await lease().acquire(noteId), isTrue);
    });

    test('two takers of a stale lease: exactly one wins', () async {
      file().writeAsStringSync('0123456789abcdef:0');
      final a = lease(), b = lease();
      final r = await Future.wait([a.acquire(noteId), b.acquire(noteId)]);
      expect(r.where((x) => x), hasLength(1));
    });

    test('a lease of another process id is taken over at once', () async {
      final dead = UploadLease(env.data, () => now, processId: 1);
      expect(await dead.acquire(noteId), isTrue); // killed, never released
      expect(await lease().acquire(noteId), isTrue); // no 10-minute wait
    });

    test('only the owner releases', () async {
      final a = lease(), b = lease();
      expect(await a.acquire(noteId), isTrue);
      await b.release(noteId);
      expect(file().existsSync(), isTrue);
      await a.release(noteId);
      expect(file().existsSync(), isFalse);
      expect(await b.acquire(noteId), isTrue);
    });

    test('a renewed lease is not stale; one that is not renewed is', () async {
      final a = lease(), b = lease();
      expect(await a.acquire(noteId), isTrue);
      now = now.add(const Duration(minutes: 9));
      await a.renew(noteId);
      now = now.add(const Duration(minutes: 9)); // 18 since acquire
      expect(await b.acquire(noteId), isFalse);
      now = now.add(const Duration(minutes: 2)); // 11 since renew
      expect(await b.acquire(noteId), isTrue);
      await a.renew(noteId); // no longer the owner: changes nothing
      await a.release(noteId);
      expect(file().existsSync(), isTrue);
    });

    test('the uploader keeps the lease fresh through the heartbeat', () async {
      final l = lease();
      expect(await l.acquire(noteId), isTrue);
      var beats = 0;
      final u = NoteUploader(
        store: env.store,
        drive: env.drive,
        device: env.device,
        log: env.log,
        merge: env.merge,
        allowed: () async => true,
        online: () async => true,
        sleep: (d) async {},
        jitter: () => 0.5,
        heartbeat: (id) async {
          beats++;
          await l.renew(id);
        },
      );
      await u.upload(noteId);
      expect(beats, greaterThanOrEqualTo(3));
    });
  });

  group('coordinator retry policy', () {
    late UploadCoordinator coordinator;
    late int scheduled;
    setUp(() {
      scheduled = 0;
      coordinator = UploadCoordinator(
        store: env.store,
        uploader: env.uploader(),
        openNote: OpenNote(env.data.rootDir),
        lease: UploadLease(env.data, DateTime.now),
        log: env.log,
        allowed: () async => env.allowed,
        online: () async => env.online,
        schedule: () async => scheduled++,
      );
    });

    test('a merge error (duplicatePageId) is retried once per process, '
        'not at every trigger', () async {
      await env.save(makeNote());
      await coordinator.noteClosed(noteId);
      await env.save(makeNote(rev: 2));
      final json = makeNote(rev: 9).copyJson();
      final pages = json['pages'] as List;
      pages.add(copyJsonValue(pages.first)); // a page id twice
      env.drive.foreignRevision(env.note, encodeKkj(Note.trusted(json)));
      await coordinator.noteClosed(noteId);
      expect(env.info.lastError?['reason'], 'duplicatePageId');

      env.drive.calls.clear();
      await coordinator.foreground(); // the one retry: fails the same way
      expect(env.drive.calls, isNotEmpty);
      expect(env.info.lastError?['reason'], 'duplicatePageId');

      env.drive.calls.clear();
      await coordinator.foreground();
      await coordinator.uploadUnsent();
      await coordinator.appStarted();
      expect(env.drive.calls, isEmpty);
      expect(env.info.state, SyncState.error);
    });

    test(
      'a note in error is also retried from app start and the task',
      () async {
        const quota = DriveError(
          'http',
          status: 403,
          reason: 'storageQuotaExceeded',
        );
        await env.save(makeNote());
        env.drive.failures['upload'] = [quota];
        await coordinator.noteClosed(noteId);
        expect(env.info.state, SyncState.error);
        await coordinator.uploadUnsent(); // the WorkManager task
        expect(env.info.state, SyncState.synced);

        await env.save(makeNote(rev: 2));
        env.drive.failures['upload'] = [quota];
        await coordinator.noteClosed(noteId);
        expect(env.info.state, SyncState.error);
        await coordinator.appStarted();
        expect(env.info.state, SyncState.synced);
      },
    );

    test('a backoff failure schedules the background task', () async {
      await env.save(makeNote());
      env.drive.failures['upload'] = [
        for (var i = 0; i < 7; i++) const DriveError('network'),
      ];
      await coordinator.noteClosed(noteId);
      expect(env.info.lastError?['class'], 'backoff');
      expect(scheduled, 1);
    });

    test(
      'a lease held by someone else reschedules instead of dropping',
      () async {
        await env.save(makeNote());
        expect(
          await UploadLease(env.data, DateTime.now).acquire(noteId),
          isTrue,
        );
        await coordinator.noteClosed(noteId);
        expect(env.drive.calls, isEmpty);
        expect(scheduled, 1);
      },
    );
  });

  group('runBackgroundUpload gate', () {
    Future<void> run({
      Map<String, Object> prefs = const {
        'signedIn': true,
        'accountSub': 's',
        'accountEmail': 'e',
      },
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      await runBackgroundUpload(
        prefs: await SharedPreferences.getInstance(),
        data: env.data,
        drive: env.drive,
        online: () async => true,
      );
    }

    setUp(() async {
      await env.save(makeNote());
    });

    test('uploads an unsent note for the signed-in account', () async {
      await run();
      expect(env.info.state, SyncState.synced);
      expect(env.drive.uploads, hasLength(1));
    });

    test('not signed in, or another account: no request', () async {
      await run(prefs: {});
      await run(prefs: {'signedIn': true});
      await run(
        prefs: {'signedIn': true, 'accountSub': 'other', 'accountEmail': 'e'},
      );
      expect(env.drive.calls, isEmpty);
    });

    test('no root folder id: no request', () async {
      await env.device.write(const SyncDevice(sub: 's', email: 'e'));
      await run();
      expect(env.drive.calls, isEmpty);
    });

    test('a trashed or deleted root is not uploaded into', () async {
      env.root.trashed = true;
      await run();
      expect(env.drive.uploads, isEmpty);

      env.root.trashed = false;
      env.root.deleted = true;
      await run();
      expect(env.drive.uploads, isEmpty);
    });

    test('the note the editor has open is skipped', () async {
      await OpenNote(env.data.rootDir).set(noteId);
      await run();
      expect(env.drive.uploads, isEmpty);
    });
  });

  testWidgets('renderThumbnail draws a PNG of the requested size', (t) async {
    final bytes = await t.runAsync(
      () => renderThumbnail(makeNote().pages.first, 300, 425),
    );
    expect(bytes, isNotNull);
    final b = Uint8List.fromList(bytes!);
    expect(b.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final h = ByteData.sublistView(b, 16, 24); // IHDR width, height
    expect((h.getUint32(0), h.getUint32(4)), (300, 425));
  });
}
