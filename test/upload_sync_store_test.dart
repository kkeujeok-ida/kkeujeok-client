import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';

import 'upload_env.dart';

void main() {
  late Directory docs;
  late NoteData data;
  late Directory dir;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-updsync-');
    data = NoteData(() async => docs);
    dir = Directory('${docs.path}/$noteDataDirName/$noteId');
    addTearDown(() => docs.deleteSync(recursive: true));
  });

  File f(String n) => File('${dir.path}/$n');

  group('SyncInfo.copyWith', () {
    test('nullable fields can be set to null, others are kept', () {
      const a = SyncInfo(
        fileId: 'F',
        baseHeadRevisionId: 'R1',
        state: SyncState.syncing,
        pendingVerify: {
          'parentRevisionId': null,
          'oursRevisionId': 'R2',
          'round': 1,
        },
        lastError: {'class': 'fatal'},
        extra: {'x': 1},
      );
      final b = a.copyWith(pendingVerify: null, lastError: null);
      expect(b.pendingVerify, isNull);
      expect(b.lastError, isNull);
      expect(b.fileId, 'F');
      expect(b.baseHeadRevisionId, 'R1');
      expect(b.state, SyncState.syncing);
      expect(b.extra, {'x': 1});
      expect(a.copyWith(fileId: null).fileId, isNull);
      expect(a.copyWith().fileId, 'F');
    });
  });

  group('updateSync', () {
    test('writes base then sync.json, never the working copy', () async {
      final steps = <String>[];
      final store = NoteStore(
        data,
        onStep: (s) async {
          steps.add(s);
        },
      );
      await store.write(makeNote());
      final working = f('working.kkj').readAsBytesSync();

      final done = await store.updateSync(
        noteId,
        (c) => c.copyWith(baseHeadRevisionId: 'R1', state: SyncState.synced),
        base: makeNote(),
      );

      expect(steps, ['base', 'sync']); // sync.json is the commit marker
      expect(done.baseHeadRevisionId, 'R1');
      expect(f('working.kkj').readAsBytesSync(), working);
      expect(f('base.R1.kkj').existsSync(), isTrue);
      final r = await store.readSync(noteId);
      expect(r.state, SyncState.synced);
      expect(r.base, isNotNull);
    });

    test('a crash after the base leaves the old sync.json and base', () async {
      var crash = false;
      final store = NoteStore(
        data,
        onStep: (s) async {
          if (crash && s == 'base') throw Crash();
        },
      );
      await store.write(makeNote());
      await store.updateSync(
        noteId,
        (c) => c.copyWith(baseHeadRevisionId: 'R1'),
        base: makeNote(),
      );
      final old = f('sync.json').readAsStringSync();

      crash = true;
      await expectLater(
        store.updateSync(
          noteId,
          (c) => c.copyWith(baseHeadRevisionId: 'R2'),
          base: makeNote(rev: 2),
        ),
        throwsA(isA<NoteSaveException>()),
      );
      expect(f('sync.json').readAsStringSync(), old);
      final r = await NoteStore(data).readSync(noteId);
      expect(r.info.baseHeadRevisionId, 'R1');
      expect(r.base, isNotNull); // the old base is still the trusted one
    });

    test('the change function sees the sync.json of the moment: no stale '
        'snapshot overwrites a newer write', () async {
      final gate = Completer<void>();
      var slow = false;
      final store = NoteStore(
        data,
        writeFile: (file, bytes) async {
          if (file.path.endsWith('sync.json.tmp') && slow) {
            slow = false;
            await gate.future; // the first write is slow
          }
          await file.writeAsBytes(bytes);
        },
      );
      await store.write(makeNote());
      await store.updateSync(noteId, (c) => c.copyWith(fileId: 'F0'));

      slow = true;
      final a = store.updateSync(noteId, (c) => c.copyWith(fileId: 'F1'));
      String? seenByB;
      final b = store.updateSync(noteId, (c) {
        seenByB = c.fileId;
        return c.copyWith(lastError: {'class': 'fatal'});
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gate.complete();
      await Future.wait([a, b]);

      expect(seenByB, 'F1'); // B ran after A's commit
      final s = (await store.readSync(noteId)).info;
      expect(s.fileId, 'F1');
      expect(s.lastError, {'class': 'fatal'}); // neither write was lost
    });

    test(
      'a note without a folder, a bad id, and another note base fail',
      () async {
        final store = NoteStore(data);
        await expectLater(
          store.updateSync(noteId, (c) => c),
          throwsA(isA<NoteSaveException>()),
        );
        await store.write(makeNote());
        await expectLater(
          store.updateSync(
            noteId,
            (c) => c.copyWith(baseHeadRevisionId: 'bad/id'),
            base: makeNote(),
          ),
          throwsA(isA<NoteSaveException>()),
        );
        await expectLater(
          store.updateSync(
            noteId,
            (c) => c.copyWith(baseHeadRevisionId: 'R1'),
            base: makeNote(
              noteIdOverride: '01926f3a-0000-7000-8000-000000000999',
            ),
          ),
          throwsA(isA<NoteSaveException>()),
        );
        await expectLater(
          store.updateSync(noteId, (c) => c.copyWith(baseHeadRevisionId: 'R9')),
          throwsA(isA<NoteSaveException>()), // no base file
        );
      },
    );

    test('a committed base id is not overwritten with other content', () async {
      final store = NoteStore(data);
      await store.write(makeNote());
      await store.updateSync(
        noteId,
        (c) => c.copyWith(baseHeadRevisionId: 'R1'),
        base: makeNote(),
      );
      final bytes = f('base.R1.kkj').readAsBytesSync();
      await expectLater(
        store.updateSync(noteId, (c) => c, base: makeNote(rev: 2)),
        throwsA(isA<NoteSaveException>()),
      );
      expect(f('base.R1.kkj').readAsBytesSync(), bytes);
      expect(decodeKkj(bytes).note, isNotNull);
    });
  });
}
