import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/library/folder_service.dart';

import 'fake_drive.dart';
import 'upload_env.dart';

const _a = '01926f3a-0000-7000-8000-000000001793';
const _b = '01926f3a-0000-7000-8000-000000001794';
const _c = '01926f3a-0000-7000-8000-000000001795';

class _Env {
  _Env(this.env) {
    final ids = [_a, _b, _c];
    service = FolderService(
      drive: env.drive,
      device: env.device,
      store: env.store,
      allowed: () async => env.allowed,
      online: () async => env.online,
      newFolderId: () => ids.removeAt(0),
      clock: () => DateTime.utc(2026, 11, 1, 9),
      upload: (id) async {
        uploaded.add(id);
        if (!uploadOk) return false;
        await uploadNote(id);
        return true;
      },
    );
  }

  final UploadEnv env;
  late final FolderService service;
  bool uploadOk = true;
  final uploaded = <String>[];

  /// The uploader as the app wires it: folders come from the service.
  Future<void> uploadNote([String id = noteId]) =>
      env.uploader(parentFileId: service.parentFileId).upload(id);

  List<FakeItem> folders() => [
    for (final i in env.drive.items)
      if (i.mimeType == folderMimeType &&
          i.appProperties['kkeujeokId'] != 'root' &&
          !i.deleted)
        i,
  ];

  FakeItem folder(String kid) => env.drive.byKkeujeokId(kid)!;
}

Future<_Env> _setup() async {
  final env = await UploadEnv.create();
  return _Env(env);
}

