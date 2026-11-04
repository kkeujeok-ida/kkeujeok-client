import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../library/library_rules.dart';
import '../library/folder_service.dart' show FolderView, LibraryFolder;
import '../model/library_view.dart';
import 'providers.dart';

enum LibrarySort {
  nameAsc,
  nameDesc,
  createdDesc,
  createdAsc,
  editedDesc,
  editedAsc,
}

/// A device setting, stored at once; newest edit first until chosen.
class LibrarySortNotifier extends Notifier<LibrarySort> {
  @override
  LibrarySort build() {
    final name = ref.read(penSlotsStoreProvider).readLibrarySort();
    return LibrarySort.values.where((s) => s.name == name).firstOrNull ??
        LibrarySort.editedDesc;
  }

  void set(LibrarySort s) {
    state = s;
    ref.read(penSlotsStoreProvider).writeLibrarySort(s.name);
  }
}

final librarySortProvider = NotifierProvider<LibrarySortNotifier, LibrarySort>(
  LibrarySortNotifier.new,
);

/// The title search of the library; never stored.
class LibraryQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

final libraryQueryProvider = NotifierProvider<LibraryQueryNotifier, String>(
  LibraryQueryNotifier.new,
);

/// What the library shows: the folder (with its subfolders while searching),
/// the title search, then the sort. The note list and the previous/next
/// notes both read it.
final visibleEntriesProvider = Provider.autoDispose<List<LibraryEntry>>((ref) {
  final folder = ref.watch(effectiveFolderProvider);
  final tree = ref.watch(folderTreeProvider).value ?? const FolderView();
  final q = libraryKey(libraryTrim(ref.watch(libraryQueryProvider)));
  return sortEntries([
    for (final e in ref.watch(libraryProvider).value ?? const <LibraryEntry>[])
      if (q.isEmpty
          ? folder == null ||
                (folder == 'root' ? e.folderId == null : e.folderId == folder)
          : e.readable &&
                (folder == null ||
                    folder == 'root' ||
                    (e.folderId != null &&
                        tree.isInside(e.folderId!, folder))) &&
                libraryKey(e.note!.title).contains(q))
        e,
  ], ref.watch(librarySortProvider));
});

/// Folders in the order of [sort]: names by name, created by the time in the
/// UUIDv7 id, edited (a folder has no edit date) by name ascending.
List<LibraryFolder> sortFolders(List<LibraryFolder> folders, LibrarySort sort) {
  final keys = {for (final f in folders) f.id: libraryKey(f.name)};
  int name(LibraryFolder a, LibraryFolder b, bool desc) => libraryNameCompare(
    keys[a.id]!,
    a.name,
    a.id,
    keys[b.id]!,
    b.name,
    b.id,
    desc: desc,
  );
  int cmp(LibraryFolder a, LibraryFolder b) => switch (sort) {
    LibrarySort.nameDesc => name(a, b, true),
    LibrarySort.createdDesc || LibrarySort.createdAsc => () {
      final c = (createdAtOf(a.id) ?? DateTime(0)).compareTo(
        createdAtOf(b.id) ?? DateTime(0),
      );
      return c == 0
          ? a.id.compareTo(b.id)
          : (sort == LibrarySort.createdDesc ? -c : c);
    }(),
    _ => name(a, b, false),
  };
  return [...folders]..sort(cmp);
}

