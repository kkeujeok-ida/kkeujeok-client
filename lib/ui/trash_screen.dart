// Story 14.2: the app trash screen and the read-only view of a trashed note.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../library/trash_service.dart';
import '../model/note.dart';
import '../render/page_painter.dart';
import 'providers.dart';
import 'snack.dart';

String _date(BuildContext context, String iso) {
  final at = DateTime.tryParse(iso);
  return at == null
      ? ''
      : DateFormat.yMd(Localizations.localeOf(context).toString())
            .format(at.toLocal());
}

/// Tells the library the trash changed: folders and the receive pick up a
/// restored item.
void _refreshLibrary(WidgetRef ref) {
  unawaited(ref.read(folderTreeProvider.notifier).refresh());
  unawaited(ref.read(noteReceiverProvider).check().catchError((_) {}));
}

/// Restores [e] and shows the snackbar; true when the item is back (or gone).
Future<bool> _restore(BuildContext context, WidgetRef ref, TrashEntry e) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  TrashOutcome r;
  try {
    r = await ref.read(trashServiceProvider).restore(e);
  } catch (_) {
    r = TrashOutcome.failed;
  }
  final text = switch (r) {
    TrashOutcome.done => '${e.title} ${l.trashRestored}',
    TrashOutcome.rootFallback => l.trashRestoredRoot,
    TrashOutcome.gone => l.trashGone,
    TrashOutcome.failed => l.trashFailed,
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(appSnackBar(content: Text(text)));
  if (r == TrashOutcome.failed) return false;
  _refreshLibrary(ref);
  return true;
}

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  List<TrashEntry>? _entries;
  bool _failed = false;
  bool _busy = false;
  String? _purging; // entry id waiting for the second tap
  bool _confirmEmpty = false;

  @override
  void initState() {
    super.initState();
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
      if (mounted) setState(() => _failed = true);
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(appSnackBar(content: Text(text)));

  Future<void> _guarded(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _purging = null;
      _confirmEmpty = false;
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
      _guarded(() async => _restore(context, ref, e));

  Future<void> _purge(TrashEntry e) => _guarded(() async {
    final r = await ref.read(trashServiceProvider).purge(e);
    if (r == TrashOutcome.failed && mounted) {
      _say(AppLocalizations.of(context).trashFailed);
    }
  });

  Future<void> _empty() => _guarded(() async {
    final left = await ref.read(trashServiceProvider).empty(_entries ?? []);
    if (left.isNotEmpty && mounted) {
      _say(AppLocalizations.of(context).trashFailed);
    }
  });

  Future<void> _open(TrashEntry e) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TrashedNoteScreen(entry: e)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entries = _entries;
    final Widget body;
    if (entries == null) {
      body = _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.trashFailed),
                  TextButton(onPressed: _load, child: Text(l.retry)),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (entries.isEmpty) {
      body = Center(child: Text(l.trashEmpty));
    } else {
      body = ListView(
        children: [
          for (final e in entries)
            _TrashRow(
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
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.trash),
        actions: [
          if (entries != null && entries.isNotEmpty)
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
      body: SafeArea(child: body),
    );
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final date = _date(context, entry.trashedAt);
    final kind = entry.isFolder ? l.trashKindFolder : l.trashKindNote;
    final sub = entry.isFolder
        ? '${l.trashNotes(entry.noteCount)} · $date'
        : date;
    const hit = Size(0, KkjTokens.spacingHitMinAndroid);
    final Widget trailing = confirmingPurge
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: hit),
                onPressed: busy ? null : onPurge,
                child: Text(l.trashPurgeConfirm),
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
          )
        : PopupMenuButton<bool>(
            tooltip: l.trashItemMenu(entry.title),
            enabled: !busy,
            onSelected: (restore) => restore ? onRestore() : onPurgeStart(),
            itemBuilder: (_) => [
              PopupMenuItem(value: true, child: Text(l.trashRestore)),
              PopupMenuItem(value: false, child: Text(l.trashPurge)),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: KkjTokens.spacingHitMinAndroid,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KkjTokens.spacing4,
              vertical: KkjTokens.spacing2,
            ),
            child: Row(
              children: [
                // Cover card: the trashed note has no device copy, so no
                // thumbnail; the badge marks it as a trash item.
                ExcludeSemantics(
                  child: SizedBox(
                    width: KkjTokens.spacing7 * 1.5,
                    height: KkjTokens.spacing7 * 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          KkjTokens.roundedSm,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Icon(
                              entry.isFolder ? Icons.folder : Icons.description,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (!entry.isFolder)
                            PositionedDirectional(
                              bottom: KkjTokens.spacing1,
                              start: KkjTokens.spacing1,
                              child: Text(
                                l.trash,
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KkjTokens.spacing3),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
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
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A trashed note, read-only and from memory: downloaded by file id, never
/// stored (spec `trash` "No device copy"). No tools, no editing.
class TrashedNoteScreen extends ConsumerStatefulWidget {
  const TrashedNoteScreen({super.key, required this.entry});

  final TrashEntry entry;

  @override
  ConsumerState<TrashedNoteScreen> createState() => _TrashedNoteScreenState();
}

class _TrashedNoteScreenState extends ConsumerState<TrashedNoteScreen> {
  Future<NoteReadResult>? _note;
  final _caches = <String, StrokePathCache>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _note = ref.read(trashServiceProvider).open(widget.entry);
  }

  Future<void> _restoreIt() async {
    if (_busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final ok = await _restore(context, ref, widget.entry);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.title)),
      body: SafeArea(
        child: Column(
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: Material(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KkjTokens.spacing4,
                    vertical: KkjTokens.spacing2,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(l.trashNoteBanner)),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(
                            0,
                            KkjTokens.spacingHitMinAndroid,
                          ),
                        ),
                        onPressed: _busy ? null : _restoreIt,
                        child: Text(l.trashRestore),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<NoteReadResult>(
                future: _note,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final note = snap.data?.note;
                  if (snap.hasError || note == null) {
                    return Center(child: Text(l.trashCannotOpen));
                  }
                  return ListView(
                    padding: const EdgeInsets.all(KkjTokens.spacing4),
                    children: [
                      for (final page in note.pages)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: KkjTokens.spacing4,
                          ),
                          child: AspectRatio(
                            aspectRatio:
                                (page['width'] as num).toDouble() /
                                (page['height'] as num).toDouble(),
                            child: ClipRect(
                              child: CustomPaint(
                                painter: PagePainter(
                                  page: page,
                                  cache: _caches.putIfAbsent(
                                    '${page['id']}',
                                    StrokePathCache.new,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