void main() {
  test(
    'offline: folder and note show at once, Drive gets one folder',
    () async {
      final t = await _setup();
      t.env.online = false;
      final r = await t.service.createFolder('  수업  ', 'root');
      expect(r.ok, isTrue);
      expect(r.id, _a);
      await t.env.save(makeNote());
      await t.service.assignNote(noteId, _a);
      var v = await t.service.view();
      expect([for (final f in v.folders) f.name], ['수업']);
      expect(v.noteFolder[noteId], _a);
      expect(await t.service.flush(), isFalse);
      expect(t.folders(), isEmpty);

      t.env.online = true;
      await t.uploadNote();
      final f = t.folder(_a);
      expect(t.env.note.parents, [f.id]);
      expect(f.parents, [t.env.root.id]);
      // A retry of everything changes nothing in Drive.
      expect(await t.service.flush(), isTrue);
      expect(await t.service.refresh(), isTrue);
      expect(t.folders().length, 1);
      expect(await t.service.hasPending(), isFalse);
      v = await t.service.view();
      expect(v.noteFolder[noteId], _a);
    },
  );

  test('a lost answer of the create does not make a second folder', () async {
    final t = await _setup();
    t.env.online = false;
    await t.service.createFolder('a', 'root');
    expect(await t.service.flush(), isFalse); // also waits for the first one
    var lost = true;
    t.env.drive.after = (call) {
      if (call == 'create' && lost) {
        lost = false;
        throw const DriveError('network'); // Drive made it, the answer is lost
      }
    };
    t.env.online = true;
    expect(await t.service.flush(), isFalse);
    expect(t.folders().length, 1);
    expect(await t.service.hasPending(), isTrue);
    expect(await t.service.flush(), isTrue);
    expect(t.folders().length, 1);
    expect(await t.service.hasPending(), isFalse);
  });

  test('rename and move are queued, sent in order and undone', () async {
    final t = await _setup();
    await t.service.createFolder('a', 'root');
    await t.service.createFolder('b', 'root');
    await t.service.flush();
    t.env.online = false;
    expect((await t.service.renameFolder(_a, 'x')).inverse, {
      'op': 'renameFolder',
      'id': _a,
      'name': 'a',
    });
    expect((await t.service.renameFolder(_a, '')).error, 'emptyName');
    expect((await t.service.moveFolder(_a, _a)).error, 'moveIntoSelf');
    final m = await t.service.moveFolder(_a, _b);
    expect(m.ok, isTrue);
    expect((await t.service.moveFolder(_b, _a)).error, 'moveIntoDescendant');
    var v = await t.service.view();
    expect(v.folder(_a)!.name, 'x');
    expect(v.folder(_a)!.parentId, _b);
    // Undo before anything was sent drops the entry.
    await t.service.undo(m.inverse!);
    t.env.online = true;
    await t.service.flush();
    expect(t.folder(_a).name, 'x');
    expect(t.folder(_a).parents, [t.env.root.id]);
    await t.service.moveFolder(_a, _b);
    await t.service.flush();
    expect(t.folder(_a).parents, [t.folder(_b).id]);
    v = await t.service.view();
    expect(v.noteCount(_b), 0);
  });

  test(
    'delete: upload, then move to .trashbin, then drop the local copy',
    () async {
      final t = await _setup();
      await t.service.createFolder('a', 'root');
      await t.env.save(makeNote());
      await t.service.assignNote(noteId, _a);
      final d = await t.service.deleteFolder(_a);
      expect(d.ok, isTrue);
      await t.service.flush();
      expect(t.uploaded, [noteId]);
      final f = t.folder(_a);
      final bin = t.env.drive.byKkeujeokId('trashbin')!;
      expect(f.parents, [bin.id]);
      expect(f.trashed, isFalse);
      expect(f.appProperties['trashedFrom'], 'root');
      expect(f.appProperties['trashedAt'], '2026-11-01T09:00:00.000Z');
      // The note went up inside the folder before the move.
      expect(t.env.note.parents, [f.id]);
      expect(await t.env.store.ids(), isEmpty);
      final v = await t.service.view();
      expect(v.folders, isEmpty);
      expect(await t.service.hasPending(), isFalse);
    },
  );

  test('delete is hidden at once; a failed upload keeps everything', () async {
    final t = await _setup();
    await t.service.createFolder('a', 'root');
    await t.service.flush();
    await t.env.save(makeNote());
    await t.service.assignNote(noteId, _a);
    t.uploadOk = false;
    await t.service.deleteFolder(_a);
    var v = await t.service.view();
    expect(v.folders, isEmpty);
    expect(v.hiddenNotes, {noteId});
    expect(await t.service.flush(), isFalse);
    expect(t.folder(_a).parents, [t.env.root.id]); // not moved
    expect(await t.env.store.ids(), [noteId]); // device copy kept
    expect(await t.service.hasPending(), isTrue);
    t.uploadOk = true;
    expect(await t.service.flush(), isTrue);
    expect(await t.env.store.ids(), isEmpty);
    v = await t.service.view();
    expect(v.hiddenNotes, isEmpty);
  });

  test(
    'refresh follows another device; a folder gone from the tree is gone',
    () async {
      final t = await _setup();
      await t.service.createFolder('a', 'root');
      await t.service.createFolder('b', 'root');
      await t.service.flush();
      // Another device: a new folder, a rename, a delete.
      final x = t.env.drive.seed(
        name: 'x',
        kkeujeokId: _c,
        parents: [t.env.root.id],
        mimeType: folderMimeType,
      );
      t.env.drive.renameForeign(t.folder(_a), 'renamed');
      final bin = t.env.drive.seed(
        name: '.trashbin',
        kkeujeokId: 'trashbin',
        parents: [t.env.root.id],
        mimeType: folderMimeType,
      );
      t.env.drive.moveForeign(t.folder(_b), bin.id);
      expect(await t.service.refresh(), isTrue);
      final v = await t.service.view();
      expect(
        {for (final f in v.folders) f.id: f.name},
        {_a: 'renamed', _c: 'x'},
      );
      expect(v.has(_b), isFalse);
      expect(x.parents, [t.env.root.id]);
    },
  );

  test('a folder cycle is drawn repaired and written to Drive', () async {
    final t = await _setup();
    await t.service.createFolder('a', 'root');
    await t.service.createFolder('b', 'root');
    await t.service.flush();
    t.env.drive.moveForeign(t.folder(_a), t.folder(_b).id);
    t.env.drive.moveForeign(t.folder(_b), t.folder(_a).id);
    expect(await t.service.refresh(), isTrue);
    final v = await t.service.view();
    expect(v.folder(_a)!.parentId, 'root');
    expect(v.folder(_b)!.parentId, _a);
    expect(t.folder(_a).parents, [t.env.root.id]);
  });
}
