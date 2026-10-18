// Story 11.3: a Drive file renamed outside the app renames the note here
// (spec drive.remoteTitle). Content, rev and sync state stay.
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/note_chain.dart';
import 'package:kkeujeok/sync/note_receiver.dart';

import 'upload_env.dart';

void main() {
  late UploadEnv env;

  setUp(() async {
    env = await UploadEnv.create();
  });

  NoteReceiver receiver() {
    final r = NoteReceiver(
      store: env.store,
      drive: env.drive,
      device: env.device,
      log: env.log,
      merge: env.merge,
      hosts: env.hosts,
      allowed: () async => true,
      online: () async => true,
      account: () => const AuthAccount(sub: 's', email: 'e'),
      sleep: (d) async {},
      jitter: () => 0.5,
      chain: NoteChain(),
    );
    addTearDown(r.dispose);
    return r;
  }

  Future<NoteReceiver> synced() async {
    await env.save(makeNote(title: 'Math'));
    await env.uploader().upload(noteId);
    final r = receiver();
    await r.check(); // takes the token
    return r;
  }

  Future<Note> work() async => (await env.store.read(noteId))!.note!;
  Future<Note> base() async => (await env.store.readSync(noteId)).base!;
  int media() => env.drive.calls.where((c) => c.startsWith('media')).length;

  test('renamed in Drive: working and base copy take the title only', () async {
    final r = await synced();
    final before = await work();
    final info = env.info;
    final calls = env.drive.calls.length;
    env.drive.renameForeign(env.note, 'Algebra.kkj');
    await r.check();
    final w = await work(), b = await base();
    expect(w.title, 'Algebra');
    expect(b.title, 'Algebra');
    expect(w.metaRev, before.metaRev);
    expect(w.pages, before.pages);
    expect(env.info.baseHeadRevisionId, info.baseHeadRevisionId);
    expect(env.info.state, SyncState.synced);
    expect((await env.store.readSync(noteId)).hasUnsent, isFalse);
    expect(
      env.drive.calls.skip(calls).where((c) => c.startsWith('media')),
      isEmpty,
    );
    expect(env.note.name, 'Algebra.kkj'); // nothing renamed it back
  });

  test('a title renamed here and not uploaded wins', () async {
    final r = await synced();
    final json = (await work()).copyJson();
    (json['meta'] as Map)['title'] = 'Mine';
    await env.save(Note.trusted(json));
    env.drive.renameForeign(env.note, 'Theirs.kkj');
    await r.check();
    expect((await work()).title, 'Mine');
    expect((await base()).title, 'Math');
  });

  test('an invalid name is not taken', () async {
    final r = await synced();
    env.drive.renameForeign(env.note, ' padded .kkj');
    await r.check();
    expect((await work()).title, 'Math');
  });

  test('a note in error is skipped', () async {
    final r = await synced();
    await env.store.updateSync(
      noteId,
      (c) => c.copyWith(state: SyncState.error),
    );
    env.drive.renameForeign(env.note, 'Algebra.kkj');
    await r.check();
    expect((await work()).title, 'Math');
    expect(media(), 0);
  });

  test('an uploading note is skipped', () async {
    final r = await synced();
    await env.store.updateSync(
      noteId,
      (c) => c.copyWith(state: SyncState.syncing),
    );
    env.drive.renameForeign(env.note, 'Algebra.kkj');
    await r.check();
    expect((await work()).title, 'Math');
  });

  test('an open note takes the new title when it is closed', () async {
    final r = await synced();
    Future<bool> host(merge, record) async => true;
    env.hosts.register(noteId, host);
    env.drive.renameForeign(env.note, 'Algebra.kkj');
    await r.check();
    expect((await work()).title, 'Math');
    env.hosts.unregister(noteId, host);
    await r.noteClosed(noteId);
    expect((await work()).title, 'Algebra');
    expect((await base()).title, 'Algebra');
  });
}
