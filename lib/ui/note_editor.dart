import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/ids.dart';
import '../model/note.dart';
import '../model/pen.dart';
import '../ops/history.dart';
import '../ops/ops.dart';
import '../ops/resolve_conflict.dart';
import '../render/page_painter.dart';
import '../render/zoom_snap.dart';
import '../sync/merge_step.dart';
import '../sync/version_history.dart' show RestoreFailure;
import 'conflict_sheet.dart';
import 'pen_toolbar.dart';
import 'providers.dart';
import 'sync_banner.dart';
import 'sync_display.dart';
import 'sync_indicator.dart';
import 'version_history.dart';

/// The writing screen: page, toolbar and the top-left `editor-corner`.
/// Input goes through `History.doOp(addStroke)`; every stroke is saved
/// through one serial queue.
class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({
    super.key,
    required this.note,
    this.openResolveSheet = false,
  });

  final Note note;

  /// The library card of a conflicted note opens the resolve sheet at once.
  final bool openResolveSheet;

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

// Toolbar height: block padding twice plus one 48 dp hit area.
const double _toolbarHeight =
    2 * KkjLight.componentsToolbarPaddingBlock +
    KkjLight.componentsPenSlotHitSize;

/// Who owns the touches right now. The first input keeps them until every
/// contact is up; a stylus/mouse is the one exception and takes over.
enum _Mode { none, touchStroke, touchIdle, gesture, ignored, pen }

/// True once a stylus has been seen (hover or contact) in this app run: from
/// then on a finger never draws, it only pinches and pans. A device that has a
/// pen is a pen device; fingers and palms must not leave ink next to it.
bool _stylusSeen = false;

@visibleForTesting
void resetStylusSeen() => _stylusSeen = false;

/// What the view does when the screen size changes.
enum _Fit { width, page, free }

// A second finger this soon after the first turns the stroke into a gesture.
const _secondFinger = Duration(milliseconds: 150);
const _zoomStep = 1.25;

