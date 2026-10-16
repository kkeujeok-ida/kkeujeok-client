import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';

import 'upload_env.dart' show makeNote, noteId;

void main() {
  late Directory docs;
  late NoteStore store;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-recv-store-');
    store = NoteStore(NoteData(() async => docs));
    addTearDown(() => docs.deleteSync(recursive: true));
  });

  File file(String name) =>
      File('${docs.path}/$noteDataDirName/$noteId/$name');

  Future<void> seedSynced() async {
    final n = makeNote();
    await store.commitSync(
      n,
      n,
      const SyncInfo(
        fileId: 'F9',
        baseHeadRevisionId: 'R1',
        state: SyncState.synced,
      ),
    );
  }

  test('commitReceive replaces working, base and sync.json together', () async {
    await seedSynced();
    final before = (await store.read(noteId))!.note!;
    final remote = makeNote(rev: 2);
    final ok = await store.commitReceive(
      noteId,
      expected: before,
      working: remote,
      base: remote,
      change: (c) => c.copyWith(baseHeadRevisionId: 'R2'),
    );
    expect(ok, isTrue);
    expect((await store.read(noteId))!.note!.pages.first['rev'], remote.pages.first['rev']);
    final s = await store.readSync(noteId);
    expect(s.info.baseHeadRevisionId, 'R2');
    expect(s.info.fileId, 'F9'); // read under the lock, not replaced
    expect(s.base!.pages.first['rev'], remote.pages.first['rev']);
  });

  test('commitReceive refuses when the working copy is not the expected one '
      'and writes nothing', () async {
    await seedSynced();
    final seen = (await store.read(noteId))!.note!;
    await store.write(makeNote(rev: 3)); // an edit lands after the decision
    final bytes = file('working.kkj').readAsBytesSync();
    final remote = makeNote(rev: 2);
    var called = false;
    final ok = await store.commitReceive(
      noteId,
      expected: seen,
      working: remote,
      base: remote,
      change: (c) {
        called = true;
        return c.copyWith(baseHeadRevisionId: 'R2');
      },
    );
    expect(ok, isFalse);
    expect(called, isFalse);
    expect(file('working.kkj').readAsBytesSync(), bytes);
    expect((await store.readSync(noteId)).info.baseHeadRevisionId, 'R1');
  });

  test('commitReceive of a new note refuses when a working copy exists',
      () async {
    await seedSynced();
    final remote = makeNote(rev: 2);
    final ok = await store.commitReceive(
      noteId,
      expected: null,
      working: remote,
      base: remote,
      change: (c) => c.copyWith(baseHeadRevisionId: 'R2'),
    );
    expect(ok, isFalse);
    expect((await store.readSync(noteId)).info.baseHeadRevisionId, 'R1');
  });

  test('commitReceive of a new note writes the three files', () async {
    final remote = makeNote();
    final ok = await store.commitReceive(
      noteId,
      expected: null,
      working: remote,
      base: remote,
      change: (c) => c.copyWith(
        fileId: 'F9',
        baseHeadRevisionId: 'R1',
        state: SyncState.synced,
      ),
    );
    expect(ok, isTrue);
    expect(file('working.kkj').existsSync(), isTrue);
    expect(file('base.R1.kkj').existsSync(), isTrue);
    final s = jsonDecode(file('sync.json').readAsStringSync()) as Map;
    expect(s['state'], 'synced');
    expect(s['fileId'], 'F9');
  });

  test('commitReceive refuses a missing expected working copy', () async {
    final remote = makeNote();
    expect(
      await store.commitReceive(
        noteId,
        expected: remote,
        working: remote,
        base: remote,
        change: (c) => c.copyWith(baseHeadRevisionId: 'R1'),
      ),
      isFalse,
    );
    expect(file('working.kkj').existsSync(), isFalse);
  });

  test('storeUnreadable keeps the bytes and is never replaced', () async {
    final junk = utf8.encode('not a kkj file');
    final ok = await store.storeUnreadable(
      noteId,
      junk,
      const SyncInfo(fileId: 'F9', state: SyncState.error),
    );
    expect(ok, isTrue);
    expect(file('working.kkj').readAsBytesSync(), junk);
    expect((await store.read(noteId))!.status, ReadStatus.unreadable);
    final again = await store.storeUnreadable(
      noteId,
      utf8.encode('other'),
      const SyncInfo(),
    );
    expect(again, isFalse);
    expect(file('working.kkj').readAsBytesSync(), junk);
  });
}
