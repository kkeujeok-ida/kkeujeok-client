part of 'library.dart';

/// The app trash drawn like a folder of the library (Story 23.2): the same
/// header (search, view, sort) and the same cards, with the sidebar kept.
/// Everything is Drive-only; a trashed note has no device copy.
class TrashView extends ConsumerStatefulWidget {
  const TrashView({super.key, this.headerStartInset = 0});

  final double headerStartInset;

  @override
  ConsumerState<TrashView> createState() => _TrashViewState();
}

class _TrashViewState extends ConsumerState<TrashView> {
  List<TrashEntry>? _entries;
  bool _failed = false;
  bool _busy = false;
  String? _purging; // entry id waiting for the second tap
  bool _confirmEmpty = false;

  @override
  void initState() {
    super.initState();
    // The search of the library does not carry over into the trash.
    Future.microtask(() {
      if (mounted) ref.read(libraryQueryProvider.notifier).set('');
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(trashServiceProvider).list();
      if (mounted) {
        setState(() {
          _entries = list;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = null;
          _failed = true;
        });
      }
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(appSnackBar(content: Text(text)));

  /// The item leaves the list at once; the Drive call follows. A failed call
  /// puts the list back by loading it again.
  Future<void> _guarded(
    Future<void> Function() body, {
    Set<String> hide = const {},
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _purging = null;
      _confirmEmpty = false;
      if (hide.isNotEmpty) {
        _entries = [
          for (final e in _entries ?? const <TrashEntry>[])
            if (!hide.contains(e.id)) e,
        ];
      }
    });
    try {
      await body();
    } catch (_) {
      if (mounted) _say(AppLocalizations.of(context).trashFailed);
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _restoreOne(TrashEntry e) =>
      _guarded(() async => restoreTrashEntry(context, ref, e), hide: {e.id});

  Future<void> _purge(TrashEntry e) => _guarded(() async {
    final r = await ref.read(trashServiceProvider).purge(e);
    if (r == TrashOutcome.failed && mounted) {
      _say(AppLocalizations.of(context).trashFailed);
    }
  }, hide: {e.id});

  Future<void> _empty() {
    final all = _entries ?? const <TrashEntry>[];
    return _guarded(() async {
      final left = await ref.read(trashServiceProvider).empty(all);
      if (left.isNotEmpty && mounted) {
        _say(AppLocalizations.of(context).trashFailed);
      }
    }, hide: {for (final e in all) e.id});
  }

  Future<void> _open(TrashEntry e) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TrashedNoteScreen(entry: e)),
    );
    if (mounted) await _load();
  }

  /// The search, then folders before notes, each in the order of the sort
  /// (name; the time sorts use the day of the delete).
  List<TrashEntry> _shown(String query, LibrarySort sort) {
    final q = libraryKey(libraryTrim(query));
    final list = [
      for (final e in _entries ?? const <TrashEntry>[])
        if (q.isEmpty || libraryKey(e.title).contains(q)) e,
    ];
    final desc =
        sort == LibrarySort.nameDesc ||
        sort == LibrarySort.createdDesc ||
        sort == LibrarySort.editedDesc;
    final byName = sort == LibrarySort.nameAsc || sort == LibrarySort.nameDesc;
    int cmp(TrashEntry a, TrashEntry b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      if (byName) {
        return libraryNameCompare(
          libraryKey(a.title),
          a.title,
          a.id,
          libraryKey(b.title),
          b.title,
          b.id,
          desc: desc,
        );
      }
      final c = a.trashedAt.compareTo(b.trashedAt);
      return c != 0 ? (desc ? -c : c) : a.id.compareTo(b.id);
    }

    return list..sort(cmp);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final view = ref.watch(libraryViewProvider);
    final query = ref.watch(libraryQueryProvider);
    final sort = ref.watch(librarySortProvider);
    final entries = _entries;
    final shown = _shown(query, sort);
    final Widget body;
    if (entries == null) {
      body = _failed
          ? _ErrorCard(message: l.trashFailed, onRetry: _load)
          : const Center(child: CircularProgressIndicator());
    } else if (entries.isEmpty) {
      body = Center(child: Text(l.trashEmpty));
    } else if (shown.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(KkjTokens.spacing3),
        child: Text(
          l.searchNoResults(query.trim()),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: _Grid(
          view: view,
          children: [
            for (final e in shown)
              _TrashCard(
                key: ValueKey(e.id),
                entry: e,
                confirmingPurge: _purging == e.id,
                busy: _busy,
                onOpen: e.isFolder ? null : () => _open(e),
                onRestore: () => _restoreOne(e),
                onPurgeStart: () => setState(() {
                  _purging = e.id;
                  _confirmEmpty = false;
                }),
                onPurgeCancel: () => setState(() => _purging = null),
                onPurge: () => _purge(e),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchHeader(
          startInset: widget.headerStartInset,
          count: shown.length,
          title: l.trash,
        ),
        if (entries != null && entries.isNotEmpty)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: KkjTokens.spacing5 + widget.headerStartInset,
              end: KkjTokens.spacing5,
              bottom: KkjTokens.spacing2,
            ),
            child: Row(
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : _confirmEmpty
                      ? _empty
                      : () => setState(() {
                          _confirmEmpty = true;
                          _purging = null;
                        }),
                  child: Text(
                    _confirmEmpty ? l.trashEmptyConfirm : l.trashEmptyAction,
                  ),
                ),
                if (_confirmEmpty)
                  IconButton(
                    tooltip: l.cancel,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _confirmEmpty = false),
                  ),
              ],
            ),
          ),
        Expanded(child: body),
      ],
    );
  }
}

