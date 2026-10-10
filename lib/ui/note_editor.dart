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

class _NoteEditorState extends ConsumerState<NoteEditor> {
  late final History _history = _sessionHistory();
  late final _store = ref.read(noteStoreProvider);
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

  Pen get _pen => defaultPenSlots.first;

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
  void dispose() {
    _tick.dispose();
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

  void _down(PointerDownEvent e) {
    final vp = _vp;
    if (_leaving || _pointer != null || vp == null || _page == null) return;
    if (e.kind == PointerDeviceKind.invertedStylus) return; // eraser: Epic 4
    final p = vp.toPage(e.localPosition);
    if (!_inPage(p)) return;
    _pointer = e.pointer;
    _t0 = e.timeStamp;
    _points
      ..clear()
      ..add(_point(e, p));
    _tick.value++;
  }

  void _move(PointerMoveEvent e) {
    final vp = _vp;
    if (_leaving || e.pointer != _pointer || vp == null) return;
    // Not clipped here: points outside the page are kept.
    _points.add(_point(e, vp.toPage(e.localPosition)));
    _tick.value++;
  }

  void _up(PointerUpEvent e) {
    final vp = _vp;
    if (_leaving || e.pointer != _pointer || vp == null) return;
    final p = vp.toPage(e.localPosition);
    final last = _points.last;
    if (last[0] != p.dx || last[1] != p.dy) _points.add(_point(e, p));
    _finish();
  }

  /// Ends the stroke with the points so far (also for a cancel).
  void _finish() {
    if (_pointer == null) return;
    final pageId = _page!['id'];
    final stroke = _stroke(List.of(_points));
    _pointer = null;
    _points.clear();
    final err = _history.doOp(
      {'op': 'addStroke', 'pageId': pageId, 'stroke': stroke},
      _ctx(),
    );
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
    await _running;
    final f = _failed;
    if (f != null) {
      try {
        await _store.write(f); // one last try; leave either way
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
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
          body: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: (e) {
                    if (e.pointer == _pointer) _finish();
                  },
                  child: LayoutBuilder(
                    builder: (context, c) {
                      if (page == null) return const SizedBox.expand();
                      final vp = _vp = PageViewport.fit(
                        c.biggest,
                        (page['width'] as num).toDouble(),
                        (page['height'] as num).toDouble(),
                        EdgeInsets.fromLTRB(
                          gap + pad.left,
                          pad.top + gap + _toolbarHeight + gap,
                          gap + pad.right,
                          gap + pad.bottom,
                        ),
                      );
                      return Semantics(
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
                              viewport: vp,
                              live: _live,
                              repaint: _tick,
                            ),
                          ),
                        ),
                      );
                    },
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
                      pen: _pen,
                      canUndo: _history.undoDepth > 0,
                      canRedo: _history.redoDepth > 0,
                      onUndo: _undo,
                      onRedo: _redo,
                    ),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            ],
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
    decoration: const ShapeDecoration(
      color: KkjLight.componentsEditorCornerBackground,
      shape: StadiumBorder(
        side: BorderSide(color: KkjLight.componentsEditorCornerBorder),
      ),
    ),
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
