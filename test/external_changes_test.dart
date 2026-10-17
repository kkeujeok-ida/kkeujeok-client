import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/merge_step.dart';
import 'package:kkeujeok/sync/note_chain.dart';
import 'package:kkeujeok/sync/note_receiver.dart';
import 'package:kkeujeok/sync/note_uploader.dart';

import 'upload_env.dart';

/// Story 3.17: the Drive file of a note is trashed, deleted, renamed, moved,
/// broken or of a newer format.
void main() {
  late UploadEnv env;
  late NoteChain chain;
  late AuthAccount? acct;
  late List<String> uploaded;
  late Future<void> Function()? flush;

  setUp(() async {
    env = await UploadEnv.create();
    chain = NoteChain();
    acct = const AuthAccount(sub: 's', email: 'e');
    uploaded = [];
    flush = null;
  });

  NoteReceiver receiver() {
    final r = NoteReceiver(
      store: env.store,
      drive: env.drive,
      device: env.device,
      log: env.log,
      merge: env.merge,
      hosts: env.hosts,
      allowed: () async => env.allowed,
      online: () async => env.online,
      account: () => acct,
      sleep: (d) async => env.sleeps.add(d),
      jitter: () => 0.5,
      chain: chain,
      flushOpen: () async => await flush?.call(),
      uploadNote: (id) async => uploaded.add(id),
    );
    addTearDown(r.dispose);
    return r;
  }

  /// A synced local note that Drive has too, and a receiver that already
  /// holds the page token.
  Future<NoteReceiver> synced() async {
    await env.save(makeNote());
    await env.uploader().upload(noteId);
    expect(env.info.state, SyncState.synced);
    final r = receiver();
    await r.check();
    return r;
  }

  Future<bool> host(LiveMerge m, Future<void> Function() r) async => true;
  void openEditor() => env.hosts.register(noteId, host);
  void closeEditor() => env.hosts.unregister(noteId, host);

  int mediaCalls() =>
      env.drive.calls.where((c) => c.startsWith('media')).length;
  bool untrashed() => env.drive.calls.any((c) => c.endsWith(':untrash'));

  group('deleted, nothing unsent', () {
    test(
      'trashed: the copy goes, the library reloads, Drive is not written',
      () async {
        final r = await synced();
        final v = r.state.value.version;
        final uploads = env.drive.uploads.length;
        env.drive.trashForeign(env.note);
        await r.check();
        expect(env.noteDir.existsSync(), isFalse);
        expect(r.state.value.version, greaterThan(v));
        expect(r.state.value.revived, 0);
        expect(env.drive.uploads.length, uploads);
        expect(untrashed(), isFalse);
        expect(env.note.trashed, isTrue);
        final err = (await env.events()).where((e) => e['event'] == 'error');
        expect(err.single['class'], 'deleted');
        expect(err.single['reason'], 'trashed');
      },
    );

    test('deleted for good: the same', () async {
      final r = await synced();
      env.drive.removeForeign(env.note);
      await r.check();
      expect(env.noteDir.existsSync(), isFalse);
      final err = (await env.events()).where((e) => e['event'] == 'error');
      expect(err.single['reason'], 'removed');
    });

    test('a file that is not the note\'s own file is ignored', () async {
      final r = await synced();
      // A duplicate file of the same note, as the cleanup of duplicates
      // trashes.
      final dup = env.drive.foreignNote(makeNote(), parent: env.root.id);
      await r.check();
      env.drive.trashForeign(dup);
      await r.check();
      expect(env.working.existsSync(), isTrue);
      expect(env.info.fileId, env.note.id);
    });

    test('removeNote refuses when the working copy moved on', () async {
      await env.save(makeNote());
      final old = (await env.store.read(noteId))!.note!;
      await env.save(makeNote(rev: 3));
      expect(await env.store.removeNote(noteId, expected: old), isFalse);
      expect(env.working.existsSync(), isTrue);
      expect(
        await env.store.removeNote(noteId, expected: makeNote(rev: 3)),
        isTrue,
      );
      expect(env.noteDir.existsSync(), isFalse);
    });
  });

  group('deleted, unsent changes', () {
    test('trashed: untrashed, same file, snackbar count, uploaded', () async {
      final r = await synced();
      final fileId = env.note.id;
      await env.save(makeNote(rev: 5));
      env.drive.trashForeign(env.note);
      await r.check();
      expect(untrashed(), isTrue);
      expect(env.note.trashed, isFalse);
      expect(env.info.fileId, fileId);
      expect(env.info.state, SyncState.pending);
      expect(env.info.lastError, isNull);
      expect(r.state.value.revived, 1);
      expect(uploaded, [noteId]);
      expect(await env.stateChanges(), isNot(contains('synced>error')));
    });

    test('deleted for good: a new file with the same noteId', () async {
      final r = await synced();
      final old = env.note.id;
      await env.save(makeNote(rev: 5));
      env.drive.removeForeign(env.note);
      await r.check();
      expect(env.info.fileId, isNull);
      expect(env.info.baseHeadRevisionId, isNull);
      expect(env.info.state, SyncState.pending);
      expect(r.state.value.revived, 1);
      expect(uploaded, [noteId]);
      expect(await env.uploader().upload(noteId), UploadOutcome.uploaded);
      expect(env.note.id, isNot(old));
      expect(env.info.fileId, env.note.id);
      expect(env.info.state, SyncState.synced);
    });

    test(
      'an untrash answered 404 turns into the deleted-for-good path',
      () async {
        final r = await synced();
        await env.save(makeNote(rev: 5));
        env.drive.trashForeign(env.note);
        env.drive.failures['update'] = [const DriveError('http', status: 404)];
        await r.check();
        expect(env.info.fileId, isNull);
        expect(r.state.value.revived, 1);
      },
    );

    test('an unresolved conflict counts as unsent', () async {
      final r = await synced();
      await env.store.updateSync(
        noteId,
        (c) => c.copyWith(
          state: SyncState.conflict,
          conflicts: [
            {'pageId': pageId, 'rev': 'r1', 'resolvedAt': null},
          ],
        ),
      );
      env.drive.trashForeign(env.note);
      await r.check();
      expect(env.working.existsSync(), isTrue);
      expect(r.state.value.revived, 1);
    });

    test(
      'a failed account re-check after the Drive call stops the run',
      () async {
        final r = await synced();
        await env.save(makeNote(rev: 5));
        env.drive.trashForeign(env.note);
        env.drive.after = (c) {
          if (c.endsWith(':untrash')) {
            acct = const AuthAccount(sub: 'x', email: 'y');
          }
        };
        await r.check();
        expect(r.state.value.revived, 0);
        expect(uploaded, isEmpty);
      },
    );

    test('a transient failure keeps the note and the token', () async {
      final r = await synced();
      final token = (await env.device.read()).pageToken;
      await env.save(makeNote(rev: 5));
      env.drive.trashForeign(env.note);
      env.drive.failures['update'] = [
        for (var i = 0; i < 7; i++) const DriveError('network'),
      ];
      await r.check();
      expect(env.working.existsSync(), isTrue);
      expect((await env.device.read()).pageToken, token);
      expect(r.state.value.revived, 0);
      await r.check(); // the change comes again
      expect(r.state.value.revived, 1);
    });
  });

  group('deleted, open', () {
    test('nothing unsent: the banner state, the copy stays', () async {
      final r = await synced();
      openEditor();
      env.drive.trashForeign(env.note);
      await r.check();
      expect(env.working.existsSync(), isTrue);
      expect(env.info.state, SyncState.error);
      expect(env.info.lastError?['class'], 'deleted');
      expect(env.info.lastError?['reason'], 'trashed');
      expect(r.state.value.revived, 0);
      // The same change again logs nothing new.
      final n = (await env.events()).where((e) => e['event'] == 'error').length;
      await r.check();
      expect(
        (await env.events()).where((e) => e['event'] == 'error').length,
        n,
      );
    });

    test(
      'edits still in the editor queue are flushed first and restore it',
      () async {
        final r = await synced();
        openEditor();
        flush = () async => env.save(makeNote(rev: 7));
        env.drive.trashForeign(env.note);
        await r.check();
        expect(untrashed(), isTrue);
        expect(r.state.value.revived, 1);
        expect(env.info.lastError, isNull);
        expect(uploaded, isEmpty); // an open note is not uploaded yet
      },
    );

    test('[다시 살리기] untrashes and the note is whole again', () async {
      final r = await synced();
      openEditor();
      env.drive.trashForeign(env.note);
      await r.check();
      await r.revive(noteId);
      expect(untrashed(), isTrue);
      expect(env.info.lastError, isNull);
      expect(env.info.state, SyncState.synced);
      expect(r.state.value.revived, 0); // no snackbar for the button
    });

    test('[다시 살리기] of a permanently deleted note creates it again', () async {
      final r = await synced();
      openEditor();
      env.drive.removeForeign(env.note);
      await r.check();
      await r.revive(noteId);
      expect(env.info.fileId, isNull);
      expect(env.info.state, SyncState.pending);
      expect(await env.uploader().upload(noteId), UploadOutcome.uploaded);
      expect(env.info.state, SyncState.synced);
    });

    test(
      'the editor is gone with nothing unsent: the copy is removed',
      () async {
        final r = await synced();
        openEditor();
        env.drive.trashForeign(env.note);
        await r.check();
        closeEditor();
        await r.noteClosed(noteId);
        expect(env.noteDir.existsSync(), isFalse);
      },
    );

    test(
      'typed after the banner: leaving restores instead of removing',
      () async {
        final r = await synced();
        openEditor();
        env.drive.trashForeign(env.note);
        await r.check();
        await env.save(makeNote(rev: 8));
        closeEditor();
        await r.noteClosed(noteId);
        expect(env.working.existsSync(), isTrue);
        expect(untrashed(), isTrue);
        expect(r.state.value.revived, 1);
        expect(uploaded, [noteId]);
      },
    );

    test('a note not marked deleted is left alone by noteClosed', () async {
      final r = await synced();
      await r.noteClosed(noteId);
      expect(env.working.existsSync(), isTrue);
    });

    test('opening it asks Drive: trashed and 404 are both seen', () async {
      final r = await synced();
      openEditor();
      env.drive.trashForeign(env.note);
      await r.noteOpened(noteId);
      expect(env.info.lastError?['reason'], 'trashed');
      env.drive.trashForeign(env.note, trashed: false);
      await r.noteOpened(noteId); // live again: the banner state ends
      expect(env.info.lastError, isNull);
      env.drive.removeForeign(env.note);
      await r.noteOpened(noteId);
      expect(env.info.lastError?['reason'], 'removed');
    });

    test('a restored file ends the deleted state at the next check', () async {
      final r = await synced();
      openEditor();
      env.drive.trashForeign(env.note);
      await r.check();
      env.drive.trashForeign(env.note, trashed: false);
      await r.check();
      expect(env.info.lastError, isNull);
      expect(env.info.state, SyncState.synced);
    });

    test('a restored file with a new head is received', () async {
      final r = await synced();
      env.hosts.register(noteId, (merge, record) async {
        final out = merge((await env.store.read(noteId))!.note!);
        await record();
        if (out != null) await env.store.write(out.note);
        return true;
      });
      env.drive.trashForeign(env.note);
      await r.check();
      env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 2)));
      env.drive.trashForeign(env.note, trashed: false);
      await r.check();
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
      expect(env.info.lastError, isNull);
      expect(env.info.state, isNot(SyncState.error));
    });

    test('a marked note nobody closed is decided by the next check', () async {
      final r = await synced();
      openEditor();
      env.drive.trashForeign(env.note);
      await r.check();
      closeEditor();
      await r.check();
      expect(env.noteDir.existsSync(), isFalse);
    });
  });

  group('rescan and start', () {
    test('a local file the listing does not show is looked up', () async {
      final r = await synced();
      final fileId = env.note.id;
      env.drive.removeForeign(env.note);
      env.drive.rejectChanges = 1;
      env.drive.calls.clear();
      await r.check();
      expect(env.drive.calls, contains('get:$fileId'));
      expect(env.noteDir.existsSync(), isFalse);
    });

    test(
      'a file moved out of the folder is still live: nothing happens',
      () async {
        final r = await synced();
        env.drive.moveForeign(env.note, 'elsewhere');
        env.drive.rejectChanges = 1;
        await r.check();
        expect(env.working.existsSync(), isTrue);
        expect(env.info.state, SyncState.synced);
        expect(env.info.fileId, env.note.id);
        // The next upload does not bring it back.
        await env.save(makeNote(rev: 4));
        expect(await env.uploader().upload(noteId), UploadOutcome.uploaded);
        expect(env.note.parents, ['elsewhere']);
      },
    );
  });

  group('rename and move', () {
    test('the head did not change: nothing is downloaded or written', () async {
      final r = await synced();
      final bytes = env.working.readAsBytesSync();
      final sync = env.syncFile.readAsStringSync();
      final media = mediaCalls();
      env.drive.renameForeign(env.note, 'Renamed in Drive.kkj');
      env.drive.moveForeign(env.note, 'elsewhere');
      await r.check();
      expect(mediaCalls(), media);
      expect(env.working.readAsBytesSync(), bytes);
      expect(env.syncFile.readAsStringSync(), sync);
      expect((await env.store.read(noteId))!.note!.title, 'a');
    });

    test('an upload sends the name back from the title', () async {
      final r = await synced();
      final name = env.note.name;
      env.drive.renameForeign(env.note, 'Renamed in Drive.kkj');
      await r.check();
      await env.save(makeNote(rev: 4));
      expect(await env.uploader().upload(noteId), UploadOutcome.uploaded);
      expect(env.note.name, name);
    });
  });

  group('unreadable remote', () {
    final junk = utf8.encode('junk');

    test('the note ends error with the head; copy and Drive stay; fixed in '
        'Drive it is received again', () async {
      final r = await synced();
      final bytes = env.working.readAsBytesSync();
      env.drive.foreignRevision(env.note, junk);
      final head = env.note.headRevisionId;
      final uploads = env.drive.uploads.length;
      await r.check();
      expect(env.info.state, SyncState.error);
      expect(env.info.lastError?['class'], 'unreadable');
      expect(env.info.lastError?['reason'], 'parse');
      expect(env.info.lastError?['head'], head);
      expect(env.working.readAsBytesSync(), bytes);
      expect(env.drive.uploads.length, uploads);
      expect(await env.uploader().upload(noteId), UploadOutcome.skipped);
      // The same head again: not downloaded again.
      final media = mediaCalls();
      env.drive.renameForeign(env.note, 'x.kkj');
      await r.check();
      expect(mediaCalls(), media);
      // Fixed in Drive: another head.
      env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 2)));
      await r.check();
      expect(env.info.state, SyncState.synced);
      expect(env.info.lastError, isNull);
      expect(env.info.baseHeadRevisionId, env.note.headRevisionId);
    });

    test('a newer format is kept and never uploaded', () async {
      final r = await synced();
      final json = makeNote(rev: 2).copyJson()..['formatVersion'] = 99;
      env.drive.foreignRevision(env.note, encodeKkj(Note.trusted(json)));
      final uploads = env.drive.uploads.length;
      await r.check();
      expect(env.info.state, SyncState.error);
      expect(env.info.lastError?['reason'], 'unsupportedVersion');
      expect(env.info.lastError?['head'], env.note.headRevisionId);
      expect(
        (await env.store.read(noteId))!.note!.pages.first['rev'],
        makeNote().pages.first['rev'],
      );
      expect(env.drive.uploads.length, uploads);
    });

    test('a remote-only broken file keeps its head in the raw copy', () async {
      env.drive.foreignNote(makeNote(), parent: env.root.id, bytes: junk);
      await receiver().check();
      expect(env.working.readAsBytesSync(), junk);
      expect(env.info.lastError?['head'], env.note.headRevisionId);
    });
  });
}
