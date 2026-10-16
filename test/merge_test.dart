// Tests of the Story 3.3 code that the shared fixtures do not reach: no input
// is mutated, results are deterministic, UUIDv5, the undo drop of `History`,
// the commit-time merge of `QueueMergeStep` over a real `NoteStore`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/uuid_v5.dart';
import 'package:kkeujeok/ops/history.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/ops/resolve_conflict.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_device_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/merge.dart';
import 'package:kkeujeok/sync/merge_step.dart';
import 'package:uuid/uuid.dart';

const _noteId = '01926f3a-0000-7000-8000-000000000900';

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

/// A page; a page of [rev] above 1 comes from a device that synced revision 1
/// first, so its `lineage` holds it (spec `merge.page3way`).
Map<String, dynamic> _page(int n, {int rev = 1, int seq = 1}) => {
  'id': _id(n),
  'width': 595,
  'height': 842,
  'background': 'plain',
  'rev': _id(1000 * n + rev),
  'seq': seq,
  'editedAt': '2026-10-10T04:20:00.000Z',
  'editedBy': 'Pixel 8',
  'elements': <Object?>[],
  if (rev > 1) 'lineage': [_id(1000 * n + rev - 1)],
};

Map<String, dynamic> _stroke(int n) => {
  'id': _id(5000 + n),
  'type': 'stroke',
  'tool': 'pen',
  'color': '#000000',
  'width': 2,
  'usePressure': true,
  'points': [
    [10, 10, 0.5, 0],
    [20 + n, 20, 0.5, 10],
  ],
};

Note _note(List<Map<String, dynamic>> pages) => Note.trusted({
  'formatVersion': 1,
  'noteId': _noteId,
  'meta': {'title': 'a'},
  'metaRev': _id(901),
  'metaSeq': 1,
  'orderRev': _id(902),
  'orderSeq': 1,
  'pages': pages,
});

Map<String, dynamic> _ctx({int seen = 0}) => {
  'now': '2026-10-16T08:00:00.000Z',
  'orderRev': _id(9001),
  'rev': _id(9002),
  'editedBy': 'Pixel 8',
  'lastSeenRemoteSeq': seen,
};

/// A copy of [n] with strokes added to page [pageNo] through the real op.
Note _draw(Note n, int pageNo, int strokes, {int from = 1}) {
  var cur = n;
  for (var i = 0; i < strokes; i++) {
    final r = addStroke(
      cur,
      {'op': 'addStroke', 'pageId': _id(pageNo), 'stroke': _stroke(from + i)},
      Ctx(
        rev: _id(7000 + from + i),
        now: '2026-10-16T07:00:00.000Z',
        editedBy: 'Pixel 8',
      ),
    );
    cur = r.note!;
  }
  return cur;
}