/// The creation time inside a UUIDv7 note id (48-bit milliseconds), or null.
DateTime? createdAtOf(String noteId) {
  final hex = noteId.replaceAll('-', '');
  if (hex.length < 12) return null;
  final ms = int.tryParse(hex.substring(0, 12), radix: 16);
  return ms == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// Unreadable notes stay last, readable ones without a date after dated ones;
/// ties fall back to the note id so the order is stable.
List<LibraryEntry> sortEntries(List<LibraryEntry> entries, LibrarySort sort) {
  int byTime(DateTime? a, DateTime? b, bool desc) {
    if (a == null || b == null) {
      return a == b ? 0 : (a == null ? 1 : -1); // missing date last
    }
    return desc ? b.compareTo(a) : a.compareTo(b);
  }

  final keys = {
    if (sort == LibrarySort.nameAsc || sort == LibrarySort.nameDesc)
      for (final e in entries) e.noteId: libraryKey(_title(e)),
  };
  int name(LibraryEntry a, LibraryEntry b, bool desc) => libraryNameCompare(
    keys[a.noteId]!,
    _title(a),
    a.noteId,
    keys[b.noteId]!,
    _title(b),
    b.noteId,
    desc: desc,
  );

  int cmp(LibraryEntry a, LibraryEntry b) {
    if (a.readable != b.readable) return a.readable ? -1 : 1;
    final c = switch (sort) {
      LibrarySort.nameAsc => name(a, b, false),
      LibrarySort.nameDesc => name(a, b, true),
      LibrarySort.createdDesc => byTime(
        createdAtOf(a.noteId),
        createdAtOf(b.noteId),
        true,
      ),
      LibrarySort.createdAsc => byTime(
        createdAtOf(a.noteId),
        createdAtOf(b.noteId),
        false,
      ),
      LibrarySort.editedDesc => byTime(a.editedAt, b.editedAt, true),
      LibrarySort.editedAsc => byTime(a.editedAt, b.editedAt, false),
    };
    return c != 0 || sort.name.startsWith('name')
        ? c
        : a.noteId.compareTo(b.noteId);
  }

  return [...entries]..sort(cmp);
}

String _title(LibraryEntry e) => e.note?.title ?? '';

String _label(AppLocalizations l, LibrarySort s) => switch (s) {
  LibrarySort.nameAsc => l.sortNameAsc,
  LibrarySort.nameDesc => l.sortNameDesc,
  LibrarySort.createdDesc => l.sortCreatedDesc,
  LibrarySort.createdAsc => l.sortCreatedAsc,
  LibrarySort.editedDesc => l.sortEditedDesc,
  LibrarySort.editedAsc => l.sortEditedAsc,
};

/// The drop-down right of the "Notes" header.
class LibrarySortMenu extends ConsumerWidget {
  const LibrarySortMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sort = ref.watch(librarySortProvider);
    return DropdownButtonHideUnderline(
      child: DropdownButton<LibrarySort>(
        key: const Key('sortMenu'),
        value: sort,
        isExpanded: true, // long labels ellipsize instead of overflowing
        isDense: false,
        alignment: AlignmentDirectional.centerEnd, // text hugs the right edge
        borderRadius: BorderRadius.circular(8),
        onChanged: (s) {
          if (s != null) ref.read(librarySortProvider.notifier).set(s);
        },
        items: [
          for (final s in LibrarySort.values)
            DropdownMenuItem(
              value: s,
              child: Text(_label(l, s), overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

String _sizeLabel(AppLocalizations l, LibrarySize s) => switch (s) {
  LibrarySize.small => l.viewSmall,
  LibrarySize.standard => l.viewStandard,
  LibrarySize.large => l.viewLarge,
};

/// "큰 리스트", "작은 그리드", ...
String libraryViewLabel(AppLocalizations l, LibraryView v) =>
    '${_sizeLabel(l, v.size)} ${v.layout == LibraryLayout.grid ? l.viewGrid : l.viewList}';

/// The view picker beside the sort drop-down: layout x size.
class LibraryViewMenu extends ConsumerWidget {
  const LibraryViewMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final view = ref.watch(libraryViewProvider);
    final current = libraryViewLabel(l, view);
    return Semantics(
      label: l.viewLabel,
      value: current,
      container: true,
      excludeSemantics: true,
      child: PopupMenuButton<LibraryView>(
        key: const Key('viewMenu'),
        tooltip: '${l.viewLabel}: $current',
        icon: Icon(
          view.layout == LibraryLayout.grid ? Icons.grid_view : Icons.view_list,
        ),
        initialValue: view,
        onSelected: ref.read(libraryViewProvider.notifier).set,
        itemBuilder: (_) => [
          for (final lay in LibraryLayout.values)
            for (final size in LibrarySize.values)
              PopupMenuItem(
                value: LibraryView(lay, size),
                child: Text(libraryViewLabel(l, LibraryView(lay, size))),
              ),
        ],
      ),
    );
  }
}
