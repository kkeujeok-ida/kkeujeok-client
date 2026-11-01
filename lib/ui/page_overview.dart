import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/page_bounds.dart';
import '../render/page_painter.dart';

/// What the overview needs from the editor that owns the note: its pages, and
/// page operations that go through the note's history and save queue.
abstract class PageOverviewHost {
  List<Map<String, dynamic>> get pages;

  /// Index of the current page.
  int get current;

  /// Ids of the pages with an unresolved conflict.
  Set<String> get conflicted;

  /// Fires when [pages] or [current] may have changed.
  Listenable get changes;

  int get undoDepth;
  void undo();

  /// Deleted pages the overview can bring back; separate from [undoDepth].
  int get deletedDepth;
  String? undeletePages();

  /// Each answers an error code, or null when done.
  String? addPage(int index);
  String? deletePages(List<String> ids);
  String? duplicatePages(List<String> ids);

  /// [index] counts the pages that are not moved (spec `ops.movePages`).
  String? movePages(List<String> ids, int index);

  /// Story 6.8. One undo step however many pages.
  String? setBackground(List<String> ids, String background);
  String? setOrientation(String id, String orientation);
}

/// What the overview closes with when a thumbnail was tapped: the page to
/// show and, for the out-of-bounds badge, the elements to select there
/// (Story 6.8).
class PageOverviewResult {
  const PageOverviewResult(this.index, [this.select = const []]);
  final int index;
  final List<String> select;
}

const _backgroundNames = ['plain', 'lined', 'grid', 'dot'];

/// Story 6.2: the full-screen page overview. Pops with the tapped page index,
/// or null when closed. Story 6.4: [+] and the ⋯ menu add, duplicate and
/// delete pages. Story 6.6: long-press drag, ⋯ move items, TalkBack actions
/// and the [선택] mode with its header. Story 6.8: background and
/// orientation from the ⋯ menu and the header, and the out-of-bounds badge.
class PageOverview extends StatefulWidget {
  const PageOverview({super.key, required this.host});

  final PageOverviewHost host;

  @override
  State<PageOverview> createState() => _PageOverviewState();
}

class _PageOverviewState extends State<PageOverview> {
  PageOverviewHost get host => widget.host;

  bool _selecting = false;
  final _sel = <String>{};
  final _scroll = ScrollController();
  Timer? _auto;
  double? _dragY;

