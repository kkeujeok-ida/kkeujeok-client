import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design_tokens/build/tokens.dart';
import '../drive/root_folder.dart' show RootStatus;
import '../l10n/app_localizations.dart';
import '../model/note.dart';
import '../render/page_painter.dart';
import '../sync/conflict_notifier.dart' show askConflictPermissionOnce;
import '../sync/note_receiver.dart';
import '../sync/receive_scheduler.dart';
import 'cannot_open_sheet.dart';
import 'library_fab.dart';
import 'library_sort.dart';
import 'new_note_sheet.dart';
import 'note_editor.dart';
import 'providers.dart';
import 'sync_banner.dart';
import 'sync_display.dart';
import 'sync_indicator.dart';

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

  // Remote changes: at root ready, on return to the foreground, every 20 s
  // while in the foreground (Story 3.13).
  late final ReceiveScheduler _receive = ReceiveScheduler(
    check: () => ref.read(noteReceiverProvider).check(),
  );
  Timer? _scanTimer;
  StreamSubscription<String>? _taps;
  bool _showScan = false; // the scan took longer than 1,000 ms

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _receive.resume();
    if (ref.read(receiveStateProvider).scanning) _watchScan(true);
    // A tap on the notification of a conflict opens that note (Story 3.19).
    final notifier = ref.read(conflictNotifierProvider);
    _taps = notifier.taps.listen(_openById, onError: (Object _) {});
    unawaited(
      notifier.launchNoteId().then((id) {
        if (id != null && mounted) _openById(id);
      }, onError: (Object _) {}),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(syncProblemsProvider).conflict) _askNotifyPermission();
      // Already known to be missing (an earlier library): ask at once.
      final status = ref.read(rootFolderProvider).status;
      if (status == RootStatus.missing) {
        _askMissing();
      } else {
        // `ref.listen` does not fire for a value that is already there: a
        // root that is ready at the first build opens the upload gate here.
        if (status == RootStatus.ready) {
          unawaited(ref.read(uploadCoordinatorProvider).rootReady());
          _receive.kick(force: true);
        }
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
    _receive.dispose();
    _scanTimer?.cancel();
    _taps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    libraryRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!mounted) return;
    final coordinator = ref.read(uploadCoordinatorProvider);
    if (s == AppLifecycleState.resumed) {
      ref.read(rootFolderProvider.notifier).checkForeground();
      unawaited(coordinator.foreground());
      _receive.resume();
      _receive.kick();
    } else if (s == AppLifecycleState.paused) {
      _receive.pause();
      unawaited(coordinator.appBackgrounded());
    }
  }

  /// The grey placeholder shows only when a scan lasts over 1,000 ms.
  void _watchScan(bool scanning) {
    _scanTimer?.cancel();
    if (scanning) {
      _scanTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) setState(() => _showScan = true);
      });
    } else if (_showScan && mounted) {
      setState(() => _showScan = false);
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

  Future<void> _push(Note note, {bool resolve = false}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NoteEditor(note: note, openResolveSheet: resolve),
        ),
      );

  Future<void> _newNote() => _guarded(() async {
    // A created note is already in the list; no reload needed.
    final note = await showNewNoteSheet(context);
    if (note != null && mounted) await _afterEditor(_push(note), note);
  });

  /// A card of a note with an unresolved conflict opens the editor with the
  /// resolve sheet already up (Story 3.21); the card's own badge state says
  /// so, no extra read.
  Future<void> _open(Note note) => _guarded(
    () => _afterEditor(
      _push(note, resolve: ref.read(noteSyncProvider(note.noteId)).hasConflict),
      note,
    ),
  );

  Future<void> _openById(String noteId) => _guarded(() async {
    final note = (await ref.read(noteStoreProvider).read(noteId))?.note;
    if (note != null && mounted) await _afterEditor(_push(note), note);
  });

  /// The first conflict shown in the foreground asks for the permission of
  /// the background notification, once (UX-DR66).
  void _askNotifyPermission() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    final l = AppLocalizations.of(context);
    unawaited(
      askConflictPermissionOnce(
        ref.read(conflictNotifierProvider),
        title: l.conflictNotificationTitle,
        channel: l.conflictNotificationChannel,
      ),
    );
  }

  /// The list is read again when the person comes back from the editor, and
  /// the closed note is uploaded (never blocking: not awaited).
  Future<void> _afterEditor(Future<void> route, Note note) async {
    await route;
    if (!mounted) return;
    ref.read(libraryProvider.notifier).reload();
    final id = note.noteId;
    final receiver = ref.read(noteReceiverProvider);
    final coordinator = ref.read(uploadCoordinatorProvider);
    // A note the editor showed as deleted elsewhere is removed (nothing
    // unsent) or restored (something unsent) before it is uploaded.
    unawaited(
      receiver
          .noteClosed(id)
          .catchError((_) {})
          .then((_) => coordinator.noteClosed(id))
          .then((_) {
            if (mounted) ref.read(libraryProvider.notifier).reload();
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(libraryProvider);
    final root = ref.watch(rootFolderProvider);
    ref.listen(rootFolderProvider, (prev, next) {
      if (next.status == RootStatus.missing) _askMissing();
      if (next.status == RootStatus.ready && prev?.status != RootStatus.ready) {
        // The upload gate just opened: app start recovery, then what waited.
        unawaited(ref.read(uploadCoordinatorProvider).rootReady());
        _receive.kick(force: true);
      }
    });
    ref.listen(onlineProvider, (_, _) {}); // the reconnect upload
    ref.listen(syncProblemsProvider.select((p) => p.conflict), (_, on) {
      if (on) _askNotifyPermission();
    });
    final recv = ref.watch(receiveStateProvider);
    ref.listen(receiveStateProvider.select((r) => r.version), (_, _) {
      ref.read(libraryProvider.notifier).reload();
    });
    ref.listen(receiveStateProvider.select((r) => r.revived), (prev, next) {
      if (next > (prev ?? 0)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.revivedSnack)));
      }
    });
    ref.listen(receiveStateProvider.select((r) => r.scanning), (_, next) {
      _watchScan(next);
    });
    final local = {
      for (final e in async.value ?? const <LibraryEntry>[]) e.noteId,
    };
    final remote = [
      for (final c in recv.cards)
        if (!local.contains(c.noteId)) c,
    ];
    final failed = async.hasError && !async.hasValue;
    final entries = sortEntries(
      async.value ?? const <LibraryEntry>[],
      ref.watch(librarySortProvider),
    );
    final cards = <Widget>[
      if (root.status == RootStatus.failed)
        ?switch (root.errorClass) {
          'reauth' => _ErrorCard(
            message: l10n.driveReauth,
            actionLabel: l10n.driveReauthAction,
            onRetry: () => ref.read(rootFolderProvider.notifier).signInAgain(),
          ),
          'backoff' => null, // the floating notice at the top right, below
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
      else if (async.hasValue &&
          entries.isEmpty &&
          remote.isEmpty &&
          !recv.scanning)
        _NewNoteCard(onTap: _newNote),
      if (_showScan && recv.scanning) ...const [
        _ScanPlaceholder(),
        _ScanPlaceholder(),
      ],
      for (final c in remote)
        _RemoteNoteCard(card: c, receiving: recv.receiving.contains(c.noteId)),
      for (final e in entries)
        e.readable
            ? _NoteCard(
                entry: e,
                receiving: recv.receiving.contains(e.noteId),
                onTap: () => _open(e.note!),
              )
            : _UnreadableCard(noteId: e.noteId),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SyncBanner(startInset: widget.headerStartInset),
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: KkjTokens.spacing5 + widget.headerStartInset,
                  end: KkjTokens.spacing5,
                  top: KkjTokens.spacing4,
                  bottom: KkjTokens.spacing3,
                ),
                child: Row(
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.library,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: KkjTokens.spacing3),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: const LibrarySortMenu(),
                      ),
                    ),
                  ],
                ),
              ),
              if (root.status == RootStatus.preparing) const _Preparing(),
              Expanded(child: _Grid(children: cards)),
            ],
          ),
        ),
        Positioned.fill(child: LibraryFab(onNewNote: _newNote)),
        // Offline notice (UX-DR40): floats at the top right, so it neither
        // pushes nor covers the list.
        if (root.status == RootStatus.failed && root.errorClass == 'backoff')
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + KkjTokens.spacing3,
            end: MediaQuery.paddingOf(context).right + KkjTokens.spacing3,
            child: DecoratedBox(
              key: const Key('offlineNotice'),
              decoration: BoxDecoration(
                color: KkjLight.componentsBannerBackground,
                borderRadius: BorderRadius.circular(
                  KkjLight.componentsCoverCardRounded,
                ),
                boxShadow: kkjShadow(KkjLight.componentsPopoverShadow),
              ),
              child: Padding(
                padding: const EdgeInsets.all(KkjLight.componentsBannerPadding),
                child: _ErrorCard(
                  message: l10n.networkError,
                  inline: true,
                  onRetry: () => ref.read(rootFolderProvider.notifier).check(),
                ),
              ),
            ),
          ),
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

