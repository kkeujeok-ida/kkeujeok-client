// The real merge in the upload engine (Story 3.3) over `FakeDrive`: pre-merge,
// strokes drawn while a download runs, conflicts and sidecars, lineage, the
// merge failures.
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/merge_step.dart';
import 'package:kkeujeok/sync/note_uploader.dart';

import 'fake_drive.dart';
import 'upload_env.dart';

const pageB = '01926f3a-0000-7000-8000-000000000002';

String rev(int n) => '01926f3a-0000-7000-8000-0000000000$n';

/// [makeNote] plus a second page B. [bRev] 2 or more is a page B the other
/// device changed after syncing revision 1 (its `lineage` says so).
Note twoPages({int rev = 1, int bRev = 1}) {
  final j = makeNote(rev: rev).copyJson();
  final b = Map<String, dynamic>.of(
    (j['pages'] as List).first as Map<String, dynamic>,
  );
  b['id'] = pageB;
  b['rev'] = '01926f3a-0000-7000-8000-0000000000${60 + bRev}';
  b['seq'] = bRev;
  if (bRev > 1) {
    b['lineage'] = ['01926f3a-0000-7000-8000-0000000000${60 + bRev - 1}'];
  }
  (j['pages'] as List).add(b);
  return Note.trusted(j);
}

Note withStrokes(Note n, int count) {
  var cur = n;
  for (var i = 0; i < count; i++) {
    cur = addStroke(
      cur,
      {
        'op': 'addStroke',
        'pageId': pageId,
        'stroke': {
          'id': '01926f3a-0000-7000-8000-00000000a0$i${cur.pages.first['seq']}',
          'type': 'stroke',
          'tool': 'pen',
          'color': '#000000',
          'width': 2,
          'usePressure': true,
          'points': [
            [1, 1, 0.5, 0],
            [2 + i, 2, 0.5, 5],
          ],
        },
      },
      Ctx(
        rev: '01926f3a-0000-7000-8000-00000000b0$i',
        now: '2026-10-16T07:00:00.000Z',
        editedBy: 'Pixel 8',
        lastSeenRemoteSeq: i,
      ),
    ).note!;
  }
  return cur;
}

