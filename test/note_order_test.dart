// Story 5.13: the order of the notes a hop walks through.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _Sync extends NoteSyncNotifier {
  _Sync(super.noteId, this.view);
  final NoteSyncView view;
  @override
  NoteSyncView build() => view;
}

void main() {
  group('neighbours', () {
    const ids = ['a', 'b', 'c'];
    test('middle, both ends, single, absent', () {
      expect(neighbours(ids, 'b'), (prev: 'a', next: 'c', n: 2, total: 3));
      expect(neighbours(ids, 'a'), (prev: null, next: 'b', n: 1, total: 3));
      expect(neighbours(ids, 'c'), (prev: 'b', next: null, n: 3, total: 3));
      expect(neighbours(['a'], 'a'), (prev: null, next: null, n: 1, total: 1));
      expect(neighbours(ids, 'z'), (prev: null, next: null, n: 0, total: 3));
    });
  });

  group('openableNoteIdsProvider', () {
    final entries = [
      LibraryEntry(_id(1), _note(1, 'Beta'), null),
      LibraryEntry(_id(2), _note(2, 'alpha'), null),
      LibraryEntry(_id(3), _note(3, 'Gamma'), null),
      LibraryEntry(_id(4), null, null), // cannot be read
      LibraryEntry(_id(5), _note(5, 'Delta'), null), // unreadable remote
    ];

    ProviderContainer make(LibrarySort sort) {
      final c = ProviderContainer(
        overrides: [
          libraryProvider.overrideWith(() => _Lib(entries)),
          noteSyncProvider(_id(5)).overrideWith(
            () => _Sync(
              _id(5),
              const NoteSyncView(
                SyncLabel.notSaved,
                errorClass: 'unreadable',
                errorReason: 'parse',
              ),
            ),
          ),
          for (final i in [1, 2, 3])
            noteSyncProvider(_id(i)).overrideWith(
              () => _Sync(_id(i), const NoteSyncView(SyncLabel.saved)),
            ),
        ],
      );
      addTearDown(c.dispose);
      c.read(librarySortProvider.notifier).set(sort);
      return c;
    }

    test('follows the library sort and drops what cannot be opened', () async {
      final c = make(LibrarySort.nameAsc);
      await c.read(libraryProvider.future);
      final sorted = sortEntries(entries, LibrarySort.nameAsc);
      expect(c.read(openableNoteIdsProvider), [
        for (final e in sorted)
          if (e.readable && e.noteId != _id(5)) e.noteId,
      ]);
      expect(c.read(openableNoteIdsProvider), [_id(2), _id(1), _id(3)]);
    });

    test('a changed sort changes the order', () async {
      final c = make(LibrarySort.nameDesc);
      await c.read(libraryProvider.future);
      expect(c.read(openableNoteIdsProvider), [_id(3), _id(1), _id(2)]);
    });
  });
}