/// The `badge` of a card whose note is not `synced`: icon and text, in the
/// badge colors of its state (UX-DR39).
class _SyncBadge extends StatelessWidget {
  const _SyncBadge(this.label);

  final SyncLabel label;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (bg, fg) = switch (label) {
      SyncLabel.twoVersions => (
        KkjLight.componentsBadgeConflictBackground,
        KkjLight.componentsBadgeConflictText,
      ),
      SyncLabel.notSaved => (
        KkjLight.componentsBadgeErrorBackground,
        KkjLight.componentsBadgeErrorText,
      ),
      _ => (
        KkjLight.componentsBadgeNeutralBackground,
        KkjLight.componentsBadgeNeutralText,
      ),
    };
    final style = TextStyle(
      fontFamily: KkjLight.componentsBadgeTextFontFamily,
      fontSize: KkjLight.componentsBadgeTextFontSize,
      fontWeight: KkjLight.componentsBadgeTextFontWeight,
      height:
          KkjLight.componentsBadgeTextLineHeight /
          KkjLight.componentsBadgeTextFontSize,
      color: fg,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KkjLight.componentsBadgeRounded),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkjTokens.spacing2,
          vertical: KkjTokens.spacing1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              syncIcon(label),
              size: KkjLight.componentsBadgeTextFontSize,
              color: fg,
            ),
            const SizedBox(width: KkjTokens.spacing1),
            Text(_badgeText(l, label), style: style),
          ],
        ),
      ),
    );
  }
}

