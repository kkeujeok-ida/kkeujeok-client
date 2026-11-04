// Story 7.9: the visible list (folder + title search + sort) and the stored sort.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/library/folder_service.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/ui/library_sort.dart';
import 'package:kkeujeok/ui/note_order.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/sync_display.dart';

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Note _note(int n, String title) => createNote(
  title: title,
  existingTitles: const [],
  background: 'plain',
  orientation: 'portrait',
  noteId: _id(n),
  pageId: _id(1000 + n),
  pageRev: _id(2000 + n),
  metaRev: _id(3000 + n),
  orderRev: _id(4000 + n),
  now: '2000-01-01T12:00:00.000Z',
  editedBy: 'Pixel 8',
).note!;

class _Lib extends LibraryNotifier {
  _Lib(this.list);
  final List<LibraryEntry> list;
  @override
  Future<List<LibraryEntry>> build() async => list;
}

class _Tree extends FolderTreeNotifier {
  @override
  Future<FolderView> build() async => const FolderView(
    folders: [LibraryFolder('A', 'A', 'root'), LibraryFolder('B', 'B', 'A')],
  );
}

class _Sync extends NoteSyncNotifier {
  _Sync(super.noteId);
  @override
  NoteSyncView build() => const NoteSyncView(SyncLabel.saved);
}

void main() {
  final entries = [
    LibraryEntry(_id(1), _note(1, 'Note 10'), null, folderId: null),
    LibraryEntry(_id(2), _note(2, 'Note 2'), null, folderId: 'A'),
    LibraryEntry(_id(3), _note(3, 'Abc'), null, folderId: 'B'),
    LibraryEntry(_id(4), null, null, folderId: 'A'),
  ];

  Future<ProviderContainer> make() async {
    final c = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith(() => _Lib(entries)),
        folderTreeProvider.overrideWith(_Tree.new),
        for (var i = 1; i <= 4; i++)
          noteSyncProvider(_id(i)).overrideWith(() => _Sync(_id(i))),
      ],
    );
    addTearDown(c.dispose);
    await c.read(libraryProvider.future);
    await c.read(folderTreeProvider.future);
    c.read(librarySortProvider.notifier).set(LibrarySort.nameAsc);
    c.read(currentFolderProvider.notifier).select(null); // 모든 노트
    return c;
  }

  List<String> ids(ProviderContainer c) => [
    for (final e in c.read(visibleEntriesProvider)) e.noteId,
  ];

  test('default sort is newest edit first', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(librarySortProvider), LibrarySort.editedDesc);
  });

  test('name order: number value, then Latin', () async {
    final c = await make();
    expect(ids(c), [_id(3), _id(2), _id(1), _id(4)]);
  });

  test('search: all folders, case-insensitive, unreadable left out', () async {
    final c = await make();
    c.read(libraryQueryProvider.notifier).set(' NOTE ');
    expect(ids(c), [_id(2), _id(1)]);
    c.read(libraryQueryProvider.notifier).set('zzz');
    expect(ids(c), isEmpty);
    c.read(libraryQueryProvider.notifier).set('');
    expect(ids(c), hasLength(4));
  });

  test('search in a folder reaches its subfolders', () async {
    final c = await make();
    c.read(currentFolderProvider.notifier).select('A');
    expect(ids(c), [_id(2), _id(4)]); // no query: this folder only
    c.read(libraryQueryProvider.notifier).set('b');
    expect(ids(c), [_id(3)]);
    c.read(libraryQueryProvider.notifier).set('note');
    expect(ids(c), [_id(2)]);
  });

  test('previous/next follows the search', () async {
    final c = await make();
    c.read(libraryQueryProvider.notifier).set('note');
    expect(c.read(openableNoteIdsProvider), [_id(2), _id(1)]);
  });

  test('the start folder is the root: only its notes show', () async {
    final c = await make();
    c.read(currentFolderProvider.notifier).select('root');
    expect(ids(c), isNotEmpty);
    expect(ids(c).length, lessThan(4));
    for (final e in c.read(visibleEntriesProvider)) {
      expect(e.folderId, isNull);
    }
    expect(ProviderContainer().read(currentFolderProvider), 'root');
  });
}
