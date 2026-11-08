import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kk.dart';

import 'package:flutter/semantics.dart'
    show Assertiveness, CustomSemanticsAction, SemanticsService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'snack.dart';

import '../design_tokens/build/tokens.dart';
import '../drive/root_folder.dart' show RootStatus;
import '../library/folder_service.dart' show FolderView, LibraryFolder;
import '../storage/note_store.dart' show NoteSaveException;
import '../storage/pdf_intake.dart' show PdfImportException, takeSharedPdf;
import 'folder_colors.dart';
import 'folder_picker_sheet.dart';
import 'folder_actions.dart';
import 'folder_sidebar.dart' show NameDialog, showConfirmDialog;
import '../l10n/app_localizations.dart';
import '../model/library_view.dart';
import '../model/note.dart';
import '../model/pdf_rules.dart' show isPdfBackground;
import '../render/page_painter.dart';
import '../render/pdf_pages.dart';
import '../sync/conflict_notifier.dart' show askConflictPermissionOnce;
import '../sync/note_receiver.dart';
import '../sync/receive_scheduler.dart';
import 'cannot_open_sheet.dart';
import 'cover_art.dart';
import 'library_fab.dart';
import 'library_sort.dart';
import 'new_note_sheet.dart';
import 'note_editor.dart';
import 'note_order.dart' show NoteArrival;
import 'pdf_import.dart';
import '../storage/hint_store.dart';
import 'handed_menu.dart';
import 'providers.dart';
import 'sync_banner.dart';
import 'sync_display.dart';
import 'sync_indicator.dart';

// View sizes are fractions of the cover column minimum (web uses the same).
const _gridFactor = {
  LibrarySize.small: 0.38,
  LibrarySize.standard: 0.8,
  LibrarySize.large: 1.2,
};
const _rowThumbFactor = {
  LibrarySize.small: 0.33,
  LibrarySize.standard: 0.5,
  LibrarySize.large: 1.0,
};