  @override
  void dispose() {
    _auto?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _note(String text, {bool undo = false}) {
    final l = AppLocalizations.of(context);
    final d = host.undoDepth; // the undo is for this change only
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: undo
              ? SnackBarAction(
                  label: l.pageUndo,
                  onPressed: () {
                    if (host.undoDepth == d) host.undo();
                  },
                )
              : null,
        ),
      );
  }

  String _id(int i) => host.pages[i]['id'] as String;

  void _add() {
    final l = AppLocalizations.of(context);
    final at = host.current + 1;
    if (host.addPage(at) == null) _note(l.pageAdded(at + 1), undo: true);
  }

  /// Pages with something on them are asked about first; blank ones go at once.
  Future<void> _delete(List<String> ids) async {
    final l = AppLocalizations.of(context);
    final first = host.pages.indexWhere((p) => p['id'] == ids.first);
    final text = ids.length == 1
        ? l.pageDeleted(first + 1)
        : l.pagesDeleted(ids.length);
    final full = host.pages.any(
      (p) => ids.contains(p['id']) && (p['elements'] as List).isNotEmpty,
    );
    if (full) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l.pageDeleteContentConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.pageDelete),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (host.deletePages(ids) != null) return;
    _leaveSelection();
    _noteDeleted(text);
  }

  /// The delete history is the overview's own: only deletes, gone on leaving.
  void _undelete() {
    if (host.undeletePages() == null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  void _noteDeleted(String text) {
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: SnackBarAction(label: l.pageUndo, onPressed: _undelete),
        ),
      );
  }

  void _duplicate(List<String> ids) {
    final l = AppLocalizations.of(context);
    final first = host.pages.indexWhere((p) => p['id'] == ids.first);
    final text = ids.length == 1
        ? l.pageDuplicated(first + 1)
        : l.pagesDuplicated(ids.length);
    if (host.duplicatePages(ids) != null) return;
    _leaveSelection();
    _note(text, undo: true);
  }

  Future<String?> _pickBackground() {
    final l = AppLocalizations.of(context);
    final names = {
      'plain': l.backgroundPlain,
      'lined': l.backgroundLined,
      'grid': l.backgroundGrid,
      'dot': l.backgroundDot,
    };
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.pageBackground),
        children: [
          for (final b in _backgroundNames)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(b),
              child: Text(names[b]!),
            ),
        ],
      ),
    );
  }

  Future<void> _background(List<String> ids) async {
    final b = await _pickBackground();
    if (b == null || !mounted) return;
    final l = AppLocalizations.of(context);
    final first = host.pages.indexWhere((p) => p['id'] == ids.first);
    final text = ids.length == 1
        ? l.pageBackgroundChanged(first + 1)
        : l.pagesBackgroundChanged(ids.length);
    final d = host.undoDepth;
    if (host.setBackground(ids, b) != null) return;
    _leaveSelection();
    // Nothing changed: no record, so no message and no Undo for another edit.
    if (host.undoDepth > d) _note(text, undo: true);
  }

  void _orient(int i, String orientation) {
    final l = AppLocalizations.of(context);
    if (host.setOrientation(_id(i), orientation) != null) return;
    _note(
      orientation == 'landscape'
          ? l.pageTurnedLandscape(i + 1)
          : l.pageTurnedPortrait(i + 1),
      undo: true,
    );
  }

  /// Turns the page the other way; null for a square page (nothing to turn).
  VoidCallback? _turn(Map<String, dynamic> page, int i) {
    final w = page['width'] as num, h = page['height'] as num;
    if (w == h) return null;
    return () => _orient(i, w > h ? 'portrait' : 'landscape');
  }

  void _leaveSelection() {
    if (_selecting) {
      setState(() {
        _selecting = false;
        _sel.clear();
      });
    }
  }

  void _moveOne(int i, int index) {
    final l = AppLocalizations.of(context);
    final id = _id(i);
    if (host.movePages([id], index) != null) return;
    _note(l.pageMoved(i + 1, index + 1), undo: true);
  }

  /// A page was dropped on the thumbnail at [j].
  void _drop(String dragged, int j) {
    final pages = host.pages;
    final ids = _selecting && _sel.contains(dragged)
        ? _sel.toList()
        : [dragged];
    final target = pages[j]['id'];
    if (ids.contains(target)) return;
    final from = pages.indexWhere((p) => p['id'] == dragged);
    final pick = ids.toSet();
    // Before the target when moving up, after it when moving down.
    final end = from < j ? j + 1 : j;
    var index = 0;
    for (var k = 0; k < end; k++) {
      if (!pick.contains(pages[k]['id'])) index++;
    }
    final l = AppLocalizations.of(context);
    if (host.movePages(ids, index) != null) return;
    final at = host.pages.indexWhere((p) => p['id'] == dragged) + 1;
    _note(
      ids.length == 1 ? l.pageMoved(from + 1, at) : l.pagesMoved(ids.length),
      undo: true,
    );
  }

  // While a thumbnail is dragged, the list scrolls when it nears an edge.
  void _dragStart(String id) {
    // A long press is a choice: checkboxes appear and this page is picked.
    setState(() {
      _selecting = true;
      _sel.add(id);
    });
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final y = _dragY;
      if (y == null || !_scroll.hasClients) return;
      final h = MediaQuery.sizeOf(context).height;
      final dy = y < 140 ? -12.0 : (y > h - 100 ? 12.0 : 0.0);
      if (dy == 0) return;
      final p = _scroll.position;
      _scroll.jumpTo(
        (p.pixels + dy).clamp(p.minScrollExtent, p.maxScrollExtent),
      );
    });
  }

  void _dragEnd() {
    _auto?.cancel();
    _auto = null;
    _dragY = null;
  }

  PreferredSizeWidget _header(AppLocalizations l, int total) {
    if (_selecting) {
      final none = _sel.isEmpty;
      return AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: KkjLight.colorSurfaceBase,
        titleSpacing: KkjTokens.spacing3,
        title: Semantics(
          header: true,
          liveRegion: true,
          child: Text(l.pageSelected(_sel.length)),
        ),
        actions: [
          if (host.deletedDepth > 0)
            IconButton(
              tooltip: l.pageUndo,
              icon: const Icon(Icons.undo),
              onPressed: _undelete,
            ),
          TextButton(
            onPressed: none ? null : () => _duplicate(_sel.toList()),
            child: Text(l.pageDuplicate),
          ),
          TextButton(
            // Every page chosen: the last page cannot be deleted.
            onPressed: none || _sel.length >= total
                ? null
                : () => _delete(_sel.toList()),
            child: Text(l.pageDelete),
          ),
          TextButton(
            onPressed: none ? null : () => _background(_sel.toList()),
            child: Text(l.pageBackgroundShort),
          ),
          IconButton(
            tooltip: l.pageSelectDone,
            icon: const Icon(Icons.close),
            onPressed: _leaveSelection,
          ),
        ],
      );
    }
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: KkjLight.colorSurfaceBase,
      title: Semantics(header: true, child: Text(l.pageOverviewTitle)),
      actions: [
        if (host.deletedDepth > 0)
          IconButton(
            tooltip: l.pageUndo,
            icon: const Icon(Icons.undo),
            onPressed: _undelete,
          ),
        IconButton(
          tooltip: l.pageAdd,
          icon: const Icon(Icons.add),
          onPressed: _add,
        ),
        TextButton(
          onPressed: () => setState(() => _selecting = true),
          child: Text(l.pageSelect),
        ),
        IconButton(
          tooltip: l.close,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: host.changes,
      builder: (context, _) {
        final pages = host.pages;
        final conflicted = host.conflicted;
        // A merge or undo may have taken a chosen page away.
        _sel.removeWhere((id) => !pages.any((p) => p['id'] == id));
        return Scaffold(
          backgroundColor: KkjLight.colorSurfaceBase,
          appBar: _header(l, pages.length),
          // Built lazily: only the thumbnails in view are drawn (NFR2).
          body: GestureDetector(
            // A tap on the empty space ends the choosing.
            behavior: HitTestBehavior.translucent,
            onTap: _selecting ? _leaveSelection : null,
            child: GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(KkjTokens.spacing3),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: KkjTokens.spacing3,
                crossAxisSpacing: KkjTokens.spacing3,
                childAspectRatio: 0.72,
              ),
              itemCount: pages.length,
              itemBuilder: (context, i) {
                final id = pages[i]['id'] as String;
                final last = pages.length - 1;
                return _Cell(
                  key: ValueKey(id),
                  page: pages[i],
                  index: i,
                  total: pages.length,
                  isCurrent: i == host.current,
                  conflict: conflicted.contains(id),
                  selecting: _selecting,
                  selected: _sel.contains(id),
                  onTap: _selecting
                      ? () => setState(
                          () => _sel.contains(id)
                              ? _sel.remove(id)
                              : _sel.add(id),
                        )
                      : () => Navigator.of(context).pop(PageOverviewResult(i)),
                  onOutTap: (ids) =>
                      Navigator.of(context).pop(PageOverviewResult(i, ids)),
                  onBackground: () => _background([id]),
                  onOrientation: _turn(pages[i], i),
                  onDuplicate: () => _duplicate([id]),
                  onDelete: pages.length > 1 ? () => _delete([id]) : null,
                  onEarlier: i > 0 ? () => _moveOne(i, i - 1) : null,
                  onLater: i < last ? () => _moveOne(i, i + 1) : null,
                  onFirst: i > 0 ? () => _moveOne(i, 0) : null,
                  onLast: i < last ? () => _moveOne(i, last) : null,
                  onDrop: (dragged) => _drop(dragged, i),
                  onDragStart: () => _dragStart(id),
                  fromBefore: (dragged) =>
                      pages.indexWhere((p) => p['id'] == dragged) < i,
                  onDragUpdate: (y) => _dragY = y,
                  onDragEnd: _dragEnd,
                  dragCount: _selecting
                      ? (_sel.contains(id) ? _sel.length : _sel.length + 1)
                      : 1,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Cell extends StatefulWidget {
  const _Cell({
    super.key,
    required this.page,
    required this.index,
    required this.total,
    required this.isCurrent,
    required this.conflict,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onOutTap,
    required this.onBackground,
    required this.onOrientation,
    required this.onDuplicate,
    required this.onDelete,
    required this.onEarlier,
    required this.onLater,
    required this.onFirst,
    required this.onLast,
    required this.onDrop,
    required this.onDragStart,
    required this.fromBefore,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.dragCount,
  });

  final Map<String, dynamic> page;
  final int index, total, dragCount;
  final bool isCurrent, conflict, selecting, selected;
  final VoidCallback onTap, onDuplicate, onDragStart, onDragEnd;

  /// Null for the last page left: it cannot be deleted.
  final VoidCallback? onDelete;

  final VoidCallback onBackground;

  /// Null for a square page.
  final VoidCallback? onOrientation;

  /// The badge: the ids of the elements outside the page.
  final void Function(List<String> ids) onOutTap;

  /// Null where the move makes no sense (the first page cannot go earlier).
  final VoidCallback? onEarlier, onLater, onFirst, onLast;

  final void Function(String dragged) onDrop;

  /// True when the dragged page sits before this one (it would land after).
  final bool Function(String dragged) fromBefore;
  final void Function(double y) onDragUpdate;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  final _cache = StrokePathCache();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = widget.page;
    final id = p['id'] as String;
    final w = (p['width'] as num).toDouble(),
        h = (p['height'] as num).toDouble();
    final ratio = (w / h).isFinite && w > 0 && h > 0
        ? (w / h).clamp(0.2, 5.0).toDouble()
        : 0.7;
    final outIds = pageOutOfBounds(w, h, [
      for (final e in p['elements'] as List) (e as Map).cast<String, dynamic>(),
    ]);
    final out = outIds.length;
    final n = widget.index + 1;
    final label = [
      l.pageSemantics(
        n,
        widget.total,
        w > h ? l.pageLandscape : l.pagePortrait,
      ),
      if (widget.isCurrent) l.pageCurrent,
      if (widget.conflict) l.pageConflictBadge,
    ].join(', ');
    const radius = KkjLight.componentsPageThumbnailRounded;
    final badge = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: KkjLight.colorStatusWarningText);
    final thumb = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(
          color: widget.isCurrent
              ? KkjLight.componentsPageThumbnailCurrentRing
              : KkjLight.componentsPageThumbnailBorder,
          width: widget.isCurrent ? 3 : 1,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: RepaintBoundary(
          child: CustomPaint(
            painter: PagePainter(page: p, cache: _cache),
          ),
        ),
      ),
    );
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DragTarget<String>(
                    onWillAcceptWithDetails: (d) => d.data != id,
                    onAcceptWithDetails: (d) => widget.onDrop(d.data),
                    builder: (context, candidates, _) => Stack(
                      // The bar sits in the gap between pages.
                      clipBehavior: Clip.none,
                      fit: StackFit.expand,
                      children: [
                        LongPressDraggable<String>(
                          data: id,
                          onDragStarted: widget.onDragStart,
                          onDragUpdate: (d) =>
                              widget.onDragUpdate(d.globalPosition.dy),
                          onDragEnd: (_) => widget.onDragEnd(),
                          onDraggableCanceled: (_, _) => widget.onDragEnd(),
                          feedback: Material(
                            color: Colors.transparent,
                            child: Opacity(
                              opacity: 0.85,
                              child: SizedBox(
                                width: 96,
                                height: 96 / ratio,
                                child: Stack(
                                  children: [
                                    Positioned.fill(child: thumb),
                                    if (widget.dragCount > 1)
                                      Positioned(
                                        right: 2,
                                        top: 2,
                                        child: CircleAvatar(
                                          radius: 11,
                                          child: Text('${widget.dragCount}'),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.3,
                            child: thumb,
                          ),
                          child: Semantics(
                            button: true,
                            label: label,
                            selected: widget.selecting ? widget.selected : null,
                            excludeSemantics: true,
                            onTap: widget.onTap,
                            customSemanticsActions: {
                              if (widget.onEarlier != null)
                                CustomSemanticsAction(label: l.pageMoveEarlier):
                                    widget.onEarlier!,
                              if (widget.onLater != null)
                                CustomSemanticsAction(label: l.pageMoveLater):
                                    widget.onLater!,
                              if (widget.onFirst != null)
                                CustomSemanticsAction(label: l.pageMoveFirst):
                                    widget.onFirst!,
                              if (widget.onLast != null)
                                CustomSemanticsAction(label: l.pageMoveLast):
                                    widget.onLast!,
                            },
                            child: GestureDetector(
                              onTap: widget.onTap,
                              child: thumb,
                            ),
                          ),
                        ),
                        if (candidates.isNotEmpty)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            // Before this page, or after it when moving down.
                            left: widget.fromBefore(candidates.first!)
                                ? null
                                : -8,
                            right: widget.fromBefore(candidates.first!)
                                ? -8
                                : null,
                            width: 4,
                            child: const IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: KkjLight
                                      .componentsPageThumbnailCurrentRing,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.selecting)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: ExcludeSemantics(
                        child: Icon(
                          widget.selected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: KkjLight.componentsPageThumbnailCurrentRing,
                        ),
                      ),
                    )
                  else
                    Positioned(
                      top: 0,
                      right: 0,
                      child: PopupMenuButton<VoidCallback>(
                        tooltip: l.pageMenu,
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: KkjLight.componentsPageThumbnailMenuButton,
                          minHeight: KkjLight.componentsPageThumbnailMenuButton,
                        ),
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (f) => f(),
                        itemBuilder: (_) => [
                          _item(widget.onDuplicate, l.pageDuplicate),
                          _item(widget.onDelete, l.pageDelete),
                          _item(widget.onBackground, l.pageChangeBackground),
                          _item(
                            widget.onOrientation,
                            w > h ? l.pageToPortrait : l.pageToLandscape,
                          ),
                        ],
                      ),
                    ),
                  if (widget.conflict || out > 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      right: 4,
                      child: Wrap(
                        spacing: 4,
                        children: [
                          if (widget.conflict)
                            ExcludeSemantics(
                              child: _badge(l.pageConflictBadge, badge),
                            ),
                          if (out > 0)
                            Semantics(
                              button: true,
                              label: l.pageOutOfBoundsBadge(out),
                              excludeSemantics: true,
                              onTap: () => widget.onOutTap(outIds),
                              child: GestureDetector(
                                onTap: () => widget.onOutTap(outIds),
                                child: _badge(
                                  l.pageOutOfBoundsBadge(out),
                                  badge,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        ExcludeSemantics(
          child: Text('$n', style: Theme.of(context).textTheme.labelMedium),
        ),
      ],
    );
  }

  Widget _badge(String t, TextStyle? style) => DecoratedBox(
    decoration: BoxDecoration(
      color: KkjLight.colorSurfaceRaised,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber,
            size: 12,
            color: KkjLight.colorStatusWarningText,
          ),
          const SizedBox(width: 2),
          Flexible(child: Text(t, style: style)),
        ],
      ),
    ),
  );

  /// A menu entry that does nothing and is greyed out when [f] is null.
  PopupMenuEntry<VoidCallback> _item(VoidCallback? f, String text) =>
      PopupMenuItem<VoidCallback>(
        value: f,
        enabled: f != null,
        child: Text(text),
      );
}
