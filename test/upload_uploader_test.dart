import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/merge_step.dart';
import 'package:kkeujeok/sync/note_uploader.dart';

import 'upload_env.dart';

void main() {
  late UploadEnv env;

  setUp(() async {
    env = await UploadEnv.create();
  });

  Future<UploadOutcome> up() => env.uploader().upload(noteId);

  group('a new note', () {
    test(
      'intent, lookup, create with content and summary, verify, base',
      () async {
        await env.save(makeNote());
        env.thumbnail = (page, w, h) async => [137, 80, 78, 71];
        String? intentAtLookup;
        env.drive.before = (c) {
          if (c == 'list') intentAtLookup = env.syncFile.readAsStringSync();
        };

        expect(await up(), UploadOutcome.uploaded);

        expect(intentAtLookup, contains('"createIntent":{"kkeujeokId"'));
        final item = env.note;
        expect(item.name, 'a.kkj');
        expect(item.parents, [env.root.id]);
        expect(item.appProperties['kkeujeokId'], noteId);
        expect(item.appProperties['kkjV'], '1');
        expect(item.appProperties['kkjMd5'], env.md5Of(item.bytes));
        expect(item.appProperties.containsKey('kkjCover'), isFalse);
        expect(item.thumbnailHint?['mimeType'], 'image/png');
        expect(item.thumbnailHint?['image'], isA<String>());
        expect(noteOf(item.bytes)!.noteId, noteId);
        expect(env.drive.uploads.single.kind, 'simple');
        expect(env.drive.calls, [
          'list',
          'upload:new',
          'get:${item.id}',
          'revisions:${item.id}',
        ]);

        final s = env.info;
        expect(s.state, SyncState.synced);
        expect(s.fileId, item.id);
        expect(s.baseHeadRevisionId, item.headRevisionId);
        expect(s.pendingVerify, isNull);
        expect(s.createIntent, isNull);
        expect(s.resumableSession, isNull);
        expect(s.lastError, isNull);
        final r = await env.store.readSync(noteId);
        expect(r.base, isNotNull);
        expect(r.hasUnsent, isFalse);

        expect(await env.eventNames(), [
          'stateChange',
          'uploadStarted',
          'uploadFinished',
          'verifyRound',
          'baseAdvanced',
          'stateChange',
        ]);
        expect(await env.stateChanges(), ['pending>syncing', 'syncing>synced']);
      },
    );

    test(
      'a lagging listing does not matter: the create response is used',
      () async {
        await env.save(makeNote());
        env.drive.lagLists = 5;
        expect(await up(), UploadOutcome.uploaded);
        expect(env.drive.items.where((i) => i.name == 'a.kkj'), hasLength(1));
        expect(env.info.fileId, env.note.id);
      },
    );

    test(
      'crash after the create: lookup finds the file, only verifies',
      () async {
        await env.save(makeNote());
        env.drive.after = (c) {
          if (c == 'upload:new') throw Crash();
        };
        await expectLater(up(), throwsA(isA<Crash>()));
        // What a killed process left: the intent and an unfinished upload.
        expect(env.info.createIntent, isNotNull);
        expect(env.info.fileId, isNull);
        expect(env.info.pendingVerify?['oursRevisionId'], isNull);

        env.drive.after = null;
        env.drive.calls.clear();
        expect(await env.uploader().upload(noteId), UploadOutcome.uploaded);

        expect(env.drive.uploads, hasLength(1)); // never uploaded again
        expect(env.drive.items.where((i) => i.name == 'a.kkj'), hasLength(1));
        expect(env.info.state, SyncState.synced);
        expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      },
    );

    test(
      'a file of the same kkeujeokId with other content is not adopted',
      () async {
        await env.save(makeNote());
        var n = 0;
        env.drive.before = (c) {
          if (c == 'upload:new' && n++ == 0) {
            env.drive.foreignNote(makeNote(rev: 9), parent: env.root.id);
            throw const DriveError('network');
          }
        };

        expect(await up(), UploadOutcome.uploaded);

        final theirs = env.drive.items.firstWhere(
          (i) => i.appProperties['kkeujeokId'] == noteId,
        );
        expect(env.info.baseHeadRevisionId, isNot(theirs.headRevisionId));
        final base = (await env.store.readSync(noteId)).base!;
        expect(base.pages.first['rev'], endsWith('51')); // ours, not theirs
      },
    );

    test('crash before the request: the whole upload is repeated', () async {
      await env.save(makeNote());
      env.drive.before = (c) {
        if (c == 'upload:new') throw Crash();
      };
      await expectLater(up(), throwsA(isA<Crash>()));
      expect(env.drive.uploads, isEmpty);
      expect(env.info.pendingVerify?['oursRevisionId'], isNull);

      env.drive.before = null;
      expect(await env.uploader().upload(noteId), UploadOutcome.uploaded);
      expect(env.drive.uploads, hasLength(1));
      expect(env.info.state, SyncState.synced);
    });

    test('an unfinished upload with oursRevisionId only verifies', () async {
      await env.save(makeNote());
      // Crash while verifying: the revision id is on disk by then.
      env.drive.before = (c) {
        if (c.startsWith('get:')) throw Crash();
      };
      await expectLater(up(), throwsA(isA<Crash>()));
      final ours = env.info.pendingVerify?['oursRevisionId'];
      expect(ours, env.note.headRevisionId);

      env.drive.before = null;
      env.drive.calls.clear();
      expect(await env.uploader().resume(noteId), UploadOutcome.uploaded);
      expect(env.drive.uploads, hasLength(1));
      expect(env.drive.calls.where((c) => c.startsWith('upload')), isEmpty);
      expect(env.drive.calls.any((c) => c.startsWith('media:')), isTrue);
      expect(env.info.baseHeadRevisionId, ours);
      expect(env.info.pendingVerify, isNull);
    });
  });

  group('an uploaded note', () {
    setUp(() async {
      await env.save(makeNote());
      await up();
      env.drive.calls.clear();
      env.drive.uploads.clear();
    });

    test('nothing unsent: no request', () async {
      expect(await up(), UploadOutcome.skipped);
      expect(env.drive.calls, isEmpty);
    });

    test('head == base: pendingVerify first, update with name and summary, '
        'no parent change, a renamed file is renamed back', () async {
      await env.save(makeNote(rev: 2));
      env.note.name = 'Renamed in Drive';
      String? atUpload;
      env.drive.before = (c) {
        if (c.startsWith('upload:')) atUpload = env.syncFile.readAsStringSync();
      };

      expect(await up(), UploadOutcome.uploaded);

      expect(atUpload, contains('"pendingVerify":{"parentRevisionId"'));
      final u = env.drive.uploads.single;
      expect(u.fileId, env.note.id);
      expect(u.metadata['name'], 'a.kkj');
      expect(u.metadata.containsKey('parents'), isFalse);
      expect(u.metadata.containsKey('addParents'), isFalse);
      expect(env.note.name, 'a.kkj');
      expect(env.note.parents, [env.root.id]);
      expect(env.note.appProperties['kkjMd5'], env.md5Of(env.note.bytes));
      expect(env.drive.calls.first, 'get:${env.note.id}');
      expect(env.info.state, SyncState.synced);
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
    });

    test('an edit made during the upload is not in the snapshot', () async {
      await env.save(makeNote(rev: 2));
      env.drive.after = (c) {
        if (c.startsWith('upload:')) {
          env.working.writeAsBytesSync(encodeKkj(makeNote(rev: 3)));
        }
      };
      expect(await up(), UploadOutcome.uploaded);

      expect(noteOf(env.note.bytes)!.pages.first['rev'], endsWith('52'));
      final r = await env.store.readSync(noteId);
      expect(r.base!.pages.first['rev'], endsWith('52'));
      expect(r.hasUnsent, isTrue);
      expect(env.info.state, SyncState.pending);
      // The working copy is the edit, untouched by the sync.
      expect(
        decodeKkj(env.working.readAsBytesSync()).note!.pages.first['rev'],
        endsWith('53'),
      );
    });

    test('head != base: merged into the working copy, conflict recorded, '
        'sidecar uploaded before the note', () async {
      await env.save(makeNote(rev: 2));
      final head = env.drive.foreignRevision(
        env.note,
        encodeKkj(makeNote(rev: 9)),
      );
      final order = <String>[];
      env.drive.after = (c) {
        if (c.startsWith('upload:')) {
          order.add(env.drive.uploads.last.metadata['name'] as String);
        }
      };

      expect(await up(), UploadOutcome.uploaded);

      // Both pages differ from the base: the remote page stays in the note,
      // ours is a sidecar.
      expect(
        noteOf(env.working.readAsBytesSync())!.pages.first['rev'],
        endsWith('59'),
      );
      expect(env.info.conflicts, hasLength(1));
      expect(env.info.conflicts.single, containsPair('kind', 'bothEdited'));
      expect(env.info.conflicts.single['rev'], endsWith('52'));
      expect(env.info.unsentSidecars, isEmpty);
      expect(order, [
        '$pageId-01926f3a-0000-7000-8000-000000000052.json',
        'a.kkj',
      ]);
      final sc = env.drive.byKkeujeokId(
        'sc:$noteId:$pageId:01926f3a-0000-7000-8000-000000000052',
      )!;
      expect(sc.appProperties['kkjIndex'], '0');
      expect(sc.appProperties['kkjEdited'], isNotNull);
      expect(env.drive.byKkeujeokId('cf:$noteId'), isNotNull);
      expect(env.drive.byKkeujeokId('conflicts')!.parents, [env.root.id]);
      expect(env.note.headRevisionId, isNot(head.id));
      expect(env.info.state, SyncState.conflict);
      expect(await env.stateChanges(), contains('syncing>conflict'));
      expect(await env.eventNames(), contains('conflictFound'));
      expect(env.info.lastError, isNull);
      expect(env.info.pendingVerify, isNull);
      expect(env.info.createIntent, isNull);
      expect((await env.device.read()).createIntents, isEmpty);
    });

    test('a remote that already holds our working copy is ours', () async {
      await env.save(makeNote(rev: 2));
      env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 2)));
      expect(await up(), UploadOutcome.uploaded);
      expect(env.drive.uploads, isEmpty);
      expect(env.info.state, SyncState.synced);
    });

    test('a foreign revision at verify is merged and uploaded again', () async {
      await env.save(makeNote(rev: 2));
      var n = 0;
      env.drive.after = (c) {
        if (c.startsWith('upload:') && n++ == 0) {
          env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 9)));
        }
      };

      expect(await up(), UploadOutcome.uploaded);

      final notes = env.drive.uploads.where(
        (u) => (u.metadata['name'] as String).endsWith('.kkj'),
      );
      expect(notes, hasLength(2)); // round 1 and round 2
      expect(env.info.lastError, isNull);
      expect(env.info.pendingVerify, isNull);
      expect(env.info.conflicts.single, containsPair('kind', 'bothEdited'));
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      expect(
        noteOf(env.note.bytes)!.pages.first['rev'],
        endsWith('59'),
        reason: 'the remote page won, ours is in the sidecar',
      );
    });

    test(
      'an external revision before our PATCH is merged once, then synced',
      () async {
        await env.save(makeNote(rev: 2));
        var n = 0;
        env.drive.before = (c) {
          if (c.startsWith('upload:') && n++ == 0) {
            env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 9)));
          }
        };

        expect(await up(), UploadOutcome.uploaded);

        // R1 (ours, after the external F) is not a candidate of round 2.
        expect(
          env.drive.uploads.where((u) => u.metadata['name'] == 'a.kkj'),
          hasLength(2),
        );
        expect(env.info.state, SyncState.conflict);
        expect(env.info.lastError, isNull);
        expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      },
    );

    test('a lost answer of an update that landed is not sent again', () async {
      await env.save(makeNote(rev: 2));
      env.drive.after = (c) {
        if (c.startsWith('upload:') && env.drive.uploads.length == 1) {
          throw const DriveError('network');
        }
      };

      expect(await up(), UploadOutcome.uploaded);

      expect(env.drive.uploads, hasLength(1)); // not sent again
      expect(env.info.state, SyncState.synced);
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
    });

    test('a head that moved before the PATCH goes back to the merge', () async {
      await env.save(makeNote(rev: 2));
      var gets = 0;
      env.drive.before = (c) {
        // 1: step 1, 2: the check before the PATCH.
        if (c.startsWith('get:') && ++gets == 2) {
          env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 9)));
        }
      };

      expect(await up(), UploadOutcome.uploaded);

      expect(
        env.drive.uploads.where((u) => u.metadata['name'] == 'a.kkj'),
        hasLength(1), // one PATCH, after the merge
      );
      expect([
        for (final e in await env.events()) e['reason'],
      ], contains('headMoved'));
      expect(env.info.conflicts, hasLength(1));
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
    });

    test('a merged answer is uploaded again with round + 1, up to 3', () async {
      await env.save(makeNote(rev: 2));
      final stub = StubMerge(env.store, (_) => Merged(makeNote(rev: 4)));
      env.merge = stub;
      env.drive.after = (c) {
        if (c.startsWith('upload:')) {
          env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 9)));
        }
      };

      expect(await up(), UploadOutcome.failed);

      expect(
        env.drive.uploads.where((u) => u.metadata['name'] == 'a.kkj'),
        hasLength(3),
      ); // the round limit
      expect(stub.calls, 3); // head == base first, then two foreign rounds
      expect(env.info.lastError, {
        'class': 'fatal',
        'reason': 'verifyExhausted',
      });
      expect(env.info.pendingVerify, isNull);
      final rounds = [
        for (final e in await env.events())
          if (e['event'] == 'verifyRound') '${e['round']}:${e['count']}',
      ];
      // The first entry is the setUp upload; the last round has nothing to
      // download because the plan answers `error`.
      expect(rounds, ['1:0', '1:1', '2:1', '3:0']);
      expect(env.working.existsSync(), isTrue); // changes stay
    });

    test('a merged answer that is then verified moves the base', () async {
      await env.save(makeNote(rev: 2));
      env.merge = StubMerge(env.store, (_) => Merged(makeNote(rev: 4)));
      var n = 0;
      env.drive.after = (c) {
        if (c.startsWith('upload:') && n++ == 0) {
          env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 9)));
        }
      };

      expect(await up(), UploadOutcome.uploaded);

      expect(
        env.drive.uploads.where((u) => u.metadata['name'] == 'a.kkj'),
        hasLength(2),
      );
      final base = (await env.store.readSync(noteId)).base!;
      expect(base.pages.first['rev'], endsWith('54')); // the merged note
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
    });

    test('a purged base is merged against the head', () async {
      await env.save(makeNote(rev: 2));
      final oldBase = env.note.headRevisionId!;
      env.drive.after = (c) {
        if (c.startsWith('upload:')) {
          env.drive.purgeRevision(env.note, oldBase);
        }
      };
      expect(await up(), UploadOutcome.uploaded);
      expect(env.info.state, SyncState.synced);
    });

    test('a remote with a newer formatVersion is never touched', () async {
      await env.save(makeNote(rev: 2));
      final json = makeNote(rev: 9).copyJson()..['formatVersion'] = 2;
      final bytes = gzip.encode(utf8Json(json));
      final head = env.drive.foreignRevision(env.note, bytes);

      expect(await up(), UploadOutcome.failed);

      expect(env.info.lastError, {
        'class': 'unreadable',
        'reason': 'unsupportedVersion',
      });
      expect(env.drive.uploads, isEmpty);
      expect(env.note.headRevisionId, head.id);
    });

    test('a remote that cannot be parsed is never touched', () async {
      await env.save(makeNote(rev: 2));
      env.drive.foreignRevision(env.note, [1, 2, 3]);
      expect(await up(), UploadOutcome.failed);
      expect(env.info.lastError, {'class': 'unreadable', 'reason': 'parse'});
      expect(env.drive.uploads, isEmpty);
    });

    test('a trashed or deleted file is `deleted`', () async {
      await env.save(makeNote(rev: 2));
      env.note.trashed = true;
      expect(await up(), UploadOutcome.failed);
      expect(env.info.lastError?['class'], 'deleted');
      expect(env.drive.uploads, isEmpty);
    });
  });

  group('errors', () {
    setUp(() async {
      await env.save(makeNote());
    });

    test('5xx waits by backoff, with the injected jitter', () async {
      env.jitter = 1; // 1.5 x nominal
      env.drive.failures['upload'] = [
        const DriveError('http', status: 503),
        const DriveError('http', status: 429),
        const DriveError('network'),
      ];
      expect(await up(), UploadOutcome.uploaded);
      expect(env.sleeps, [
        const Duration(milliseconds: 1500),
        const Duration(milliseconds: 3000),
        const Duration(milliseconds: 6000),
      ]);
      final waits = [
        for (final e in await env.events())
          if (e['event'] == 'backoff') '${e['attempt']}:${e['delayMs']}',
      ];
      expect(waits, ['1:1500', '2:3000', '3:6000']);
    });

    test('a verify answer that cannot be parsed is not `unreadable`', () async {
      env.drive.failures['revisions'] = [const DriveError('parse')];
      expect(await up(), UploadOutcome.failed);
      expect(env.info.lastError, {'class': 'fatal', 'reason': 'verifyParse'});
      expect(env.info.pendingVerify, isNotNull); // verify repeats, no re-upload
    });

    test('403 rateLimitExceeded is a backoff', () async {
      env.drive.failures['upload'] = [
        const DriveError('http', status: 403, reason: 'rateLimitExceeded'),
      ];
      expect(await up(), UploadOutcome.uploaded);
      expect(env.sleeps, hasLength(1));
    });

    test('the 7th failure is `failed` and logs only the error', () async {
      env.drive.failures['upload'] = [
        for (var i = 0; i < 7; i++) const DriveError('http', status: 500),
      ];
      expect(await up(), UploadOutcome.failed);
      expect(env.sleeps, hasLength(6));
      expect(env.drive.uploads, isEmpty); // the fake threw before recording
      final log = await env.events();
      expect(log.where((e) => e['event'] == 'backoff'), hasLength(6));
      final errors = log.where((e) => e['event'] == 'error').toList();
      expect(errors, hasLength(1));
      expect(errors.single['class'], 'backoff');
      expect(errors.single['status'], 500);
      expect(env.info.state, SyncState.error);
      expect(env.info.lastError?['class'], 'backoff');
    });

    test('storageQuotaExceeded is not retried', () async {
      env.drive.failures['upload'] = [
        const DriveError('http', status: 403, reason: 'storageQuotaExceeded'),
      ];
      expect(await up(), UploadOutcome.failed);
      expect(env.sleeps, isEmpty);
      expect(env.info.lastError?['class'], 'quota');
      expect(env.info.state, SyncState.error);
      // The edit is on the device untouched.
      expect(env.working.existsSync(), isTrue);
    });

    test('no token is `reauth`', () async {
      env.drive.failures['list'] = [
        const DriveError('http', status: 401, reason: 'noToken'),
      ];
      expect(await up(), UploadOutcome.failed);
      expect(env.info.lastError, {
        'class': 'reauth',
        'status': 401,
        'reason': 'noToken',
      });
    });

    test('a note in `error` is not uploaded until it gets `retry`', () async {
      env.drive.failures['upload'] = [
        const DriveError('http', status: 403, reason: 'storageQuotaExceeded'),
      ];
      await up();
      env.drive.calls.clear();
      expect(await up(), UploadOutcome.skipped);
      expect(env.drive.calls, isEmpty);
    });
  });

  group('gate', () {
    test('offline: no request, the note stays pending', () async {
      await env.save(makeNote());
      env.online = false;
      expect(await up(), UploadOutcome.skipped);
      expect(env.drive.calls, isEmpty);
      final r = await env.store.readSync(noteId);
      expect(r.state, SyncState.pending);
    });

    test('uploads not allowed: no request', () async {
      await env.save(makeNote());
      env.allowed = false;
      expect(await up(), UploadOutcome.skipped);
      expect(env.drive.calls, isEmpty);
      expect(env.syncFile.existsSync(), isFalse); // nothing even written
    });

    test('a working copy that cannot be read is never touched', () async {
      await env.save(makeNote());
      env.working.writeAsBytesSync([9, 9, 9]);
      expect(await up(), UploadOutcome.skipped);
      expect(env.drive.calls, isEmpty);
      expect(env.working.readAsBytesSync(), [9, 9, 9]);
    });

    test('two calls at once make one upload', () async {
      await env.save(makeNote());
      final u = env.uploader();
      final r = await Future.wait([u.upload(noteId), u.upload(noteId)]);
      expect(r, [UploadOutcome.uploaded, UploadOutcome.skipped]);
      expect(env.drive.uploads, hasLength(1));
    });
  });

  group('resumable', () {
    test(
      'a body over 5 MiB uses a session saved in resumableSession',
      () async {
        await env.save(bigNote(megabytes: 5.6));
        String? atPut;
        env.drive.before = (c) {
          if (c.startsWith('resumable:put')) {
            atPut = env.syncFile.readAsStringSync();
          }
        };
        expect(await up(), UploadOutcome.uploaded);

        final u = env.drive.uploads.single;
        expect(u.kind, 'resumable');
        expect(u.size, greaterThan(5242880));
        expect(atPut, contains('"resumableSession":{"uri"'));
        expect(env.note.bytes.length, u.size);
        expect(env.note.appProperties['kkjMd5'], env.md5Of(env.note.bytes));
        expect(u.metadata['name'], 'a.kkj');
        expect(env.info.resumableSession, isNull);
        expect(env.info.state, SyncState.synced);
      },
    );

    test('chunks are 8 MiB; a body of two chunks is two puts', () async {
      await env.save(bigNote(megabytes: 8.5));
      expect(await up(), UploadOutcome.uploaded);
      final puts = env.drive.calls.where((c) => c.startsWith('resumable:put'));
      expect(puts.length, 2);
      expect(puts.last, endsWith(':8388608'));
    });

    test(
      'kill mid-flight: the session is not continued, a new one restarts at 0',
      () async {
        await env.save(bigNote(megabytes: 8.5));
        env.drive.after = (c) {
          if (c.startsWith('resumable:put') && c.endsWith(':0')) throw Crash();
        };
        await expectLater(up(), throwsA(isA<Crash>()));
        expect(env.info.resumableSession, isNotNull);
        expect(env.drive.byKkeujeokId(noteId), isNull); // not there yet
        env.drive.after = null;
        env.drive.calls.clear();

        expect(await env.uploader().resume(noteId), UploadOutcome.uploaded);
        expect(env.drive.calls.first.startsWith('resumable:query'), isTrue);
        expect(env.drive.uploads, hasLength(2));
        expect(env.info.state, SyncState.synced);
        expect(env.note.bytes, isNotEmpty);
      },
    );

    test(
      'kill after the last chunk: the session answers with the file',
      () async {
        await env.save(bigNote(megabytes: 5.6));
        env.drive.after = (c) {
          if (c.startsWith('resumable:done')) throw Crash();
        };
        await expectLater(up(), throwsA(isA<Crash>()));
        env.drive.after = null;
        env.drive.calls.clear();

        expect(await env.uploader().resume(noteId), UploadOutcome.uploaded);
        expect(env.drive.uploads, hasLength(1)); // never uploaded again
        expect(env.info.state, SyncState.synced);
        expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      },
    );

    test('an expired session (404 or 410) restarts at byte 0', () async {
      await env.save(bigNote(megabytes: 5.6));
      var n = 0;
      env.drive.before = (c) {
        if (c.startsWith('resumable:put') && n++ == 0) {
          env.drive.expireSessions();
        }
      };
      env.drive.expiredStatus = 410;
      expect(await up(), UploadOutcome.uploaded);
      expect(env.drive.uploads, hasLength(2));
    });
  });
}

List<int> utf8Json(Object? v) => utf8.encode(jsonEncode(v));
