import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
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

/// Kept for the run of the app only; every launch starts by name.
class LibrarySortNotifier extends Notifier<LibrarySort> {
  @override
  LibrarySort build() => LibrarySort.nameAsc;

  void set(LibrarySort s) => state = s;
}

final librarySortProvider = NotifierProvider<LibrarySortNotifier, LibrarySort>(
  LibrarySortNotifier.new,
);

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

  int cmp(LibraryEntry a, LibraryEntry b) {
    if (a.readable != b.readable) return a.readable ? -1 : 1;
    final c = switch (sort) {
      LibrarySort.nameAsc => _name(a).compareTo(_name(b)),
      LibrarySort.nameDesc => _name(b).compareTo(_name(a)),
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
    return c != 0 ? c : a.noteId.compareTo(b.noteId);
  }

  return [...entries]..sort(cmp);
}

String _name(LibraryEntry e) => (e.note?.title ?? '').toLowerCase();

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