void main() {
  group('pure functions', () {
    final base = _note([_page(1), _page(2)]);
    final local = _draw(base, 1, 1); // page 1 changed here
    final remote = Note.trusted(
      base.copyJson()
        ..['pages'] = [_page(1, rev: 2, seq: 2), _page(2, rev: 2, seq: 2)],
    ); // both pages changed there

    test('no input is mutated and the result shares nothing with them', () {
      final inputs = [base, local, remote].map((n) => n.copyJson()).toList();
      final ctx = _ctx();
      final frozen = jsonEncode([...inputs, ctx]);
      final out = mergeNotes(inputs[0], inputs[1], inputs[2], ctx);
      expect(out['result'], 'merged');
      expect(jsonEncode([...inputs, ctx]), frozen);
      // Writing into the result must not reach an input.
      final note = out['note'] as Map<String, dynamic>;
      for (final p in (note['pages'] as List).cast<Map<String, dynamic>>()) {
        (p['elements'] as List).add('x');
        p['rev'] = 'changed';
      }
      for (final c in out['sidecars'] as List) {
        ((c as Map)['page'] as Map)['rev'] = 'changed';
      }
      expect(jsonEncode([...inputs, ctx]), frozen);
    });

    test('resolveConflict mutates none of its inputs', () {
      final r = mergeNotes(
        base.copyJson(),
        local.copyJson(),
        remote.copyJson(),
        _ctx(),
      );
      final note = r['note'] as Map<String, dynamic>;
      final conflict = (r['conflicts'] as List).first as Map<String, dynamic>;
      final sidecar = (r['sidecars'] as List).first as Map<String, dynamic>;
      final frozen = jsonEncode([note, conflict, sidecar]);
      final out = resolveConflict(note, conflict, sidecar, 'both', _ctx());
      expect(out['result'], 'resolved');
      expect(jsonEncode([note, conflict, sidecar]), frozen);
    });

    test('the same input gives the same output', () {
      Map<String, Object?> run() => mergeNotes(
        base.copyJson(),
        local.copyJson(),
        remote.copyJson(),
        _ctx(),
      );
      expect(jsonEncode(run()), jsonEncode(run()));
    });

    test('error precedence: unsupportedVersion, noteIdMismatch, duplicate', () {
      final other = base.copyJson()..['noteId'] = 'other';
      final dup = base.copyJson()..['pages'] = [_page(1), _page(1)];
      final v2 = base.copyJson()..['formatVersion'] = 2;
      Map<String, Object?> m(Map<String, dynamic> l, Map<String, dynamic> r) =>
          mergeNotes(null, l, r, _ctx());
      // All three at once: the version wins.
      expect(m(dup, v2..['noteId'] = 'other'), {
        'result': 'unsupportedVersion',
      });
      // Mismatch and a duplicate: the mismatch wins.
      expect(m(dup, other), {'error': 'noteIdMismatch'});
      expect(m(dup, base.copyJson()), {'error': 'duplicatePageId'});
    });

    test('a page of an unknown background is read-only and kept verbatim', () {
      final odd = _page(3)..['background'] = {'kind': 'image'};
      final out = mergeNotes(
        null,
        _note([_page(1)]).copyJson(),
        _note([_page(1), odd]).copyJson(),
        _ctx(),
      );
      expect(out['readOnlyPages'], [_id(3)]);
    });

    test('requeue: the pages that changed while the network ran', () {
      final start = base;
      final commit = _draw(base, 1, 3);
      final out = mergeRequeueNotes(
        base: base.copyJson(),
        localAtStart: start.copyJson(),
        localAtCommit: commit.copyJson(),
        remote: Note.trusted(
          base.copyJson()..['pages'] = [_page(1), _page(2, rev: 2, seq: 2)],
        ).copyJson(),
        ctx: _ctx(),
      );
      expect(out['requeue'], {
        'pages': [_id(1)],
        'order': false,
        'meta': false,
      });
      // The three strokes are in the result, the remote page 2 as well.
      final pages = ((out['note'] as Map)['pages'] as List).cast<Map>();
      expect(pages[0]['elements'], hasLength(3));
      expect(pages[1]['rev'], _id(2002));
      expect(out['conflicts'], isEmpty);
    });
  });

  group('uuidV5', () {
    test('the RFC 4122 example', () {
      expect(
        uuidV5('python.org', '6ba7b810-9dad-11d1-80b4-00c04fd430c8'),
        '886313e1-3b8a-5372-9b90-0c9aee199e5d',
      );
    });

    test('agrees with package:uuid for the page id namespace', () {
      for (final name in ['a:b', '${_id(1)}:${_id(2)}', '끄적', '']) {
        expect(
          uuidV5(name, pageIdNamespace),
          const Uuid().v5(pageIdNamespace, name),
        );
      }
    });
  });

  group('History.adopt', () {
    Ctx ctx(int n) =>
        Ctx(rev: _id(8000 + n), now: '2026-10-16T07:00:00.000Z', editedBy: 'x');

    test('drops the records of the given pages, keeps the others', () {
      final h = History(_note([_page(1), _page(2)]));
      expect(
        h.doOp({
          'op': 'addStroke',
          'pageId': _id(1),
          'stroke': _stroke(1),
        }, ctx(1)),
        isNull,
      );
      expect(
        h.doOp({
          'op': 'addStroke',
          'pageId': _id(2),
          'stroke': _stroke(2),
        }, ctx(2)),
        isNull,
      );
      expect(
        h.doOp({
          'op': 'addStroke',
          'pageId': _id(2),
          'stroke': _stroke(3),
        }, ctx(3)),
        isNull,
      );
      expect(h.undo(ctx(4)), isNull); // one redo record, page 2
      expect(h.undoDepth, 2);
      expect(h.redoDepth, 1);

      final merged = h.note.copyJson();
      (merged['pages'] as List)[1] = _page(2, rev: 9);
      h.adopt(Note.trusted(merged), {_id(2)});
      expect(h.undoDepth, 1); // page 1 stays
      expect(h.redoDepth, 0); // the page 2 redo record went
      expect(h.note.pages[1]['rev'], _id(2009));
      // The record that stays still works on the adopted note.
      expect(h.undo(ctx(5)), isNull);
      expect((h.note.pages.first['elements'] as List), isEmpty);
    });

    test('an empty drop keeps every record', () {
      final h = History(_note([_page(1)]));
      h.doOp({
        'op': 'addStroke',
        'pageId': _id(1),
        'stroke': _stroke(1),
      }, ctx(1));
      h.adopt(h.note, {});
      expect(h.undoDepth, 1);
    });
  });

  group('QueueMergeStep over a NoteStore', () {
    late Directory docs;
    late NoteStore store;
    late QueueMergeStep step;
    var revs = 0;
    final applied = <(String, Set<String>)>[];

    File dirFile(String name) =>
        File('${docs.path}/$noteDataDirName/$_noteId/$name');

    setUp(() {
      docs = Directory.systemTemp.createTempSync('kkj-merge-');
      addTearDown(() => docs.deleteSync(recursive: true));
      store = NoteStore(NoteData(() async => docs));
      revs = 0;
      applied.clear();
      step = QueueMergeStep(
        store: store,
        hosts: MergeHosts(),
        clock: () => DateTime.utc(2026, 10, 16),
        newRev: () => _id(9100 + ++revs),
        onApplied: (id, n, drop) => applied.add((id, drop)),
      );
    });

    final base = _note([_page(1), _page(2)]);

    Note remoteWithPage2Changed() => Note.trusted(
      base.copyJson()..['pages'] = [_page(1), _page(2, rev: 2, seq: 2)],
    );

    test(
      'strokes drawn while the download ran stay (only local changed)',
      () async {
        // The sync started from `base`; three strokes land before the commit.
        final start = base;
        await store.write(_draw(base, 1, 3));
        final out = await step.merge(
          localAtStart: start,
          base: base,
          remote: remoteWithPage2Changed(),
        );
        expect(out, isA<Merged>());
        final w = (await store.read(_noteId))!.note!;
        expect(w.pages[0]['elements'], hasLength(3));
        expect(w.pages[1]['rev'], _id(2002)); // the remote page is taken
        expect((out as Merged).conflicts, 0);
        // Page 2 became the remote page; page 1 with the strokes is kept.
        expect(applied.single.$2, {_id(2)});
      },
    );

    test(
      'strokes on a page the remote also changed are in a sidecar',
      () async {
        final start = base;
        await store.write(_draw(base, 1, 3));
        final remote = Note.trusted(
          base.copyJson()..['pages'] = [_page(1, rev: 2, seq: 2), _page(2)],
        );
        final out = await step.merge(
          localAtStart: start,
          base: base,
          remote: remote,
        );

        expect((out as Merged).conflicts, 1);
        final w = (await store.read(_noteId))!.note!;
        expect(w.pages[0]['rev'], _id(1002)); // the remote page
        final info = (await store.readSync(_noteId)).info;
        expect(info.conflicts.single['kind'], 'bothEdited');
        expect(info.conflicts.single['resolvedAt'], isNull);
        expect(info.unsentSidecars.single['pageId'], _id(1));
        final sc = await store.readSidecar(
          _noteId,
          _id(1),
          info.conflicts.single['rev'] as String,
        );
        expect(((sc!['page'] as Map)['elements'] as List), hasLength(3));
        expect(applied.single.$2, {_id(1)});
        // Merging the same result again records nothing twice.
        await store.write(_draw(base, 1, 3));
        await step.merge(localAtStart: start, base: base, remote: remote);
        final again = (await store.readSync(_noteId)).info;
        expect(again.conflicts, hasLength(1));
        expect(again.unsentSidecars, hasLength(1));
      },
    );

    test('lastSeenRemoteSeq is stored in sync.json and only raised', () async {
      await store.write(base);
      final remote = Note.trusted(
        base.copyJson()..['pages'] = [_page(1, rev: 2, seq: 7), _page(2)],
      );
      await step.merge(localAtStart: base, base: base, remote: remote);
      expect((await store.readSync(_noteId)).info.lastSeenRemoteSeq, 7);
      final json = jsonDecode(dirFile('sync.json').readAsStringSync()) as Map;
      expect(json['lastSeenRemoteSeq'], 7);
      await step.merge(localAtStart: base, base: base, remote: base);
      expect((await store.readSync(_noteId)).info.lastSeenRemoteSeq, 7);
    });

    test('a newer remote format changes no file', () async {
      await store.write(_draw(base, 1, 1));
      final before = dirFile('working.kkj').readAsBytesSync();
      final v2 = Note.trusted(base.copyJson()..['formatVersion'] = 2);
      final out = await step.merge(localAtStart: base, base: base, remote: v2);
      expect(out, isA<MergeUnsupported>());
      expect(dirFile('working.kkj').readAsBytesSync(), before);
      expect(dirFile('sync.json').existsSync(), isFalse);
      expect(dirFile('sidecars').existsSync(), isFalse);
      expect(applied, isEmpty);
    });

    test('an error result changes no file', () async {
      await store.write(base);
      final before = dirFile('working.kkj').readAsBytesSync();
      final dup = Note.trusted(
        base.copyJson()..['pages'] = [_page(1), _page(1)],
      );
      final out = await step.merge(localAtStart: base, base: base, remote: dup);
      expect((out as MergeFailed).code, 'duplicatePageId');
      expect(dirFile('working.kkj').readAsBytesSync(), before);
      expect(dirFile('sync.json').existsSync(), isFalse);
    });

    test('an unreadable sync.json is never replaced', () async {
      await store.write(base);
      dirFile('sync.json').writeAsStringSync('{ not json');
      final before = dirFile('working.kkj').readAsBytesSync();
      await expectLater(
        step.merge(
          localAtStart: base,
          base: base,
          remote: remoteWithPage2Changed(),
        ),
        throwsA(isA<NoteSaveException>()),
      );
      expect(dirFile('working.kkj').readAsBytesSync(), before);
      expect(dirFile('sync.json').readAsStringSync(), '{ not json');
    });

    test('the working copy is read inside the lock, not before it', () async {
      // A slow write holds the lock while another save is queued behind it:
      // the merge must see the queued save, never the state before it.
      await store.write(base);
      final saves = store.write(_draw(base, 1, 2)); // queued first
      final merged = step.merge(
        localAtStart: base,
        base: base,
        remote: remoteWithPage2Changed(),
      );
      await Future.wait([saves, merged]);
      final w = (await store.read(_noteId))!.note!;
      expect(w.pages[0]['elements'], hasLength(2));
      expect(w.pages[1]['rev'], _id(2002));
    });

    test('an unchanged result writes nothing', () async {
      await store.write(base);
      final stamp = dirFile('working.kkj').lastModifiedSync();
      final before = dirFile('working.kkj').readAsBytesSync();
      final out = await step.merge(
        localAtStart: base,
        base: base,
        remote: base,
      );
      expect(out, isA<Merged>());
      expect(dirFile('working.kkj').readAsBytesSync(), before);
      expect(dirFile('working.kkj').lastModifiedSync(), stamp);
      expect(applied, isEmpty);
      // Only the highest seq seen is noted; no conflict is recorded.
      final info = (await store.readSync(_noteId)).info;
      expect(info.conflicts, isEmpty);
      expect(info.lastSeenRemoteSeq, 1);
    });
  });

  group('QueueMergeStep with an open editor (host)', () {
    late Directory docs;
    late NoteStore store;
    late MergeHosts hosts;
    late QueueMergeStep step;
    late History history;
    var revs = 0;

    setUp(() async {
      docs = Directory.systemTemp.createTempSync('kkj-merge-');
      addTearDown(() => docs.deleteSync(recursive: true));
      store = NoteStore(NoteData(() async => docs));
      hosts = MergeHosts();
      revs = 0;
      step = QueueMergeStep(
        store: store,
        hosts: hosts,
        clock: () => DateTime.utc(2026, 10, 16),
        newRev: () => _id(9100 + ++revs),
      );
      history = History(_note([_page(1), _page(2)]));
      await store.write(history.note);
    });

    // The editor's loop, as `NoteEditor._applyMerge` runs it.
    MergeHost host({void Function()? duringRecord, int tries = 20}) =>
        (merge, record) async {
          for (var i = 0; i < tries; i++) {
            final live = history.note;
            final r = merge(live);
            duringRecord?.call();
            await record();
            if (!identical(history.note, live)) continue;
            if (r != null) {
              history.adopt(r.note, r.undoDrop);
              await store.write(history.note);
            }
            return true;
          }
          return false;
        };

    test(
      'the live note is merged, an edit during record is merged again',
      () async {
        var drew = false;
        hosts.register(
          _noteId,
          host(
            duringRecord: () {
              if (drew) return;
              drew =
                  true; // a stroke lands while the conflict files are written
              history.doOp(
                {'op': 'addStroke', 'pageId': _id(2), 'stroke': _stroke(9)},
                Ctx(
                  rev: _id(7777),
                  now: '2026-10-16T07:30:00.000Z',
                  editedBy: 'x',
                ),
              );
            },
          ),
        );
        final base = history.note;
        final remote = Note.trusted(
          base.copyJson()..['pages'] = [_page(1, rev: 2, seq: 2), _page(2)],
        );
        final out = await step.merge(
          localAtStart: base,
          base: base,
          remote: remote,
        );
        expect(out, isA<Merged>());
        // Page 1 is the remote page, the stroke drawn meanwhile is on page 2.
        expect(history.note.pages[0]['rev'], _id(1002));
        expect(history.note.pages[1]['elements'], hasLength(1));
        expect(
          (await store.read(_noteId))!.note!.pages[1]['elements'],
          hasLength(1),
        );
      },
    );

    test(
      'an editor that never gets a quiet moment gives up: queueBusy',
      () async {
        var n = 0;
        hosts.register(
          _noteId,
          host(
            tries: 3,
            duringRecord: () {
              history.doOp(
                {'op': 'addStroke', 'pageId': _id(2), 'stroke': _stroke(++n)},
                Ctx(
                  rev: _id(7700 + n),
                  now: '2026-10-16T07:30:00.000Z',
                  editedBy: 'x',
                ),
              );
            },
          ),
        );
        final base = _note([_page(1), _page(2)]);
        final remote = Note.trusted(
          base.copyJson()..['pages'] = [_page(1, rev: 2, seq: 2), _page(2)],
        );
        final out = await step.merge(
          localAtStart: base,
          base: base,
          remote: remote,
        );
        expect((out as MergeFailed).code, 'queueBusy');
      },
    );

    test('a conflict is recorded before the live note is replaced', () async {
      final order = <String>[];
      hosts.register(_noteId, (merge, record) async {
        final live = history.note;
        final r = merge(live);
        await record();
        order.add(
          'recorded:${(await store.readSync(_noteId)).info.conflicts.length}',
        );
        if (r != null) {
          history.adopt(r.note, r.undoDrop);
          order.add('adopted');
        }
        return true;
      });
      final base = history.note;
      history.doOp({
        'op': 'addStroke',
        'pageId': _id(1),
        'stroke': _stroke(1),
      }, Ctx(rev: _id(7001), now: '2026-10-16T07:30:00.000Z', editedBy: 'x'));
      final remote = Note.trusted(
        base.copyJson()..['pages'] = [_page(1, rev: 2, seq: 2), _page(2)],
      );
      await step.merge(localAtStart: base, base: base, remote: remote);
      expect(order, ['recorded:1', 'adopted']);
      expect(history.undoDepth, 0); // page 1's record went with the page
    });
  });

  test('SyncInfo keeps lastSeenRemoteSeq as an unknown key', () {
    final info = SyncInfo.fromJson({'lastSeenRemoteSeq': 5})!;
    expect(info.lastSeenRemoteSeq, 5);
    expect(info.toJson()['lastSeenRemoteSeq'], 5);
    expect(info.copyWith(conflicts: const []).lastSeenRemoteSeq, 5);
    expect(const SyncInfo().lastSeenRemoteSeq, 0);
    expect(SyncInfo.fromJson({'lastSeenRemoteSeq': -3})!.lastSeenRemoteSeq, 0);
  });

  test('wire format: the .kkj of a merged note reads back', () {
    final out = mergeNotes(
      null,
      _note([_page(1)]).copyJson(),
      _note([_page(2)]).copyJson(),
      _ctx(),
    );
    final n = Note.trusted(out['note'] as Map<String, dynamic>);
    expect(decodeKkj(encodeKkj(n)).note!.pages, hasLength(2));
  });

  group('SyncDeviceStore.update', () {
    late Directory docs;
    late SyncDeviceStore device;
    setUp(() {
      docs = Directory.systemTemp.createTempSync('kkj-dev-');
      addTearDown(() => docs.deleteSync(recursive: true));
      device = SyncDeviceStore(NoteData(() async => docs));
    });

    test('changes the record under the lock and keeps unknown keys', () async {
      File('${docs.path}/sync-device.json').writeAsStringSync(
        jsonEncode({'sub': 's', 'extraKey': 1, 'createIntents': []}),
      );
      await Future.wait([
        device.update((d) => d.copyWith(conflictsFolderId: 'c1')),
        device.update(
          (d) => d.copyWith(
            createIntents: [
              ...d.createIntents,
              {'kkeujeokId': 'x', 'kind': 'conflicts', 'parentId': 'r'},
            ],
          ),
        ),
      ]);
      final d = await device.read();
      expect(d.sub, 's');
      expect(d.conflictsFolderId, 'c1'); // neither update lost the other
      expect(d.createIntents, hasLength(1));
      expect(d.extra['extraKey'], 1);
    });

    test('an unreadable record is never replaced', () async {
      File('${docs.path}/sync-device.json').writeAsStringSync('{ nope');
      await expectLater(
        device.update((d) => d.copyWith(conflictsFolderId: 'c')),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        File('${docs.path}/sync-device.json').readAsStringSync(),
        '{ nope',
      );
    });
  });
}
