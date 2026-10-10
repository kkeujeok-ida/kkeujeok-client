import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';

const id = '01926f3a-0000-7000-8000-000000000900';

Note _note({String title = 'a', Map<String, dynamic>? extra}) {
  final r = createNote(
    title: title,
    existingTitles: [],
    background: 'plain',
    orientation: 'portrait',
    noteId: id,
    pageId: '01926f3a-0000-7000-8000-000000000001',
    pageRev: '01926f3a-0000-7000-8000-000000000051',
    metaRev: '01926f3a-0000-7000-8000-000000000901',
    orderRev: '01926f3a-0000-7000-8000-000000000902',
    now: '2026-10-10T04:20:00.000Z',
    editedBy: 'Pixel 8',
  );
  if (extra == null) return r.note!;
  return Note.parse({...r.note!.copyJson(), ...extra}).note!;
}

void main() {
  late Directory docs;
  late NoteData data;
  late NoteStore store;
  late Directory dir;
  late File working, tmp;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-store-');
    data = NoteData(() async => docs);
    store = NoteStore(data);
    dir = Directory('${docs.path}/$noteDataDirName/$id');
    working = File('${dir.path}/working.kkj');
    tmp = File('${dir.path}/working.kkj.tmp');
    addTearDown(() => docs.deleteSync(recursive: true));
  });

  test('write then read, only working.kkj is left', () async {
    final n = _note();
    await store.write(n);
    final r = (await store.read(id))!;
    expect(r.status, ReadStatus.ok);
    expect(r.note!.copyJson(), equals(n.copyJson()));
    expect(dir.listSync().map((e) => e.uri.pathSegments.last).toList(), [
      'working.kkj',
    ]);
    // gzip JSON
    expect(gzip.decode(working.readAsBytesSync()), isNotEmpty);
  });

  test('unknown fields survive write and read', () async {
    final n = _note(
      extra: {
        'future': {'a': 1.234},
      },
    );
    await store.write(n);
    expect(
      (await store.read(id))!.note!.copyJson()['future'],
      equals({'a': 1.234}),
    );
  });

  test('interrupted write: leftover tmp is dropped, previous kept', () async {
    final n = _note();
    await store.write(n);
    tmp.writeAsBytesSync([1, 2, 3]);
    final r = (await store.read(id))!;
    expect(r.note!.title, 'a');
    expect(tmp.existsSync(), isFalse);
  });

  test('interrupted first write: no note, tmp cleaned', () async {
    dir.createSync(recursive: true);
    tmp.writeAsBytesSync([1, 2, 3]);
    expect(await store.list(), isEmpty);
    expect(await store.read(id), isNull);
    expect(tmp.existsSync(), isFalse);
  });

  test('write failure throws and keeps the old file', () async {
    await store.write(_note());
    final before = working.readAsBytesSync();
    final failing = NoteStore(
      data,
      writeFile: (f, b) async {
        f.writeAsBytesSync([9]); // half-written temp
        throw const FileSystemException('No space left on device');
      },
    );
    await expectLater(
      failing.write(_note(title: 'b')),
      throwsA(isA<NoteSaveException>()),
    );
    expect(working.readAsBytesSync(), before);
    expect(tmp.existsSync(), isFalse);
  });

  group('files this client cannot read are never rewritten', () {
    for (final (name, bytes) in <(String, List<int>)>[
      ('broken gzip', [1, 2, 3, 4]),
      (
        'newer version',
        gzip.encode(utf8.encode(jsonEncode({'formatVersion': 2, 'x': 1}))),
      ),
    ]) {
      test(name, () async {
        dir.createSync(recursive: true);
        working.writeAsBytesSync(bytes);
        final r = (await store.read(id))!;
        expect(r.writable, isFalse);
        expect(
          r.status,
          name == 'broken gzip'
              ? ReadStatus.unreadable
              : ReadStatus.unsupportedVersion,
        );
        final listed = await store.list();
        expect(listed.single.noteId, id);
        expect(listed.single.result.status, r.status);
        await expectLater(
          store.write(_note()),
          throwsA(isA<NoteSaveException>()),
        );
        expect(working.readAsBytesSync(), bytes);
        expect(tmp.existsSync(), isFalse);
      });
    }
  });

  test('list uses the folder name, not the noteId inside the file', () async {
    await store.write(_note());
    final other = '01926f3a-0000-7000-8000-000000000999';
    Directory('${docs.path}/$noteDataDirName/$other').createSync();
    working.copySync('${docs.path}/$noteDataDirName/$other/working.kkj');
    final ids = (await store.list()).map((e) => e.noteId).toSet();
    expect(ids, {id, other});
  });

  test('a non-UUID note id is rejected', () {
    expect(() => store.read('../x'), throwsArgumentError);
  });

  test('NoteData.clear removes the note folders', () async {
    await store.write(_note());
    await data.clear();
    expect(dir.existsSync(), isFalse);
    expect(await store.list(), isEmpty);
  });

  test('list skips a non-UUID folder next to a valid note', () async {
    await store.write(_note());
    Directory('${docs.path}/$noteDataDirName/not-a-note').createSync();
    final listed = await store.list();
    expect(listed.map((e) => e.noteId), [id]);
  });

  test('concurrent writes and list never lose the file', () async {
    await store.write(_note());
    final results = await Future.wait([
      for (var i = 0; i < 5; i++) store.write(_note(title: 't$i')),
      for (var i = 0; i < 5; i++) store.list(),
      for (var i = 0; i < 5; i++) store.read(id),
    ]);
    expect(results, isNotEmpty);
    expect((await store.read(id))!.status, ReadStatus.ok);
    expect(tmp.existsSync(), isFalse);
  });

  test('a copied folder whose inner noteId differs is unreadable', () async {
    await store.write(_note());
    final other = '01926f3a-0000-7000-8000-000000000999';
    Directory('${docs.path}/$noteDataDirName/$other').createSync();
    working.copySync('${docs.path}/$noteDataDirName/$other/working.kkj');
    final r = (await store.read(other))!;
    expect(r.status, ReadStatus.unreadable);
    expect(r.writable, isFalse);
  });

  test('encode failure is a NoteSaveException and leaves no tmp', () async {
    final bad = Note.trusted({
      ..._note().copyJson(),
      'pages': [
        {..._note().pages.first, 'width': double.nan},
      ],
    });
    await expectLater(store.write(bad), throwsA(isA<NoteSaveException>()));
    expect(tmp.existsSync(), isFalse);
  });
}
