import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design_tokens/build/tokens.dart';
import '../drive/root_folder.dart' show RootStatus;
import '../l10n/app_localizations.dart';
import '../model/note.dart';
import '../render/page_painter.dart';
import 'library_fab.dart';
import 'new_note_sheet.dart';
import 'note_editor.dart';
import 'providers.dart';

const double _phoneMaxWidth = 600; // dp: below this the grid has 2 columns

/// The cover grid, its empty state and the round `+`.
class LibraryScreen extends ConsumerStatefulWidget {
  /// [headerStartInset] keeps the header clear of a button the shell floats
  /// at the top-left.
  const LibraryScreen({super.key, this.headerStartInset = 0});

  final double headerStartInset;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

/// Told by the app's navigator when a route over the library is popped, so
/// a deferred "root missing" question is asked then.
final libraryRouteObserver = RouteObserver<ModalRoute<void>>();

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver, RouteAware {
  bool _dialogOpen = false;
  bool _missingWaiting = false; // asked while another route was on top

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Already known to be missing (an earlier library): ask at once.
      if (ref.read(rootFolderProvider).status == RootStatus.missing) {
        _askMissing();
      } else {
        ref.read(rootFolderProvider.notifier).check();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !identical(route, _route)) {
      libraryRouteObserver.unsubscribe(this);
      _route = route;
      libraryRouteObserver.subscribe(this, route);
    }
  }

  ModalRoute<void>? _route;

  /// A route that covered the library (settings, a sheet, a dialog, the
  /// editor) was popped.
  @override
  void didPopNext() {
    if (!_missingWaiting) return;
    _missingWaiting = false;
    // The navigator is locked while it notifies: ask after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ref.read(rootFolderProvider).status == RootStatus.missing) {
        _askMissing();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    libraryRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && mounted) {
      ref.read(rootFolderProvider.notifier).checkForeground();
    }
  }

  /// The missing-root dialog: one at a time, only over the library (not
  /// over an open note), never after dispose.
  Future<void> _askMissing() async {
    if (!mounted || _dialogOpen) return;
    if (ModalRoute.of(context)?.isCurrent != true) {
      _missingWaiting = true;
      return;
    }
    _dialogOpen = true;
    try {
      final l10n = AppLocalizations.of(context);
      final choice = await showDialog<_MissingChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.rootMissingTitle),
          content: Text(l10n.rootMissingBody),
          actions: [
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(_MissingChoice.create),
              child: Text(l10n.rootMissingCreate),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_MissingChoice.later),
              child: Text(l10n.rootMissingLater),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_MissingChoice.signOut),
              child: Text(l10n.rootMissingSignOut),
            ),
          ],
        ),
      );
      if (!mounted) return;
      switch (choice) {
        case _MissingChoice.create:
          ref.read(rootFolderProvider.notifier).recreate();
        case _MissingChoice.signOut:
          ref.read(authProvider.notifier).signOut();
        case _MissingChoice.later || null:
          break; // asked again at the next foreground
      }
    } finally {
      _dialogOpen = false;
    }
  }

  // One sheet or editor route at a time: a second tap while one is opening
  // or open would stack another (and could create a duplicate note).
  bool _busy = false;

  Future<void> _guarded(Future<void> Function() body) async {
    if (_busy) return;
    _busy = true;
    try {
      await body();
    } finally {
      _busy = false;
    }
  }

  Future<void> _push(Note note) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => NoteEditor(note: note)));

  Future<void> _newNote() => _guarded(() async {
    // A created note is already in the list; no reload needed.
    final note = await showNewNoteSheet(context);
    if (note != null && mounted) await _afterEditor(_push(note));
  });

  Future<void> _open(Note note) => _guarded(() => _afterEditor(_push(note)));

  /// The list is read again when the person comes back from the editor.
  Future<void> _afterEditor(Future<void> route) async {
    await route;
    if (mounted) ref.read(libraryProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(libraryProvider);
    final root = ref.watch(rootFolderProvider);
    ref.listen(rootFolderProvider, (_, next) {
      if (next.status == RootStatus.missing) _askMissing();
    });
    final failed = async.hasError && !async.hasValue;
    final entries = async.value ?? const <LibraryEntry>[];
    final cards = <Widget>[
      if (root.status == RootStatus.failed)
        switch (root.errorClass) {
          'backoff' => _ErrorCard(
            message: l10n.networkError,
            onRetry: () => ref.read(rootFolderProvider.notifier).check(),
          ),
          'reauth' => _ErrorCard(
            message: l10n.driveReauth,
            actionLabel: l10n.driveReauthAction,
            onRetry: () => ref.read(rootFolderProvider.notifier).signInAgain(),
          ),
          _ => _ErrorCard(
            message: l10n.drivePrepareFailed,
            onRetry: () => ref.read(rootFolderProvider.notifier).check(),
          ),
        },
      if (failed)
        _ErrorCard(
          message: l10n.loadFailed,
          onRetry: () => ref.read(libraryProvider.notifier).reload(),
        )
      else if (async.hasValue && entries.isEmpty)
        _NewNoteCard(onTap: _newNote),
      for (final e in entries)
        e.readable
            ? _NoteCard(entry: e, onTap: () => _open(e.note!))
            : const _UnreadableCard(),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: KkjTokens.spacing5 + widget.headerStartInset,
                  end: KkjTokens.spacing5,
                  top: KkjTokens.spacing4,
                  bottom: KkjTokens.spacing3,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.library,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              if (root.status == RootStatus.preparing) const _Preparing(),
              Expanded(child: _Grid(children: cards)),
            ],
          ),
        ),
        Positioned.fill(child: LibraryFab(onNewNote: _newNote)),
      ],
    );
  }
}

