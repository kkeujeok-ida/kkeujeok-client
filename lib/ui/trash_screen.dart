// Story 14.2: the app trash screen and the read-only view of a trashed note.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../library/trash_service.dart';
import '../model/note.dart';
import '../render/page_painter.dart';
import 'providers.dart';
import 'kk.dart';
import 'snack.dart';

/// Restores [e] and shows the snackbar; true when the item is back (or gone).
Future<bool> restoreTrashEntry(
  BuildContext context,
  WidgetRef ref,
  TrashEntry e,
) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Read before the await: the screen may be gone when the restore ends.
  final service = ref.read(trashServiceProvider);
  final tree = ref.read(folderTreeProvider.notifier);
  final receiver = ref.read(noteReceiverProvider);
  final coordinator = ref.read(uploadCoordinatorProvider);
  TrashOutcome r;
  try {
    r = await service.restore(e);
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
  // Folders and the receive pick up a restored item.
  unawaited(tree.refresh());
  // A restored note comes down as a new note; whatever it leaves unsent goes
  // up as soon as the receive is done (it showed "저장 대기" until a restart).
  unawaited(
    receiver
        .check()
        .catchError((_) {})
        .then((_) => e.isFolder ? null : coordinator.noteClosed(e.id))
        .catchError((_) {}),
  );
  return true;
}

/// A trashed note, read-only and from memory: downloaded by file id, never
/// stored (spec `trash` "No device copy"). No tools, no editing.
/// A page with a usable size; AspectRatio asserts on anything else.
bool _sized(Map<String, dynamic> p) {
  final w = p['width'], h = p['height'];
  return w is num && h is num && w > 0 && h > 0;
}

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
  void dispose() {
    for (final c in _caches.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _note = ref.read(trashServiceProvider).open(widget.entry);
  }

  Future<void> _restoreIt() async {
    if (_busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final ok = await restoreTrashEntry(context, ref, widget.entry);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.title, overflow: TextOverflow.ellipsis),
        actions: [
          // The notice is a compact chip in the brand color, as wide as it
          // needs to be, at the end of the title bar.
          Flexible(
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: KkjTokens.spacing3,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Kk.colorAccentSoft,
                    borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: KkjTokens.spacing3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            l.trashNoteBanner,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Kk.colorAccentText,
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Kk.colorAccentText,
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
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
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
                        if (_sized(page))
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
