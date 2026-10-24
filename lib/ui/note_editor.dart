import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/element_clipboard.dart';
import '../model/ids.dart';
import '../model/image_rules.dart';
import '../model/note.dart';
import '../model/pen.dart';
import '../model/select.dart';
import '../model/text_layout.dart';
import '../ops/history.dart';
import '../ops/ops.dart';
import '../ops/resolve_conflict.dart';
import '../render/asset_images.dart';
import '../render/page_painter.dart';
import '../render/selection_painter.dart';
import '../render/zoom_snap.dart';
import '../storage/image_intake.dart';
import '../sync/merge_step.dart';
import '../sync/version_history.dart' show RestoreFailure;
import 'conflict_sheet.dart';
import 'pen_toolbar.dart';
import 'providers.dart';
import 'selection_menu.dart';
import 'sync_banner.dart';
import 'sync_display.dart';
import 'sync_indicator.dart';
import 'text_edit.dart';
import 'text_format_bar.dart';
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

enum _Tool { pen, lasso, text }

enum _XKind { move, scale, rotate, width }

// A selection drag: [box] is the selection's document box, [down] where it
// began (document coordinates), [last] the latest pointer position (screen).
class _Xf {
  _Xf(this.kind, this.corner, this.box, this.down, this.last);
  final _XKind kind;
  final int corner; // scale: 0 top-left, clockwise
  final Rect box;
  final Offset down;
  Offset last;
}

// No resize goes below this factor (the op rejects non-positive ones).
const _minScale = 0.05;

/// The text box being edited: nothing is stored until it is confirmed.
/// [element] is null for a new box.
class _TextEdit {
  _TextEdit({
    required this.pageId,
    required this.element,
    required this.base,
    required this.x,
    required this.y,
    required this.width,
    required this.rotation,
    required this.ctl,
  });

  final String pageId;
  final Map<String, dynamic>? element;
  final Map<String, dynamic> base;
  final double x, y, width, rotation;
  final StyledTextController ctl;
  final focus = FocusNode();
}

/// What the view does when the screen size changes.
enum _Fit { width, page, free }

// A second finger this soon after the first turns the stroke into a gesture.
const _secondFinger = Duration(milliseconds: 150);
const _zoomStep = 1.25;