class _NoteEditorState extends ConsumerState<NoteEditor>
    with SingleTickerProviderStateMixin {
  late final History _history = _sessionHistory();
  late final _store = ref.read(noteStoreProvider);
  late final _openNote = ref.read(openNoteProvider);
  late final _coordinator = ref.read(uploadCoordinatorProvider);
  late final _hosts = ref.read(mergeHostsProvider);
  late final MergeHost _host = _applyMerge;

  /// `lastSeenRemoteSeq` of `sync.json` (spec `merge.seqAfterMerge`): the
  /// next operation takes `max(page.seq, this) + 1`.
  int _lastSeen = 0;
  // One outline cache per page: a shared one would drop the other pages'.
  final _caches = <String, StrokePathCache>{};
  final _tick = ValueNotifier<int>(0);

  // Saves coalesce: at most one write runs, and only the newest snapshot
  // waits behind it. [_failed] is the snapshot the last write could not save.
  Future<void>? _running;
  Note? _latest;
  Note? _failed;
  bool _leaving = false;

  int? _pointer; // the one pointer that is drawing
  // The page the stroke in progress belongs to and that page's top-left in
  // document coordinates (strokes use the touched page's coordinates).
  String? _strokePageId;
  Offset _origin = Offset.zero;
  // Completed when the stroke in progress ends (value: its page id), so a
  // merge waits for it and the finished stroke is in the sidecar (Story 3.19).
  Completer<String?>? _strokeDone;
  // The pre-merge version of a page whose stroke was in progress when a
  // conflict locked it: shown, never saved, gone with the editor.
  Map<String, dynamic>? _held;
  // A write on a locked page: the banner stressed for a moment, and the
  // assertive notice at most once a second.
  bool _emphasis = false;
  Timer? _emphasisTimer;
  DateTime? _announcedAt;
  Duration _t0 = Duration.zero;
  final _points = <List<num>>[];
  PageViewport? _vp;
  // The scale badge at the top right: whole percent, null when hidden.
  final _zoomBadge = ValueNotifier<int?>(null);
  Timer? _zoomBadgeTimer;
  _Fit _fit = _Fit.width;
  Size _size = Size.zero;
  EdgeInsets _padding = EdgeInsets.zero;

  _Mode _mode = _Mode.none;
  final _touches = <int, Offset>{}; // every touch down, by pointer
  int _firstId = -1, _gA = -1, _gB = -1;
  Duration _firstDown = Duration.zero;
  double _s0 = 1, _d0 = 1;
  Offset _p0 = Offset.zero; // page point under the fingers' center at start

  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(_animate);
  PageViewport? _from, _to;

  final _slotFocus = FocusNode();
  final _canvasFocus = FocusNode();
  bool _sheetOpen = false;

  Pen get _pen => ref.read(penSlotsProvider).first;

  /// Opens the pen popover; not while a stroke or a gesture is going on.
  Future<void> _editPen() async {
    if (_leaving || _pointer != null || _mode != _Mode.none) return;
    await showDialog<void>(
      context: context,
      builder: (_) => const PenEditDialog(),
    );
    if (mounted) _slotFocus.requestFocus();
  }

  /// The session's history for this note, unless the saved note differs
  /// from it in any way (a failed save, another edit): then start fresh
  /// rather than undo into state that is not on disk.
  History _sessionHistory() {
    final map = ref.read(noteHistoriesProvider);
    final id = widget.note.noteId;
    final h = map[id];
    if (h != null && _same(h.note.copyJson(), widget.note.copyJson())) {
      h.note = widget.note;
      return h;
    }
    return map[id] = History(widget.note);
  }

  static bool _same(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          Iterable<int>.generate(a.length).every((i) => _same(a[i], b[i]));
    }
    return a == b;
  }

  Ctx _ctx() => Ctx(
    rev: newId(),
    now: canonicalNow(DateTime.now()),
    editedBy: deviceEditedBy,
    lastSeenRemoteSeq: _lastSeen,
  );

  /// Queues the history's current note for saving.
  void _commit() {
    _latest = _history.note;
    _running ??= _drain().whenComplete(() => _running = null);
  }

  void _undo() => _replay(true);
  void _redo() => _replay(false);

  void _replay(bool undo) {
    if (!mounted || _pointer != null || _leaving || _readOnly) return;
    if (_pageLocked) {
      _blocked();
      return;
    }
    final depth = undo ? _history.undoDepth : _history.redoDepth;
    if (depth == 0) return;
    final err = undo ? _history.undo(_ctx()) : _history.redo(_ctx());
    if (err != null) {
      _snack(AppLocalizations.of(context).historyNotApplied);
      return;
    }
    setState(() {});
    _tick.value++;
    _commit();
  }

  bool get _pageLocked => _history.isLocked(_page?['id'] as String?);

  /// Resolves when no stroke is in progress; the value is the page id of the
  /// stroke that just ended, else null.
  Future<String?> _strokeEnd() => _pointer == null
      ? Future<String?>.value()
      : (_strokeDone ??= Completer<String?>()).future;

  void _strokeEnded(String? pageId) {
    final c = _strokeDone;
    _strokeDone = null;
    c?.complete(pageId);
  }

  /// Makes exactly the pages of [ids] that the note still has read-only (a
  /// resolved page is editable again); a stroke in progress is let to end
  /// first.
  void _lockWhenIdle(Set<String> ids) {
    if (_pointer != null) {
      unawaited(_strokeEnd().then((_) => _lockWhenIdle(ids)));
      return;
    }
    final here = {for (final p in _history.note.pages) p['id'] as String};
    final set = ids.where(here.contains).toSet();
    if (_history.sameLocks(set)) return;
    _history.setLocks(set);
    if (mounted) setState(() {});
  }

  /// A write on a locked page was refused: stress the banner once and say so.
  void _blocked() {
    if (!mounted) return;
    if (!_emphasis && !MediaQuery.disableAnimationsOf(context)) {
      setState(() => _emphasis = true);
      _emphasisTimer?.cancel();
      _emphasisTimer = Timer(const Duration(milliseconds: 800), () {
        _emphasisTimer = null;
        if (mounted) setState(() => _emphasis = false);
      });
    }
    final now = DateTime.now();
    final last = _announcedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _announcedAt = now;
    _announce(AppLocalizations.of(context).conflictReadOnlyBlocked);
  }

  void _announce(String text, {bool polite = false}) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        text,
        Directionality.of(context),
        assertiveness: polite ? Assertiveness.polite : Assertiveness.assertive,
      ),
    );
  }

  /// A conflict that showed up while the editor is open.
  void _announceConflict(ConflictInfo c) {
    final l = AppLocalizations.of(context);
    _announce(
      c.kind == 'remoteDeleted'
          ? l.conflictFoundDeleted(c.index + 1)
          : l.conflictFound(c.index + 1),
    );
  }

  // Pages sit one under the other in document coordinates, centered on the
  // widest, with this gap (page units) between them. A one-page note is the
  // document itself, as before.
  static const _pageGap = 24.0;

  List<Map<String, dynamic>> get _pages => _history.note.pages;

  ({List<Rect> rects, double w, double h}) _geometry() {
    final pages = _pages;
    var w = 0.0, y = 0.0;
    final sizes = [
      for (final p in pages)
        ((p['width'] as num).toDouble(), (p['height'] as num).toDouble()),
    ];
    for (final (pw, _) in sizes) {
      if (pw > w) w = pw;
    }
    final rects = <Rect>[];
    for (final (pw, ph) in sizes) {
      rects.add(Rect.fromLTWH((w - pw) / 2, y, pw, ph));
      y += ph + _pageGap;
    }
    return (rects: rects, w: w, h: sizes.isEmpty ? 0 : y - _pageGap);
  }

  /// The page nearest the middle of what is on screen: the one that undo,
  /// the read-only mark and "fit page" talk about.
  int _activeIndex() {
    final n = _pages.length;
    final vp = _vp;
    if (n < 2 || vp == null) return 0;
    final mid = vp.toPage(
      Offset(
        _size.width / 2,
        _padding.top + (_size.height - _padding.vertical) / 2,
      ),
    );
    final rects = _geometry().rects;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < n; i++) {
      final r = rects[i];
      final d = mid.dy < r.top
          ? r.top - mid.dy
          : mid.dy > r.bottom
          ? mid.dy - r.bottom
          : 0.0;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  Map<String, dynamic>? get _page {
    final pages = _pages;
    return pages.isEmpty ? null : pages[_activeIndex()];
  }

  /// Index of the page under a document point; -1 between or outside pages.
  int _pageAt(Offset doc) {
    final rects = _geometry().rects;
    for (var i = 0; i < rects.length; i++) {
      if (_inRect(rects[i], doc)) return i;
    }
    return -1;
  }

  // The edges count as inside, as they always did.
  static bool _inRect(Rect r, Offset p) =>
      p.dx >= r.left && p.dy >= r.top && p.dx <= r.right && p.dy <= r.bottom;

  @override
  void initState() {
    super.initState();
    // No upload of this note while it is open; a background upload asks the
    // queue to reach the disk first.
    _openNote.set(widget.note.noteId);
    _coordinator.flushOpen = _flush;
    // A sync result for this note is merged into this queue and history.
    _hosts.register(widget.note.noteId, _host);
    _loadLastSeen();
    // Asks Drive whether the note is current (not awaited: never blocks
    // opening).
    unawaited(ref.read(noteReceiverProvider).noteOpened(widget.note.noteId));
    if (_receiving) _watchReceiving(true);
    if (widget.openResolveSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSheet());
    }
  }

  Timer? _latestTimer;
  bool _showLatest = false; // received for over 1,000 ms

  void _watchReceiving(bool on) {
    _latestTimer?.cancel();
    if (on) {
      _latestTimer = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) setState(() => _showLatest = true);
      });
    } else if (_showLatest && mounted) {
      setState(() => _showLatest = false);
    }
  }

  bool get _receiving =>
      ref.read(receiveStateProvider).receiving.contains(widget.note.noteId);

  /// The note was made in a newer format: shown, never edited (Story 3.17).
  bool get _readOnly =>
      ref.read(noteSyncProvider(widget.note.noteId)).newVersion;

  /// `lastSeenRemoteSeq` is taken; the answer is the page ids with an
  /// unresolved conflict, or null when `sync.json` could not be read (the
  /// locks then stay as they are).
  Future<Set<String>?> _readSync() async {
    try {
      final s = await _store.readSync(widget.note.noteId);
      if (s.info.lastSeenRemoteSeq > _lastSeen) {
        _lastSeen = s.info.lastSeenRemoteSeq;
      }
      return {
        for (final c in s.info.unresolvedConflicts) c['pageId'] as String,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadLastSeen() async {
    final locked = await _readSync();
    if (mounted && locked != null) _lockWhenIdle(locked);
  }

  // ---- conflict resolve sheet (Story 3.21) ------------------------------

  /// When the other device's version was uploaded: the newest revision of
  /// the Drive file while online; null otherwise (the page's `editedAt`
  /// stands in).
  // shortcut: the head revision, not the one that holds the page; fix when
  // the revision id of "theirs" is recorded at merge.
  Future<DateTime?> _otherTime(String? fileId) async {
    if (fileId == null || !ref.read(uploadsAllowedProvider)) return null;
    try {
      final online = await ref
          .read(networkProbeProvider)()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!online) return null;
      final revs = await ref
          .read(driveClientProvider)
          .listRevisions(fileId)
          .timeout(const Duration(seconds: 3));
      DateTime? latest;
      for (final r in revs) {
        final t = DateTime.tryParse(r.modifiedTime);
        if (t != null && (latest == null || t.isAfter(latest))) latest = t;
      }
      return latest?.toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<List<ConflictItem>> _conflictItems() async {
    final id = widget.note.noteId;
    final s = await _store.readSync(id);
    final time = s.info.unresolvedConflicts.isEmpty
        ? null
        : await _otherTime(s.info.fileId);
    final items = <ConflictItem>[];
    for (final c in s.info.unresolvedConflicts) {
      try {
        final sc = await _store.readSidecar(
          id,
          c['pageId'] as String,
          c['rev'] as String,
        );
        if (sc == null || sc['page'] is! Map) continue; // nothing to compare
        final current = _pages.where((p) => p['id'] == c['pageId']).firstOrNull;
        // The page must be there unless the other device deleted it.
        if (current == null && c['kind'] != 'remoteDeleted') continue;
        items.add(
          ConflictItem(
            entry: c,
            sidecar: sc,
            current: current,
            otherTime: time,
          ),
        );
      } catch (_) {
        // A damaged entry is skipped; the others can still be settled.
      }
    }
    return items;
  }

  /// [해결하기] and the library card: the sheet over the unresolved conflicts.
  Future<void> _openSheet() async {
    if (_sheetOpen || _leaving || !mounted) return;
    _sheetOpen = true;
    try {
      var items = <ConflictItem>[];
      try {
        items = await _conflictItems();
      } catch (_) {}
      if (!mounted) return;
      if (items.isEmpty) {
        _snack(AppLocalizations.of(context).conflictResolveFailed);
        return;
      }
      final done = await showConflictSheet(
        context,
        items: items,
        onResolve: _resolveChoices,
      );
      // The last conflict is settled: back to the page.
      if (done && mounted) _canvasFocus.requestFocus();
    } finally {
      _sheetOpen = false;
    }
  }

  /// Settles the chosen conflicts one after the other; answers the page ids
  /// that are settled. The first failure stops the rest.
  Future<Set<String>> _resolveChoices(
    List<(ConflictItem, String)> choices,
  ) async {
    final l = AppLocalizations.of(context);
    final done = <String>{};
    for (final (item, choice) in choices) {
      final used = await _resolveOne(item, choice);
      if (used == null) break;
      done.add(item.pageId);
      if (choices.length == 1 && mounted) {
        final n = item.pageNo;
        _announce(switch (used) {
          'mine' => l.conflictResolvedThis(n),
          'theirs' => l.conflictResolvedOther(n),
          'both' => l.conflictResolvedBoth(n),
          'remove' => l.conflictResolvedRemove(n),
          _ => l.conflictResolvedKeep(n),
        }, polite: true);
      }
    }
    if (done.isEmpty) return done;
    if (choices.length > 1 && mounted) {
      _announce(l.conflictResolvedAll(done.length), polite: true);
    }
    // The resolution goes up (the note stays open).
    unawaited(_coordinator.syncNow(widget.note.noteId));
    return done;
  }

  // Resolutions that are in the note but whose `sync.json` write failed, by
  // page id and rev: a retry only writes `sync.json` again, so the note is
  // never resolved twice (keep-both would add a page).
  final _unrecorded = <String, (Map<String, Object?>, String)>{};

  /// One `resolveConflict` through the merge host, then `sync.json`. Answers
  /// the choice that was applied, or null when nothing was settled.
  Future<String?> _resolveOne(ConflictItem item, String choice) async {
    final id = widget.note.noteId;
    final key = '${item.pageId}:${item.entry['rev']}';
    final saved = _unrecorded[key];
    if (saved != null) {
      if (!await _coordinator.conflictResolved(id, saved.$1)) return null;
      _unrecorded.remove(key);
      _held = null;
      await _loadLastSeen();
      return saved.$2;
    }
    await _readSync(); // the freshest lastSeenRemoteSeq
    var used = choice;
    var out = <String, Object?>{};
    final ctx = {
      'now': canonicalNow(DateTime.now()),
      'orderRev': newId(),
      'rev': newId(),
      'editedBy': deviceEditedBy,
      'lastSeenRemoteSeq': _lastSeen,
    };
    Map<String, Object?> run(Note live) =>
        resolveConflict(live.copyJson(), item.entry, item.sidecar, used, ctx);
    final applied = await _applyMerge((live) {
      out = run(live);
      if (out['error'] == 'identicalVersions') {
        used = 'theirs'; // same version on both sides: keep one
        out = run(live);
      }
      if (out['result'] != 'resolved') return null;
      return (
        note: Note.trusted(out['note'] as Map<String, dynamic>),
        undoDrop: <String>{...(out['undoDrop'] as List).cast<String>()},
      );
    }, () async {});
    if (!applied || out['result'] != 'resolved') return null;
    final conflict = out['conflict'] as Map<String, Object?>;
    var ok = await _coordinator.conflictResolved(id, conflict);
    if (!ok) ok = await _coordinator.conflictResolved(id, conflict);
    if (!ok) {
      _unrecorded[key] = (conflict, used);
      return null;
    }
    _held = null;
    await _loadLastSeen(); // the page is no longer locked
    return used;
  }

  // ---- version history (Story 3.24) -------------------------------------

  Future<void> _openHistory() async {
    if (_leaving || !mounted) return;
    final restored = await showVersionHistory(
      context,
      noteId: widget.note.noteId,
      onRestore: _restoreVersion,
    );
    if (!restored || !mounted) return;
    _canvasFocus.requestFocus();
    _announce(AppLocalizations.of(context).versionRestored, polite: true);
  }

  /// The restore procedure of spec `version-history`; the note is changed
  /// through [_applyMerge], the same queue as every edit and every sync.
  Future<RestoreFailure?> _restoreVersion(
    Map<String, Object?> entry,
    String fileId,
  ) async {
    if (_leaving || _readOnly || _receiving) return RestoreFailure.notApplied;
    final id = widget.note.noteId;
    final failure = await ref
        .read(versionRestorerProvider)
        .restore(
          noteId: id,
          fileId: fileId,
          entry: entry,
          live: () => _history.note,
          apply: _applyMerge,
        );
    if (failure == null) {
      if (!mounted) return null; // restored all the same
      _held = null;
      await _loadLastSeen(); // the locks follow the conflicts that are left
      // The restored note goes up like any edit.
      unawaited(_coordinator.syncNow(id));
    }
    return failure;
  }

  /// Applies a merge to the live note as one item of the save queue (spec
  /// `merge.requeue`). The merge runs on the note as it is now; when an edit
  /// landed while [record] wrote the conflict files, it runs again on the
  /// new note, so nothing drawn meanwhile is lost. The adoption has no
  /// `await` between the check and the swap. Undo and redo records of the
  /// replaced pages are dropped (AD-16) and the buttons follow the rest.
  Future<bool> _applyMerge(
    LiveMerge merge,
    Future<void> Function() record,
  ) async {
    String? stroked; // the page of a stroke that ended while we waited
    for (var tries = 0; tries < 20; tries++) {
      // A stroke in progress ends first, so it is part of the version that
      // goes to the sidecar.
      stroked = await _strokeEnd() ?? stroked;
      final live = _history.note;
      final r = merge(live);
      await record();
      final conflicted = await _readSync();
      if (_pointer != null || !identical(_history.note, live)) continue;
      final here = {for (final p in (r?.note ?? live).pages) p['id'] as String};
      if (conflicted != null) {
        _history.setLocks(conflicted.where(here.contains).toSet());
      }
      if (r != null) {
        final held = stroked != null && (conflicted?.contains(stroked) ?? false)
            ? live.pages.where((p) => p['id'] == stroked).firstOrNull
            : null;
        _history.adopt(r.note, r.undoDrop);
        _relayout();
        _failed = null; // an older snapshot must never be written again
        if (held != null) _held = held;
        if (mounted) {
          setState(() {});
          _tick.value++;
        }
        _commit();
        await _flush();
      }
      if (mounted) setState(() {});
      await _loadLastSeen();
      return true;
    }
    return false;
  }

  /// The document changed (pages made or taken away): the view follows.
  void _relayout() {
    if (_vp == null || _pages.isEmpty) return;
    _anim.stop();
    _vp = _fit != _Fit.free ? _laidOut(_fit) : _clamp(_vp!);
  }

  /// Waits until every queued save is on disk (one more try for a failed
  /// one). Never throws.
  Future<void> _flush() async {
    try {
      await _running;
      final f = _failed;
      if (f != null) {
        await _store.write(f);
        _failed = null;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _latestTimer?.cancel();
    _emphasisTimer?.cancel();
    _zoomBadgeTimer?.cancel();
    _zoomBadge.dispose();
    _strokeEnded(null);
    if (_coordinator.flushOpen == _flush) _coordinator.flushOpen = null;
    _hosts.unregister(widget.note.noteId, _host);
    _openNote.clear(widget.note.noteId);
    _anim.dispose();
    _tick.dispose();
    _slotFocus.dispose();
    _canvasFocus.dispose();
    super.dispose();
  }

  Map<String, dynamic> _stroke(List<List<num>> points) => {
    'id': newId(),
    'type': 'stroke',
    'tool': 'pen',
    'color': _pen.color,
    'width': _pen.width,
    'usePressure': _pen.usePressure,
    'points': points,
  };

  Map<String, dynamic>? _live() =>
      _pointer == null ? null : _stroke(List.of(_points));

  double _pressure(PointerEvent e) {
    if (e.kind != PointerDeviceKind.stylus) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (!(range > 0)) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  List<num> _point(PointerEvent e, Offset page) => [
    page.dx,
    page.dy,
    _pressure(e),
    (e.timeStamp - _t0).inMilliseconds,
  ];

  double get _pageW => _geometry().w;
  double get _pageH => _geometry().h;
  double get _extraBottom => _toolbarHeight + KkjTokens.spacing3;

  PageViewport _clamp(PageViewport v) =>
      v.clamped(_size, _pageW, _pageH, _padding, extraBottom: _extraBottom);

  PageViewport _laidOut(_Fit f) {
    final w = _pageW, h = _pageH;
    switch (f) {
      case _Fit.page:
        // The page on screen (the only one of a one-page note), whole.
        final rects = _geometry().rects;
        if (rects.isEmpty) return _vp ?? PageViewport(1, _padding.topLeft);
        final r = rects[_activeIndex()];
        final v = PageViewport.fit(_size, r.width, r.height, _padding);
        final at = PageViewport(v.scale, v.offset - r.topLeft * v.scale);
        return _clamp(at.zoomAbout(at.offset + r.topLeft * at.scale, at.scale));
      case _Fit.width:
      case _Fit.free:
        return _clamp(PageViewport.fitWidth(_size, w, h, _padding));
    }
  }

  /// The scale where the page is as wide as the padded view (spec zoom.snap).
  double get _fitScale => (_size.width - _padding.horizontal) / _pageW;

  void _flashZoom(double scale) {
    _zoomBadge.value = (scale * 100).round();
    _zoomBadgeTimer?.cancel();
    _zoomBadgeTimer = Timer(const Duration(milliseconds: 1200), () {
      _zoomBadge.value = null;
    });
  }

  void _setView(PageViewport v, _Fit fit) => setState(() {
    _vp = v;
    _fit = fit;
  });

  void _animate() {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    final t = Curves.easeOut.transform(_anim.value);
    setState(
      () => _vp = PageViewport(
        lerpDouble(from.scale, to.scale, t)!,
        Offset.lerp(from.offset, to.offset, t)!,
      ),
    );
  }

  /// Moves the view to [to]; at once when the system asks for no animation.
  void _goTo(PageViewport to, _Fit fit) {
    // Not under a stroke or a pinch.
    if (_pointer != null || _mode == _Mode.gesture) return;
    final from = _vp;
    if (from != null && from.scale != to.scale) _flashZoom(to.scale);
    _anim.stop();
    if (from == null || MediaQuery.disableAnimationsOf(context)) {
      _setView(to, fit);
      return;
    }
    _fit = fit;
    _from = from;
    _to = to;
    _anim.forward(from: 0);
  }

  /// Ends a running zoom animation at its target.
  void _snap() {
    if (!_anim.isAnimating) return;
    _anim.stop();
    setState(() => _vp = _to ?? _vp);
  }

  void _zoomBy(double factor) {
    // Steps build on where a running animation is headed.
    final vp = _anim.isAnimating ? _to : _vp;
    if (vp == null || _page == null) return;
    final s = zoomSnap(vp.scale * factor, _fitScale);
    _goTo(_clamp(vp.zoomAbout(_size.center(Offset.zero), s)), _Fit.free);
  }

  void _down(PointerDownEvent e) {
    if (_leaving || _vp == null || _page == null) return;
    _snap();
    switch (e.kind) {
      case PointerDeviceKind.touch:
        _touchDown(e);
      case PointerDeviceKind.stylus || PointerDeviceKind.mouse:
        _penDown(e);
      default:
        break; // eraser (Epic 4), trackpad, unknown: no input
    }
  }

  void _touchDown(PointerDownEvent e) {
    _touches[e.pointer] = e.localPosition;
    switch (_mode) {
      case _Mode.none:
        // A new finger while others are still down is never input.
        if (_touches.length > 1) {
          _mode = _Mode.ignored;
          return;
        }
        _firstId = e.pointer;
        _firstDown = e.timeStamp;
        final p = _vp!.toPage(e.localPosition);
        final at = _pageAt(p);
        if (!_stylusSeen && at >= 0) {
          _mode = _Mode.touchStroke;
          _begin(e, p, at);
        } else {
          _mode = _Mode
              .touchIdle; // pen mode or off page: a finger only moves the view
        }
      case _Mode.touchIdle:
        // Nothing is being drawn, so a second finger starts the gesture
        // whenever it lands.
        if (_touches.length == 2) _startGesture(_firstId, e.pointer);
      case _Mode.touchStroke:
        if (_touches.length == 2 && e.timeStamp - _firstDown <= _secondFinger) {
          _discardStroke();
          _startGesture(_firstId, e.pointer);
        } // later fingers are ignored; the stroke goes on
      case _Mode.gesture || _Mode.ignored || _Mode.pen:
        break;
    }
  }

  void _hover(PointerHoverEvent e) {
    if (e.kind == PointerDeviceKind.stylus) _stylusSeen = true;
  }

  void _penDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.stylus) _stylusSeen = true;
    if (_mode == _Mode.pen) return;
    // A stylus or mouse takes over: touch stroke and gesture are dropped.
    // Fingers still down stay in [_touches], so they never turn into ink.
    _discardStroke();
    _mode = _Mode.none;
    final p = _vp!.toPage(e.localPosition);
    final at = _pageAt(p);
    if (at < 0) return;
    _mode = _Mode.pen;
    _begin(e, p, at);
  }

  void _begin(PointerDownEvent e, Offset doc, int index) {
    // A page with an unresolved conflict is read-only (Story 3.19): no
    // stroke; a finger may still pinch.
    final target = _pages[index];
    if (_history.isLocked(target['id'] as String?)) {
      _blocked();
      _mode = _mode == _Mode.touchStroke ? _Mode.touchIdle : _Mode.ignored;
      return;
    }
    // The note is being received or is read-only: no stroke (Stories 3.13,
    // 3.17).
    if (_receiving || _readOnly) {
      _mode = _Mode.ignored;
      return;
    }
    _pointer = e.pointer;
    _strokePageId = target['id'] as String;
    _origin = _geometry().rects[index].topLeft;
    _t0 = e.timeStamp;
    _points
      ..clear()
      ..add(_point(e, doc - _origin));
    _tick.value++;
  }

  /// Drops the stroke in progress: no op, no save.
  void _discardStroke() {
    if (_pointer == null) return;
    _pointer = null;
    _points.clear();
    _tick.value++;
    _strokeEnded(null);
  }

  void _startGesture(int a, int b) {
    _snap();
    _fit = _Fit.free;
    _mode = _Mode.gesture;
    _gA = a;
    _gB = b;
    final pa = _touches[a]!, pb = _touches[b]!;
    final vp = _vp!;
    _s0 = vp.scale;
    _d0 = (pa - pb).distance.clamp(1.0, double.infinity);
    _p0 = vp.toPage((pa + pb) / 2);
  }

  void _pinch() {
    final pa = _touches[_gA], pb = _touches[_gB];
    if (pa == null || pb == null) return;
    final focal = (pa + pb) / 2;
    // The request counts from the unsnapped start scale, so a long pinch
    // leaves the snap (spec zoom.snap, "Releasing").
    final s = zoomSnap(_s0 * (pa - pb).distance / _d0, _fitScale);
    if (s != _vp?.scale) _flashZoom(s);
    _setView(_clamp(PageViewport(s, focal - _p0 * s)), _Fit.free);
  }

  void _panBy(Offset d) {
    final vp = _vp;
    if (vp == null || _pointer != null) return;
    _setView(_clamp(PageViewport(vp.scale, vp.offset + d)), _Fit.free);
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent && _pages.length > 1 && !_leaving) {
      _snap();
      _panBy(-e.scrollDelta);
    }
  }

  void _move(PointerMoveEvent e) {
    if (_leaving || _vp == null) return;
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      if (_mode == _Mode.gesture && (e.pointer == _gA || e.pointer == _gB)) {
        _pinch();
        return;
      }
      // A finger that is not drawing scrolls a note of several pages.
      if (_mode == _Mode.touchIdle &&
          e.pointer == _firstId &&
          _touches.length == 1 &&
          _pages.length > 1) {
        _panBy(e.delta);
        return;
      }
    }
    if (e.pointer != _pointer) return;
    // Not clipped here: points outside the page are kept.
    _points.add(_point(e, _vp!.toPage(e.localPosition) - _origin));
    _tick.value++;
  }

  void _up(PointerUpEvent e) {
    final vp = _vp;
    if (!_leaving && vp != null && e.pointer == _pointer) {
      final p = vp.toPage(e.localPosition) - _origin;
      final last = _points.last;
      if (last[0] != p.dx || last[1] != p.dy) _points.add(_point(e, p));
      _finish();
    }
    _release(e.pointer);
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer == _pointer) _finish();
    _release(e.pointer);
  }

  void _release(int id) {
    final known = _touches.remove(id) != null;
    // One finger left after a gesture: nothing until all are up.
    if (known && _mode == _Mode.gesture && (id == _gA || id == _gB)) {
      _mode = _Mode.ignored;
    }
    // All contacts up and nothing drawing: clean slate.
    if (_touches.isEmpty && _pointer == null) _mode = _Mode.none;
  }

  /// Ends the stroke with the points so far (also for a cancel).
  void _finish() {
    if (_pointer == null) return;
    final pageId = _strokePageId;
    if (pageId == null || !_pages.any((p) => p['id'] == pageId)) {
      // A merge took the page away while the stroke was being drawn.
      _discardStroke();
      return;
    }
    final stroke = _stroke(List.of(_points));
    _pointer = null;
    _points.clear();
    if (_mode == _Mode.pen || _mode == _Mode.touchStroke) _mode = _Mode.none;
    final err = _history.doOp({
      'op': 'addStroke',
      'pageId': pageId,
      'stroke': stroke,
    }, _ctx());
    setState(() {});
    _tick.value++;
    _strokeEnded(pageId);
    if (err == null) {
      _commit();
    } else {
      _snack(AppLocalizations.of(context).strokeNotAdded);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _drain() async {
    while (_latest != null) {
      final n = _latest!;
      _latest = null;
      try {
        await _store.write(n);
        _failed = null;
      } catch (_) {
        // The stroke stays; the next stroke saves the whole note again.
        _failed = n;
        if (mounted) _snack(AppLocalizations.of(context).noteSaveFailed);
      }
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _finish();
    // Every queued save is on disk before the route is gone, so the upload
    // the library starts after the pop reads the last stroke.
    await _flush();
    if (mounted) Navigator.of(context).pop();
  }

  /// Places the view for this size (also on the first build); a free view
  /// is only brought back into range.
  void _layout(Size size, EdgeInsets pad) {
    const gap = KkjTokens.spacing3;
    final padding = EdgeInsets.fromLTRB(
      gap + pad.left,
      pad.top + gap + _toolbarHeight + gap,
      gap + pad.right,
      gap + pad.bottom,
    );
    if (_vp != null && size == _size && padding == _padding) return;
    final first = _vp == null;
    _size = size;
    _padding = padding;
    _anim.stop();
    _vp = first || _fit != _Fit.free ? _laidOut(_fit) : _clamp(_vp!);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      receiveStateProvider.select(
        (r) => r.receiving.contains(widget.note.noteId),
      ),
      (_, on) => _watchReceiving(on),
    );

    // A conflict that appears while the editor is open locks its page and is
    // announced; the first read of an already conflicted note is not.
    ref.listen(noteSyncProvider(widget.note.noteId), (prev, next) {
      if (!next.loaded) return;
      _lockWhenIdle(next.conflictPages);
      if (prev == null || !prev.loaded) return;
      final fresh = next.conflicts.where(
        (c) => !prev.conflictPages.contains(c.pageId),
      );
      if (fresh.isNotEmpty) _announceConflict(fresh.first);
    });

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: widget.note.title,
      explicitChildNodes: true,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          backgroundColor: KkjLight.colorSurfaceSunken,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SyncBanner(
                noteId: widget.note.noteId,
                onCloseNote: () => Navigator.of(context).maybePop(),
                onResolve: _openSheet,
                emphasis: _emphasis,
              ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  // The banner takes the status bar's place.
                  removeTop: syncBannerShown(ref, noteId: widget.note.noteId),
                  child: Builder(builder: _body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Every page, one under the other: each is named "N페이지 / M" and draws
  /// itself at its place in the document.
  List<Widget> _pageViews(AppLocalizations l10n) {
    final pages = _pages;
    final rects = _geometry().rects;
    final vp = _vp!;
    return [
      for (var i = 0; i < pages.length; i++)
        () {
          final p = pages[i];
          final id = p['id'] as String;
          final held = _held;
          final shown = held != null && held['id'] == id ? held : p;
          final landscape = (p['width'] as num) > (p['height'] as num);
          return Semantics(
            label: l10n.pageSemantics(
              i + 1,
              pages.length,
              landscape ? l10n.orientationLandscape : l10n.orientationPortrait,
            ),
            value: _history.isLocked(id)
                ? '${l10n.handwriting}, ${l10n.conflictPageSemantics}'
                : l10n.handwriting,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: PagePainter(
                  page: shown,
                  cache: _caches.putIfAbsent(id, StrokePathCache.new),
                  viewport: PageViewport(
                    vp.scale,
                    vp.offset + rects[i].topLeft * vp.scale,
                  ),
                  // Read at paint time: the first stroke of a session starts after this
                  // build, when `_strokePageId` was still null.
                  live: () => id == _strokePageId ? _live() : null,
                  repaint: _tick,
                ),
              ),
            ),
          );
        }(),
    ];
  }

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pad = MediaQuery.paddingOf(context);
    const gap = KkjTokens.spacing3;
    final page = _page;
    final locked = _pageLocked;
    final readOnly = ref.watch(
      noteSyncProvider(widget.note.noteId).select((v) => v.newVersion),
    );
    final receiving = ref.watch(
      receiveStateProvider.select(
        (r) => r.receiving.contains(widget.note.noteId),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (page != null) _layout(c.biggest, pad);
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerHover: _hover,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _cancel,
                onPointerSignal: _signal,
                child: page == null
                    ? const SizedBox.expand()
                    : Focus(
                        focusNode: _canvasFocus,
                        child: Stack(
                          fit: StackFit.expand,
                          children: _pageViews(l10n),
                        ),
                      ),
              ),
            ),
            if (_showLatest)
              Positioned(
                bottom: pad.bottom + gap,
                left: pad.left + gap,
                right: pad.right + gap,
                child: Semantics(
                  liveRegion: true,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: KkjLight.componentsBadgeNeutralBackground,
                        borderRadius: BorderRadius.circular(
                          KkjLight.componentsBadgeRounded,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KkjTokens.spacing3,
                          vertical: KkjTokens.spacing1,
                        ),
                        child: Text(
                          l10n.receivingLatest,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: pad.top + gap + _toolbarHeight + gap,
              right: pad.right + gap,
              child: IgnorePointer(
                child: ValueListenableBuilder<int?>(
                  valueListenable: _zoomBadge,
                  builder: (context, p, _) => p == null
                      ? const SizedBox.shrink()
                      : Semantics(
                          liveRegion: true,
                          container: true,
                          label: '$p%',
                          excludeSemantics: true,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: KkjLight.componentsBadgeNeutralBackground,
                              borderRadius: BorderRadius.circular(
                                KkjLight.componentsBadgeRounded,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: KkjTokens.spacing3,
                                vertical: KkjTokens.spacing1,
                              ),
                              child: Text(
                                '$p%',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              top: pad.top + gap,
              left: pad.left + gap,
              right: pad.right + gap,
              child: LayoutBuilder(
                builder: (context, top) {
                  // ponytail: with room the toolbar stays centered; on a
                  // phone the indicator and the menu (2 x 48 dp) leave the
                  // toolbar less room, so the right side takes only its width.
                  final wide = top.maxWidth >= 480;
                  final left = _Corner(
                    tooltip: l10n.backToLibrary,
                    // Always through PopScope, so the queue drains.
                    onBack: () => Navigator.of(context).maybePop(),
                  );
                  final right = _MoreMenu(
                    noteId: widget.note.noteId,
                    percent: ((_vp?.scale ?? 1) * 100).round(),
                    canZoomOut: (_vp?.scale ?? 1) > PageViewport.zoomMin,
                    canZoomIn: (_vp?.scale ?? 1) < PageViewport.zoomMax,
                    onZoomOut: () => _zoomBy(1 / _zoomStep),
                    onZoomIn: () => _zoomBy(_zoomStep),
                    onFitWidth: () => _goTo(_laidOut(_Fit.width), _Fit.width),
                    onFitPage: () => _goTo(_laidOut(_Fit.page), _Fit.page),
                    onVersionHistory: readOnly || receiving
                        ? null
                        : _openHistory,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.topStart,
                          child: left,
                        ),
                      ),
                      PenToolbar(
                        pen: ref.watch(penSlotsProvider).first,
                        onPenTap: _editPen,
                        slotFocus: _slotFocus,
                        canUndo: !readOnly && !locked && _history.undoDepth > 0,
                        canRedo: !readOnly && !locked && _history.redoDepth > 0,
                        onUndo: _undo,
                        onRedo: _redo,
                      ),
                      if (wide)
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.topEnd,
                            child: right,
                          ),
                        )
                      else
                        right,
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// `editor-corner`: the back arrow alone.
class _Corner extends StatelessWidget {
  const _Corner({required this.tooltip, required this.onBack});

  final String tooltip;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: _cornerDecoration,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: tooltip,
          constraints: const BoxConstraints(
            minWidth: KkjTokens.spacingHitMinAndroid,
            minHeight: KkjTokens.spacingHitMinAndroid,
          ),
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ],
    ),
  );
}

const _cornerDecoration = ShapeDecoration(
  color: KkjLight.componentsEditorCornerBackground,
  shape: StadiumBorder(
    side: BorderSide(color: KkjLight.componentsEditorCornerBorder),
  ),
);

/// Top-right `editor-corner`: the overflow button and its zoom menu
/// ([-] [N%] [+] stays open; the fit items close it).
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.noteId,
    required this.percent,
    required this.canZoomOut,
    required this.canZoomIn,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFitWidth,
    required this.onFitPage,
    required this.onVersionHistory,
  });

  final String noteId;
  final int percent;
  final bool canZoomOut, canZoomIn;
  final VoidCallback onZoomOut, onZoomIn, onFitWidth, onFitPage;
  final VoidCallback? onVersionHistory;

  static const _hit = BoxConstraints(
    minWidth: KkjTokens.spacingHitMinAndroid,
    minHeight: KkjTokens.spacingHitMinAndroid,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const item = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(KkjTokens.spacingHitMinAndroid, KkjTokens.spacingHitMinAndroid),
      ),
    );
    return DecoratedBox(
      decoration: _cornerDecoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SyncIndicator(noteId: noteId),
          MenuAnchor(
            style: MenuStyle(
              backgroundColor: const WidgetStatePropertyAll(
                KkjLight.componentsPopoverBackground,
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    KkjLight.componentsPopoverRounded,
                  ),
                ),
              ),
            ),
            menuChildren: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.zoomOut,
                    constraints: _hit,
                    icon: const Icon(Icons.remove),
                    disabledColor: KkjLight.colorInkDisabled,
                    onPressed: canZoomOut ? onZoomOut : null,
                  ),
                  Semantics(
                    container: true,
                    label: l10n.zoomLevel(percent),
                    excludeSemantics: true,
                    child: SizedBox(
                      width: 56,
                      height: KkjTokens.spacingHitMinAndroid,
                      child: Center(child: Text('$percent%')),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.zoomIn,
                    constraints: _hit,
                    icon: const Icon(Icons.add),
                    disabledColor: KkjLight.colorInkDisabled,
                    onPressed: canZoomIn ? onZoomIn : null,
                  ),
                ],
              ),
              MenuItemButton(
                style: item,
                onPressed: onFitWidth,
                child: Text(l10n.fitWidth),
              ),
              MenuItemButton(
                style: item,
                onPressed: onFitPage,
                child: Text(l10n.fitPage),
              ),
              MenuItemButton(
                style: item,
                onPressed: onVersionHistory,
                child: Text(l10n.versionHistory),
              ),
            ],
            builder: (context, controller, _) => IconButton(
              tooltip: l10n.moreMenu,
              constraints: _hit,
              icon: const Icon(Icons.more_horiz),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ],
      ),
    );
  }
}