/// Rows of equal-width cards. Rows size to their content, so large text
/// never clips a card.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const gap = KkjTokens.spacing5;
    return LayoutBuilder(
      builder: (context, c) {
        final inner = c.maxWidth - 2 * gap;
        final cols = c.maxWidth < _phoneMaxWidth
            ? 2
            : math.max(
                2,
                ((inner + gap) / (KkjTokens.spacingCoverColumnMin + gap))
                    .floor(),
              );
        final rows = (children.length + cols - 1) ~/ cols;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            gap,
            0,
            gap,
            KkjLight.componentsFabSize + 2 * KkjLight.componentsFabInset,
          ),
          itemCount: rows,
          itemBuilder: (context, r) => Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(
                    child: r * cols + i < children.length
                        ? children[r * cols + i]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

BoxDecoration _coverBox({Color? border}) => BoxDecoration(
  color: KkjLight.componentsCoverCardFallbackBackground,
  borderRadius: BorderRadius.circular(KkjLight.componentsCoverCardRounded),
  border: Border.all(
    color: border ?? KkjLight.componentsCoverCardFallbackBorder,
  ),
  boxShadow: border == null
      ? kkjShadow(KkjLight.componentsCoverCardShadow)
      : null,
);

/// The 3:4 thumbnail place: the first page, drawn by the same painter as the
/// writing screen, kept in its own proportions inside the card.
class _Thumb extends StatelessWidget {
  const _Thumb({this.page, this.disabled = false, this.child});

  final Map<String, dynamic>? page;
  final bool disabled;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final w = (page?['width'] as num?)?.toDouble();
    final h = (page?['height'] as num?)?.toDouble();
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: DecoratedBox(
        decoration: _coverBox(
          border: disabled ? KkjLight.colorInkDisabled : null,
        ),
        child:
            child ??
            (w == null || h == null
                ? null
                : Padding(
                    padding: const EdgeInsets.all(KkjTokens.spacing2),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: w / h,
                        child: DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: KkjLight.componentsCoverCardFallbackBorder,
                            ),
                          ),
                          child: _PageThumb(page: page!),
                        ),
                      ),
                    ),
                  )),
      ),
    );
  }
}

class _PageThumb extends StatefulWidget {
  const _PageThumb({required this.page});

  final Map<String, dynamic> page;

  @override
  State<_PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends State<_PageThumb> {
  final _cache = StrokePathCache();

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: PagePainter(page: widget.page, cache: _cache),
    ),
  );
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.entry, required this.onTap});

  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = entry.note!;
    final at = entry.editedAt;
    final date = at == null
        ? null
        : DateFormat.yMd(Localizations.localeOf(context).toString())
              .format(at.toLocal());
    return Semantics(
      button: true,
      label: note.title,
      value: date, // no date text and no semantics date when unknown
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          KkjLight.componentsCoverCardRounded,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Thumb(page: note.pages.isEmpty ? null : note.pages.first),
            const SizedBox(height: KkjTokens.spacing2),
            Text(
              note.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
            if (date != null) Text(date, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// A note this client cannot read: shown dimmed, never opened or touched.
class _UnreadableCard extends StatelessWidget {
  const _UnreadableCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: KkjLight.colorInkDisabled);
    return Semantics(
      label: l10n.cannotOpen,
      enabled: false,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Thumb(disabled: true),
          const SizedBox(height: KkjTokens.spacing2),
          Text(l10n.cannotOpen, style: style),
        ],
      ),
    );
  }
}

/// The empty library's single card: opens the new-note sheet.
class _NewNoteCard extends StatelessWidget {
  const _NewNoteCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = Theme.of(context).textTheme.labelMedium;
    return Semantics(
      button: true,
      label: l10n.newNote,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          KkjLight.componentsCoverCardRounded,
        ),
        child: _Thumb(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, color: KkjLight.colorInkSecondary),
              const SizedBox(height: KkjTokens.spacing2),
              Text(l10n.newNote, style: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the empty-library card when the folder could not be
/// listed.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    this.actionLabel,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: KkjTokens.spacing3),
          FilledButton(
            onPressed: onRetry,
            child: Text(actionLabel ?? l10n.retry),
          ),
        ],
      ),
    );
  }
}

enum _MissingChoice { create, later, signOut }

/// "Drive 준비 중" under the header while the root folder is being prepared.
class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).drivePreparing;
    return Semantics(
      liveRegion: true,
      container: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkjTokens.spacing5,
          vertical: KkjTokens.spacing2,
        ),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: KkjTokens.spacing4,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: KkjTokens.spacing3),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