/// Every list is one note per row, thumbnail on the left.
bool _isRows(LibraryView v) => v.layout == LibraryLayout.list;

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
      _takeShared();
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
      _takeShared();
      ref.read(rootFolderProvider.notifier).checkForeground();
      unawaited(ref.read(folderTreeProvider.notifier).refresh());
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

  // Selection mode (Story 18.4): note ids picked by a long press.
  final _selected = <String>{};
  bool get _selecting => _selected.isNotEmpty;

  void _announceSelected() {
    if (!mounted) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        AppLocalizations.of(context).selectedCount(_selected.length),
        Directionality.of(context),
        assertiveness: Assertiveness.polite,
      ),
    );
  }

  void _toggleSelect(String id) {
    setState(
      () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
    );
    _announceSelected();
  }

  void _clearSelect() {
    if (_selected.isNotEmpty) setState(_selected.clear);
  }

  /// The selected notes that are still in the list.
  List<String> _selectedNow() {
    final here = {for (final e in ref.read(visibleEntriesProvider)) e.noteId};
    return [
      for (final id in _selected)
        if (here.contains(id)) id,
    ];
  }

  Future<void> _deleteSelected() => _guarded(() async {
    final ids = _selectedNow();
    if (ids.isEmpty) return;
    final l = AppLocalizations.of(context);
    final ok = await showConfirmDialog(
      context,
      body: l.notesDeleteBody(ids.length),
      confirm: l.noteDeleteConfirm,
    );
    if (!ok || !mounted) return;
    final coordinator = ref.read(uploadCoordinatorProvider);
    final notifier = ref.read(libraryProvider.notifier);
    for (final id in ids) {
      await coordinator.deleteNote(id);
    }
    if (!mounted) return;
    _clearSelect();
    notifier.reload();
  });

  Future<void> _moveSelected() => _guarded(() async {
    final ids = _selectedNow();
    if (ids.isEmpty) return;
    final l = AppLocalizations.of(context);
    final tree = ref.read(folderTreeProvider).value ?? const FolderView();
    final target = await showFolderPicker(
      context,
      title: l.notesMoveTitle(ids.length),
      view: tree,
      selected: null,
    );
    if (target == null || !mounted) return;
    await _moveNotesTo(ids, target);
  });

  /// Moves [ids] into [target] ('root' = Home); a snackbar offers [되돌리기].
  Future<void> _moveNotesTo(List<String> ids, String target) async {
    final l = AppLocalizations.of(context);
    final tree = ref.read(folderTreeProvider).value ?? const FolderView();
    final notifier = ref.read(folderTreeProvider.notifier);
    final inverses = <Map<String, Object?>>[];
    var failed = false;
    for (final id in ids) {
      final r = await notifier.moveNote(id, target);
      if (!r.ok) {
        failed = true;
      } else if (r.inverse != null) {
        inverses.add(r.inverse!);
      }
    }
    if (!mounted) return;
    _clearSelect();
    if (failed) return _snack(l.noteActionFailed);
    if (inverses.isEmpty) return;
    final name = target == 'root'
        ? l.folderTopLevel
        : tree.folder(target)!.name;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        appSnackBar(
          content: Text(l.notesMoved(ids.length, name)),
          action: SnackBarAction(
            label: l.undo,
            onPressed: () {
              for (final inv in inverses) {
                notifier.undo(inv);
              }
            },
          ),
        ),
      );
  }

  /// A note card was dropped on a folder card or `../`: the whole selection
  /// moves when the dragged note is part of it.
  Future<void> _dropNote(String id, String target) => _guarded(() async {
    final ids = _selected.contains(id) ? _selectedNow() : [id];
    await _moveNotesTo(ids, target);
  });

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
          builder: (_) =>
              NoteEditor(note: note, openResolveSheet: resolve, onHop: _hop),
        ),
      );

  /// Story 5.13: the editor moves to another note by replacing its route, so
  /// Back always lands on the library. The old route's `_afterEditor` runs
  /// when it is replaced; the new one gets its own for the last close.
  void _hop(Note to, bool resolve, int dir, NoteArrival? arrival) {
    if (!mounted) return;
    final route = PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => NoteEditor(
        note: to,
        openResolveSheet: resolve,
        arrival: arrival,
        onHop: _hop,
      ),
      transitionsBuilder: (ctx, anim, _, child) =>
          MediaQuery.disableAnimationsOf(ctx)
          ? FadeTransition(opacity: anim, child: child)
          : SlideTransition(
              position: Tween(
                begin: Offset(dir.toDouble(), 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
    );
    unawaited(_afterEditor(Navigator.of(context).pushReplacement(route), to));
  }

  /// Story 9.2: a PDF another app opened or shared waits until the library
  /// is here (so after sign-in), then is imported like a picked one.
  Future<void> _takeShared() async {
    if (_busy) return; // taken again when the open import or sheet ends
    try {
      final s = await takeSharedPdf();
      if (s != null && mounted) unawaited(_importPdf(s));
    } on PdfImportException {
      if (mounted) _snack(AppLocalizations.of(context).pdfErrUnreadable);
    }
  }

  Future<void> _importPdf([({String path, String name})? given]) async {
    await _guarded(() async {
      final file = given ?? await pickPdf();
      if (file == null || !mounted) return;
      final r = await showPdfImport(context, path: file.path, name: file.name);
      // A shared copy is ours to remove; a picked file is the picker's cache.
      if (given != null) {
        try {
          File(file.path).deleteSync();
        } catch (_) {}
      }
      if (!mounted) return;
      if (r is Note) {
        await _afterEditor(_push(r), r);
      } else if (r is String) {
        _snack(r);
      }
    });
    // A share that came in meanwhile was left waiting.
    if (mounted) unawaited(_takeShared());
  }

  Future<void> _newNote() => _guarded(() async {
    // A created note is already in the list; no reload needed.
    final note = await showNewNoteSheet(context);
    if (note != null && mounted) await _afterEditor(_push(note), note);
  });

  /// A card of a note with an unresolved conflict opens the editor with the
  /// resolve sheet already up (Story 3.21); the card's own badge state says
  /// so, no extra read.
  Future<void> _open(Note cached) => _guarded(() async {
    // The list may hold a note a receive has replaced since: open the disk's.
    final note =
        (await ref.read(noteStoreProvider).read(cached.noteId))?.note ?? cached;
    if (!mounted) return;
    await _afterEditor(
      _push(note, resolve: ref.read(noteSyncProvider(note.noteId)).hasConflict),
      note,
    );
  });

  Future<void> _openById(String noteId) => _guarded(() async {
    final note = (await ref.read(noteStoreProvider).read(noteId))?.note;
    if (note != null && mounted) await _afterEditor(_push(note), note);
  });

  void _noteAction(_NoteAction a, LibraryEntry e) {
    switch (a) {
      case _NoteAction.rename:
        _rename(e);
      case _NoteAction.move:
        _move(e);
      case _NoteAction.cover:
        _cover(e);
      case _NoteAction.delete:
        _delete(e.noteId);
    }
  }

  /// Story 7.7: new title in a dialog (empty is not accepted); the card and
  /// the Drive file name follow.
  Future<void> _rename(LibraryEntry e) => _guarded(() async {
    final l = AppLocalizations.of(context);
    final title = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
        title: l.noteRename,
        confirm: l.folderSave,
        initial: e.note!.title,
        label: l.noteTitle,
        tooLong: l.noteTitleTooLong,
      ),
    );
    if (title == null || !mounted) return;
    try {
      await ref.read(libraryProvider.notifier).rename(e.noteId, title);
    } on NoteSaveException {
      if (mounted) _snack(l.noteActionFailed);
    }
  });

  /// Story 7.3: pick a cover (or none); the card follows.
  Future<void> _cover(LibraryEntry e) => _guarded(() async {
    final pick = await showCoverSheet(context, selected: e.note!.coverId);
    if (pick == null || !mounted) return;
    try {
      await ref.read(libraryProvider.notifier).setCover(e.noteId, pick.id);
    } on NoteSaveException {
      if (mounted) _snack(AppLocalizations.of(context).noteActionFailed);
    }
  });

  /// Story 7.7: folder picker, then a snackbar with [되돌리기].
  Future<void> _move(LibraryEntry e) => _guarded(() async {
    final l = AppLocalizations.of(context);
    final tree = ref.read(folderTreeProvider).value ?? const FolderView();
    final target = await showFolderPicker(
      context,
      title: l.noteMoveTitle(e.note!.title),
      view: tree,
      selected: e.folderId ?? 'root',
    );
    if (target == null || !mounted) return;
    final r = await ref
        .read(folderTreeProvider.notifier)
        .moveNote(e.noteId, target);
    if (!mounted) return;
    if (!r.ok) return _snack(l.noteActionFailed);
    final inverse = r.inverse;
    if (inverse == null) return; // already there
    final name = target == 'root'
        ? l.folderTopLevel
        : tree.folder(target)!.name;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        appSnackBar(
          content: Text(l.noteMoved(name)),
          action: SnackBarAction(
            label: l.undo,
            onPressed: () =>
                ref.read(folderTreeProvider.notifier).undo(inverse),
          ),
        ),
      );
  });

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(appSnackBar(content: Text(text)));

  /// Story 7.7: asks in place, then hides the card at once; the upload of
  /// unsent changes and the Drive trash follow (offline: when connected).
  Future<void> _delete(String noteId) => _guarded(() async {
    final l = AppLocalizations.of(context);
    final ok = await showConfirmDialog(
      context,
      body: l.noteDeleteBody,
      confirm: l.noteDeleteConfirm,
    );
    if (!ok || !mounted) return;
    final coordinator = ref.read(uploadCoordinatorProvider);
    final notifier = ref.read(libraryProvider.notifier);
    await coordinator.deleteNote(noteId);
    if (mounted) notifier.reload();
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
    ref.listen(onlineProvider, (prev, on) {
      // The reconnect upload; folder changes made offline go up too.
      if (on && prev == false) {
        unawaited(ref.read(folderTreeProvider.notifier).refresh());
      }
    });
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
          ..showSnackBar(appSnackBar(content: Text(l10n.revivedSnack)));
      }
    });
    ref.listen(revivedNoticeProvider, (prev, next) {
      if (next > (prev ?? 0)) _snack(l10n.revivedSnack);
    });
    ref.listen(receiveStateProvider.select((r) => r.scanning), (_, next) {
      _watchScan(next);
    });
    final folder = ref.watch(effectiveFolderProvider);
    ref.listen(effectiveFolderProvider, (_, _) => _clearSelect());
    final tree = ref.watch(folderTreeProvider).value ?? const FolderView();
    final local = {
      for (final e in async.value ?? const <LibraryEntry>[]) e.noteId,
    };
    // Hidden (trashed) notes show nowhere; a folder shows only its notes.
    final remote = [
      for (final c in recv.cards)
        if (ref.watch(libraryQueryProvider).trim().isEmpty &&
            !local.contains(c.noteId) &&
            !tree.hiddenNotes.contains(c.noteId) &&
            (folder == null || (tree.noteFolder[c.noteId] ?? 'root') == folder))
          c,
    ];
    final view = ref.watch(libraryViewProvider);
    // Cards other than a note keep one thumbnail's width in a row list.
    Widget cap(Widget w) => _isRows(view)
        ? Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    KkjTokens.spacingCoverColumnMin *
                    _rowThumbFactor[view.size]!,
              ),
              child: w,
            ),
          )
        : w;
    final failed = async.hasError && !async.hasValue;
    final entries = ref.watch(visibleEntriesProvider);
    final query = ref.watch(libraryQueryProvider).trim();
    final sort = ref.watch(librarySortProvider);
    // Story 18.3: subfolders first (not while searching or in "모든 노트"),
    // after the `../` slot of a folder below the top level.
    final inFolder = folder != null && query.isEmpty;
    final subfolders = inFolder
        ? sortFolders(tree.childrenOf(folder), sort)
        : const <LibraryFolder>[];
    final up = inFolder && folder != 'root' ? tree.folder(folder) : null;
    final emptyFolder =
        !failed &&
        query.isEmpty &&
        async.hasValue &&
        entries.isEmpty &&
        remote.isEmpty &&
        subfolders.isEmpty &&
        !recv.scanning;
    // The first-note hint is gone for good once a note exists.
    if (async.hasValue &&
        entries.isNotEmpty &&
        ref.read(hintsProvider).contains(Hint.firstNote)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(hintsProvider.notifier).done(Hint.firstNote);
      });
    }
    final cards = <Widget>[
      if (up != null)
        cap(
          _ParentCard(
            canDrop: (_) => true,
            onDrop: (d) => d is LibraryFolder
                ? moveFolderTo(context, ref, d, up.parentId)
                : _dropNote((d as _NoteDrag).id, up.parentId),
            onOpen: () =>
                ref.read(currentFolderProvider.notifier).select(up.parentId),
          ),
        ),
      for (final f in subfolders)
        cap(
          _FolderCard(
            key: ValueKey('folder-card-${f.id}'),
            folder: f,
            onOpen: () => ref.read(currentFolderProvider.notifier).select(f.id),
            canDrop: (d) => d is LibraryFolder
                ? d.id != f.id && !tree.isInside(f.id, d.id)
                : d is _NoteDrag,
            onDrop: (d) => d is LibraryFolder
                ? moveFolderTo(context, ref, d, f.id)
                : _dropNote((d as _NoteDrag).id, f.id),
            onRename: () => renameFolderDialog(context, ref, f),
            onMove: () => moveFolderDialog(context, ref, f),
            onDelete: () => deleteFolderDialog(context, ref, f),
          ),
        ),
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
      else if (query.isNotEmpty && async.hasValue && entries.isEmpty)
        Padding(
          padding: const EdgeInsets.all(KkjTokens.spacing3),
          child: Text(
            l10n.searchNoResults(query),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        )
      else if (emptyFolder)
        cap(_NewNoteCard(onTap: _newNote)),
      if (_showScan && recv.scanning) ...[
        cap(const _ScanPlaceholder()),
        cap(const _ScanPlaceholder()),
      ],
      for (final c in remote)
        cap(
          _RemoteNoteCard(
            card: c,
            receiving: recv.receiving.contains(c.noteId),
          ),
        ),
      for (final e in entries)
        e.readable
            ? _DraggableNote(
                noteId: e.noteId,
                title: e.note!.title,
                onStart: () {
                  if (!_selected.contains(e.noteId)) _toggleSelect(e.noteId);
                },
                child: _NoteCard(
                  entry: e,
                  receiving: recv.receiving.contains(e.noteId),
                  selecting: _selecting,
                  selected: _selected.contains(e.noteId),
                  onTap: () =>
                      _selecting ? _toggleSelect(e.noteId) : _open(e.note!),
                  onLongPress: () => _selected.contains(e.noteId)
                      ? null
                      : _toggleSelect(e.noteId),
                  onAction: (a) => _noteAction(a, e),
                ),
              )
            : cap(_UnreadableCard(noteId: e.noteId)),
    ];

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelect();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SyncBanner(startInset: widget.headerStartInset),
                if (_selecting)
                  _SelectBar(
                    startInset: widget.headerStartInset,
                    count: _selected.length,
                    onCancel: _clearSelect,
                    onMove: _moveSelected,
                    onDelete: _deleteSelected,
                  )
                else
                  _SearchHeader(
                    startInset: widget.headerStartInset,
                    count: entries.length,
                    title: l10n.library,
                  ),
                if (root.status == RootStatus.preparing) const _Preparing(),
                if (emptyFolder && folder != null && folder != 'root')
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      widget.headerStartInset + KkjTokens.spacing3,
                      KkjTokens.spacing2,
                      KkjTokens.spacing3,
                      0,
                    ),
                    child: Text(
                      l10n.folderEmpty,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                if (emptyFolder &&
                    (folder == null || folder == 'root') &&
                    ref.watch(hintsProvider).contains(Hint.firstNote))
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      widget.headerStartInset + KkjTokens.spacing3,
                      KkjTokens.spacing2,
                      KkjTokens.spacing3,
                      0,
                    ),
                    child: Text(
                      l10n.hintFirstNote,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Kk.colorInkSecondary),
                    ),
                  ),
                Expanded(
                  child: GestureDetector(
                    // A tap on empty space ends the selection.
                    behavior: HitTestBehavior.translucent,
                    onTap: _selecting ? _clearSelect : null,
                    child: _Grid(view: view, children: cards),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: LibraryFab(
              onImportPdf: () => _importPdf(),
              onNewNote: _newNote,
              onNewFolder: () =>
                  createFolderDialog(context, ref, folder ?? 'root'),
            ),
          ),
          // Offline notice (UX-DR40): floats at the top right, so it neither
          // pushes nor covers the list.
          if (root.status == RootStatus.failed && root.errorClass == 'backoff')
            PositionedDirectional(
              top: MediaQuery.paddingOf(context).top + KkjTokens.spacing3,
              end: MediaQuery.paddingOf(context).right + KkjTokens.spacing3,
              child: DecoratedBox(
                key: const Key('offlineNotice'),
                decoration: BoxDecoration(
                  color: Kk.componentsBannerBackground,
                  borderRadius: BorderRadius.circular(
                    KkjLight.componentsCoverCardRounded,
                  ),
                  boxShadow: kkjShadow(Kk.componentsPopoverShadow),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(
                    KkjLight.componentsBannerPadding,
                  ),
                  child: _ErrorCard(
                    message: l10n.networkError,
                    inline: true,
                    onRetry: () =>
                        ref.read(rootFolderProvider.notifier).check(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rows of equal-width cards. Rows size to their content, so large text
/// never clips a card.
class _Grid extends StatelessWidget {
  const _Grid({required this.view, required this.children});

  final LibraryView view;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const edge = KkjTokens.spacing5;
    final grid = view.layout == LibraryLayout.grid;
    final gap = KkjTokens.spacing3;
    return LayoutBuilder(
      builder: (context, c) {
        final inner = c.maxWidth - 2 * edge;
        final min =
            KkjTokens.spacingCoverColumnMin *
            (grid ? _gridFactor[view.size]! : 1.0);
        final cols = grid
            ? math.max(1, ((inner + gap) / (min + gap)).floor())
            : 1;
        final lines = (children.length + cols - 1) ~/ cols;
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            edge,
            0,
            edge,
            KkjLight.componentsFabSize + 2 * KkjLight.componentsFabInset,
          ),
          itemCount: lines,
          itemBuilder: (context, r) => Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) SizedBox(width: gap),
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
  color: Kk.componentsCoverCardFallbackBackground,
  borderRadius: BorderRadius.circular(KkjLight.componentsCoverCardRounded),
  border: Border.all(color: border ?? Kk.componentsCoverCardFallbackBorder),
  boxShadow: border == null ? kkjShadow(Kk.componentsCoverCardShadow) : null,
);

/// The 3:4 thumbnail place: the first page, drawn by the same painter as the
/// writing screen, kept in its own proportions inside the card.
class _Thumb extends StatelessWidget {
  const _Thumb({this.page, this.disabled = false, this.child, this.coverFile});

  final Map<String, dynamic>? page;

  /// A known cover's file: drawn instead of the first page.
  final String? coverFile;
  final bool disabled;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final w = (page?['width'] as num?)?.toDouble();
    final h = (page?['height'] as num?)?.toDouble();
    if (child == null && coverFile != null) {
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              KkjLight.componentsCoverCardRounded,
            ),
            boxShadow: kkjShadow(Kk.componentsCoverCardShadow),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              KkjLight.componentsCoverCardRounded,
            ),
            child: CoverArt(coverFile!),
          ),
        ),
      );
    }
    if (child == null && w != null && h != null) {
      // Only the page, like the web library: no card frame or margin around it.
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: Center(
          child: AspectRatio(
            aspectRatio: w / h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Kk.componentsCoverCardFallbackBackground,
                borderRadius: BorderRadius.circular(
                  KkjLight.componentsCoverCardRounded,
                ),
                boxShadow: kkjShadow(Kk.componentsCoverCardShadow),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  KkjLight.componentsCoverCardRounded,
                ),
                child: _PageThumb(page: page!),
              ),
            ),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: DecoratedBox(
        decoration: _coverBox(border: disabled ? Kk.colorInkDisabled : null),
        child: child,
      ),
    );
  }
}