class _NoteEditorState extends ConsumerState<NoteEditor>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  late final _assetSync = ref.read(assetSyncProvider);
  late final _assetStore = ref.read(assetStoreProvider);
  late final _images = AssetImages(_assetStore, _assetSync);

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

  _Tool _tool = _Tool.pen;
  // The selection is UI state only: no op, no save. One page (Epic 4).
  String? _selPage;
  Set<String> _selected = {};
  // The lasso in progress (document coordinates) and whether the pointer has
  // left the tap slop since it went down.
  bool _lassoing = false;
  final _lassoPts = <Offset>[];
  Offset _lassoDown = Offset.zero;
  bool _lassoMoved = false;

  // ---- images (Story 4.12) ----------------------------------------------

  void _onAssets() {
    if (!mounted) return;
    _tick.value++;
    setState(() {});
  }

  /// Fetches the assets the note lacks and asks Drive about the others.
  void _syncAssets() {
    final m = <String, String>{};
    for (final p in _pages) {
      for (final e in p['elements'] as List) {
        if (e is Map && e['type'] == 'image' && e['asset'] is String) {
          m[e['asset'] as String] = '${e['ext']}';
        }
      }
    }
    if (m.isNotEmpty) unawaited(_assetSync.ensure(m));
  }

  /// [이미지]: gallery or camera, then the insert.
  Future<void> _chooseImage() async {
    _commitText();
    final id = _page?['id'] as String?;
    if (id == null || !_canEditPage(id)) {
      _blocked();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final src = await showModalBottomSheet<IntakeSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.imageFromGallery),
              onTap: () => Navigator.pop(context, IntakeSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.imageFromCamera),
              onTap: () => Navigator.pop(context, IntakeSource.camera),
            ),
          ],
        ),
      ),
    );
    if (src != null && mounted) await _insertImage(src, id);
  }

  /// One image into the page the sheet was opened for, at the center of what
  /// is in view, selected. One `insertImage` = one undo step. The bytes are
  /// stored first: the element is never put in without them.
  Future<void> _insertImage(IntakeSource src, String pageId) async {
    final l10n = AppLocalizations.of(context);
    final r = await ref.read(imageIntakeProvider).pick(src);
    if (!mounted) return;
    final failure = r.failure;
    if (failure != null) {
      switch (failure) {
        case IntakeFailure.cancelled:
          break;
        case IntakeFailure.denied:
          await _permissionDialog();
        case IntakeFailure.tooLarge:
          _snack(l10n.imageTooLarge);
        case IntakeFailure.unsupported:
          _snack(l10n.imageUnsupported);
        case IntakeFailure.convertFailed:
          _snack(l10n.imageConvertFailed);
      }
      return;
    }
    final img = r.image!;
    final String hash;
    try {
      hash = await _assetStore.write(img.bytes, img.ext);
    } catch (_) {
      if (mounted) _snack(l10n.imageStoreFailed);
      return;
    }
    if (!mounted) return;
    _assetSync.markLocal(hash);
    final i = _pages.indexWhere((p) => p['id'] == pageId);
    if (i < 0 || !_canEditPage(pageId)) {
      _blocked();
      return;
    }
    final pw = (_pages[i]['width'] as num).toDouble();
    final ph = (_pages[i]['height'] as num).toDouble();
    final fit = imageInitialSize(img.pxWidth, img.pxHeight, pw, ph);
    final w = fit['width']!.toDouble(), h = fit['height']!.toDouble();
    // Centered on what is in view, kept on the page.
    final vp = _vp;
    final view = vp == null
        ? Offset(pw / 2, ph / 2)
        : vp.toPage(
                Offset(
                  _padding.left + (_size.width - _padding.horizontal) / 2,
                  _padding.top + (_size.height - _padding.vertical) / 2,
                ),
              ) -
              _geometry().rects[i].topLeft;
    final cx = view.dx.clamp(w / 2, math.max(w / 2, pw - w / 2));
    final cy = view.dy.clamp(h / 2, math.max(h / 2, ph - h / 2));
    final id = newId();
    final err = _history.doOp({
      'op': 'insertImage',
      'pageId': pageId,
      'asset': hash,
      'ext': img.ext,
      'pxWidth': img.pxWidth,
      'pxHeight': img.pxHeight,
      'x': cx - w / 2,
      'y': cy - h / 2,
      'width': w,
      'height': h,
    }, _ctx(ids: [id]));
    if (err != null) {
      _snack(l10n.strokeNotAdded);
      return;
    }
    if (img.converted) _snack(l10n.imageConverted);
    _setTool(_Tool.lasso);
    _select(pageId, {id});
    _tick.value++;
    _commit();
  }

  Future<void> _permissionDialog() async {
    final l10n = AppLocalizations.of(context);
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.imagePermissionTitle),
        content: Text(l10n.imagePermissionReason),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.openSettings),
          ),
        ],
      ),
    );
    if (open == true) await ref.read(imageIntakeProvider).openSettings();
  }

  /// A [다시 시도] over each placeholder whose fetch failed.
  List<Widget> _retryButtons(AppLocalizations l10n) {
    final vp = _vp;
    if (vp == null) return const [];
    final rects = _geometry().rects;
    return [
      for (var i = 0; i < _pages.length; i++)
        for (final e in _pages[i]['elements'] as List)
          if (drawableImage(e) &&
              _images.state('${(e as Map)['asset']}') == AssetState.failed)
            () {
              final m = e as Map<String, dynamic>;
              final c =
                  vp.offset +
                  (rects[i].topLeft +
                          Offset(
                            (m['x'] as num).toDouble() +
                                (m['width'] as num).toDouble() / 2,
                            (m['y'] as num).toDouble() +
                                (m['height'] as num).toDouble() / 2,
                          )) *
                      vp.scale;
              return Positioned(
                left: c.dx - 56,
                top: c.dy + 8,
                width: 112,
                height: KkjTokens.spacingHitMinAndroid,
                child: TextButton(
                  onPressed: () =>
                      _assetSync.retry('${m['asset']}', '${m['ext']}'),
                  child: Text(l10n.imageRetry),
                ),
              );
            }(),
    ];
  }

  void _setTool(_Tool t) {
    if (t == _tool || _pointer != null) return;
    _commitText();
    setState(() => _tool = t);
    _select(null, {});
  }

  // ---- text boxes (Story 4.9) -------------------------------------------

  // The text box being edited: nothing is stored until it is confirmed.
  _TextEdit? _te;
  // A text-tool press that becomes a new box when it ends as a tap.
  ({int pointer, String pageId, Offset page})? _textTap;
  // The press that may become the first tap of a double tap.
  int _tapPointer = -1;
  Offset _tapAt = Offset.zero;
  Duration _tapTime = Duration.zero;
  ({Duration t, Offset at, int depth})? _lastTap;

  static const _tapSlop = 10.0;
  static const _doubleTapGap = Duration(milliseconds: 350);
  static const _caretGap = 24.0;

  bool _canEditPage(String pageId) =>
      !_readOnly && !_receiving && !_history.isLocked(pageId);

  /// The element the edit shows now (stored fields, current text and runs).
  Map<String, dynamic> _teElement(_TextEdit te) => {
    ...te.base,
    'type': 'text',
    'x': te.x,
    'y': te.y,
    'width': te.width,
    'rotation': te.rotation,
    'text': te.ctl.text,
    'runs': te.ctl.runs,
  };

  void _beginText(String pageId, Offset at, [Map<String, dynamic>? el]) {
    _commitText();
    if (!_canEditPage(pageId) || !_pages.any((p) => p['id'] == pageId)) return;
    final page = _pages.firstWhere((p) => p['id'] == pageId);
    final base = <String, dynamic>{
      'size': el?['size'] is num
          ? (el!['size'] as num).toDouble().clamp(sizeMin, sizeMax)
          : sizeDefault,
      'color': el?['color'] is String ? el!['color'] : colorDefault,
      'bold': el?['bold'] == true,
      'italic': el?['italic'] == true,
    };
    final text = el?['text'] as String? ?? '';
    final ctl = StyledTextController(
      text: text,
      runs: el?['runs'] is List ? el!['runs'] as List : const [],
      base: base,
      scale: _vp?.scale ?? 1,
    );
    ctl.selection = TextSelection.collapsed(offset: text.length);
    final te = _TextEdit(
      pageId: pageId,
      element: el,
      base: base,
      x: el == null ? at.dx : (el['x'] as num).toDouble(),
      y: el == null ? at.dy : (el['y'] as num).toDouble(),
      width: el == null
          ? (page['width'] as num).toDouble() / 2
          : (el['width'] as num).toDouble(),
      rotation: ((el?['rotation'] as num?) ?? 0).toDouble(),
      ctl: ctl,
    );
    ctl.addListener(_teChanged);
    _select(null, {});
    setState(() => _te = te);
    _tick.value++;
  }

  void _teChanged() {
    if (!mounted) return;
    setState(() {});
    _tick.value++;
  }

  /// Confirms the box being edited: one op, one undo step (none for an
  /// unchanged box or a blank new one).
  void _commitText() {
    final te = _te;
    if (te == null) return;
    _te = null;
    te.ctl.removeListener(_teChanged);
    te.focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      te.ctl.dispose();
      te.focus.dispose();
    });
    final text = te.ctl.text, runs = te.ctl.runs, el = te.element;
    final ids = <String>[];
    Map<String, dynamic>? op;
    if (el == null) {
      ids.add(newId());
      op = {
        'op': 'createTextBox',
        'pageId': te.pageId,
        'x': te.x,
        'y': te.y,
        'width': te.width,
        'text': text,
        'runs': runs,
      };
    } else if (text != el['text'] ||
        !jsonEqual(
          runs,
          normalizeRuns(el['runs'] as List? ?? const [], cpLen(text)),
        )) {
      op = {
        'op': 'editText',
        'pageId': te.pageId,
        'id': el['id'],
        'text': text,
        'runs': runs,
      };
    }
    String? err;
    if (op != null && _canEditPage(te.pageId)) {
      err = _history.doOp(op, _ctx(ids: ids));
    }
    if (err == 'pageReadOnly') {
      _blocked();
    } else if (err != null) {
      _snack(AppLocalizations.of(context).strokeNotAdded);
    }
    // The keyboard is gone: the view may sit past the page end again.
    if (_vp != null && _fit == _Fit.free) _vp = _clamp(_vp!);
    setState(() {});
    _tick.value++;
    if (op != null && err == null) _commit();
  }

  /// The text box under [local] (screen), topmost, with its page.
  (String, Map<String, dynamic>)? _textAt(Offset local) {
    final vp = _vp;
    if (vp == null) return null;
    final p = vp.toPage(local);
    final i = _pageAt(p);
    if (i < 0) return null;
    final page = _pages[i], o = p - _geometry().rects[i].topLeft;
    final texts = [
      for (final e in page['elements'] as List)
        if ((e as Map)['type'] == 'text' && e['text'] is String)
          e.cast<String, dynamic>(),
    ];
    final id = selectTap(texts, (o.dx, o.dy), 0);
    if (id == null) return null;
    return (page['id'] as String, texts.firstWhere((e) => e['id'] == id));
  }

  /// Scrolls so that the caret ends [_caretGap] above the keyboard.
  void _revealCaret(double keyboard) {
    final te = _te, vp = _vp;
    if (te == null || vp == null || keyboard <= 0) return;
    final i = _pages.indexWhere((p) => p['id'] == te.pageId);
    if (i < 0) return;
    final lay = layoutText(_teElement(te));
    final cp = te.ctl.caretCp;
    final line = lay.lines.firstWhere(
      (l) => cp < l.end,
      orElse: () => lay.lines.last,
    );
    final doc =
        _geometry().rects[i].topLeft +
        Offset(te.x, te.y + line.top + line.height);
    final y = vp.offset.dy + doc.dy * vp.scale;
    final over = y - (_size.height - keyboard - _caretGap);
    if (over > 0.5) {
      _fit = _Fit.free;
      setState(() => _vp = PageViewport(vp.scale, vp.offset - Offset(0, over)));
    }
  }

  /// Overlay widgets of the box being edited: the field and the format bar.
  List<Widget> _editOverlay(EdgeInsets pad, double keyboard) {
    final te = _te!, vp = _vp!;
    final i = _pages.indexWhere((p) => p['id'] == te.pageId);
    if (i < 0) {
      // A merge took the page away: the edit is gone with it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _te == te) {
          _te = null;
          te.ctl.removeListener(_teChanged);
          te.focus.unfocus();
          te.ctl.dispose();
          te.focus.dispose();
          setState(() {});
          _tick.value++;
        }
      });
      return const [];
    }
    final s = vp.scale;
    te.ctl.scale = s;
    final tl =
        vp.offset + (_geometry().rects[i].topLeft + Offset(te.x, te.y)) * s;
    final h = layoutText(_teElement(te)).height * s;
    const gap = KkjTokens.spacing3;
    final bar = textFormatBarSize;
    final minTop = pad.top + gap + _toolbarHeight + gap;
    final maxBottom = _size.height - math.max(keyboard, pad.bottom);
    final aboveRoom = tl.dy - 8 - bar.height >= minTop;
    final left = tl.dx
        .clamp(
          pad.left,
          math.max(pad.left, _size.width - pad.right - bar.width),
        )
        .toDouble();
    final base = te.base;
    final color = parseColor(base['color']);
    return [
      Positioned(
        left: tl.dx,
        top: tl.dy,
        width: te.width * s,
        child: Transform.rotate(
          angle: te.rotation * math.pi / 180,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(color: KkjLight.componentsSelectionOutline),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: h),
              child: TextField(
                controller: te.ctl,
                focusNode: te.focus,
                autofocus: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration.collapsed(hintText: null),
                scrollPadding: EdgeInsets.zero,
                cursorColor: color,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: (base['size'] as double) * s,
                  height: lineHeight,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
      if (aboveRoom)
        Positioned(
          left: left,
          bottom: _size.height - tl.dy + 8,
          child: TextFormatBar(controller: te.ctl, panelFirst: true),
        )
      else
        Positioned(
          left: left,
          top: math.min(
            tl.dy + h + 8,
            math.max(minTop, maxBottom - bar.height),
          ),
          child: TextFormatBar(controller: te.ctl),
        ),
    ];
  }

  // Where a blank lasso tap landed (page id, document point): the small
  // paste / select-all menu hangs there until anything else happens.
  (String, Offset)? _blank;

  void _select(String? pageId, Set<String> ids) {
    _blank = null;
    final same = ids.length == _selected.length && _selected.containsAll(ids);
    setState(() {
      _selPage = ids.isEmpty ? null : pageId;
      _selected = ids;
    });
    if (!same && ids.isNotEmpty && mounted) {
      _announce(AppLocalizations.of(context).selectedCount(ids.length));
    }
  }

  /// Document-space box of the selection. Ids that are gone (undo, a merge,
  /// a removed page) are pruned here; an empty selection is cleared.
  Rect? _selectionBox() {
    if (_selected.isEmpty) return null;
    final i = _pages.indexWhere((p) => p['id'] == _selPage);
    final els = i < 0
        ? <Map<String, dynamic>>[]
        : [
            for (final e in _pages[i]['elements'] as List)
              if (_selected.contains((e as Map)['id']))
                e.cast<String, dynamic>(),
          ];
    if (els.length != _selected.length) {
      _selected = {for (final e in els) e['id'] as String};
      if (_selected.isEmpty) _selPage = null;
    }
    return selectionBounds(els)?.shift(_geometry().rects[i].topLeft);
  }

  void _clearSelection() {
    if (_selected.isNotEmpty) {
      _select(null, {});
    } else if (_blank != null) {
      setState(() => _blank = null);
    }
  }

  List<Map<String, dynamic>> _selEls() => [
    for (final e
        in (_pages.firstWhere(
              (p) => p['id'] == _selPage,
              orElse: () => {'elements': []},
            )['elements']
            as List))
      if (_selected.contains((e as Map)['id'])) e.cast<String, dynamic>(),
  ];

  void _copy() => ref.read(elementClipboardProvider.notifier).set(_selEls());

  void _cut() {
    if (!_canEditSel) return;
    _copy();
    _delete();
  }

  void _delete() {
    final page = _selPage;
    if (page == null) return;
    _doSel({'op': 'delete', 'ids': _selected.toList()}, page);
    _clearSelection();
  }

  Future<void> _pickColor() async {
    final page = _selPage, ids = _selected.toList();
    final c = await pickStrokeColor(context);
    if (c != null && page != null && mounted) {
      _doSel({'op': 'setStrokeColor', 'ids': ids, 'color': c}, page);
    }
  }

  Future<void> _pickWidth() async {
    final page = _selPage, ids = _selected.toList();
    final first = _selEls().where((e) => e['type'] == 'stroke').firstOrNull;
    final w = await pickStrokeWidth(
      context,
      ((first?['width'] as num?) ?? 2).toDouble(),
    );
    if (w != null && page != null && mounted) {
      _doSel({'op': 'setStrokeWidth', 'ids': ids, 'width': w}, page);
    }
  }

  bool get _canPasteBlank {
    final b = _blank;
    return b != null &&
        !_readOnly &&
        !_receiving &&
        !_history.isLocked(b.$1) &&
        ref.read(elementClipboardProvider).isNotEmpty;
  }

  /// The blank-tap spot, or null (and cleared) when a merge removed its page.
  (String, Offset)? _liveBlank() {
    final b = _blank;
    if (b != null && !_pages.any((p) => p['id'] == b.$1)) _blank = null;
    return _blank;
  }

  void _pasteBlank() {
    final b = _liveBlank(), clip = ref.read(elementClipboardProvider);
    if (b == null || !_canPasteBlank) return;
    final at = b.$2 - _pageOrigin(b.$1);
    final ids = [for (final _ in clip) newId()];
    final err = _history.doOp({
      'op': 'paste',
      'pageId': b.$1,
      'elements': clip,
      'target': {
        'pageId': b.$1,
        'center': [at.dx, at.dy],
      },
    }, _ctx(ids: ids));
    if (err != null) {
      _snack(AppLocalizations.of(context).strokeNotAdded);
      return;
    }
    _select(b.$1, ids.toSet());
    _tick.value++;
    _commit();
  }

  void _selectAllBlank() {
    final b = _liveBlank();
    if (b == null) return;
    final els = _pages.firstWhere((p) => p['id'] == b.$1)['elements'] as List;
    _select(b.$1, {for (final e in els) (e as Map)['id'] as String});
  }

  // The aspect lock of the selection menu: UI state only, kept when the
  // selection goes away.
  bool _ratioLock = true;
  // The drag of the selection in progress (move, scale or rotate).
  _Xf? _xf;

  bool get _canEditSel =>
      _selPage != null &&
      !_readOnly &&
      !_receiving &&
      !_history.isLocked(_selPage);

  Offset _pageOrigin(String? pageId) =>
      _geometry().rects[_pages.indexWhere((p) => p['id'] == pageId)].topLeft;

  /// Starts a move, scale or rotate when [e] lands on the selection box or a
  /// handle. Screen-space hits: handles are 48 dp wide, the box itself moves.
  bool _beginXform(PointerDownEvent e) {
    if (_tool != _Tool.lasso || _pointer != null || !_canEditSel) return false;
    final b = _selectionBox(), vp = _vp;
    if (b == null || vp == null) return false;
    final r = Rect.fromPoints(
      vp.offset + b.topLeft * vp.scale,
      vp.offset + b.bottomRight * vp.scale,
    );
    const reach = KkjTokens.spacingHitMinAndroid / 2;
    final at = e.localPosition;
    final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    final corner = corners.indexWhere((c) => (at - c).distance <= reach);
    final inside = r.inflate(reach / 2).contains(at); // flat strokes too
    // A box smaller than the handles moves first; handles only outside it.
    final small = r.width < reach * 2 || r.height < reach * 2;
    // The side handles of a single text box change its width.
    final ts = _textSel();
    // A corner at least as near as a side handle wins (short boxes).
    final nearCorner = corners.map((c) => (at - c).distance).reduce(math.min);
    final dl = ts == null
        ? double.infinity
        : (at - (vp.offset + ts.l * vp.scale)).distance;
    final dr = ts == null
        ? double.infinity
        : (at - (vp.offset + ts.r * vp.scale)).distance;
    final wk = math.min(dl, dr) > reach || math.min(dl, dr) >= nearCorner
        ? -1
        : (dl <= dr ? 0 : 1);
    var xc = corner;
    final _XKind kind;
    if (wk >= 0) {
      kind = _XKind.width;
      xc = wk;
    } else if ((at - Offset(r.center.dx, r.top - selectionRotateGap))
            .distance <=
        reach) {
      kind = _XKind.rotate;
    } else if (corner >= 0 && !(small && inside)) {
      kind = _XKind.scale;
    } else if (inside) {
      kind = _XKind.move;
    } else {
      return false;
    }
    _pointer = e.pointer;
    _strokePageId = _selPage;
    _origin = _pageOrigin(_selPage);
    _xf = _Xf(kind, xc, b, vp.toPage(at), at);
    _tick.value++;
    return true;
  }

  /// A single selected text box that can be edited: the element and the
  /// points of its two side handles (document coordinates).
  ({Map<String, dynamic> el, Offset l, Offset r, double angle})? _textSel() {
    if (_tool != _Tool.lasso || _selected.length != 1 || !_canEditSel) {
      return null;
    }
    final el = _selEls().firstOrNull;
    if (el == null || el['type'] != 'text' || el['text'] is! String) {
      return null;
    }
    final w = math.max(widthMin, (el['width'] as num).toDouble());
    final c =
        _pageOrigin(_selPage) +
        Offset(
          (el['x'] as num).toDouble() + w / 2,
          (el['y'] as num).toDouble() + layoutText(el).height / 2,
        );
    final a = ((el['rotation'] as num?) ?? 0).toDouble() * math.pi / 180;
    final u = Offset(math.cos(a), math.sin(a)) * (w / 2);
    return (el: el, l: c - u, r: c + u, angle: a);
  }

  /// What the drag to [local] would do: the op, and the box it would leave
  /// (document coordinates, turned by `angle` radians). Null when it changes
  /// nothing.
  ({Map<String, dynamic> op, Rect box, double angle})? _xfResult(
    _Xf x,
    Offset local,
  ) {
    final p = _vp!.toPage(local), b = x.box;
    switch (x.kind) {
      case _XKind.move:
        final d = p - x.down;
        if (d.distance * _vp!.scale < 1) return null;
        return (
          op: {'op': 'move', 'dx': d.dx, 'dy': d.dy},
          box: b.shift(d),
          angle: 0.0,
        );
      case _XKind.scale:
        final cs = [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft];
        final c = cs[x.corner], anchor = cs[(x.corner + 2) % 4];
        final v0 = c - anchor;
        final v = p - x.down + v0; // dragged corner, from the anchor
        var sx = 1.0, sy = 1.0;
        if (_ratioLock) {
          final l2 = v0.dx * v0.dx + v0.dy * v0.dy;
          if (l2 > 0) sx = sy = (v.dx * v0.dx + v.dy * v0.dy) / l2;
        } else {
          if (v0.dx != 0) sx = v.dx / v0.dx;
          if (v0.dy != 0) sy = v.dy / v0.dy;
        }
        sx = math.max(sx, _minScale);
        sy = math.max(sy, _minScale);
        if (sx == 1 && sy == 1) return null;
        Offset m(Offset q) =>
            anchor + Offset((q.dx - anchor.dx) * sx, (q.dy - anchor.dy) * sy);
        final a = anchor - _origin;
        return (
          op: {
            'op': 'scale',
            'sx': sx,
            'sy': sy,
            'anchor': [a.dx, a.dy],
          },
          box: Rect.fromPoints(m(b.topLeft), m(b.bottomRight)),
          angle: 0.0,
        );
      case _XKind.width:
        final t = _textSel();
        if (t == null) return null;
        final w = math.max(widthMin, (t.el['width'] as num).toDouble());
        final d = p - x.down;
        final along = d.dx * math.cos(t.angle) + d.dy * math.sin(t.angle);
        final nw = math.max(widthMin, w + (x.corner == 1 ? along : -along));
        if ((nw - w).abs() < 0.01) return null;
        final o = _pageOrigin(_selPage);
        return (
          op: {'op': 'setTextBoxWidth', 'id': t.el['id'], 'width': nw},
          box: Rect.fromLTWH(
            o.dx + (t.el['x'] as num).toDouble(),
            o.dy + (t.el['y'] as num).toDouble(),
            nw,
            layoutText({...t.el, 'width': nw}).height,
          ),
          angle: t.angle,
        );
      case _XKind.rotate:
        final o = b.center;
        var a =
            math.atan2(p.dy - o.dy, p.dx - o.dx) -
            math.atan2(x.down.dy - o.dy, x.down.dx - o.dx);
        a = math.atan2(math.sin(a), math.cos(a)); // into (-pi, pi]
        final deg = a * 180 / math.pi;
        if (deg.abs() < 0.01) return null;
        return (op: {'op': 'rotate', 'angle': deg}, box: b, angle: a);
    }
  }

  /// Ends the drag: one op, one undo step; nothing for a zero change.
  void _finishXform(Offset local) {
    final x = _xf, pageId = _selPage;
    final r = x == null ? null : _xfResult(x, local);
    final ids = _selected.toList();
    _xf = null;
    _pointer = null;
    if (_mode == _Mode.pen || _mode == _Mode.ignored) _mode = _Mode.none;
    if (r != null && pageId != null) _doSel({...r.op, 'ids': ids}, pageId);
    setState(() {});
    _tick.value++;
    _strokeEnded(pageId);
  }

  /// Applies a selection op to [pageId] and saves it.
  void _doSel(Map<String, dynamic> op, String pageId) {
    if (!_canEditSel) return;
    final err = _history.doOp({...op, 'pageId': pageId}, _ctx());
    if (err == 'pageReadOnly') {
      _blocked();
    } else if (err == 'elementNotFound') {
      _clearSelection(); // a merge took the element away
    } else if (err != null) {
      _snack(AppLocalizations.of(context).strokeNotAdded);
    }
    setState(() {});
    _tick.value++;
    if (err == null) _commit();
  }

  /// A menu step about the selection center: scale by [f], or rotate 90.
  void _step(_XKind kind, [double f = 1]) {
    final b = _selectionBox(), page = _selPage;
    if (b == null || page == null || _xf != null || _pointer != null) return;
    final o = b.center - _pageOrigin(page);
    _doSel({
      'ids': _selected.toList(),
      ...kind == _XKind.rotate
          ? {'op': 'rotate', 'angle': 90}
          : {
              'op': 'scale',
              'sx': f,
              'sy': f,
              'anchor': [o.dx, o.dy],
            },
    }, page);
  }

  /// Top-left of the floating menu: above the box (below when there is no
  /// room), clamped into the screen.
  Offset _menuAt(Rect box, EdgeInsets pad, Size size) {
    final vp = _vp!;
    final r = Rect.fromPoints(
      vp.offset + box.topLeft * vp.scale,
      vp.offset + box.bottomRight * vp.scale,
    );
    const gap = KkjTokens.spacing3, m = selectionHandleRadius + 8;
    final min = pad.top + gap + _toolbarHeight + gap;
    final max = math.max(min, _size.height - pad.bottom - size.height);
    final above = r.top - selectionRotateGap - m - size.height;
    final below = r.bottom + m;
    final top = selectionMenuPrefersAbove
        ? (above >= min ? above : below)
        : (below <= max ? below : above);
    final left = ((r.center.dx - size.width / 2).clamp(
      pad.left,
      math.max(pad.left, _size.width - pad.right - size.width),
    )).toDouble();
    return Offset(left, top.clamp(min, max).toDouble());
  }

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

  Ctx _ctx({List<String> ids = const []}) => Ctx(
    ids: ids,
    rev: newId(),
    now: canonicalNow(DateTime.now()),
    editedBy: deviceEditedBy,
    lastSeenRemoteSeq: _lastSeen,
  );

  /// Queues the history's current note for saving.
  void _commit() {
    _syncAssets();
    _latest = _history.note;
    _running ??= _drain().whenComplete(() => _running = null);
  }

  void _undo() => _replay(true);
  void _redo() => _replay(false);

  void _replay(bool undo) {
    _commitText();
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
    WidgetsBinding.instance.addObserver(this);
    // No upload of this note while it is open; a background upload asks the
    // queue to reach the disk first.
    _openNote.set(widget.note.noteId);
    _coordinator.flushOpen = _flush;
    // A sync result for this note is merged into this queue and history.
    _hosts.register(widget.note.noteId, _host);
    _images.addListener(_onAssets);
    _syncAssets();
    _loadLastSeen();
    // A receive may have replaced the note before the mark was set.
    unawaited(_rereadDisk());
    // Asks Drive whether the note is current (not awaited: never blocks
    // opening).
    unawaited(ref.read(noteReceiverProvider).noteOpened(widget.note.noteId));
    if (_receiving) _watchReceiving(true);
    if (widget.openResolveSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSheet());
    }
  }

  /// The note on disk differs from the one this editor opened with (a
  /// receive landed first): start from the disk's. Not when this editor
  /// already has strokes of its own that are not saved.
  Future<void> _rereadDisk() async {
    try {
      final disk = (await _store.read(widget.note.noteId))?.note;
      if (disk == null || !mounted || _readOnly) return;
      if (_same(disk.copyJson(), _history.note.copyJson())) return;
      if (_pointer != null ||
          _running != null ||
          _latest != null ||
          _failed != null) {
        return;
      }
      _history.adopt(disk, {
        for (final p in _history.note.pages) p['id'] as String,
      });
      _syncAssets();
      _relayout();
      setState(() {});
      _tick.value++;
    } catch (_) {}
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
    _syncSoon();
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
        lastSeen: 0,
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

  /// The upload of a change that just happened (the note stays open); the
  /// version history reloads when it is done.
  Future<void>? _lastSync;

  void _syncSoon() {
    final id = widget.note.noteId;
    late final Future<void> f;
    f = _coordinator.syncNow(id).catchError((Object _) {}).whenComplete(() {
      if (identical(_lastSync, f))
        _lastSync = null; // done: nothing to wait for
    });
    _lastSync = f;
  }

  Future<void> _openHistory() async {
    if (_leaving || !mounted) return;
    final restored = await showVersionHistory(
      context,
      noteId: widget.note.noteId,
      onRestore: _restoreVersion,
      sync: () => _lastSync,
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
      _syncSoon();
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
        if (!await _flush())
          return false; // not on disk: no upload, `_lastSeen` stays
        // Only once the merge is adopted and saved: a stroke that follows takes a seq above it.
        if (r.lastSeen > _lastSeen) _lastSeen = r.lastSeen;
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
  /// one). Never throws; false when a save is still not on disk.
  Future<bool> _flush() async {
    try {
      await _running;
      final f = _failed;
      if (f != null) {
        await _store.write(f);
        _failed = null;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Typed text must not wait for a process the OS may kill.
    if (state != AppLifecycleState.resumed) _commitText();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _latestTimer?.cancel();
    _emphasisTimer?.cancel();
    _zoomBadgeTimer?.cancel();
    _zoomBadge.dispose();
    _strokeEnded(null);
    if (_coordinator.flushOpen == _flush) _coordinator.flushOpen = null;
    _hosts.unregister(widget.note.noteId, _host);
    _images.removeListener(_onAssets);
    _images.dispose();
    _openNote.clear(widget.note.noteId);
    _anim.dispose();
    _tick.dispose();
    _slotFocus.dispose();
    _canvasFocus.dispose();
    final te = _te;
    if (te != null) {
      te.ctl.removeListener(_teChanged);
      te.ctl.dispose();
      te.focus.dispose();
    }
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
    if (_consumedByText(e)) return;
    switch (e.kind) {
      case PointerDeviceKind.touch:
        _touchDown(e);
      case PointerDeviceKind.stylus || PointerDeviceKind.mouse:
        _penDown(e);
      default:
        break; // eraser (Epic 4), trackpad, unknown: no input
    }
  }

  /// Text editing owns a press first: outside the box a press only confirms
  /// the box; a second tap on a box starts editing it.
  bool _consumedByText(PointerDownEvent e) {
    if (_te != null) {
      _commitText();
      if (_mode == _Mode.none) _mode = _Mode.ignored;
      return true;
    }
    final last = _lastTap;
    if (last != null &&
        _touches.isEmpty &&
        e.timeStamp - last.t < _doubleTapGap &&
        (e.localPosition - last.at).distance < 48) {
      _lastTap = null;
      final hit = _textAt(e.localPosition);
      if (hit != null && _canEditPage(hit.$1)) {
        // The first tap of the pair may have drawn a pen dot: take it back.
        if (_tool == _Tool.pen && _history.undoDepth == last.depth + 1) {
          _history.undo(_ctx());
          _commit();
        }
        if (_mode == _Mode.none) _mode = _Mode.ignored;
        _beginText(hit.$1, Offset.zero, hit.$2);
        return true;
      }
    }
    _tapPointer = _touches.isEmpty && _pointer == null ? e.pointer : -1;
    _tapAt = e.localPosition;
    _tapTime = e.timeStamp;
    return false;
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
        if (_beginXform(e)) {
          _mode = _Mode.ignored;
          setState(() {});
          return;
        }
        if (!_stylusSeen && at >= 0) {
          _mode = _Mode.touchStroke;
          _begin(e, p, at);
        } else {
          if (!_stylusSeen && _tool == _Tool.lasso) _clearSelection();
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
    if (_beginXform(e)) {
      _mode = _Mode.pen;
      setState(() {});
      return;
    }
    final p = _vp!.toPage(e.localPosition);
    final at = _pageAt(p);
    if (at < 0) {
      if (_tool == _Tool.lasso) _clearSelection(); // a tap in the margin
      return;
    }
    _mode = _Mode.pen;
    _begin(e, p, at);
  }

  void _begin(PointerDownEvent e, Offset doc, int index) {
    // A page with an unresolved conflict is read-only (Story 3.19): no
    // stroke; a finger may still pinch.
    final target = _pages[index];
    // Selecting (to copy) works on read-only and locked pages too.
    final select = _tool == _Tool.lasso;
    if (!select && _history.isLocked(target['id'] as String?)) {
      _blocked();
      _mode = _mode == _Mode.touchStroke ? _Mode.touchIdle : _Mode.ignored;
      return;
    }
    // The note is being received or is read-only: no stroke (Stories 3.13,
    // 3.17).
    if (!select && (_receiving || _readOnly)) {
      _mode = _Mode.ignored;
      return;
    }
    if (_tool == _Tool.text) {
      // A tap on a blank spot makes a box when the press ends.
      _textTap = (
        pointer: e.pointer,
        pageId: target['id'] as String,
        page: doc,
      );
      if (_mode == _Mode.touchStroke) _mode = _Mode.touchIdle;
      return;
    }
    _pointer = e.pointer;
    _strokePageId = target['id'] as String;
    _origin = _geometry().rects[index].topLeft;
    if (_tool == _Tool.lasso) {
      _lassoing = true;
      _lassoMoved = false;
      _lassoDown = e.localPosition;
      _lassoPts
        ..clear()
        ..add(doc);
      _tick.value++;
      return;
    }
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
    _lassoing = false;
    _lassoPts.clear();
    final dragged = _xf != null;
    _xf = null;
    if (dragged && mounted) setState(() {});
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
    if ((e.pointer == _tapPointer || _textTap?.pointer == e.pointer) &&
        (e.localPosition - _tapAt).distance > _tapSlop) {
      _tapPointer = -1;
      _textTap = null;
    }
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
    if (_xf != null) {
      _xf!.last = e.localPosition;
      _tick.value++;
      return;
    }
    if (_lassoing) {
      _lassoPts.add(_vp!.toPage(e.localPosition));
      if ((e.localPosition - _lassoDown).distance > 8) _lassoMoved = true;
      _tick.value++;
      return;
    }
    // Not clipped here: points outside the page are kept.
    _points.add(_point(e, _vp!.toPage(e.localPosition) - _origin));
    _tick.value++;
  }

  void _up(PointerUpEvent e) {
    final vp = _vp;
    final tapped =
        e.pointer == _tapPointer &&
        (e.localPosition - _tapAt).distance < _tapSlop &&
        e.timeStamp - _tapTime < const Duration(milliseconds: 400) &&
        _mode != _Mode.gesture;
    if (e.pointer == _tapPointer) {
      _tapPointer = -1;
      _lastTap = tapped
          ? (t: e.timeStamp, at: e.localPosition, depth: _history.undoDepth)
          : null;
    }
    final tt = _textTap;
    if (tt != null && tt.pointer == e.pointer) {
      _textTap = null;
      if (tapped && !_leaving) _textTapped(tt);
    }
    if (!_leaving && vp != null && e.pointer == _pointer) {
      if (_xf != null) {
        _finishXform(e.localPosition);
        _release(e.pointer);
        return;
      }
      if (_lassoing) {
        _lassoPts.add(vp.toPage(e.localPosition));
        // A flick can move only between the last move and the up.
        if ((e.localPosition - _lassoDown).distance > 8) _lassoMoved = true;
        _finish();
        _release(e.pointer);
        return;
      }
      final p = vp.toPage(e.localPosition) - _origin;
      final last = _points.last;
      if (last[0] != p.dx || last[1] != p.dy) _points.add(_point(e, p));
      _finish();
    }
    _release(e.pointer);
  }

  /// A text-tool tap: a new box on a blank spot (an element there: nothing).
  void _textTapped(({int pointer, String pageId, Offset page}) tt) {
    if (!_pages.any((p) => p['id'] == tt.pageId)) return;
    final o = tt.page - _pageOrigin(tt.pageId);
    final els = [
      for (final e
          in _pages.firstWhere((p) => p['id'] == tt.pageId)['elements'] as List)
        (e as Map).cast<String, dynamic>(),
    ];
    if (selectTap(els, (o.dx, o.dy), 0) == null) _beginText(tt.pageId, o);
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer == _tapPointer) _tapPointer = -1;
    if (_textTap?.pointer == e.pointer) _textTap = null;
    if (e.pointer == _pointer) {
      _lassoing || _xf != null ? _discardStroke() : _finish();
    }
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
    if (_xf != null) {
      _discardStroke(); // leaving mid-drag: no half-done change
      return;
    }
    final pageId = _strokePageId;
    if (pageId == null || !_pages.any((p) => p['id'] == pageId)) {
      // A merge took the page away while the stroke was being drawn.
      _discardStroke();
      return;
    }
    if (_lassoing) {
      _finishLasso(pageId);
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

  void _finishLasso(String pageId) {
    final tapDoc = _lassoPts.first;
    final els = [
      for (final e
          in _pages.firstWhere((p) => p['id'] == pageId)['elements'] as List)
        (e as Map).cast<String, dynamic>(),
    ];
    final List<String> ids;
    if (_lassoMoved) {
      ids = selectLasso(els, [
        for (final p in _lassoPts) (p.dx - _origin.dx, p.dy - _origin.dy),
      ]);
    } else {
      final p = _lassoPts.first - _origin;
      final hit = selectTap(els, (p.dx, p.dy), 6);
      ids = hit == null ? [] : [hit];
    }
    _pointer = null;
    _lassoing = false;
    _lassoPts.clear();
    if (_mode == _Mode.pen || _mode == _Mode.touchStroke) _mode = _Mode.none;
    _select(pageId, ids.toSet());
    if (ids.isEmpty && !_lassoMoved) {
      setState(() => _blank = (pageId, tapDoc));
    }
    _tick.value++;
    // Only releases a merge waiting for the pointer; nothing is saved here.
    _strokeEnded(pageId);
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
    _commitText();
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
          if (didPop) return;
          // Back confirms a text box being edited and stays.
          if (_te != null) {
            _commitText();
          } else {
            _leave();
          }
        },
        child: Scaffold(
          // The keyboard is handled here: the page scrolls to the caret.
          resizeToAvoidBottomInset: false,
          backgroundColor: KkjLight.colorSurfaceSunken,
          body: Builder(builder: _body),
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
                  hidden: () => _te?.element?['id'] as String?,
                  images: _images,
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
    _images
      ..downloadingLabel = l10n.imageDownloading
      ..failedLabel = l10n.imageDownloadFailed
      ..imageLabel = l10n.imageSemantics
      ..pendingLabel = l10n.imagePendingSemantics;
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
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (_te != null && keyboard > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealCaret(keyboard);
      });
    }
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
                          children: [
                            ..._pageViews(l10n),
                            CustomPaint(
                              size: Size.infinite,
                              painter: SelectionPainter(
                                viewport: _vp!,
                                box: _selectionBox(),
                                lasso: () => _lassoing ? _lassoPts : const [],
                                preview: () {
                                  final x = _xf;
                                  if (x == null) return null;
                                  final r = _xfResult(x, x.last);
                                  return r == null ? null : (r.box, r.angle);
                                },
                                widthHandles: () {
                                  final t = _textSel();
                                  return t == null ? const [] : [t.l, t.r];
                                },
                                repaint: _tick,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            if (page != null) ..._retryButtons(l10n),
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
            // Over the page, under the toolbar: it stays put while the page
            // scrolls and never pushes the toolbar or the menu down.
            Positioned(
              top: pad.top + gap + _toolbarHeight + gap,
              left: 0,
              right: 0,
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: SyncBanner(
                  noteId: widget.note.noteId,
                  onCloseNote: () => Navigator.of(context).maybePop(),
                  onResolve: _openSheet,
                  emphasis: _emphasis,
                ),
              ),
            ),
            if (page != null &&
                _xf == null &&
                !_lassoing &&
                (_selected.isNotEmpty || _blank != null))
              Builder(
                builder: (context) {
                  final box = _selectionBox();
                  final blank = _liveBlank();
                  final vp = _vp;
                  if (box == null) {
                    if (blank == null || vp == null || _tool != _Tool.lasso) {
                      return const Positioned(child: SizedBox.shrink());
                    }
                    final p = vp.offset + (blank.$2 * vp.scale);
                    return Positioned(
                      left: (p.dx - 100).clamp(
                        pad.left,
                        math.max(pad.left, _size.width - pad.right - 200),
                      ),
                      top: (p.dy + 8).clamp(
                        pad.top + gap + _toolbarHeight + gap,
                        math.max(
                          pad.top + gap + _toolbarHeight + gap,
                          _size.height - pad.bottom - 64,
                        ),
                      ),
                      child: BlankTapMenu(
                        canPaste: _canPasteBlank,
                        onPaste: _pasteBlank,
                        onSelectAll: _selectAllBlank,
                      ),
                    );
                  }
                  final edit = _canEditSel;
                  final strokes = _selEls().any((e) => e['type'] == 'stroke');
                  final at = _menuAt(
                    box,
                    pad,
                    selectionMenuSize(edit: edit, strokes: strokes),
                  );
                  return Positioned(
                    left: at.dx,
                    top: at.dy,
                    child: SelectionMenu(
                      edit: edit,
                      strokes: strokes,
                      ratioLock: _ratioLock,
                      onRatioLock: () =>
                          setState(() => _ratioLock = !_ratioLock),
                      onScaleUp: () => _step(_XKind.scale, 1.25),
                      onScaleDown: () => _step(_XKind.scale, 0.8),
                      onRotate90: () => _step(_XKind.rotate),
                      onCopy: _copy,
                      onColor: _pickColor,
                      onWidth: _pickWidth,
                      onCut: _cut,
                      onDelete: _delete,
                    ),
                  );
                },
              ),
            if (_te != null && page != null && _vp != null)
              ..._editOverlay(pad, keyboard),
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
                      // Hidden while the keyboard is open.
                      if (keyboard <= 0)
                        PenToolbar(
                          pen: ref.watch(penSlotsProvider).first,
                          onPenTap: _tool != _Tool.pen
                              ? () => _setTool(_Tool.pen)
                              : _editPen,
                          lassoSelected: _tool == _Tool.lasso,
                          onLasso: () => _setTool(_Tool.lasso),
                          textSelected: _tool == _Tool.text,
                          onText: () => _setTool(_Tool.text),
                          onImage: readOnly || receiving || locked
                              ? null
                              : _chooseImage,
                          slotFocus: _slotFocus,
                          canUndo:
                              !readOnly && !locked && _history.undoDepth > 0,
                          canRedo:
                              !readOnly && !locked && _history.redoDepth > 0,
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