/// A trashed note or folder, drawn like the library's cards: a thumbnail
/// place (no device copy, so an icon and the trash badge), the name and the
/// day of the delete, the ⋯ menu at the end.
class _TrashCard extends ConsumerWidget {
  const _TrashCard({
    super.key,
    required this.entry,
    required this.confirmingPurge,
    required this.busy,
    required this.onOpen,
    required this.onRestore,
    required this.onPurgeStart,
    required this.onPurgeCancel,
    required this.onPurge,
  });

  final TrashEntry entry;
  final bool confirmingPurge;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback onRestore;
  final VoidCallback onPurgeStart;
  final VoidCallback onPurgeCancel;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rows = _isRows(ref.watch(libraryViewProvider));
    final at = DateTime.tryParse(entry.trashedAt);
    final date = at == null
        ? ''
        : DateFormat.yMd(Localizations.localeOf(context).toString())
              .format(at.toLocal());
    final kind = entry.isFolder ? l.trashKindFolder : l.trashKindNote;
    final sub = entry.isFolder
        ? '${l.trashNotes(entry.noteCount)} · $date'
        : date;
    final Widget thumb = entry.isFolder
        ? AspectRatio(
            aspectRatio: 3 / 4,
            child: DecoratedBox(
              decoration: _coverBox(),
              child: _FolderFace(
                icon: Icons.folder,
                color: Kk.colorInkSecondary,
                label: entry.title,
                maxLines: 2,
                showLabel: !rows,
              ),
            ),
          )
        : _Thumb(
            child: Stack(
              children: [
                Center(
                  child: Icon(Icons.description, color: Kk.colorInkSecondary),
                ),
                PositionedDirectional(
                  bottom: KkjTokens.spacing1,
                  start: KkjTokens.spacing1,
                  child: Text(l.trash, style: theme.textTheme.labelSmall),
                ),
              ],
            ),
          );
    final menu = PopupMenuButton<bool>(
      offset: handedMenu(ref.watch(leftHandedProvider), 48).offset,
      constraints: handedMenu(ref.watch(leftHandedProvider), 48).constraints,
      tooltip: l.trashItemMenu(entry.title),
      enabled: !busy,
      icon: const Icon(Icons.more_horiz),
      onSelected: (restore) => restore ? onRestore() : onPurgeStart(),
      itemBuilder: (_) => [
        PopupMenuItem(value: true, child: Text(l.trashRestore)),
        PopupMenuItem(value: false, child: Text(l.trashPurge)),
      ],
    );
    final confirm = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
            ),
            onPressed: busy ? null : onPurge,
            child: Text(l.trashPurgeConfirm, textAlign: TextAlign.center),
          ),
        ),
        IconButton(
          tooltip: l.cancel,
          constraints: const BoxConstraints(
            minWidth: KkjTokens.spacingHitMinAndroid,
            minHeight: KkjTokens.spacingHitMinAndroid,
          ),
          icon: const Icon(Icons.close),
          onPressed: onPurgeCancel,
        ),
      ],
    );
    final text = confirmingPurge
        ? confirm
        : Stack(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 48),
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(top: 0, end: 0, child: menu),
            ],
          );
    return Semantics(
      container: true,
      label: l.trashItemSemantics(entry.title, kind, date),
      customSemanticsActions: {
        CustomSemanticsAction(label: l.trashRestore): onRestore,
        CustomSemanticsAction(label: l.trashPurge): onPurgeStart,
      },
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(
          KkjLight.componentsCoverCardRounded,
        ),
        child: rows
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width:
                        KkjTokens.spacingCoverColumnMin * _rowThumbWidth(ref),
                    child: ExcludeSemantics(child: thumb),
                  ),
                  const SizedBox(width: KkjTokens.spacing3),
                  Expanded(child: text),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(child: thumb),
                  const SizedBox(height: KkjTokens.spacing2),
                  text,
                ],
              ),
      ),
    );
  }
}