class _PageThumb extends ConsumerStatefulWidget {
  const _PageThumb({required this.page});

  final Map<String, dynamic> page;

  @override
  ConsumerState<_PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends ConsumerState<_PageThumb> {
  final _cache = StrokePathCache();
  PdfPages? _pdf;

  @override
  void initState() {
    super.initState();
    final bg = widget.page['background'];
    if (!isPdfBackground(bg)) return;
    // A PDF first page: the PDF is drawn under the strokes when it is already
    // on this device. The library never downloads it for a thumbnail.
    final store = ref.read(assetStoreProvider);
    final sync = ref.read(assetSyncProvider);
    _pdf = PdfPages(store, sync);
    final hash = '${(bg as Map)['asset']}';
    unawaited(
      store.pdfPath(hash).then((path) {
        if (path != null && mounted) sync.markLocal(hash);
      }),
    );
  }

  @override
  void dispose() {
    _pdf?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: PagePainter(
        page: widget.page,
        cache: _cache,
        pdf: _pdf,
        repaint: _pdf,
      ),
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
        Kk.componentsBadgeConflictBackground,
        Kk.componentsBadgeConflictText,
      ),
      SyncLabel.notSaved => (
        Kk.componentsBadgeErrorBackground,
        Kk.componentsBadgeErrorText,
      ),
      _ => (Kk.componentsBadgeNeutralBackground, Kk.componentsBadgeNeutralText),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
          if (date != null)
            Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

enum _NoteAction { rename, move, cover, delete }

class _NoteCard extends ConsumerStatefulWidget {
  const _NoteCard({
    required this.entry,
    required this.onTap,
    required this.onAction,
    this.receiving = false,
    this.selecting = false,
    this.selected = false,
    this.onLongPress,
  });

  final LibraryEntry entry;
  final VoidCallback onTap;

  /// Selection mode (Story 18.4): a long press starts it, a tap toggles.
  final bool selecting;
  final bool selected;
  final VoidCallback? onLongPress;
  final void Function(_NoteAction) onAction;
  final bool receiving;

  @override
  ConsumerState<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends ConsumerState<_NoteCard> {
  final _menu = GlobalKey<PopupMenuButtonState<_NoteAction>>();

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final receiving = widget.receiving;
    final onTap = widget.onTap;
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
    final view = ref.watch(libraryViewProvider);
    // An id the index does not know (or no index yet) stays a thumbnail.
    final coverId = note.coverId;
    final coverFile = coverId == null
        ? null
        : (ref.watch(coverIndexProvider).value ?? const [])
              .where((c) => c.id == coverId)
              .firstOrNull
              ?.file;
    final thumb = _CardThumb(
      thumb: _Thumb(
        page: note.pages.isEmpty ? null : note.pages.first,
        coverFile: coverFile,
      ),
      label: label,
    );
    final picked = Stack(
      children: [
        _DropFrame(highlight: widget.selected, child: thumb),
        if (widget.selecting)
          PositionedDirectional(
            top: KkjTokens.spacing2,
            start: KkjTokens.spacing2,
            child: Icon(
              widget.selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: widget.selected
                  ? theme.colorScheme.primary
                  : Kk.colorInkSecondary,
            ),
          ),
      ],
    );
    // The 48dp ⋯ button floats at the top end instead of sizing the title
    // row, so the title and date stay close; minHeight keeps the whole
    // button inside the card's hit-test bounds.
    final text = Stack(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
                if (date != null)
                  Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        PositionedDirectional(
          top: 0,
          end: 0,
          child: PopupMenuButton<_NoteAction>(
            key: _menu,
            offset: handedMenu(ref.watch(leftHandedProvider), 48).offset,
            constraints: handedMenu(
              ref.watch(leftHandedProvider),
              48,
            ).constraints,
            tooltip: l.moreMenu,
            icon: const Icon(Icons.more_horiz),
            onSelected: widget.onAction,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _NoteAction.rename,
                child: Text(l.noteRename),
              ),
              PopupMenuItem(value: _NoteAction.move, child: Text(l.noteMove)),
              PopupMenuItem(
                value: _NoteAction.cover,
                child: Text(l.noteChangeCover),
              ),
              PopupMenuItem(
                value: _NoteAction.delete,
                child: Text(l.noteDelete),
              ),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      selected: widget.selecting ? widget.selected : null,
      label: note.title,
      // "자료구조, 두 버전, 오늘": the state is part of the value; no date
      // text and no semantics date when unknown.
      value: [if (label != null) _badgeText(l, label), ?date].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: widget.onLongPress,
      customSemanticsActions: {
        CustomSemanticsAction(label: l.noteRename): () =>
            widget.onAction(_NoteAction.rename),
        CustomSemanticsAction(label: l.noteMove): () =>
            widget.onAction(_NoteAction.move),
        CustomSemanticsAction(label: l.noteChangeCover): () =>
            widget.onAction(_NoteAction.cover),
        CustomSemanticsAction(label: l.noteDelete): () =>
            widget.onAction(_NoteAction.delete),
      },
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          KkjLight.componentsCoverCardRounded,
        ),
        child: _isRows(view)
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width:
                        KkjTokens.spacingCoverColumnMin *
                        _rowThumbFactor[view.size]!,
                    child: picked,
                  ),
                  const SizedBox(width: KkjTokens.spacing3),
                  Expanded(child: text),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  picked,
                  const SizedBox(height: KkjTokens.spacing2),
                  text,
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
        ?.copyWith(color: Kk.colorInkDisabled);
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
              Icon(Icons.add, color: Kk.colorInkSecondary),
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

/// The header row (title, view picker, sort) with the title search folded
/// into an icon at its far right (Story 18.8). The icon opens a field that
/// grows leftwards over the row and takes focus; it stays open while the query
/// is not empty and folds on empty + blur or Back. The result count is
/// announced politely a moment after the last keystroke.
class _SearchHeader extends ConsumerStatefulWidget {
  const _SearchHeader({
    required this.startInset,
    required this.count,
    required this.title,
  });

  final double startInset;
  final int count;
  final String title;

  @override
  ConsumerState<_SearchHeader> createState() => _SearchHeaderState();
}

class _SearchHeaderState extends ConsumerState<_SearchHeader> {
  final _c = TextEditingController();
  final _focus = FocusNode(debugLabel: 'search');
  Timer? _timer;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _c.text = ref.read(libraryQueryProvider);
    _open = _c.text.isNotEmpty;
    _focus.addListener(() {
      if (!_focus.hasFocus && _c.text.isEmpty && _open && mounted) {
        setState(() => _open = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  void _announce() {
    if (!mounted || ref.read(libraryQueryProvider).trim().isEmpty) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        AppLocalizations.of(context).searchResultCount(widget.count),
        Directionality.of(context),
        assertiveness: Assertiveness.polite,
      ),
    );
  }

  void _changed(String v) {
    ref.read(libraryQueryProvider.notifier).set(v);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), _announce);
  }

  void _show() {
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _close() {
    _c.clear();
    _changed('');
    _focus.unfocus();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    const box = KkjTokens.spacingHitMinAndroid;
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: KkjTokens.spacing5 + widget.startInset,
          end: KkjTokens.spacing5,
          top: KkjTokens.spacing4,
          bottom: KkjTokens.spacing3,
        ),
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              // Under the open field: out of focus order and of TalkBack.
              ExcludeFocus(
                excluding: _open,
                child: ExcludeSemantics(
                  excluding: _open,
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            widget.title,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ),
                      const SizedBox(width: KkjTokens.spacing3),
                      // View picker and sort sit together left of the search
                      // icon; the title shrinks first.
                      const LibraryViewMenu(),
                      // At most 200, and never more than 60% of what the view
                      // picker leaves, so the title keeps some room.
                      SizedBox(
                        width: math.min(200, (c.maxWidth - 60 - box) * 0.6),
                        child: const LibrarySortMenu(),
                      ),
                      const SizedBox(width: box),
                    ],
                  ),
                ),
              ),
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: _open ? c.maxWidth : box,
                  color: _open ? theme.scaffoldBackgroundColor : null,
                  alignment: AlignmentDirectional.centerEnd,
                  child: _open
                      ? ClipRect(
                          child: OverflowBox(
                            alignment: AlignmentDirectional.centerEnd,
                            minWidth: 0,
                            maxWidth: c.maxWidth,
                            child: SizedBox(
                              width: c.maxWidth,
                              child: TextField(
                                key: const Key('searchField'),
                                controller: _c,
                                focusNode: _focus,
                                onChanged: _changed,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: l10n.searchHint,
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: IconButton(
                                    key: const Key('searchClear'),
                                    tooltip: l10n.searchClear,
                                    icon: const Icon(Icons.close),
                                    onPressed: _close,
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                        )
                      : IconButton(
                          key: const Key('searchOpen'),
                          tooltip: l10n.searchOpen,
                          constraints: const BoxConstraints(
                            minWidth: box,
                            minHeight: box,
                          ),
                          icon: const Icon(Icons.search),
                          onPressed: _show,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top bar of the selection mode: count, move, delete, cancel.
class _SelectBar extends StatelessWidget {
  const _SelectBar({
    required this.startInset,
    required this.count,
    required this.onCancel,
    required this.onMove,
    required this.onDelete,
  });

  final double startInset;
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: KkjTokens.spacing5 + startInset,
        end: KkjTokens.spacing5,
        top: KkjTokens.spacing4,
        bottom: KkjTokens.spacing3,
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('selectCancel'),
            tooltip: l10n.selectCancel,
            icon: const Icon(Icons.close),
            onPressed: onCancel,
          ),
          Expanded(
            child: Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                l10n.selectedCount(count),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          IconButton(
            key: const Key('selectMove'),
            tooltip: l10n.selectMove,
            icon: const Icon(Icons.drive_file_move_outlined),
            onPressed: onMove,
          ),
          IconButton(
            key: const Key('selectDelete'),
            tooltip: l10n.selectDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

enum _FolderAction { rename, move, color, delete }

/// A subfolder in the list (Story 18.3): tap enters; a long press drags it
/// onto another folder card or the `../` card; the ⋯ menu is the accessible
/// way to rename, move and delete.
class _FolderCard extends ConsumerWidget {
  const _FolderCard({
    super.key,
    required this.folder,
    required this.onOpen,
    required this.canDrop,
    required this.onDrop,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
  });

  final LibraryFolder folder;
  final VoidCallback onOpen;
  final bool Function(Object dragged) canDrop;
  final void Function(Object dragged) onDrop;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  Future<void> _pickColor(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final cur = ref.read(folderColorsProvider)[folder.id];
    final pick = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.folderColor),
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: KkjTokens.spacing2,
            runSpacing: KkjTokens.spacing2,
            children: [
              for (var i = 0; i < folderPalette.length; i++)
                Semantics(
                  button: true,
                  selected: cur == i,
                  label: l.folderColorOption(i + 1),
                  child: InkWell(
                    onTap: () => Navigator.of(ctx).pop(i),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(KkjTokens.spacing2),
                      child: Icon(
                        cur == i ? Icons.check_circle : Icons.folder,
                        size: 40,
                        color: folderPalette[i],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(-1),
            child: Text(l.folderColorDefault),
          ),
        ],
      ),
    );
    if (pick == null) return;
    ref
        .read(folderColorsProvider.notifier)
        .set(folder.id, pick < 0 ? null : pick);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colorIndex = ref.watch(folderColorsProvider)[folder.id];
    final face = DragTarget<Object>(
      onWillAcceptWithDetails: (d) => canDrop(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, hover, _) => _DropFrame(
        highlight: hover.isNotEmpty,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(
            KkjLight.componentsCoverCardRounded,
          ),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: LayoutBuilder(
              builder: (context, box) {
                final narrow = box.maxWidth < 120;
                return Stack(
                  children: [
                    _FolderFace(
                      icon: Icons.folder,
                      color: colorIndex == null
                          ? Kk.colorInkSecondary
                          : folderPalette[colorIndex % folderPalette.length],
                      label: folder.name,
                      maxLines: 2,
                    ),
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      // A small card keeps most of its face tappable: its button
                      // shrinks below 48dp (the actions are also semantic actions).
                      child: PopupMenuButton<_FolderAction>(
                        // `child` instead of `icon`: an icon button keeps a 48dp target.
                        // ignore: sort_child_properties_last
                        child: narrow
                            ? const SizedBox.square(
                                dimension: 28,
                                child: Icon(Icons.more_horiz, size: 16),
                              )
                            : null,
                        offset: handedMenu(
                          ref.watch(leftHandedProvider),
                          48,
                        ).offset,
                        constraints: handedMenu(
                          ref.watch(leftHandedProvider),
                          48,
                        ).constraints,
                        tooltip: l.folderMenu(folder.name),
                        icon: narrow ? null : const Icon(Icons.more_horiz),
                        onSelected: (a) => switch (a) {
                          _FolderAction.rename => onRename(),
                          _FolderAction.move => onMove(),
                          _FolderAction.delete => onDelete(),
                          _FolderAction.color => _pickColor(context, ref),
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: _FolderAction.rename,
                            child: Text(l.folderRename),
                          ),
                          PopupMenuItem(
                            value: _FolderAction.move,
                            child: Text(l.folderMove),
                          ),
                          PopupMenuItem(
                            value: _FolderAction.color,
                            child: Text(l.folderColor),
                          ),
                          PopupMenuItem(
                            value: _FolderAction.delete,
                            child: Text(l.folderDelete),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: folder.name,
      hint: l.folderOpenHint,
      excludeSemantics: true,
      onTap: onOpen,
      customSemanticsActions: {
        CustomSemanticsAction(label: l.folderRename): onRename,
        CustomSemanticsAction(label: l.folderMove): onMove,
        CustomSemanticsAction(label: l.folderColor): () =>
            _pickColor(context, ref),
        CustomSemanticsAction(label: l.folderDelete): onDelete,
      },
      child: LongPressDraggable<Object>(
        data: folder,
        feedback: Material(
          color: Colors.transparent,
          child: Chip(
            avatar: const Icon(Icons.folder_outlined),
            label: Text(folder.name),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: face),
        child: face,
      ),
    );
  }
}

/// Icon over a name, scaled to the card so it never overflows (small grids
/// are about 64 wide).
class _FolderFace extends StatelessWidget {
  const _FolderFace({
    required this.icon,
    required this.color,
    required this.label,
    required this.maxLines,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 64.0;
      final inner = math.max(0.0, w - 2 * KkjTokens.spacing2);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KkjTokens.spacing2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: inner,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: math.min(64.0, inner * 0.6), color: color),
                  const SizedBox(height: KkjTokens.spacing1),
                  Text(
                    label,
                    maxLines: maxLines,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The `../` card: note-thumbnail sized, first slot of a folder below the top
/// level. A tap goes up; a folder dropped on it moves up one level.
class _ParentCard extends StatelessWidget {
  const _ParentCard({
    required this.onOpen,
    required this.canDrop,
    required this.onDrop,
  });

  final VoidCallback onOpen;
  final bool Function(Object dragged) canDrop;
  final void Function(Object dragged) onDrop;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l.folderParentCard,
      excludeSemantics: true,
      onTap: onOpen,
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (d) => canDrop(d.data),
        onAcceptWithDetails: (d) => onDrop(d.data),
        builder: (context, hover, _) => _DropFrame(
          highlight: hover.isNotEmpty,
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(
              KkjLight.componentsCoverCardRounded,
            ),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                children: [
                  _FolderFace(
                    icon: Icons.folder_open,
                    color: Kk.colorInkSecondary,
                    label: '../',
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring around a card: a folder is dragged over it, or the note is picked.
class _DropFrame extends StatelessWidget {
  const _DropFrame({required this.highlight, required this.child});

  final bool highlight;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(KkjLight.componentsCoverCardRounded),
      border: highlight
          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
          : null,
    ),
    child: child,
  );
}

/// What a note card carries while dragged onto a folder card or `../`.
class _NoteDrag {
  const _NoteDrag(this.id);
  final String id;
}

/// A long press that moves starts a drag (and selects the note, so a long
/// press without a move is the selection gesture of Story 18.4).
class _DraggableNote extends StatelessWidget {
  const _DraggableNote({
    required this.noteId,
    required this.title,
    required this.onStart,
    required this.child,
  });

  final String noteId;
  final String title;
  final VoidCallback onStart;
  final Widget child;

  @override
  Widget build(BuildContext context) => LongPressDraggable<Object>(
    data: _NoteDrag(noteId),
    onDragStarted: onStart,
    feedback: Material(
      color: Colors.transparent,
      child: Chip(
        avatar: const Icon(Icons.description_outlined),
        label: Text(title),
      ),
    ),
    childWhenDragging: Opacity(opacity: 0.4, child: child),
    child: child,
  );
}
