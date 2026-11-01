import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/library/folder_service.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/note_uploader.dart';

import 'fake_drive.dart';
import 'upload_env.dart';

const _f = '01926f3a-0000-7000-8000-000000001793';

class _T {
  _T(this.env) {
    service = FolderService(
      drive: env.drive,
      device: env.device,
      store: env.store,
      allowed: () async => env.allowed,
      online: () async => env.online,
      newFolderId: () => _f,
      clock: () => DateTime.utc(2026, 11, 1, 9),
      upload: (id) async {
        await up.upload(id);
        return true;
      },
    );
    up = env.uploader(
      parentFileId: service.parentFileId,
      trashbinFileId: service.trashbinFileId,
      parentIdOf: service.parentIdOf,
    );
  }

  final UploadEnv env;
  late final FolderService service;
  late final NoteUploader up;
}

Future<_T> _setup() async => _T(await UploadEnv.create());

void main() {
  test(
    'delete: unsent upload, then move into .trashbin with the origin',
    () async {
      final t = await _setup();
      await t.service.createFolder('수업', 'root');
      await t.service.flush();
      await t.env.save(makeNote());
      await t.service.assignNote(noteId, _f);
      expect(await t.up.markTrash(noteId), isTrue);
      expect(t.env.info.extra['pendingTrash'], containsPair('from', _f));
      expect(await t.up.trashNote(noteId), isTrue);
      final bin = t.env.drive.byKkeujeokId('trashbin')!;
      expect(t.env.drive.uploads, hasLength(1));
      expect(t.env.note.parents, [bin.id]);
      expect(t.env.note.trashed, isFalse);
      expect(t.env.note.appProperties['trashedFrom'], _f);
      expect(t.env.note.appProperties['trashedAt'], isNotEmpty);
      expect(await t.env.store.read(noteId), isNull);
    },
  );

  test('offline delete keeps the mark; the legacy true is migrated', () async {
    final t = await _setup();
    await t.env.save(makeNote());
    t.env.online = false;
    await t.up.markTrash(noteId);
    expect(await t.up.trashNote(noteId), isFalse);
    expect(t.env.info.pendingTrash, isTrue);
    expect(await t.env.store.read(noteId), isNotNull);
    await t.env.store.updateSync(
      noteId,
      (c) => c.copyWith(extra: {...c.extra, pendingTrashKey: true}),
    );
    t.env.online = true;
    expect(await t.up.trashNote(noteId), isTrue);
    expect(t.env.note.appProperties['trashedFrom'], 'root');
    expect(await t.env.store.read(noteId), isNull);
  });

  test('a note in conflict is not deleted: the device copy stays', () async {
    final t = await _setup();
    await t.env.save(makeNote());
    await t.up.upload(noteId);
    await t.env.store.updateSync(
      noteId,
      (c) => c.copyWith(state: SyncState.conflict),
    );
    await t.up.markTrash(noteId);
    expect(await t.up.trashNote(noteId), isFalse);
    expect(await t.env.store.read(noteId), isNotNull);
  });

  test(
    'moveNote of a note with no local file id is found by kkeujeokId',
    () async {
      final t = await _setup();
      await t.service.createFolder('수업', 'root');
      await t.service.flush();
      // A card whose file Drive has, this device not yet received.
      final remote = t.env.drive.seed(
        name: 'x.kkj',
        kkeujeokId: noteId,
        parents: [t.env.root.id],
      );
      expect((await t.service.moveNote(noteId, _f)).ok, isTrue);
      expect(await t.service.flush(), isTrue);
      expect(remote.parents, [t.env.drive.byKkeujeokId(_f)!.id]);
      // Not in Drive at all: the entry leaves the queue, the upload places it.
      expect((await t.service.moveNote('n2', 'root')).ok, isTrue);
      expect(await t.service.flush(), isTrue);
      expect(await t.service.hasPending(), isFalse);
    },
  );

  test(
    'another device deleted the note: gone, or revived with unsent',
    () async {
      final t = await _setup();
      await t.env.save(makeNote());
      await t.up.upload(noteId);
      final bin = t.env.drive.seed(
        name: '.trashbin',
        kkeujeokId: 'trashbin',
        parents: [t.env.root.id],
        mimeType: folderMimeType,
      );
      t.env.note.parents = [bin.id];
      // Unsent changes: moved back to the top level, notice counted once.
      await t.env.save(makeNote(rev: 2));
      expect(await t.service.refresh(), isTrue);
      expect(t.env.note.parents, [t.env.root.id]);
      expect(await t.service.takeRevived(), 1);
      expect(await t.service.takeRevived(), 0);
      // Nothing unsent: the device copy is removed.
      await t.up.upload(noteId);
      t.env.note.parents = [bin.id];
      expect(await t.service.refresh(), isTrue);
      expect(await t.env.store.read(noteId), isNull);
    },
  );
}