void main() {
  late UploadEnv env;
  Future<UploadOutcome> up() => env.uploader().upload(noteId);

  setUp(() async {
    env = await UploadEnv.create();
    await env.save(twoPages());
    expect(await up(), UploadOutcome.uploaded); // base: revision 1
    env.drive.calls.clear();
    env.drive.uploads.clear();
  });

  List<Map<String, dynamic>> pagesOf(Note n) => n.pages;
  Iterable<FakeUpload> noteUploads() =>
      env.drive.uploads.where((u) => u.metadata['name'] == 'a.kkj');

  test(
    'strokes drawn while the head is downloaded are in the upload',
    () async {
      // Another device changed page B; here page A gets three strokes while
      // the download runs.
      await env.save(
        withStrokes(twoPages(), 1),
      ); // unsent change, starts the sync
      env.drive.foreignRevision(env.note, encodeKkj(twoPages(bRev: 2)));
      var drawn = false;
      env.drive.before = (c) {
        if (c.startsWith('media:') && !drawn) {
          drawn = true;
          env.working.writeAsBytesSync(encodeKkj(withStrokes(twoPages(), 4)));
        }
      };

      expect(await up(), UploadOutcome.uploaded);

      final sent = noteOf(env.note.bytes)!;
      expect(drawn, isTrue);
      expect(
        pagesOf(sent)[0]['elements'],
        hasLength(4),
        reason: 'nothing lost',
      );
      expect(
        pagesOf(sent)[1]['rev'],
        endsWith('62'),
        reason: 'the remote page',
      );
      expect(env.info.conflicts, isEmpty);
      expect(env.info.state, SyncState.synced);
      final w = noteOf(env.working.readAsBytesSync())!;
      expect(pagesOf(w)[0]['elements'], hasLength(4));
    },
  );

  test(
    'strokes on a page the other device changed too are a sidecar',
    () async {
      await env.save(withStrokes(twoPages(), 1));
      // The other device changed page A: it has a lineage and another rev.
      final theirs = twoPages().copyJson();
      final a = (theirs['pages'] as List).first as Map<String, dynamic>;
      a['rev'] = rev(70);
      a['seq'] = 2;
      a['lineage'] = [rev(51)];
      env.drive.foreignRevision(env.note, encodeKkj(Note.trusted(theirs)));
      var drawn = false;
      env.drive.before = (c) {
        if (c.startsWith('media:') && !drawn) {
          drawn = true;
          env.working.writeAsBytesSync(encodeKkj(withStrokes(twoPages(), 3)));
        }
      };

      expect(await up(), UploadOutcome.uploaded);

      expect(pagesOf(noteOf(env.note.bytes)!)[0]['rev'], rev(70));
      final c = env.info.conflicts.single;
      expect(c['kind'], 'bothEdited');
      final sc = env.drive.byKkeujeokId('sc:$noteId:$pageId:${c['rev']}')!;
      expect(sc.name, '$pageId-${c['rev']}.json');
      final record = String.fromCharCodes(sc.bytes);
      // The three strokes are in the sidecar, in the record of the loser.
      expect(RegExp('"type":"stroke"').allMatches(record), hasLength(3));
      expect(env.info.unsentSidecars, isEmpty);
      expect(env.info.state, SyncState.conflict);
    },
  );

  test('head == base: a page changed here gets its lineage, in the upload '
      'and in the working copy', () async {
    await env.save(twoPages(rev: 2)); // page A has a new rev
    expect(await up(), UploadOutcome.uploaded);
    final sent = pagesOf(noteOf(env.note.bytes)!)[0];
    expect(sent['rev'], rev(52));
    expect(sent['lineage'], [rev(51)]);
    final w = pagesOf(noteOf(env.working.readAsBytesSync())!)[0];
    expect(w['lineage'], [rev(51)]);
    expect(await env.eventNames(), isNot(contains('merged')));
    expect(env.info.state, SyncState.synced);
  });

  test(
    'a sidecar that cannot be uploaded keeps the note from going up',
    () async {
      await env.save(twoPages(rev: 2));
      env.drive.foreignRevision(env.note, encodeKkj(twoPages(rev: 9)));
      env.drive.failures['upload:new'] = [
        const DriveError('http', status: 403, reason: 'forbidden'),
      ];
      expect(await up(), UploadOutcome.failed);
      expect(noteUploads(), isEmpty);
      expect(env.info.unsentSidecars, hasLength(1));
      expect(env.info.conflicts, hasLength(1));
      // `conflict` has no `failed` transition (sync.stateMachine): the state
      // stays, the error is in `lastError` and in the log.
      expect(env.info.state, SyncState.conflict);
      expect(env.info.lastError?['class'], 'fatal');
      expect(await env.eventNames(), contains('error'));

      // The next trigger sends the sidecar first, then the note.
      expect(await up(), UploadOutcome.uploaded);
      expect(env.info.unsentSidecars, isEmpty);
      // The merged note is the head Drive already has: nothing more to send.
      expect(noteUploads(), isEmpty);
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      expect(
        env.drive.byKkeujeokId('sc:$noteId:$pageId:${rev(52)}'),
        isNotNull,
      );
      expect(env.info.state, SyncState.conflict);
      expect(env.info.lastError, isNull);
    },
  );

  test('a sidecar that is already in Drive is not created twice', () async {
    await env.save(twoPages(rev: 2));
    env.drive.foreignRevision(env.note, encodeKkj(twoPages(rev: 9)));
    // A crash after the create left the file; the intent led to it.
    final left = env.drive.seed(
      name: 'x.json',
      kkeujeokId: 'sc:$noteId:$pageId:${rev(52)}',
    );
    expect(await up(), UploadOutcome.uploaded);
    expect(
      env.drive.items.where(
        (i) => i.appProperties['kkeujeokId']?.startsWith('sc:') ?? false,
      ),
      [left],
    );
    expect(env.info.unsentSidecars, isEmpty);
  });

  test(
    'unsupportedVersion from the step: nothing written, nothing uploaded',
    () async {
      await env.save(twoPages(rev: 2));
      env.drive.foreignRevision(env.note, encodeKkj(twoPages(rev: 9)));
      env.merge = StubMerge(env.store, (_) => const MergeUnsupported());
      final before = env.working.readAsBytesSync();

      expect(await up(), UploadOutcome.failed);

      expect(noteUploads(), isEmpty);
      expect(env.working.readAsBytesSync(), before);
      expect(env.info.lastError, {
        'class': 'unreadable',
        'reason': 'unsupportedVersion',
      });
      expect(env.info.pendingVerify, isNull);
    },
  );

  test(
    'a merge the queue cannot take now (queueBusy) is deferred, not fatal',
    () async {
      await env.save(twoPages(rev: 2));
      env.drive.foreignRevision(env.note, encodeKkj(twoPages(rev: 9)));
      env.merge = StubMerge(env.store, (_) => const MergeFailed('queueBusy'));

      expect(await up(), UploadOutcome.failed);

      expect(env.info.lastError, {
        'class': 'backoff',
        'reason': 'mergeDeferred',
      });
    },
  );

  test('no mergeUnavailable: the default step is the real one', () async {
    await env.save(twoPages(rev: 2));
    env.drive.foreignRevision(env.note, encodeKkj(twoPages(rev: 9)));
    expect(await up(), UploadOutcome.uploaded);
    expect(env.info.lastError, isNull);
    expect(await env.eventNames(), contains('merged'));
  });

  test('two devices: a change of the other device reaches this one and '
      'comes back', () async {
    // The other device changed page B and uploaded; this one has page A.
    await env.save(withStrokes(twoPages(), 2));
    env.drive.foreignRevision(env.note, encodeKkj(twoPages(bRev: 2)));
    expect(await up(), UploadOutcome.uploaded);
    final w = noteOf(env.working.readAsBytesSync())!;
    expect(pagesOf(w)[1]['rev'], endsWith('62'));
    expect(pagesOf(w)[0]['elements'], hasLength(2));
    expect(env.info.lastSeenRemoteSeq, 2);
    // Both changes are on Drive and in the base.
    final base = (await env.store.readSync(noteId)).base!;
    expect(pagesOf(base)[1]['rev'], endsWith('62'));
    expect(pagesOf(base)[0]['elements'], hasLength(2));
  });
}