String _badgeText(AppLocalizations l, SyncLabel s) => switch (s) {
  SyncLabel.receiving => l.receiving,
  SyncLabel.offline => l.syncBadgeOffline,
  _ => syncText(l, s),
};

/// A card thumbnail with the badge in its corner while [label] is set.
class _CardThumb extends StatelessWidget {
  const _CardThumb({required this.thumb, required this.label});

  final Widget thumb;
  final SyncLabel? label;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      thumb,
      if (label != null)
        PositionedDirectional(
          top: KkjTokens.spacing2,
          end: KkjTokens.spacing2,
          child: _SyncBadge(label!),
        ),
    ],
  );
}

/// The grey 3:4 place of a card while the tree is scanned.
class _ScanPlaceholder extends StatelessWidget {
  const _ScanPlaceholder();

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context).scanningNotes,
    excludeSemantics: true,
    child: const _Thumb(child: SizedBox.expand()),
  );
}

/// A note that exists on Drive but is not downloaded yet: the card is drawn
/// from its summary (title and date, no thumbnail).
class _RemoteNoteCard extends StatelessWidget {
  const _RemoteNoteCard({required this.card, required this.receiving});

  final RemoteCard card;
  final bool receiving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = card.modifiedAt == null
        ? null
        : DateTime.tryParse(card.modifiedAt!);
    final date = at == null
        ? null
        : DateFormat.yMd(Localizations.localeOf(context).toString())
              .format(at.toLocal());
    return Semantics(
      label: card.title,
      value: receiving ? AppLocalizations.of(context).receiving : date,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardThumb(
            thumb: const _Thumb(child: SizedBox.expand()),
            label: receiving ? SyncLabel.receiving : null,
          ),
          const SizedBox(height: KkjTokens.spacing2),
          Text(
            card.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
          if (date != null) Text(date, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({
    required this.entry,
    required this.onTap,
    this.receiving = false,
  });

  final LibraryEntry entry;
  final VoidCallback onTap;
  final bool receiving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final v = ref.watch(noteSyncProvider(entry.noteId));
    // `synced` has no badge; a note being received shows it at once.
    final label = receiving
        ? SyncLabel.receiving
        : (!v.loaded || v.label == SyncLabel.saved ? null : v.label);
    // The remote file cannot be read: the card is the "열 수 없음" one.
    if (v.unreadable) return _UnreadableCard(noteId: entry.noteId);
    final note = entry.note!;
    final at = entry.editedAt;
    final date = at == null
        ? null
        : DateFormat.yMd(Localizations.localeOf(context).toString())
              .format(at.toLocal());
    return Semantics(
      button: true,
      label: note.title,
      // "자료구조, 두 버전, 오늘": the state is part of the value; no date
      // text and no semantics date when unknown.
      value: [if (label != null) _badgeText(l, label), ?date].join(', '),
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
            _CardThumb(
              thumb: _Thumb(page: note.pages.isEmpty ? null : note.pages.first),
              label: label,
            ),
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
/// A tap opens the sheet that says what happened (Story 3.17).
class _UnreadableCard extends StatelessWidget {
  const _UnreadableCard({required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: KkjLight.colorInkDisabled);
    void open() => showCannotOpenSheet(context, noteId);
    return Semantics(
      label: l10n.cannotOpen,
      button: true,
      excludeSemantics: true,
      onTap: open,
      child: InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(
          KkjLight.componentsCoverCardRounded,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Thumb(disabled: true),
            const SizedBox(height: KkjTokens.spacing2),
            Text(l10n.cannotOpen, style: style),
          ],
        ),
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
    this.inline = false,
  });

  final String message;
  final String? actionLabel;

  /// Message and button side by side on one row.
  final bool inline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: inline
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: KkjTokens.spacing3),
                FilledButton(
                  onPressed: onRetry,
                  child: Text(actionLabel ?? l10n.retry),
                ),
              ],
            )
          : Column(
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
