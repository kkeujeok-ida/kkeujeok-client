import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/library/folder_service.dart';
import 'package:kkeujeok/library/trash_service.dart';

import 'upload_env.dart';

const _a = '01926f3a-0000-7000-8000-000000001793';

Future<(UploadEnv, FolderService, TrashService)> _setup() async {
  final env = await UploadEnv.create();
  final folders = FolderService(
    drive: env.drive,
    device: env.device,
    store: env.store,
    allowed: () async => true,
    online: () async => true,
    newFolderId: () => _a,
    clock: () => DateTime.utc(2026, 11, 1, 9),
    upload: (id) async {
      await env.uploader(parentFileId: (_) async => null).upload(id);
      return true;
    },
  );
  await folders.createFolder('a', 'root');
  await folders.flush();
  await folders.deleteFolder(_a);
  await folders.flush();
  final trash = TrashService(
    drive: env.drive,
    device: env.device,
    folders: folders,
  );
  return (env, folders, trash);
}

void main() {
  test('list, restore to origin, and a gone item', () async {
    final (env, _, trash) = await _setup();
    final list = await trash.list();
    expect(
      [for (final e in list) (e.id, e.isFolder, e.title)],
      [(_a, true, 'a')],
    );
    final item = env.drive.byKkeujeokId(_a)!;
    expect(await trash.restore(list.single), TrashOutcome.done);
    expect(item.parents, [env.root.id]);
    expect(item.appProperties.containsKey('trashedFrom'), isFalse);
    expect(item.appProperties.containsKey('trashedAt'), isFalse);
    expect(await trash.list(), isEmpty);
    item.deleted = true;
    expect(await trash.restore(list.single), TrashOutcome.gone);
  });

  test('origin missing restores to the top level with a notice', () async {
    final (env, _, trash) = await _setup();
    final item = env.drive.byKkeujeokId(_a)!;
    item.appProperties['trashedFrom'] = 'no-such-folder';
    final e = (await trash.list()).single;
    expect(await trash.restore(e), TrashOutcome.rootFallback);
    expect(item.parents, [env.root.id]);
  });

  test('purge and empty set trashed=true, never delete', () async {
    final (env, _, trash) = await _setup();
    final item = env.drive.byKkeujeokId(_a)!;
    final e = (await trash.list()).single;
    expect(await trash.purge(e), TrashOutcome.done);
    expect(item.trashed, isTrue);
    expect(item.deleted, isFalse);
    expect(await trash.purge(e), TrashOutcome.gone);
    expect(await trash.empty([e]), isEmpty);
  });
}
