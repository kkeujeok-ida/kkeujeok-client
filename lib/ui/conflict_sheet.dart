import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../render/page_painter.dart';
import 'shell.dart' show collapsedMinWidth, expandedMinWidth;

/// One unresolved conflict as the sheet shows it (Story 3.21).
class ConflictItem {
  const ConflictItem({
    required this.entry,
    required this.sidecar,
    this.current,
    this.otherTime,
  });

  /// The `sync.json` `conflicts` entry.
  final Map<String, Object?> entry;

  /// The sidecar record: this device's version (`page`).
  final Map<String, Object?> sidecar;

  /// The page of the note now: the other device's version. Null when the
  /// note has no such page (`remoteDeleted`).
  final Map<String, dynamic>? current;

  /// When the other device's version was uploaded (a Drive revision time);
  /// null offline, then the page's `editedAt` stands in.
  final DateTime? otherTime;

  String get pageId => entry['pageId'] as String;
  String get kind => (entry['kind'] as String?) ?? 'bothEdited';
  int get pageNo => ((entry['originalIndex'] as int?) ?? 0) + 1;
  bool get deleted => kind != 'bothEdited';

  /// Left preview: this device. Null when this device deleted the page.
  Map<String, dynamic>? get mine =>
      kind == 'localDeleted' ? null : sidecar['page'] as Map<String, dynamic>?;

  /// Right preview: the other device. Null when it deleted the page.
  Map<String, dynamic>? get theirs => kind == 'remoteDeleted' ? null : current;

  DateTime? get mineTime => _time(sidecar['editedAt']);
  DateTime? get theirsTime => otherTime ?? _time(current?['editedAt']);

  /// The `resolveConflict` choice for "this device" / "the other device";
  /// a deleted page follows the side pointed at (deleted = remove).
  String choiceFor({required bool thisDevice}) => switch (kind) {
    'bothEdited' => thisDevice ? 'mine' : 'theirs',
    'remoteDeleted' => thisDevice ? 'keep' : 'remove',
    _ => thisDevice ? 'remove' : 'keep',
  };

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

/// Settles the choices in order; answers the page ids that are settled.
typedef ResolveCallback = Future<Set<String>> Function(
  List<(ConflictItem, String)> choices,
);

/// Opens the resolve sheet: a centered dialog from 840 dp, else a bottom
/// sheet. Completes when it closes; true when every conflict was settled.
Future<bool> showConflictSheet(
  BuildContext context, {
  required List<ConflictItem> items,
  required ResolveCallback onResolve,
}) async {
  final body = _ConflictBody(items: items, onResolve: onResolve);
  final r = MediaQuery.sizeOf(context).width >= expandedMinWidth
      ? await showDialog<bool>(
          context: context,
          barrierColor: KkjLight.componentsConflictSheetScrim,
          builder: (_) => Dialog(
            backgroundColor: KkjLight.componentsConflictSheetBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                KkjLight.componentsConflictSheetRounded,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: body,
            ),
          ),
        )
      : await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: KkjLight.componentsConflictSheetBackground,
          barrierColor: KkjLight.componentsConflictSheetScrim,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KkjLight.componentsConflictSheetRounded),
            ),
          ),
          builder: (_) => body,
        );
  return r == true;
}

/// Elements of [page] whose id is not in [other], as one range in page
/// coordinates; null when there is none.
Rect? changedRange(Map<String, dynamic> page, Map<String, dynamic>? other) {
  final have = {
    for (final e in (other?['elements'] as List? ?? const []))
      if (e is Map && e['id'] is String) e['id'],
  };
  Rect? r;
  for (final e in (page['elements'] as List? ?? const [])) {
    if (!drawableStroke(e) || have.contains((e as Map)['id'])) continue;
    final half = (e['width'] as num).toDouble() / 2;
    for (final p in e['points'] as List) {
      final q = Rect.fromCenter(
        center: Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        width: half * 2,
        height: half * 2,
      );
      r = r == null ? q : r.expandToInclude(q);
    }
  }
  return r;
}

