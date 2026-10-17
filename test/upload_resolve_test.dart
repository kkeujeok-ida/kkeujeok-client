// Story 3.21: the sync side of a resolved conflict: the `resolve` event, the
// `kkjResolved` mark on the sidecar after the verified upload, the 30-day
// cleanup at app start.
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/storage/note_store.dart' show NoteSaveException;
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/note_uploader.dart';
import 'package:kkeujeok/sync/open_note.dart';
import 'package:kkeujeok/sync/upload_coordinator.dart';

import 'fake_drive.dart';
import 'upload_env.dart';

String _canon(DateTime t) => t.toUtc().toIso8601String();

Map<String, Object?> _entry({
  String page = pageId,
  String kind = 'bothEdited',
  String rev = 'r1',
  String? resolvedAt,
}) => {
  'pageId': page,
  'kind': kind,
  'rev': rev,
  'theirsRev': 't1',
  'detectedAt': '2026-10-10T00:00:00.000Z',
  'originalIndex': 0,
  'resolvedAt': resolvedAt,
};

void main() {
  late UploadEnv env;
  late NoteUploader up;

  setUp(() async {
    env = await UploadEnv.create();
    up = env.uploader();
    await env.save(makeNote());
    await up.upload(noteId); // verified: synced, nothing unsent
    expect(env.info.state, SyncState.synced);
  });

  Future<void> setConflicts(
    List<Map<String, Object?>> conflicts, {
    SyncState? state,
  }) => env.store.updateSync(
    noteId,
    (c) => c.copyWith(conflicts: conflicts, state: state),
  );

  FakeItem sidecar({String page = pageId, String rev = 'r1', String? at}) {
    final i = env.drive.seed(
      name: '$page-$rev.json',
      kkeujeokId: 'sc:$noteId:$page:$rev',
      parents: const ['x'],
    );
    if (at != null) i.appProperties['kkjResolved'] = at;
    return i;
  }

  group('resolved', () {
    test('the entry takes resolvedAt and the state moves conflict -> pending '
        'when nothing is left', () async {
      await env.save(makeNote(rev: 2)); // the resolution changed the note
      await setConflicts([_entry()], state: SyncState.conflict);
      await up.resolved(noteId, _entry(resolvedAt: '2026-10-17T01:00:00.000Z'));
      final i = env.info;
      expect(i.conflicts.single['resolvedAt'], '2026-10-17T01:00:00.000Z');
      expect(i.unresolvedConflicts, isEmpty);
      expect(i.state, SyncState.pending);
      expect(await env.stateChanges(), contains('conflict>pending'));
    });

    test('another conflict is left: still conflict', () async {
      await env.save(makeNote(rev: 2));
      await setConflicts([
        _entry(),
        _entry(page: 'other', rev: 'r2'),
      ], state: SyncState.conflict);
      await up.resolved(noteId, _entry(resolvedAt: '2026-10-17T01:00:00.000Z'));
      expect(env.info.unresolvedConflicts, hasLength(1));
      expect(env.info.state, SyncState.conflict);
      expect(await env.stateChanges(), isNot(contains('conflict>pending')));
    });

    test('a resolve that leaves the note as Drive has it is saved, not '
        'pending', () async {
      await setConflicts([_entry()], state: SyncState.conflict);
      await up.resolved(noteId, _entry(resolvedAt: '2026-10-17T01:00:00.000Z'));
      expect(env.info.state, SyncState.synced);
      expect(
        await env.stateChanges(),
        containsAllInOrder(['conflict>pending', 'pending>synced']),
      );
    });

    test('an entry that is not there is an error, nothing changes', () async {
      await setConflicts([_entry()], state: SyncState.conflict);
      await expectLater(
        up.resolved(noteId, _entry(page: 'nope', resolvedAt: 'x')),
        throwsA(isA<NoteSaveException>()),
      );
      expect(env.info.unresolvedConflicts, hasLength(1));
      expect(env.info.state, SyncState.conflict);
    });

    test('no note content in what is logged', () async {
      await setConflicts([_entry()], state: SyncState.conflict);
      await up.resolved(noteId, _entry(resolvedAt: '2026-10-17T01:00:00.000Z'));
      for (final e in await env.events()) {
        expect(e.keys, isNot(contains('pageId')));
      }
    });
  });

  group('kkjResolved on the sidecar', () {
    const at = '2026-10-17T01:00:00.000Z';

    test('set by a metadata-only update once the upload is verified', () async {
      final sc = sidecar();
      await setConflicts([_entry(resolvedAt: at)]);
      env.drive.calls.clear();
      await up.markResolved(noteId);
      expect(sc.appProperties['kkjResolved'], at);
      expect(sc.appProperties['kkeujeokId'], 'sc:$noteId:$pageId:r1');
      expect(env.drive.calls, contains('update:${sc.id}:props'));
      expect(env.drive.uploads, hasLength(1)); // no content upload
      expect(env.info.conflicts.single['sidecarMarked'], isTrue);
      // Once is enough.
      env.drive.calls.clear();
      await up.markResolved(noteId);
      expect(env.drive.calls, isEmpty);
    });

    test(
      'not before the upload is verified (the note has unsent changes)',
      () async {
        final sc = sidecar();
        await setConflicts([_entry(resolvedAt: at)]);
        await env.save(makeNote(rev: 2));
        env.drive.calls.clear();
        await up.markResolved(noteId);
        expect(sc.appProperties.containsKey('kkjResolved'), isFalse);
        expect(env.drive.calls, isEmpty);
        // The upload runs, then the mark.
        await up.upload(noteId);
        await up.markResolved(noteId);
        expect(sc.appProperties['kkjResolved'], at);
      },
    );

    test('an unresolved conflict is not marked', () async {
      final sc = sidecar();
      await setConflicts([_entry()]);
      env.drive.calls.clear();
      await up.markResolved(noteId);
      expect(sc.appProperties.containsKey('kkjResolved'), isFalse);
      expect(env.drive.calls, isEmpty);
    });

    test('a failure is logged and retried at the next call', () async {
      final sc = sidecar();
      await setConflicts([_entry(resolvedAt: at)]);
      env.drive.failures['update'] = [const DriveError('http', status: 400)];
      await up.markResolved(noteId); // never throws
      expect(sc.appProperties.containsKey('kkjResolved'), isFalse);
      expect(env.info.conflicts.single['sidecarMarked'], isNull);
      expect(await env.eventNames(), contains('error'));
      await up.markResolved(noteId);
      expect(sc.appProperties['kkjResolved'], at);
      expect(env.info.conflicts.single['sidecarMarked'], isTrue);
    });

    test('no sidecar on Drive: the flag stays unset, checked again', () async {
      await setConflicts([_entry(resolvedAt: at)]);
      await up.markResolved(noteId);
      expect(env.info.conflicts.single['sidecarMarked'], isNull);
      final sc = sidecar(); // it shows up later
      await up.markResolved(noteId);
      expect(sc.appProperties['kkjResolved'], at);
      expect(env.info.conflicts.single['sidecarMarked'], isTrue);
    });

    test('one conflict failing does not stop the next', () async {
      final a = sidecar(rev: 'r1');
      final b = sidecar(rev: 'r2');
      await setConflicts([
        _entry(rev: 'r1', resolvedAt: at),
        _entry(rev: 'r2', resolvedAt: at),
      ]);
      env.drive.failures['update'] = [const DriveError('http', status: 400)];
      await up.markResolved(noteId);
      expect(a.appProperties.containsKey('kkjResolved'), isFalse);
      expect(b.appProperties['kkjResolved'], at);
      expect(env.info.conflicts[0]['sidecarMarked'], isNull);
      expect(env.info.conflicts[1]['sidecarMarked'], isTrue);
    });

    test('offline or gate closed: nothing, nothing lost', () async {
      final sc = sidecar();
      await setConflicts([_entry(resolvedAt: at)]);
      env.online = false;
      await up.markResolved(noteId);
      env.online = true;
      env.allowed = false;
      await up.markResolved(noteId);
      expect(sc.appProperties.containsKey('kkjResolved'), isFalse);
      env.allowed = true;
      await up.markResolved(noteId);
      expect(sc.appProperties['kkjResolved'], at);
    });

    test('a sidecar still unsent is created with kkjResolved', () async {
      await env.store.writeSidecars(noteId, [
        {
          'noteId': noteId,
          'pageId': pageId,
          'rev': 'r1',
          'seq': 1,
          'editedAt': '2026-10-10T00:00:00.000Z',
          'editedBy': 'Pixel 8',
          'kind': 'bothEdited',
          'page': {'id': pageId},
        },
      ]);
      await env.store.updateSync(
        noteId,
        (c) => c.copyWith(
          conflicts: [_entry(resolvedAt: at)],
          unsentSidecars: [
            {'pageId': pageId, 'rev': 'r1'},
          ],
        ),
      );
      await up.upload(noteId);
      final sc = env.drive.byKkeujeokId('sc:$noteId:$pageId:r1')!;
      expect(sc.appProperties['kkjResolved'], at);
      env.drive.calls.clear();
      await up.markResolved(noteId);
      expect(env.drive.calls.where((c) => c.startsWith('update')), isEmpty);
      expect(env.info.conflicts.single['sidecarMarked'], isTrue);
    });
  });

  group('cleanup at app start', () {
    late UploadCoordinator coordinator;

    setUp(() {
      coordinator = UploadCoordinator(
        store: env.store,
        uploader: env.uploader(),
        openNote: OpenNote(env.data.rootDir),
        lease: UploadLease(env.data, DateTime.now),
        log: env.log,
        allowed: () async => env.allowed,
        online: () async => env.online,
        schedule: () async {},
      );
    });

    test('sidecars resolved more than 30 days ago go to the trash; younger '
        'ones stay', () async {
      final old = DateTime.now().subtract(const Duration(days: 31));
      final young = DateTime.now().subtract(const Duration(days: 29));
      final a = sidecar(rev: 'old', at: _canon(old));
      final b = sidecar(rev: 'young', at: _canon(young));
      final c = sidecar(rev: 'open');
      await setConflicts([
        _entry(rev: 'old', resolvedAt: _canon(old)),
        _entry(rev: 'young', resolvedAt: _canon(young)),
        _entry(rev: 'open'),
      ]);
      await coordinator.appStarted();
      expect(a.trashed, isTrue);
      expect(b.trashed, isFalse);
      expect(c.trashed, isFalse);
      expect(env.info.conflicts[0]['sidecarTrashed'], isTrue);
      expect(env.info.conflicts[1]['sidecarTrashed'], isNull);
      // Not hard-deleted, and not asked again.
      expect(a.deleted, isFalse);
      env.drive.calls.clear();
      await coordinator.appStarted();
      expect(env.drive.calls.where((c) => c.startsWith('update')), isEmpty);
    });

    test('a failure is ignored and the next start tries again', () async {
      final old = DateTime.now().subtract(const Duration(days: 40));
      final a = sidecar(rev: 'old', at: _canon(old));
      await setConflicts([_entry(rev: 'old', resolvedAt: _canon(old))]);
      env.drive.failures['update'] = [const DriveError('http', status: 400)];
      await coordinator.appStarted(); // does not throw
      expect(a.trashed, isFalse);
      await coordinator.appStarted();
      expect(a.trashed, isTrue);
    });

    test(
      'an old sidecar that was never marked is marked, then trashed',
      () async {
        final old = DateTime.now().subtract(const Duration(days: 40));
        final a = sidecar(rev: 'old');
        await setConflicts([_entry(rev: 'old', resolvedAt: _canon(old))]);
        await coordinator.appStarted();
        expect(a.appProperties['kkjResolved'], _canon(old));
        expect(a.trashed, isTrue);
      },
    );

    test('a start with no resolved conflict makes no request', () async {
      env.drive.calls.clear();
      await coordinator.appStarted();
      expect(env.drive.calls, isEmpty);
    });
  });

  test(
    'the next upload marks a resolved sidecar after the note went up',
    () async {
      const at = '2026-10-17T01:00:00.000Z';
      final sc = sidecar();
      await setConflicts([_entry(resolvedAt: at)]);
      await env.save(makeNote(rev: 2));
      final coordinator = UploadCoordinator(
        store: env.store,
        uploader: env.uploader(),
        openNote: OpenNote(env.data.rootDir),
        lease: UploadLease(env.data, DateTime.now),
        log: env.log,
        allowed: () async => env.allowed,
        online: () async => env.online,
        schedule: () async {},
      );
      await coordinator.syncNow(noteId);
      expect(env.drive.uploads, hasLength(2));
      expect(sc.appProperties['kkjResolved'], at);
    },
  );
}
