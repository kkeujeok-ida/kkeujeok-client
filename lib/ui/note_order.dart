import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/note.dart';
import 'library_sort.dart';
import 'providers.dart';
import 'sync_display.dart';

/// Device check (D-58) is a human task: if One UI takes the three-finger
/// swipe, set this to false and only the menu items remain.
const kThreeFingerSwipe = true;

/// Opens [to] in place of the editor that calls it (the library owns the route).
typedef NoteHop = void Function(
  Note to,
  bool resolve,
  int dir,
  NoteArrival? arrival,
);

/// Where the editor came from after a hop: for the chip, the back snackbar
/// and the announcement of the new editor.
class NoteArrival {
  const NoteArrival({
    required this.backNoteId,
    required this.backTitle,
    required this.n,
    required this.total,
    required this.dir,
  });

  final String backNoteId, backTitle;
  final int n, total;

  /// -1 previous, +1 next: the way the hop went.
  final int dir;
}

/// The neighbours of [id] in [ids]; null prev/next at an end or when [id] is
/// not in the list. [n] is the 1-based place (0 when absent).
({String? prev, String? next, int n, int total}) neighbours(
  List<String> ids,
  String id,
) {
  final i = ids.indexOf(id);
  if (i < 0) return (prev: null, next: null, n: 0, total: ids.length);
  return (
    prev: i > 0 ? ids[i - 1] : null,
    next: i < ids.length - 1 ? ids[i + 1] : null,
    n: i + 1,
    total: ids.length,
  );
}

/// Library order (the current sort) of the notes that can be opened.
final openableNoteIdsProvider = Provider.autoDispose<List<String>>((ref) {
  final entries = sortEntries(
    ref.watch(libraryProvider).value ?? const <LibraryEntry>[],
    ref.watch(librarySortProvider),
  );
  return [
    for (final e in entries)
      if (e.readable &&
          !ref.watch(noteSyncProvider(e.noteId).select((v) => v.unreadable)))
        e.noteId,
  ];
});
