import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';

const id = '01926f3a-0000-7000-8000-000000000900';
const page = '01926f3a-0000-7000-8000-000000000001';

Note _note({String pageRev = '01926f3a-0000-7000-8000-000000000051'}) {
  final r = createNote(
    title: 'a',
    existingTitles: [],
    background: 'plain',
    orientation: 'portrait',
    noteId: id,
    pageId: page,
    pageRev: pageRev,
    metaRev: '01926f3a-0000-7000-8000-000000000901',
    orderRev: '01926f3a-0000-7000-8000-000000000902',
    now: '2026-10-10T04:20:00.000Z',
    editedBy: 'Pixel 8',
  );
  return r.note!;
}

// A page whose rev differs from [_note]'s default.
final _rev2 = _note(pageRev: '01926f3a-0000-7000-8000-000000000052');

void main() {
  late Directory docs;
  late Directory dir;
  late NoteData data;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-sync-');
    data = NoteData(() async => docs);
    dir = Directory('${docs.path}/$noteDataDirName/$id');
    addTearDown(() => docs.deleteSync(recursive: true));
  });

  File f(String name) => File('${dir.path}/$name');
  List<String> names() => dir.existsSync()
      ? (dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort())
      : [];

  Note? openBase(String rev) =>
      decodeKkj(f('base.$rev.kkj').readAsBytesSync()).note;

  group('readSync', () {
    test('a folder with only working.kkj is pending and unsent', () async {
      final store = NoteStore(data);
      await store.write(_note());
      final r = await store.readSync(id);
      expect(r.state, SyncState.pending);
      expect(r.hasUnsent, isTrue);
      expect(r.base, isNull);
      expect(r.info.baseHeadRevisionId, isNull);
      expect(names(), ['working.kkj']); // reading changed nothing
    });

    test('no folder at all does not throw', () async {
      final r = await NoteStore(data).readSync(id);
      expect(r.hasUnsent, isTrue);
      expect(r.state, SyncState.pending);
    });

    test(
      'a broken sync.json is the same as none and nothing is cleaned',
      () async {
        final store = NoteStore(data);
        await store.commitSync(
          _note(),
          _note(),
          const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
        );
        for (final text in ['{ not json', '[1]', '{"state":"dirty"}']) {
          f('sync.json').writeAsStringSync(text);
          final r = await NoteStore(data).readSync(id);
          expect(r.state, SyncState.pending, reason: text);
          expect(r.hasUnsent, isTrue, reason: text);
          expect(r.base, isNull, reason: text);
          expect(f('base.R1.kkj').existsSync(), isTrue, reason: text);
          expect(f('sync.json').readAsStringSync(), text, reason: text);
        }
      },
    );

    test(
      'saved synced but working differs: effective state is pending',
      () async {
        final store = NoteStore(data);
        await store.commitSync(
          _rev2,
          _note(),
          const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
        );
        final r = await store.readSync(id);
        expect(r.info.state, SyncState.synced);
        expect(r.hasUnsent, isTrue);
        expect(r.state, SyncState.pending);
      },
    );

    test(
      'equal revisions stay synced; other states are kept as saved',
      () async {
        final store = NoteStore(data);
        await store.commitSync(
          _note(),
          _note(),
          const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
        );
        var r = await store.readSync(id);
        expect((r.hasUnsent, r.state), (false, SyncState.synced));
        expect(r.base!.copyJson(), equals(_note().copyJson()));

        await store.commitSync(
          _note(),
          null,
          const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.conflict),
        );
        r = await store.readSync(id);
        expect(r.state, SyncState.conflict);
      },
    );

    test('pendingVerify and unsent sidecars count as unsent', () async {
      final store = NoteStore(data);
      await store.commitSync(
        _note(),
        _note(),
        const SyncInfo(
          baseHeadRevisionId: 'R1',
          state: SyncState.synced,
          pendingVerify: {
            'parentRevisionId': 'R0',
            'oursRevisionId': 'R1',
            'round': 1,
          },
        ),
      );
      var r = await store.readSync(id);
      expect((r.hasUnsent, r.state), (true, SyncState.pending));

      await store.commitSync(
        _note(),
        null,
        const SyncInfo(
          baseHeadRevisionId: 'R1',
          state: SyncState.synced,
          unsentSidecars: [
            {'pageId': page, 'rev': 'a0'},
          ],
        ),
      );
      r = await store.readSync(id);
      expect((r.hasUnsent, r.state), (true, SyncState.pending));
    });

    test('a working copy that cannot be read is unsent and pending', () async {
      final store = NoteStore(data);
      await store.commitSync(
        _note(),
        _note(),
        const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
      );
      final other = _note().copyJson()..['noteId'] = page; // foreign noteId
      final newer = {..._note().copyJson(), 'formatVersion': 99};
      final bad = <List<int>?>[
        [1, 2, 3],
        gzip.encode(utf8.encode(jsonEncode(newer))),
        gzip.encode(utf8.encode(jsonEncode(other))),
        null, // missing
      ];
      for (final bytes in bad) {
        if (bytes == null) {
          f('working.kkj').deleteSync();
        } else {
          f('working.kkj').writeAsBytesSync(bytes);
        }
        final r = await NoteStore(data).readSync(id);
        expect((r.hasUnsent, r.state), (true, SyncState.pending));
        expect(r.base, isNotNull); // the base it names is still read
      }
      f('sync.json').deleteSync(); // and with no sync.json at all
      final r = await NoteStore(data).readSync(id);
      expect((r.hasUnsent, r.state), (true, SyncState.pending));
    });

    test('a path-like baseHeadRevisionId reads and deletes nothing', () async {
      final store = NoteStore(data);
      await store.write(_note());
      // what "base.<id>.kkj" with id "../x" could point at
      final outside = File('${docs.path}/$noteDataDirName/x.kkj')
        ..writeAsStringSync('keep');
      f('sync.json').writeAsStringSync(
        jsonEncode({'baseHeadRevisionId': '../x', 'state': 'synced'}),
      );
      final r = await store.readSync(id);
      expect(r.base, isNull);
      expect(r.hasUnsent, isTrue);
      expect(outside.existsSync(), isTrue);
    });

    test('an unreadable base is no base', () async {
      final store = NoteStore(data);
      await store.commitSync(
        _note(),
        _note(),
        const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
      );
      f('base.R1.kkj').writeAsBytesSync([1, 2, 3]);
      final r = await store.readSync(id);
      expect(r.base, isNull);
      expect(r.hasUnsent, isTrue);
    });
  });

  group('commitSync', () {
    test(
      'order is working, base, sync.json and unknown keys survive',
      () async {
        final seen = <String>[];
        late NoteStore store;
        store = NoteStore(
          data,
          onStep: (step) async {
            seen.add('$step:${names().join(',')}');
          },
        );
        await store.commitSync(
          _note(),
          _note(),
          const SyncInfo(
            baseHeadRevisionId: 'R1',
            fileId: 'F1',
            state: SyncState.synced,
            extra: {'future': 1},
          ),
        );
        expect(seen, [
          'working:working.kkj',
          'base:base.R1.kkj,working.kkj',
          'sync:base.R1.kkj,sync.json,working.kkj',
        ]);
        final r = await NoteStore(data).readSync(id);
        expect(r.info.fileId, 'F1');
        expect(r.info.toJson()['future'], 1);
        expect(names(), ['base.R1.kkj', 'sync.json', 'working.kkj']);
      },
    );

    test('a null base id writes no base file', () async {
      await NoteStore(data).commitSync(_note(), null, const SyncInfo());
      expect(names(), ['sync.json', 'working.kkj']);
    });

    test('the old base is removed once sync.json names the new one', () async {
      final store = NoteStore(data);
      await store.commitSync(
        _note(),
        _note(),
        const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
      );
      await store.commitSync(
        _rev2,
        _rev2,
        const SyncInfo(baseHeadRevisionId: 'R2', state: SyncState.synced),
      );
      expect(names(), ['base.R2.kkj', 'sync.json', 'working.kkj']);
    });

    // The state before: committed R1 with the first note. The commit being
    // interrupted moves to rev2 and R2.
    for (final (step, wantBase, wantUnsent) in [
      ('working', 'R1', true),
      ('base', 'R1', true),
      ('sync', 'R2', false),
    ]) {
      test('stopped right after $step: reopens consistently', () async {
        await NoteStore(data).commitSync(
          _note(),
          _note(),
          const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
        );
        final crashing = NoteStore(
          data,
          onStep: (s) async {
            if (s == step) throw StateError('killed');
          },
        );
        await expectLater(
          crashing.commitSync(
            _rev2,
            _rev2,
            const SyncInfo(baseHeadRevisionId: 'R2', state: SyncState.synced),
          ),
          throwsA(isA<NoteSaveException>()),
        );

        final r = await NoteStore(data).readSync(id); // "new process"
        expect(r.info.baseHeadRevisionId, wantBase);
        expect(r.base, isNotNull);
        expect(
          r.base!.copyJson(),
          equals((wantBase == 'R1' ? _note() : _rev2).copyJson()),
        );
        expect(r.hasUnsent, wantUnsent);
        expect(r.state, wantUnsent ? SyncState.pending : SyncState.synced);
        final left = names();
        expect(left.where((n) => n.endsWith('.tmp')), isEmpty);
        expect(left.where((n) => n.startsWith('base.')).toList(), [
          'base.$wantBase.kkj',
        ]);
      });
    }

    test('a failing temp write keeps the previous sync.json', () async {
      await NoteStore(data).commitSync(
        _note(),
        _note(),
        const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
      );
      final before = f('sync.json').readAsBytesSync();
      final failing = NoteStore(
        data,
        writeFile: (file, bytes) async {
          await file.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
          if (file.path.endsWith('sync.json.tmp')) throw StateError('disk');
        },
      );
      await expectLater(
        failing.commitSync(
          _rev2,
          _rev2,
          const SyncInfo(baseHeadRevisionId: 'R2', state: SyncState.synced),
        ),
        throwsA(isA<NoteSaveException>()),
      );
      expect(f('sync.json').readAsBytesSync(), before);
      expect(names().where((n) => n.endsWith('.tmp')), isEmpty);
      final r = await NoteStore(data).readSync(id);
      expect(r.info.baseHeadRevisionId, 'R1');
      expect(r.base, isNotNull);
    });

    test('a half-written temp file left by a kill is dropped', () async {
      final store = NoteStore(data);
      await store.commitSync(
        _note(),
        _note(),
        const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
      );
      f('sync.json.tmp').writeAsBytesSync([1, 2]);
      f('base.R9.kkj.tmp').writeAsBytesSync([1, 2]);
      f('working.kkj.tmp').writeAsBytesSync([1, 2]);
      final r = await store.readSync(id);
      expect(r.state, SyncState.synced);
      expect(names(), ['base.R1.kkj', 'sync.json', 'working.kkj']);
    });

    test(
      'refuses an unreadable or newer working copy and changes nothing',
      () async {
        dir.createSync(recursive: true);
        for (final bytes in [
          [1, 2, 3],
          gzip.encode(
            utf8.encode(
              jsonEncode({..._note().copyJson(), 'formatVersion': 99}),
            ),
          ),
        ]) {
          f('working.kkj').writeAsBytesSync(bytes);
          await expectLater(
            NoteStore(data).commitSync(
              _note(),
              _note(),
              const SyncInfo(baseHeadRevisionId: 'R1'),
            ),
            throwsA(isA<NoteSaveException>()),
          );
          expect(f('working.kkj').readAsBytesSync(), bytes);
          expect(names(), ['working.kkj']);
        }
      },
    );

    test('a committed base id is not overwritten with other content', () async {
      final store = NoteStore(data);
      const info = SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced);
      await store.commitSync(_note(), _note(), info);
      final before = f('base.R1.kkj').readAsBytesSync();
      await expectLater(
        store.commitSync(_rev2, _rev2, info), // same id, new content
        throwsA(isA<NoteSaveException>()),
      );
      expect(f('base.R1.kkj').readAsBytesSync(), before);
      // the same content again is fine and writes nothing
      await store.commitSync(_note(), _note(), info);
      expect(f('base.R1.kkj').readAsBytesSync(), before);
    });

    test('refuses inconsistent input', () async {
      final store = NoteStore(data);
      Future<void> bad(Note? base, SyncInfo info) => expectLater(
        store.commitSync(_note(), base, info),
        throwsA(isA<NoteSaveException>()),
      );
      await bad(_note(), const SyncInfo()); // base without an id
      await bad(_note(), const SyncInfo(baseHeadRevisionId: '../x')); // bad id
      await bad(null, const SyncInfo(baseHeadRevisionId: 'R1')); // no file
      expect(names(), isEmpty);
    });
  });

  group('write', () {
    test('touches only working.kkj', () async {
      final store = NoteStore(data);
      await store.commitSync(
        _note(),
        _note(),
        const SyncInfo(baseHeadRevisionId: 'R1', state: SyncState.synced),
      );
      final base = f('base.R1.kkj').readAsBytesSync();
      final sync = f('sync.json').readAsBytesSync();
      final stamp = f('sync.json').lastModifiedSync();
      await store.write(_rev2);
      expect(f('base.R1.kkj').readAsBytesSync(), base);
      expect(f('sync.json').readAsBytesSync(), sync);
      expect(f('sync.json').lastModifiedSync(), stamp);
      expect(names(), ['base.R1.kkj', 'sync.json', 'working.kkj']);
      expect(openBase('R1')!.pages.single['rev'], _note().pages.single['rev']);
      // ... and that is enough to show it as unsent
      final r = await store.readSync(id);
      expect(r.hasUnsent, isTrue);
      expect(r.state, SyncState.pending);
    });
  });

  group('onWrite', () {
    test('runs after write and commitSync; its failure is swallowed', () async {
      var calls = 0;
      final store = NoteStore(
        data,
        onWrite: () async {
          calls++;
          throw StateError('tag failed');
        },
      );
      await store.write(_note());
      await store.commitSync(_note(), null, const SyncInfo());
      expect(calls, 2);
    });

    test('does not run for a save that failed', () async {
      var calls = 0;
      final store = NoteStore(
        data,
        writeFile: (_, _) async => throw StateError('disk'),
        onWrite: () async => calls++,
      );
      await expectLater(
        store.write(_note()),
        throwsA(isA<NoteSaveException>()),
      );
      expect(calls, 0);
    });
  });
}
