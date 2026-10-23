// Story 3.24: the restore procedure of spec `version-history` over a fake
// Drive: read, upload and verify, pin, apply through the queue. A failing step
// restores nothing.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/restore.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/merge_step.dart';
import 'package:kkeujeok/sync/open_note.dart';
import 'package:kkeujeok/sync/upload_coordinator.dart';
import 'package:kkeujeok/sync/version_history.dart';
import 'package:kkeujeok/sync/version_list.dart';

import 'fake_drive.dart';
import 'upload_env.dart';

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

void main() {
  late UploadEnv env;
  late UploadCoordinator coordinator;
  late VersionRestorer restorer;
  late List<String> order; // what happened, in order
  late bool applyOk;
  late int revN;
  late int calls;

  setUp(() async {
    env = await UploadEnv.create();
    revN = 0;
    calls = 0;
    order = [];
    applyOk = true;
    coordinator = UploadCoordinator(
      store: env.store,
      uploader: env.uploader(),
      openNote: OpenNote(env.data.rootDir),
      lease: UploadLease(env.data, () => DateTime.utc(2026, 10, 11, 9)),
      log: env.log,
      allowed: () async => env.allowed,
      online: () async => env.online,
      schedule: () async {},
    );
    restorer = VersionRestorer(
      drive: env.drive,
      store: env.store,
      coordinator: coordinator,
      clock: () => DateTime.utc(2026, 10, 18, 9),
      delay: (_) async {},
      newRev: () => _id(7000 + revN++),
    );
    env.drive.before = (c) => order.add(c.split(':').first);
  });

  /// R1 = note rev 1 uploaded, R2 = rev 2 (the head).
  Future<void> twoRevisions() async {
    await env.save(makeNote(rev: 1));
    await coordinator.noteClosed(noteId);
    await env.save(makeNote(rev: 2));
    await coordinator.noteClosed(noteId);
    expect(env.note.revisions, hasLength(2));
    env.drive.calls.clear();
    order.clear();
  }

  /// The queue entry point of the editor, as a test double: it runs the merge
  /// on the working copy and writes the result.
  Future<bool> host(LiveMerge m, Future<void> Function() record) async {
    calls++;
    if (!applyOk) return false;
    order.add('apply');
    final live = (await env.store.read(noteId))!.note!;
    final r = m(live);
    await record();
    if (r != null) await env.store.write(r.note);
    return true;
  }

  Future<Map<String, Object?>> entryOf(
    bool Function(Map<String, Object?>) pick,
  ) async {
    final fileId = env.info.fileId!;
    final d = await VersionSource(env.drive).load(noteId, fileId);
    final r = versionListRule({
      'now': '2026-10-18T09:00:00.000Z',
      'noteId': noteId,
      'headRevisionId': d.headRevisionId,
      'revisions': [
        for (final v in d.revisions)
          {
            'id': v.id,
            'modifiedTime': v.modifiedTime,
            'keepForever': v.keepForever,
          },
      ],
      'sidecars': [
        for (final f in d.sidecars) {'appProperties': f.appProperties},
      ],
    });
    return (r['entries'] as List).cast<Map<String, Object?>>().firstWhere(pick);
  }

  Future<RestoreFailure?> restore(Map<String, Object?> entry) async {
    final cur = (await env.store.read(noteId))!.note!;
    return restorer.restore(
      noteId: noteId,
      fileId: env.info.fileId!,
      entry: entry,
      live: () => cur,
      apply: host,
    );
  }

  Future<Note> working() async => (await env.store.read(noteId))!.note!;

  Map<String, dynamic> pageOf(Note n) => n.pages.first;

  /// A sidecar of [pageId] on Drive, as the upload makes it.
  FakeItem sidecar(
    Note n, {
    String? rev,
    String? resolved = '2026-10-17T01:00:00.000Z',
    int index = 0,
    String? pid,
    Map<String, dynamic>? page,
  }) {
    final p = page ?? n.pages.first;
    final pageId0 = pid ?? p['id'] as String;
    final folder =
        env.drive.byKkeujeokId('cf:$noteId') ??
        env.drive.seed(name: noteId, kkeujeokId: 'cf:$noteId');
    final id = 'sc:$noteId:$pageId0:${rev ?? p['rev']}';
    final f = env.drive.seed(
      name: '$pageId0.json',
      kkeujeokId: id,
      parents: [folder.id],
    );
    f.appProperties.addAll({
      'kkjEdited': '${p['editedAt']}',
      'kkjIndex': '$index',
      'kkjResolved': ?resolved,
    });
    env.drive.foreignRevision(
      f,
      utf8.encode(
        jsonEncode({
          'noteId': noteId,
          'pageId': pageId0,
          'rev': rev ?? p['rev'],
          'seq': p['seq'],
          'editedAt': p['editedAt'],
          'editedBy': p['editedBy'],
          'kind': 'bothEdited',
          'page': p,
        }),
      ),
    );
    return f;
  }

  group('restore a revision', () {
    test('uploads and verifies, pins that revision, then applies, in this '
        'order; the restored note is a new unsent edit', () async {
      await twoRevisions();
      await env.save(makeNote(rev: 3)); // unsent edit
      final r1 = env.note.revisions.first.id;
      final e = await entryOf((e) => e['revisionId'] == r1);
      expect(e['restorable'], isTrue);

      expect(await restore(e), isNull);

      final iUpload = order.indexOf('upload');
      final iPin = order.indexOf('pin');
      expect(iUpload, isNonNegative);
      expect(iPin, greaterThan(iUpload));
      expect(order.indexOf('apply'), greaterThan(iPin));
      // The pinned revision holds the unsent edit (rev 3), not R1/R2.
      final pinned = env.note.revisions.where((r) => r.keepForever).single;
      expect(pinned.id, env.note.headRevisionId);
      expect(noteOf(pinned.bytes)!.pages.first['rev'], endsWith('53'));
      expect(env.note.revisions.first.keepForever, isFalse);

      final n = await working();
      final p = pageOf(n);
      expect(p['rev'], isNot(makeNote(rev: 3).pages.first['rev']));
      expect(p['rev'], isNot(makeNote(rev: 1).pages.first['rev']));
      expect(p['seq'], greaterThan(1)); // above every seq known
      expect(p['lineage'], contains(makeNote(rev: 3).pages.first['rev']));
      expect(n.title, 'a'); // meta stays
      expect((await env.store.readSync(noteId)).hasUnsent, isTrue);
    });

    Future<RestoreFailure?> lagging({required bool catchUp}) async {
      await twoRevisions();
      final r1 = env.note.revisions.first.id;
      final e = await entryOf((e) => e['revisionId'] == r1);
      late FakeRevision hidden;
      var n = 0;
      env.drive.before = (c) {
        if (!c.startsWith('revisions')) return;
        n++;
        if (n == 1) hidden = env.note.revisions.removeLast();
        if (n == 2 && catchUp) env.note.revisions.add(hidden);
      };
      return restore(e);
    }

    test('the listing lags behind the head once: the pin asks again', () async {
      expect(await lagging(catchUp: true), isNull);
      expect(env.note.revisions.where((r) => r.keepForever), hasLength(1));
    });

    test('the listing never shows the head: notPinned', () async {
      expect(await lagging(catchUp: false), RestoreFailure.notPinned);
    });

    test('nothing unsent: only the head is confirmed, no upload', () async {
      await twoRevisions();
      final r1 = env.note.revisions.first.id;
      final head = env.note.headRevisionId;
      final e = await entryOf((e) => e['revisionId'] == r1);
      expect(await restore(e), isNull);
      expect(order, isNot(contains('upload')));
      expect(order, contains('pin'));
      expect(env.note.revisions.where((r) => r.keepForever).single.id, head);
    });

    test('an open conflict is resolved by a whole-note restore', () async {
      await twoRevisions();
      await env.store.updateSync(
        noteId,
        (c) => c.copyWith(
          state: SyncState.conflict,
          conflicts: [
            {
              'pageId': pageId,
              'kind': 'bothEdited',
              'rev': 'x1',
              'theirsRev': 'x2',
              'detectedAt': '2026-10-17T00:00:00.000Z',
              'originalIndex': 0,
              'resolvedAt': null,
            },
          ],
        ),
      );
      final e = await entryOf(
        (e) => e['revisionId'] == env.note.revisions.first.id,
      );
      expect(await restore(e), isNull);
      final i = env.info;
      expect(i.unresolvedConflicts, isEmpty);
      expect(i.conflicts.single['resolvedAt'], '2026-10-18T09:00:00.000Z');
      expect(i.state, SyncState.pending);
    });

    test('at the cap of 200 pins the oldest is released first', () async {
      await twoRevisions();
      final old = [
        for (var k = 0; k < 200; k++)
          FakeRevision(
            'P$k',
            '2026-01-01T00:${(k ~/ 60).toString().padLeft(2, '0')}:'
                '${(k % 60).toString().padLeft(2, '0')}.000Z',
            const [],
          )..keepForever = true,
      ];
      env.note.revisions.insertAll(0, old);
      final e = await entryOf((e) => e['revisionId'] == 'R1');
      env.drive.calls.clear();
      expect(await restore(e), isNull);
      final pins = env.drive.calls.where((c) => c.startsWith('pin:')).toList();
      expect(pins.first, endsWith(':P0:false'));
      expect(pins.last, endsWith(':true'));
      expect(pins, hasLength(2));
      expect(env.note.revisions.where((r) => r.keepForever), hasLength(200));
    });
  });

  group('a failing step restores nothing', () {
    Future<void> unchanged(Note before) async {
      expect(calls, 0, reason: 'the queue was not touched');
      expect(pageOf(await working())['rev'], pageOf(before)['rev']);
    }

    test('purged revision: nothing uploaded or pinned', () async {
      await twoRevisions();
      final before = await working();
      final r1 = env.note.revisions.first.id;
      final e = await entryOf((e) => e['revisionId'] == r1);
      env.drive.purgeRevision(env.note, r1);
      expect(await restore(e), RestoreFailure.unreadable);
      expect(order, isNot(contains('upload')));
      expect(order, isNot(contains('pin')));
      await unchanged(before);
    });

    test('a version that does not parse', () async {
      await twoRevisions();
      final r1 = env.note.revisions.first;
      final e = await entryOf((e) => e['revisionId'] == r1.id);
      r1.bytes
        ..clear()
        ..addAll([1, 2, 3]);
      expect(await restore(e), RestoreFailure.unreadable);
      expect(order, isNot(contains('pin')));
      expect(calls, 0);
    });

    test('a missing sidecar', () async {
      await twoRevisions();
      final s = sidecar(makeNote(rev: 1));
      final e = await entryOf((e) => e['kind'] == 'sidecar');
      s.deleted = true;
      expect(await restore(e), RestoreFailure.unreadable);
      expect(order, isNot(contains('pin')));
    });

    test('the current state cannot be uploaded: offline', () async {
      await twoRevisions();
      await env.save(makeNote(rev: 3));
      final before = await working();
      final e = await entryOf(
        (e) => e['revisionId'] == env.note.revisions.first.id,
      );
      env.online = false;
      expect(await restore(e), RestoreFailure.notSaved);
      expect(order, isNot(contains('pin')));
      await unchanged(before);
    });

    test('the upload fails: sync error, no pin', () async {
      await twoRevisions();
      await env.save(makeNote(rev: 3));
      final before = await working();
      final e = await entryOf(
        (e) => e['revisionId'] == env.note.revisions.first.id,
      );
      env.drive.failures['upload'] = [
        const DriveError('http', status: 403, reason: 'storageQuotaExceeded'),
      ];
      expect(await restore(e), RestoreFailure.notSaved);
      expect(env.info.state, SyncState.error);
      expect(order, isNot(contains('pin')));
      await unchanged(before);
    });

    test('the pin fails: sync error, note unchanged', () async {
      await twoRevisions();
      final before = await working();
      final e = await entryOf(
        (e) => e['revisionId'] == env.note.revisions.first.id,
      );
      env.drive.failures['pin'] = [
        const DriveError('http', status: 403, reason: 'storageQuotaExceeded'),
      ];
      expect(await restore(e), RestoreFailure.notPinned);
      expect(env.info.state, SyncState.error);
      expect(env.note.revisions.where((r) => r.keepForever), isEmpty);
      await unchanged(before);
    });

    test('releasing a pin at the cap fails: nothing restored', () async {
      await twoRevisions();
      final before = await working();
      env.note.revisions.insertAll(0, [
        for (var k = 0; k < 200; k++)
          FakeRevision('P$k', '2026-01-01T00:00:00.000Z', const [])
            ..keepForever = true,
      ]);
      final e = await entryOf((e) => e['revisionId'] == 'R1');
      env.drive.failures['pin'] = [const DriveError('network')];
      expect(await restore(e), RestoreFailure.notPinned);
      expect(env.note.revisions.where((r) => r.keepForever), hasLength(200));
      await unchanged(before);
    });

    test('Drive head moved by another device: not saved, no pin', () async {
      await twoRevisions();
      final before = await working();
      final e = await entryOf(
        (e) => e['revisionId'] == env.note.revisions.first.id,
      );
      env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 9)));
      expect(await restore(e), RestoreFailure.notSaved);
      expect(order, isNot(contains('pin')));
      await unchanged(before);
    });

    test('the file is in the trash: not saved, no pin', () async {
      await twoRevisions();
      final before = await working();
      final e = await entryOf(
        (e) => e['revisionId'] == env.note.revisions.first.id,
      );
      env.note.trashed = true;
      expect(await restore(e), RestoreFailure.notSaved);
      expect(order, isNot(contains('pin')));
      await unchanged(before);
    });

    test('a note in a sync error that stays: not saved', () async {
      await twoRevisions();
      final before = await working();
      final e = await entryOf(
        (e) => e['revisionId'] == env.note.revisions.first.id,
      );
      await env.store.updateSync(
        noteId,
        (c) =>
            c.copyWith(state: SyncState.error, lastError: {'class': 'deleted'}),
      );
      expect(await restore(e), RestoreFailure.notSaved);
      expect(order, isNot(contains('pin')));
      await unchanged(before);
    });

    test(
      'the editor queue cannot be flushed: nothing uploaded or pinned',
      () async {
        await twoRevisions();
        await env.save(makeNote(rev: 3));
        final before = await working();
        final e = await entryOf(
          (e) => e['revisionId'] == env.note.revisions.first.id,
        );
        coordinator.flushOpen = () async => throw StateError('disk');
        expect(await restore(e), RestoreFailure.notSaved);
        expect(order, isNot(contains('upload')));
        expect(order, isNot(contains('pin')));
        await unchanged(before);
      },
    );

    test('a pin that is already purged (404) counts as released', () async {
      await twoRevisions();
      env.note.revisions.insertAll(0, [
        for (var k = 0; k < 200; k++)
          FakeRevision('P$k', '2026-01-01T00:00:00.000Z', const [])
            ..keepForever = true,
      ]);
      final e = await entryOf((e) => e['revisionId'] == 'R1');
      env.drive.failures['pin'] = [const DriveError('http', status: 404)];
      expect(await restore(e), isNull);
      expect(env.info.state, isNot(SyncState.error));
      expect(env.note.revisions.last.keepForever, isTrue); // the head
    });

    test('the mark fails after a release: the old pin is put back', () async {
      await twoRevisions();
      final before = await working();
      env.note.revisions.insertAll(0, [
        for (var k = 0; k < 200; k++)
          FakeRevision('P$k', '2026-01-01T00:00:00.000Z', const [])
            ..keepForever = true,
      ]);
      final e = await entryOf((e) => e['revisionId'] == 'R1');
      env.drive.before = (c) {
        if (c.startsWith('pin:') && c.endsWith(':true') && !c.contains(':P')) {
          throw const DriveError('network');
        }
      };
      expect(await restore(e), RestoreFailure.notPinned);
      expect(env.note.revisions.where((r) => r.keepForever), hasLength(200));
      expect(env.note.revisions.first.keepForever, isTrue); // P0 again
      await unchanged(before);
    });

    test('the queue gives up: the pin stays, the note is unchanged', () async {
      await twoRevisions();
      final before = await working();
      final e = await entryOf(
        (e) => e['revisionId'] == env.note.revisions.first.id,
      );
      applyOk = false;
      expect(await restore(e), RestoreFailure.notApplied);
      expect(pageOf(await working())['rev'], pageOf(before)['rev']);
    });
  });

  group('restore a sidecar page', () {
    test('a page that is in the note is replaced in place', () async {
      await twoRevisions();
      sidecar(makeNote(rev: 1), rev: _id(8001));
      final e = await entryOf((e) => e['kind'] == 'sidecar');
      expect(e['restorable'], isTrue);
      expect(await restore(e), isNull);
      final p = pageOf(await working());
      expect(p['id'], pageId);
      expect(p['rev'], isNot(_id(8001))); // a fresh rev
      expect(p['seq'], greaterThan(1));
      expect((await env.store.read(noteId))!.note!.pages, hasLength(1));
      expect(env.note.revisions.where((r) => r.keepForever), hasLength(1));
    });

    test(
      'a sidecar that is only on this device is restored from the file',
      () async {
        await twoRevisions();
        final p = {...makeNote(rev: 1).pages.first, 'rev': _id(8003)};
        await env.store.writeSidecars(noteId, [
          {
            'noteId': noteId,
            'pageId': p['id'],
            'rev': p['rev'],
            'seq': 1,
            'editedAt': p['editedAt'],
            'editedBy': 'Galaxy Tab',
            'kind': 'bothEdited',
            'page': p,
          },
        ]);
        final e = {
          'kind': 'sidecar',
          'pageId': p['id'],
          'rev': p['rev'],
          'originalIndex': 0,
        };
        expect(await restore(e), isNull);
        expect(pageOf(await working())['id'], pageId);
      },
    );

    test(
      'an edit between the pin and the apply: changed, nothing restored',
      () async {
        await twoRevisions();
        final e = await entryOf(
          (e) => e['kind'] == 'revision' && e['current'] != true,
        );
        Future<bool> editing(
          LiveMerge m,
          Future<void> Function() record,
        ) async {
          await env.save(makeNote(rev: 3));
          return host(m, record);
        }

        final cur = await working();
        final failure = await restorer.restore(
          noteId: noteId,
          fileId: env.info.fileId!,
          entry: e,
          live: () => cur,
          apply: editing,
        );
        expect(failure, RestoreFailure.changed);
        expect(
          pageOf(await working())['rev'],
          makeNote(rev: 3).pages.first['rev'],
        );
      },
    );

    test('a page that is not in the note comes back at its index', () async {
      await twoRevisions();
      final gone = makeNote(rev: 1).pages.first;
      final other = {...gone, 'id': _id(55), 'rev': _id(8002)};
      sidecar(makeNote(rev: 1), pid: _id(55), page: other, index: 0);
      final e = await entryOf((e) => e['kind'] == 'sidecar');
      expect(await restore(e), isNull);
      final n = await working();
      expect(n.pages, hasLength(2));
      expect(n.pages.first['id'], _id(55));
      expect(n.pages.last['id'], pageId);
    });
  });

  group('malformed restore input is an error, not an exception', () {
    final base = makeNote().copyJson();
    final page = makeNote(rev: 2).pages.first;
    final ctx = {
      'revs': [_id(1)],
      'rev': _id(1),
      'orderRev': _id(2),
      'now': '2026-10-18T09:00:00.000Z',
      'editedBy': 'x',
      'lastSeenRemoteSeq': 0,
    };

    Map<String, dynamic> version(List<dynamic> pages) => {
      ...base,
      'pages': pages,
    };

    test('restoreNote', () {
      final noRev = {...page}..remove('rev');
      for (final (v, c) in <(Map<String, dynamic>, Map<String, dynamic>)>[
        (version([noRev]), ctx),
        (
          version([
            page,
            {...page, 'id': 'z'},
          ]),
          ctx,
        ), // revs too short
        (version([page]), {...ctx, 'revs': []}),
        (version([page]), {...ctx}..remove('revs')),
      ]) {
        expect(restoreNote(base, {'op': 'restoreNote', 'version': v}, c, []), {
          'error': 'invalidInput',
        });
      }
      expect(
        restoreNote(
          base,
          {'op': 'restoreNote', 'version': version([])},
          ctx,
          [],
        )['error'],
        isNull,
      );
    });

    test('restorePage', () {
      for (final idx in <Object?>[null, 'x', 1.5]) {
        expect(
          restorePage(
            base,
            {
              'op': 'restorePage',
              'pageId': page['id'],
              'page': page,
              'originalIndex': idx,
            },
            ctx,
            [],
          ),
          {'error': 'invalidInput'},
        );
      }
      expect(
        restorePage(
          base,
          {
            'op': 'restorePage',
            'pageId': page['id'],
            'page': {...page}..remove('rev'),
            'originalIndex': 0,
          },
          ctx,
          [],
        ),
        {'error': 'invalidInput'},
      );
    });
  });

  group('the list source', () {
    test('revisions with their pins and the sidecars of the note', () async {
      await twoRevisions();
      env.note.revisions.first.keepForever = true;
      sidecar(makeNote(rev: 1));
      final d = await VersionSource(env.drive).load(noteId, env.info.fileId!);
      expect(d.headRevisionId, env.note.headRevisionId);
      expect([for (final r in d.revisions) r.keepForever], [true, false]);
      expect(d.sidecars, hasLength(1));
      expect(
        d.sidecars.single.appProperties['kkjResolved'],
        '2026-10-17T01:00:00.000Z',
      );
    });

    test('no sidecar folder is no sidecar', () async {
      await twoRevisions();
      final d = await VersionSource(env.drive).load(noteId, env.info.fileId!);
      expect(d.sidecars, isEmpty);
    });

    test('a revision without pages is unreadable', () async {
      await twoRevisions();
      final j = makeNote().copyJson()..['pages'] = [];
      env.drive.foreignRevision(env.note, encodeKkj(Note.trusted(j)));
      final r = await VersionSource(env.drive)
          .inspectRevision(noteId, env.info.fileId!, env.note.headRevisionId!);
      expect(r.info, {'ok': false, 'reason': 'unreadable'});
    });

    test('a purged revision is purged, not an error', () async {
      await twoRevisions();
      final r1 = env.note.revisions.first.id;
      env.drive.purgeRevision(env.note, r1);
      final r = await VersionSource(env.drive)
          .inspectRevision(noteId, env.info.fileId!, r1);
      expect(r.info, {'ok': false, 'reason': 'purged'});
    });

    test('a revision gives device names and the first page', () async {
      await twoRevisions();
      final r = await VersionSource(
        env.drive,
      ).inspectRevision(noteId, env.info.fileId!, env.note.revisions.first.id);
      expect(r.ok, isTrue);
      expect((r.info['pages'] as List).single['editedBy'], 'Pixel 8');
      expect(r.page!['id'], pageId);
    });

    test('a note of a newer format is unsupportedVersion', () async {
      await twoRevisions();
      final j = makeNote().copyJson()..['formatVersion'] = 2;
      env.drive.foreignRevision(env.note, encodeKkj(Note.trusted(j)));
      final r = await VersionSource(env.drive)
          .inspectRevision(noteId, env.info.fileId!, env.note.headRevisionId!);
      expect(r.info, {'ok': false, 'reason': 'unsupportedVersion'});
    });

    test('a sidecar of other ids is unreadable', () async {
      await twoRevisions();
      final s = sidecar(makeNote(rev: 1));
      final r = await VersionSource(env.drive)
          .inspectSidecar(noteId, s.id, _id(99), 'nope');
      expect(r.info, {'ok': false, 'reason': 'unreadable'});
    });
  });
}