/// The thin `status-warning` outline over a fitted preview.
class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.page, this.range);

  final Map<String, dynamic> page;
  final Rect range;

  @override
  void paint(Canvas canvas, Size size) {
    final w = (page['width'] as num).toDouble();
    final h = (page['height'] as num).toDouble();
    if (!(w.isFinite && h.isFinite && w > 0 && h > 0)) return;
    final vp = PageViewport.fit(size, w, h, EdgeInsets.zero);
    canvas
      ..save()
      ..translate(vp.offset.dx, vp.offset.dy)
      ..scale(vp.scale)
      ..drawRect(
        range.inflate(4),
        Paint()
          ..color = KkjLight.componentsConflictSheetChangeOutline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / vp.scale,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      !identical(old.page, page) || old.range != range;
}

class _ConflictBody extends StatefulWidget {
  const _ConflictBody({required this.items, required this.onResolve});

  final List<ConflictItem> items;
  final ResolveCallback onResolve;

  @override
  State<_ConflictBody> createState() => _ConflictBodyState();
}

class _ConflictBodyState extends State<_ConflictBody> {
  late final List<ConflictItem> _items = [...widget.items];
  final _caches = <String, (StrokePathCache, StrokePathCache)>{};
  final _primary = FocusNode();
  final _restThis = GlobalKey(), _restOther = GlobalKey();
  int _pos = 0;
  bool _busy = false;

  /// The "rest" button that was tapped once: `true` = this device.
  bool? _confirm;

  ConflictItem get _item => _items[_pos];

  @override
  void dispose() {
    _primary.dispose();
    super.dispose();
  }

  void _focusPrimary() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _primary.requestFocus();
  });

  void _go(int to) {
    setState(() {
      _pos = to;
      _confirm = null;
    });
    _focusPrimary();
  }

  Future<void> _apply(List<(ConflictItem, String)> choices) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _confirm = null;
    });
    var settled = <String>{};
    try {
      settled = await widget.onResolve(choices);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      _items.removeWhere((i) => settled.contains(i.pageId));
      if (_pos >= _items.length) _pos = _items.length - 1;
    });
    if (settled.length < choices.length) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).conflictResolveFailed),
          ),
        );
      if (_items.isNotEmpty) _focusPrimary();
      return;
    }
    if (_items.isEmpty) {
      Navigator.of(context).pop(true);
    } else {
      _focusPrimary();
    }
  }

  void _rest(bool thisDevice) {
    if (_busy) return;
    if (_confirm != thisDevice) {
      setState(() => _confirm = thisDevice);
      return;
    }
    _apply([for (final i in _items) (i, i.choiceFor(thisDevice: thisDevice))]);
  }

  /// A tap anywhere but on a "rest" button takes the question back.
  void _pointerDown(PointerDownEvent e) {
    if (_confirm == null) return;
    for (final k in [_restThis, _restOther]) {
      final box = k.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        final r = box.localToGlobal(Offset.zero) & box.size;
        if (r.contains(e.position)) return;
      }
    }
    setState(() => _confirm = null);
  }

  /// Width over height kept in a sane range; 1 for a page with no usable size.
  static double _ratio(num w, num h) {
    final r = w / h;
    return r.isFinite && r > 0 ? r.clamp(0.4, 2.5).toDouble() : 1.0;
  }

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  ButtonStyle get _primaryStyle => FilledButton.styleFrom(
    backgroundColor: KkjLight.componentsConflictSheetPrimaryBackground,
    foregroundColor: KkjLight.componentsConflictSheetPrimaryText,
    minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        KkjLight.componentsConflictSheetPrimaryRounded,
      ),
    ),
  );

  ButtonStyle get _versionStyle => OutlinedButton.styleFrom(
    backgroundColor: KkjLight.componentsConflictSheetVersionButtonBackground,
    foregroundColor: KkjLight.componentsConflictSheetVersionButtonText,
    minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
    side: const BorderSide(
      color: KkjLight.componentsConflictSheetVersionButtonBorder,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        KkjLight.componentsConflictSheetVersionButtonRounded,
      ),
    ),
  );

  /// One side: tag, preview (or the deleted-page card), who and when, and
  /// its own button when there is one.
  Widget _side(
    BuildContext context, {
    required bool thisDevice,
    required Widget? button,
  }) {
    final l = AppLocalizations.of(context);
    final item = _item;
    final page = thisDevice ? item.mine : item.theirs;
    final tag = thisDevice ? l.conflictTagThis : l.conflictTagOther;
    final style = Theme.of(context).textTheme;
    final mineT = item.mineTime, theirsT = item.theirsTime;
    final newer = !item.deleted && mineT != null && theirsT != null
        ? (thisDevice ? mineT.isAfter(theirsT) : theirsT.isAfter(mineT))
        : false;
    final time = thisDevice ? mineT : theirsT;
    final by = thisDevice
        ? item.sidecar['editedBy']
        : item.current?['editedBy'];
    final when = page == null
        ? null
        : l.conflictEditedAt('${by ?? ''}', time == null ? '' : _fmt(time));
    final caches = _caches.putIfAbsent(
      item.pageId,
      () => (StrokePathCache(), StrokePathCache()),
    );
    final other = thisDevice ? item.theirs : item.mine;
    final range = page == null || other == null
        ? null
        : changedRange(page, other);

    final Widget box;
    if (page == null) {
      final w =
          (item.current?['width'] ??
                  (item.sidecar['page'] as Map?)?['width'] ??
                  1)
              as num;
      final h =
          (item.current?['height'] ??
                  (item.sidecar['page'] as Map?)?['height'] ??
                  1.4)
              as num;
      box = AspectRatio(
        aspectRatio: _ratio(w, h),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: KkjLight.componentsConflictSheetPreviewBorder,
            ),
            borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(KkjTokens.spacing3),
              child: Text(
                thisDevice ? l.conflictDeletedHere : l.conflictDeletedOther,
                textAlign: TextAlign.center,
                style: style.bodyMedium,
              ),
            ),
          ),
        ),
      );
    } else {
      final w = (page['width'] as num).toDouble();
      final h = (page['height'] as num).toDouble();
      box = Semantics(
        image: true,
        label: l.conflictPreviewSemantics(tag, item.pageNo),
        child: ExcludeSemantics(
          child: AspectRatio(
            aspectRatio: _ratio(w, h),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(
                  color: KkjLight.componentsConflictSheetPreviewBorder,
                ),
                borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
              ),
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: PagePainter(
                        page: page,
                        cache: thisDevice ? caches.$1 : caches.$2,
                      ),
                    ),
                    if (range != null)
                      CustomPaint(painter: _OutlinePainter(page, range)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: KkjLight.componentsConflictSheetTagBackground,
                    borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KkjTokens.spacing2,
                      vertical: KkjTokens.spacing1,
                    ),
                    child: Text(
                      tag,
                      style: style.labelMedium?.copyWith(
                        color: KkjLight.componentsConflictSheetTagText,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: KkjTokens.spacing2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Center(child: box),
              ),
              if (when != null) ...[
                const SizedBox(height: KkjTokens.spacing2),
                Text(when, style: style.bodySmall),
              ],
              if (newer)
                Text(
                  l.conflictMoreRecent,
                  style: style.labelMedium?.copyWith(
                    color: KkjLight.colorStatusWarningText,
                  ),
                ),
            ],
          ),
        ),
        if (button != null) ...[
          const SizedBox(height: KkjTokens.spacing2),
          button,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The last conflict was just settled; the route is closing.
    if (_items.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final item = _item;
    final sideBySide = MediaQuery.sizeOf(context).width >= collapsedMinWidth;
    final n = _items.length;

    Widget version(String text, VoidCallback f) => OutlinedButton(
      style: _versionStyle,
      onPressed: _busy ? null : f,
      child: Text(text),
    );
    Widget primary(String text, VoidCallback f) => FilledButton(
      focusNode: _primary,
      autofocus: true,
      style: _primaryStyle,
      onPressed: _busy ? null : f,
      child: Text(text),
    );
    void pick(String c) => _apply([(item, c)]);

    final Widget left, right;
    if (item.kind == 'bothEdited') {
      left = _side(
        context,
        thisDevice: true,
        button: version(l.conflictKeepThis, () => pick('mine')),
      );
      right = _side(
        context,
        thisDevice: false,
        button: version(l.conflictKeepOther, () => pick('theirs')),
      );
    } else {
      // The side that still has the page keeps it (primary); the side that
      // deleted it offers to delete.
      final keepThis = item.kind == 'remoteDeleted';
      Widget keep() => primary(l.conflictKeepVersion, () => pick('keep'));
      Widget remove() => version(l.conflictRemovePage, () => pick('remove'));
      left = _side(
        context,
        thisDevice: true,
        button: keepThis ? keep() : remove(),
      );
      right = _side(
        context,
        thisDevice: false,
        button: keepThis ? remove() : keep(),
      );
    }

    const gap = SizedBox(width: KkjTokens.spacing4, height: KkjTokens.spacing4);
    final previews = sideBySide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              gap,
              Expanded(child: right),
            ],
          )
        : Column(children: [left, gap, right]);

    Widget rest(GlobalKey key, bool thisDevice) {
      final armed = _confirm == thisDevice;
      return TextButton(
        key: key,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
        ),
        onPressed: _busy ? null : () => _rest(thisDevice),
        child: Text(
          armed
              ? l.conflictRestAllConfirm(n)
              : thisDevice
              ? l.conflictRestAllThis
              : l.conflictRestAllOther,
          textAlign: TextAlign.center,
        ),
      );
    }

    return PopScope(
      canPop: !_busy,
      child: Listener(
        onPointerDown: _pointerDown,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          label: l.conflictSheetTitle,
          explicitChildNodes: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KkjTokens.spacing5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l.conflictSheetTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: KkjTokens.spacing2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.conflictSheetProgress(item.pageNo, _pos + 1, n),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: l.conflictPrev,
                      constraints: const BoxConstraints(
                        minWidth: KkjTokens.spacingHitMinAndroid,
                        minHeight: KkjTokens.spacingHitMinAndroid,
                      ),
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _busy || _pos == 0
                          ? null
                          : () => _go(_pos - 1),
                    ),
                    IconButton(
                      tooltip: l.conflictNext,
                      constraints: const BoxConstraints(
                        minWidth: KkjTokens.spacingHitMinAndroid,
                        minHeight: KkjTokens.spacingHitMinAndroid,
                      ),
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _busy || _pos >= n - 1
                          ? null
                          : () => _go(_pos + 1),
                    ),
                  ],
                ),
                const SizedBox(height: KkjTokens.spacing2),
                Text(
                  l.conflictQuestion,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: KkjTokens.spacing3),
                previews,
                if (item.kind == 'bothEdited') ...[
                  const SizedBox(height: KkjTokens.spacing4),
                  primary(l.conflictKeepBoth, () => pick('both')),
                ],
                if (n >= 2) ...[
                  const SizedBox(height: KkjTokens.spacing2),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [rest(_restThis, true), rest(_restOther, false)],
                  ),
                ],
                const SizedBox(height: KkjTokens.spacing2),
                Text(
                  l.conflictRecoverNote,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l.conflictLater),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
