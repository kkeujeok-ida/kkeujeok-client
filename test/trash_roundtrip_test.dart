// Story 14.4: the Drive state the web client leaves in `.trashbin` (and what
// someone does by hand in the Drive UI) read by the Android trash and library.
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/library/folder_service.dart';
import 'package:kkeujeok/library/trash_service.dart';
import 'package:kkeujeok/drive/drive_client.dart' show noteMimeType;

import 'fake_drive.dart';
import 'upload_env.dart';

const _f = '01926f3a-0000-7000-8000-000000001001'; // live folder
const _d = '01926f3a-0000-7000-8000-000000001002'; // folder trashed elsewhere
const _n1 = '01926f3a-0000-7000-8000-000000002001'; // note in _f
const _n2 = '01926f3a-0000-7000-8000-000000002002'; // note trashed elsewhere
const _n3 = '01926f3a-0000-7000-8000-000000002003'; // note below _d
const _at1 = '2026-11-01T00:00:00.000Z';
const _at2 = '2026-11-02T00:00:00.000Z';

class _T {
  _T(this.env, this.folders, this.trash);
  final UploadEnv env;
  final FolderService folders;
  final TrashService trash;
  FakeItem get bin => env.drive.byKkeujeokId('trashbin')!;

  FakeItem seed(
    String id,
    List<String> parents, {
    bool folder = false,
    Map<String, String> props = const {},
  }) {
    final i = env.drive.seed(
      name: folder ? id : '$id.kkj',
      kkeujeokId: id,
      parents: parents,
      mimeType: folder ? folderMimeType : noteMimeType,
    );
    i.appProperties.addAll(props);
    return i;
  }
}

/// Drive as the other client leaves it: live folder `_f` with `_n1`; `_n2`
/// and folder `_d` (holding `_n3`) in `.trashbin`.
Future<_T> _setup() async {
  final env = await UploadEnv.create();
  final folders = FolderService(
    drive: env.drive,
    device: env.device,
    store: env.store,
    allowed: () async => true,
    online: () async => true,
    newFolderId: () => _f,
    clock: () => DateTime.utc(2026, 11, 3),
    upload: (id) async => true,
  );
  final trash = TrashService(
    drive: env.drive,
    device: env.device,
    folders: folders,
  );
  final t = _T(env, folders, trash);
  final bin = env.drive.seed(
    name: '.trashbin',
    kkeujeokId: 'trashbin',
    parents: [env.root.id],
    mimeType: folderMimeType,
  );
  final f = t.seed(_f, [env.root.id], folder: true);
  t.seed(_n1, [f.id]);
  t.seed(_n2, [bin.id], props: {'trashedFrom': _f, 'trashedAt': _at1});
  final d = t.seed(
    _d,
    [bin.id],
    folder: true,
    props: {'trashedFrom': 'root', 'trashedAt': _at2},
  );
  t.seed(_n3, [d.id]);
  expect(await folders.refresh(), isTrue);
  return t;
}

void main() {
  test('(a) a note with unsent changes trashed by the other client is revived, not lost', () async {
    final t = await _setup();
    await t.env.store.write(makeNote(noteIdOverride: _n2));
    expect(await t.folders.refresh(), isTrue);
    expect(await t.env.store.ids(), contains(_n2));
    expect(t.env.drive.byKkeujeokId(_n2)!.parents, [
      t.env.drive.byKkeujeokId(_f)!.id,
    ]);
    expect([for (final e in await t.trash.list()) e.id], [_d]);
  });

  test('(a) trashed by the other client: in the trash list, nowhere in the library', () async {
    final t = await _setup();
    final v = await t.folders.view();
    // Hidden notes are not drawn: only _n1 has a folder.
    expect([for (final f in v.folders) f.id], [_f]);
    expect(v.noteFolder.keys, [_n1]);
    final list = await t.trash.list();
    expect(
      [for (final e in list) (e.id, e.isFolder, e.noteCount)],
      [(_d, true, 1), (_n2, false, 0)],
    );
  });

  test(
    '(b) restore returns to the origin; origin gone means top level',
    () async {
      final t = await _setup();
      final list = await t.trash.list();
      expect(
        await t.trash.restore(list.firstWhere((e) => e.id == _n2)),
        TrashOutcome.done,
      );
      expect(t.env.drive.byKkeujeokId(_n2)!.parents, [
        t.env.drive.byKkeujeokId(_f)!.id,
      ]);
      expect(
        await t.trash.restore(list.firstWhere((e) => e.id == _d)),
        TrashOutcome.done,
      );
      expect(await t.folders.refresh(), isTrue);
      final v = await t.folders.view();
      expect(v.noteFolder[_n2], _f);
      expect(v.noteFolder[_n3], _d);
      // Origin deleted afterwards: top level with the notice.
      final n = t.seed(
        '01926f3a-0000-7000-8000-000000002004',
        [t.bin.id],
        props: {'trashedFrom': _f, 'trashedAt': _at1},
      );
      t.env.drive.byKkeujeokId(_f)!.deleted = true;
      final e = (await t.trash.list()).single;
      expect(await t.trash.restore(e), TrashOutcome.rootFallback);
      expect(n.parents, [t.env.root.id]);
    },
  );

  test(
    '(c) purge and empty set trashed=true and drop the item from the list',
    () async {
      final t = await _setup();
      final list = await t.trash.list();
      expect(await t.trash.purge(list.first), TrashOutcome.done);
      expect([for (final e in await t.trash.list()) e.id], [_n2]);
      expect(await t.trash.empty(await t.trash.list()), isEmpty);
      for (final id in [_d, _n2]) {
        final i = t.env.drive.byKkeujeokId(id)!;
        expect(i.trashed, isTrue);
        expect(i.deleted, isFalse);
      }
      expect(await t.trash.list(), isEmpty);
    },
  );

  test('(d) Drive UI: moved out is a library item; hand-added is listed by modifiedTime; a lost .trashbin is recreated', () async {
    final t = await _setup();
    // Moved out of .trashbin by hand: stale properties are ignored.
    t.env.drive.moveForeign(t.env.drive.byKkeujeokId(_n2)!, t.env.root.id);
    // Put in by hand: no properties.
    final hand = t.seed('01926f3a-0000-7000-8000-000000002005', [t.bin.id])
      ..modifiedTime = '2026-11-02T12:00:00.000Z';
    expect(await t.folders.refresh(), isTrue);
    final v = await t.folders.view();
    expect(v.noteFolder.containsKey(_n2), isTrue);
    expect(v.noteFolder.containsKey(hand.appProperties['kkeujeokId']), isFalse);
    final e = (await t.trash.list()).firstWhere(
      (x) => x.id == hand.appProperties['kkeujeokId'],
    );
    expect(e.trashedFrom, isNull);
    expect(e.trashedAt, '2026-11-02T12:00:00.000Z');
    expect(await t.trash.restore(e), TrashOutcome.done);
    expect(hand.parents, [t.env.root.id]);

    // .trashbin deleted: the next delete makes a new one; nothing is lost.
    final old = t.bin;
    old.deleted = true;
    await t.folders.createFolder('x', 'root');
    await t.folders.flush();
    await t.folders.deleteFolder(_f);
    await t.folders.flush();
    final fresh = t.bin;
    expect(fresh.id, isNot(old.id));
    expect(t.env.drive.byKkeujeokId(_f)!.parents, [fresh.id]);
    expect(t.env.drive.byKkeujeokId(_n3), isNotNull);
  });
}
