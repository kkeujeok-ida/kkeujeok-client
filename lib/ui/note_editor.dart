import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/ids.dart';
import '../model/note.dart';
import '../model/pen.dart';
import '../ops/history.dart';
import '../ops/ops.dart';
import '../render/page_painter.dart';
import '../sync/merge_step.dart';
import 'pen_toolbar.dart';
import 'providers.dart';

/// The writing screen: page, toolbar and the top-left `editor-corner`.
/// Input goes through `History.doOp(addStroke)`; every stroke is saved
/// through one serial queue.
class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({super.key, required this.note});

  final Note note;

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
  final _cache = StrokePathCache();
  final _tick = ValueNotifier<int>(0);

  // Saves coalesce: at most one write runs, and only the newest snapshot
  // waits behind it. [_failed] is the snapshot the last write could not save.
  Future<void>? _running;
  Note? _latest;
  Note? _failed;
  bool _leaving = false;

  int? _pointer; // the one pointer that is drawing
  Duration _t0 = Duration.zero;
  final _points = <List<num>>[];
  PageViewport? _vp;
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
    if (!mounted || _pointer != null || _leaving) return;
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

  Map<String, dynamic>? get _page {
    final pages = _history.note.pages;
    return pages.isEmpty ? null : pages.first;
  }

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

  Future<void> _loadLastSeen() async {
    try {
      final s = await _store.readSync(widget.note.noteId);
      if (s.info.lastSeenRemoteSeq > _lastSeen) {
        _lastSeen = s.info.lastSeenRemoteSeq;
      }
    } catch (_) {}
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
    for (var tries = 0; tries < 20; tries++) {
      final live = _history.note;
      final r = merge(live);
      await record();
      if (!identical(_history.note, live)) continue;
      if (r != null) {
        _history.adopt(r.note, r.undoDrop);
        _failed = null; // an older snapshot must never be written again
        if (mounted) {
          setState(() {});
          _tick.value++;
        }
        _commit();
        await _flush();
      }
      await _loadLastSeen();
      return true;
    }
    return false;
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
    if (_coordinator.flushOpen == _flush) _coordinator.flushOpen = null;
    _hosts.unregister(widget.note.noteId, _host);
    _openNote.clear(widget.note.noteId);
    _anim.dispose();
    _tick.dispose();
    _slotFocus.dispose();
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

  bool _inPage(Offset p) {
    final page = _page!;
    return p.dx >= 0 &&
        p.dy >= 0 &&
        p.dx <= (page['width'] as num) &&
        p.dy <= (page['height'] as num);
  }

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

  double get _pageW => (_page!['width'] as num).toDouble();
  double get _pageH => (_page!['height'] as num).toDouble();
  double get _extraBottom => _toolbarHeight + KkjTokens.spacing3;

  PageViewport _clamp(PageViewport v) =>
      v.clamped(_size, _pageW, _pageH, _padding, extraBottom: _extraBottom);

  PageViewport _laidOut(_Fit f) {
    final w = _pageW, h = _pageH;
    switch (f) {
      case _Fit.page:
        final v = PageViewport.fit(_size, w, h, _padding);
        return _clamp(v.zoomAbout(v.offset, v.scale)); // scale into range
      case _Fit.width:
      case _Fit.free:
        return _clamp(PageViewport.fitWidth(_size, w, h, _padding));
    }
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
    final s = (vp.scale * factor).clamp(
      PageViewport.zoomMin,
      PageViewport.zoomMax,
    );
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
        if (!_stylusSeen && _inPage(p)) {
          _mode = _Mode.touchStroke;
          _begin(e, p);
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
    if (!_inPage(p)) return;
    _mode = _Mode.pen;
    _begin(e, p);
  }

  void _begin(PointerDownEvent e, Offset page) {
    // The note is being received: no stroke (Story 3.13).
    if (_receiving) {
      _mode = _Mode.ignored;
      return;
    }
    _pointer = e.pointer;
    _t0 = e.timeStamp;
    _points
      ..clear()
      ..add(_point(e, page));
    _tick.value++;
  }

  /// Drops the stroke in progress: no op, no save.
  void _discardStroke() {
    if (_pointer == null) return;
    _pointer = null;
    _points.clear();
    _tick.value++;
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
    final s = (_s0 * (pa - pb).distance / _d0).clamp(
      PageViewport.zoomMin,
      PageViewport.zoomMax,
    );
    _setView(_clamp(PageViewport(s, focal - _p0 * s)), _Fit.free);
  }

  void _move(PointerMoveEvent e) {
    if (_leaving || _vp == null) return;
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      if (_mode == _Mode.gesture && (e.pointer == _gA || e.pointer == _gB)) {
        _pinch();
        return;
      }
    }
    if (e.pointer != _pointer) return;
    // Not clipped here: points outside the page are kept.
    _points.add(_point(e, _vp!.toPage(e.localPosition)));
    _tick.value++;
  }

  void _up(PointerUpEvent e) {
    final vp = _vp;
    if (!_leaving && vp != null && e.pointer == _pointer) {
      final p = vp.toPage(e.localPosition);
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
    final page = _page;
    if (page == null) {
      // A merge took the last page away while the stroke was being drawn.
      _discardStroke();
      return;
    }
    final pageId = page['id'];
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
    final l10n = AppLocalizations.of(context);
    final pad = MediaQuery.paddingOf(context);
    const gap = KkjTokens.spacing3;
    final page = _page;
    final landscape =
        page != null && (page['width'] as num) > (page['height'] as num);
    final title = Theme.of(context).textTheme.labelMedium;
    ref.listen(
      receiveStateProvider.select(
        (r) => r.receiving.contains(widget.note.noteId),
      ),
      (_, on) => _watchReceiving(on),
    );

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
          body: LayoutBuilder(
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
                      child: page == null
                          ? const SizedBox.expand()
                          : Semantics(
                              label: l10n.pageSemantics(
                                1,
                                widget.note.pages.length,
                                landscape
                                    ? l10n.orientationLandscape
                                    : l10n.orientationPortrait,
                              ),
                              value: l10n.handwriting,
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: PagePainter(
                                    page: page,
                                    cache: _cache,
                                    viewport: _vp!,
                                    live: _live,
                                    repaint: _tick,
                                  ),
                                ),
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
                    top: pad.top + gap,
                    left: pad.left + gap,
                    right: pad.right + gap,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.topStart,
                            child: _Corner(
                              title: widget.note.title,
                              style: title,
                              tooltip: l10n.backToLibrary,
                              // Always through PopScope, so the queue drains.
                              onBack: () => Navigator.of(context).maybePop(),
                            ),
                          ),
                        ),
                        PenToolbar(
                          pen: ref.watch(penSlotsProvider).first,
                          onPenTap: _editPen,
                          slotFocus: _slotFocus,
                          canUndo: _history.undoDepth > 0,
                          canRedo: _history.redoDepth > 0,
                          onUndo: _undo,
                          onRedo: _redo,
                        ),
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.topEnd,
                            child: _MoreMenu(
                              percent: ((_vp?.scale ?? 1) * 100).round(),
                              canZoomOut:
                                  (_vp?.scale ?? 1) > PageViewport.zoomMin,
                              canZoomIn:
                                  (_vp?.scale ?? 1) < PageViewport.zoomMax,
                              onZoomOut: () => _zoomBy(1 / _zoomStep),
                              onZoomIn: () => _zoomBy(_zoomStep),
                              onFitWidth: () =>
                                  _goTo(_laidOut(_Fit.width), _Fit.width),
                              onFitPage: () =>
                                  _goTo(_laidOut(_Fit.page), _Fit.page),
                            ),
                          ),
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
    );
  }
}

/// `editor-corner`: back arrow and the title on one line; display only.
class _Corner extends StatelessWidget {
  const _Corner({
    required this.title,
    required this.style,
    required this.tooltip,
    required this.onBack,
  });

  final String title;
  final TextStyle? style;
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
        Flexible(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: KkjTokens.spacing4),
            child: Text(
              title,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
    required this.percent,
    required this.canZoomOut,
    required this.canZoomIn,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFitWidth,
    required this.onFitPage,
  });

  final int percent;
  final bool canZoomOut, canZoomIn;
  final VoidCallback onZoomOut, onZoomIn, onFitWidth, onFitPage;

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
      child: MenuAnchor(
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
        ],
        builder: (context, controller, _) => IconButton(
          tooltip: l10n.moreMenu,
          constraints: _hit,
          icon: const Icon(Icons.more_horiz),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }
}
