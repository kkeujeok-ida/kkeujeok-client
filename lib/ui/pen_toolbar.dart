import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kk.dart';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/eraser.dart';
import '../model/pen.dart';
import '../model/pen_palette.dart';
import '../render/page_painter.dart' show fillStroke, parseColor;
import '../render/stroke_outline.dart';
import 'library_fab.dart' show kkjShadow;
import 'pen_advanced.dart';
import 'pen_color_picker.dart';
import 'providers.dart';

/// The floating rounded bar: handle (drag to move, tap for the position menu) | pen slots
/// (scroll, reorder) | [+] | undo/redo | tools. Tapping the selected slot
/// opens the pen edit popover.
/// Touch size of a toolbar button: tighter than the 48 dp default so the bar is short.
const _hit = 34.0;
const _icon = 20.0;

/// A button as small as its icon: no 48 dp tap-target padding around it.
final _compact = IconButton.styleFrom(
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  padding: EdgeInsets.zero,
  minimumSize: const Size(_hit, _hit),
);

class PenToolbar extends StatefulWidget {
  const PenToolbar({
    super.key,
    required this.slots,
    this.selectedSlot = 0,
    this.maxSlotsWidth = double.infinity,
    this.maxSlotsExtent,
    this.vertical = false,
    this.fromRight = false,
    this.handleKey,
    this.onHandleTap,
    this.onHandleLongPressStart,
    this.onHandleLongPressMoveUpdate,
    this.onHandleLongPressEnd,
    this.onHandleLongPressCancel,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.onSlotTap,
    this.onAdd,
    this.onMove,
    this.slotFocus,
    this.eraserSelected = false,
    this.eraserMode = EraserMode.stroke,
    this.onEraser,
    this.lassoSelected = false,
    this.onLasso,
    this.textSelected = false,
    this.onText,
    this.shapeSelected = false,
    this.shapeKind = 'rect',
    this.shapeLock = false,
    this.onShapeOpened,
    this.onShapePick,
    this.onImage,
  });

  /// Width of everything but the slot list: padding, grip, [+], the divider,
  /// undo, redo, eraser, lasso, text and image. These never shrink or fold away.
  static const fixedWidth = 345.0;

  /// The same for the vertical bar (the [+] is 34 tall, not 48).
  static const fixedHeight = 331.0;

  /// Length of one slot along a horizontal bar (tighter than the 48 dp cell
  /// the vertical bar is wide).
  static const slotAlong = 42.0;

  /// Width of the vertical bar: one slot cell.
  static const verticalWidth = KkjLight.componentsPenSlotHitSize;

  final List<Pen> slots;
  final int selectedSlot;

  /// Most width the slot list may take; wider lists scroll inside it.
  final double maxSlotsWidth;

  /// Vertical bar: most height the slot list may take (else [maxSlotsWidth]).
  final double? maxSlotsExtent;

  /// Laid out top to bottom (docked left or right).
  final bool vertical;

  /// Vertical bar on the right half: nibs come in from the right edge.
  final bool fromRight;

  /// Anchors the position menu.
  final GlobalKey? handleKey;
  final VoidCallback? onHandleTap;
  final void Function(Offset global)? onHandleLongPressStart;
  final void Function(Offset global)? onHandleLongPressMoveUpdate;
  final void Function(Offset global)? onHandleLongPressEnd;
  final VoidCallback? onHandleLongPressCancel;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// A tap on slot `i`; the editor picks it, or opens its popover if picked.
  final void Function(int i)? onSlotTap;
  final VoidCallback? onAdd;

  /// Slot `from` was dropped at `to` (the index it ends up at).
  final void Function(int from, int to)? onMove;
  final FocusNode? slotFocus;
  final bool eraserSelected;
  final EraserMode eraserMode;
  final VoidCallback? onEraser;
  final bool lassoSelected;
  final VoidCallback? onLasso;
  final bool textSelected;
  final VoidCallback? onText;

  /// [도형]: the shape tool; the menu picks `triangle`, `rect`, `circle` or
  /// toggles the ratio lock (`lock`).
  final bool shapeSelected;
  final String shapeKind;
  final bool shapeLock;
  final VoidCallback? onShapeOpened;
  final void Function(String value)? onShapePick;

  /// [이미지]: opens the gallery / camera choice. Null disables it.
  final VoidCallback? onImage;

  @override
  State<PenToolbar> createState() => _PenToolbarState();
}

class _PenToolbarState extends State<PenToolbar> {
  static const _slotW = KkjLight.componentsPenSlotHitSize;
  static const _arrowW = 28.0;
  static const _fade = 20.0;

  final _scroll = ScrollController();
  final _bar = GlobalKey();
  Offset? _pointer; // last pointer position while a slot is dragged

  bool get _v => widget.vertical;

  // Along the bar a slot is 48 dp wide, or 34 dp tall when vertical.
  double get _item => _v ? _hit : PenToolbar.slotAlong;
  double get _viewW => math.max(
    _v ? widget.maxSlotsExtent ?? widget.maxSlotsWidth : widget.maxSlotsWidth,
    _item,
  );
  double get _width => math.min(widget.slots.length * _item, _viewW);
  double get _maxExtent => math.max(0, widget.slots.length * _item - _width);

  @override
  void didUpdateWidget(PenToolbar old) {
    super.didUpdateWidget(old);
    if (old.selectedSlot != widget.selectedSlot ||
        old.vertical != widget.vertical ||
        old.slots.length != widget.slots.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goTo(double to) {
    if (!_scroll.hasClients) return;
    to = to.clamp(0.0, _maxExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(to);
    } else {
      _scroll.animateTo(
        to,
        duration: KkjLight.componentsPenSlotSelectedDuration,
        curve: Curves.easeOut,
      );
    }
  }

  /// Scrolls just far enough that the selected slot is fully in view.
  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final left = widget.selectedSlot * _item, off = _scroll.offset;
    if (left < off) {
      _goTo(left);
    } else if (left + _item > off + _width) {
      _goTo(left + _item - _width);
    }
  }

  bool _insideBar() {
    final box = _bar.currentContext?.findRenderObject() as RenderBox?;
    final at = _pointer;
    if (box == null || !box.attached || at == null) return true;
    return (box.localToGlobal(Offset.zero) & box.size).contains(at);
  }

  void _reorder(int from, int to) {
    // Dropped outside the toolbar: the slot goes back where it was.
    if (_insideBar()) widget.onMove?.call(from, to);
  }

  Widget _slot(BuildContext context, int i, AppLocalizations l10n) {
    final pen = widget.slots[i];
    final active =
        !widget.eraserSelected && !widget.lassoSelected && !widget.textSelected;
    final selected = active && i == widget.selectedSlot;
    final color = _colorName(l10n, pen);
    final width = pen.width.toStringAsFixed(1);
    return ReorderableDelayedDragStartListener(
      key: ObjectKey(pen), // each slot is its own Pen object
      index: i,
      child: Semantics(
        label: switch (pen.tool) {
          'highlighter' => l10n.highlighterSlotLabel(color, width),
          'pen' => l10n.penSlotLabel(color, width),
          _ => l10n.kindSlotLabel(_kindName(l10n, pen.tool), color, width),
        },
        button: true,
        selected: selected,
        onTap: () => widget.onSlotTap?.call(i),
        customSemanticsActions: {
          if (i > 0)
            CustomSemanticsAction(label: l10n.moveSlotEarlier): () =>
                widget.onMove?.call(i, i - 1),
          if (i < widget.slots.length - 1)
            CustomSemanticsAction(label: l10n.moveSlotLater): () =>
                widget.onMove?.call(i, i + 1),
        },
        excludeSemantics: true,
        child: InkResponse(
          focusNode: i == widget.selectedSlot ? widget.slotFocus : null,
          onTap: () => widget.onSlotTap?.call(i),
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(
            KkjLight.componentsToolbarRounded,
          ),
          child: _PenSlot(
            pen: pen,
            selected: selected,
            vertical: _v,
            fromRight: widget.fromRight,
          ),
        ),
      ),
    );
  }

  Widget _slots(AppLocalizations l10n) {
    return AnimatedBuilder(
      animation: _scroll,
      builder: (context, _) {
        final off = _scroll.hasClients ? _scroll.offset : 0.0;
        final more = _maxExtent > 0;
        final back = more && off > 0.5;
        final fwd = more && off < _maxExtent - 0.5;
        final v = _v;
        return SizedBox(
          width: v ? _slotW : _width,
          height: v ? _width : _hit,
          child: Stack(
            children: [
              // The edge that has more behind it fades out.
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => LinearGradient(
                  begin: v ? Alignment.topCenter : Alignment.centerLeft,
                  end: v ? Alignment.bottomCenter : Alignment.centerRight,
                  colors: [
                    back ? Colors.transparent : Colors.black,
                    Colors.black,
                    Colors.black,
                    fwd ? Colors.transparent : Colors.black,
                  ],
                  stops: [0, _fade / _width, 1 - _fade / _width, 1],
                ).createShader(r),
                child: Listener(
                  onPointerDown: (e) => _pointer = e.position,
                  onPointerMove: (e) => _pointer = e.position,
                  child: ReorderableListView.builder(
                    scrollController: _scroll,
                    scrollDirection: v ? Axis.vertical : Axis.horizontal,
                    buildDefaultDragHandles: false,
                    padding: EdgeInsets.zero,
                    itemExtent: _item,
                    itemCount: widget.slots.length,
                    onReorderItem: _reorder,
                    itemBuilder: (c, i) => _slot(c, i, l10n),
                  ),
                ),
              ),
              if (back)
                Positioned(
                  left: 0,
                  top: 0,
                  child: _ScrollArrow(
                    vertical: v,
                    icon: v ? Icons.expand_less : Icons.chevron_left,
                    tooltip: l10n.scrollSlotsBack,
                    onTap: () => _goTo(off - _item),
                  ),
                ),
              if (fwd)
                Positioned(
                  right: v ? null : 0,
                  left: v ? 0 : null,
                  bottom: v ? 0 : null,
                  top: v ? null : 0,
                  child: _ScrollArrow(
                    vertical: v,
                    icon: v ? Icons.expand_more : Icons.chevron_right,
                    tooltip: l10n.scrollSlotsForward,
                    onTap: () => _goTo(off + _item),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final v = _v;
    return DecoratedBox(
      key: _bar,
      decoration: BoxDecoration(
        color: Kk.componentsToolbarBackground,
        borderRadius: BorderRadius.circular(KkjLight.componentsToolbarRounded),
        boxShadow: kkjShadow(Kk.componentsToolbarShadow),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: v ? KkjLight.componentsToolbarPaddingInline : 0,
          horizontal: v ? 0 : KkjLight.componentsToolbarPaddingInline,
        ),
        child: Flex(
          direction: v ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Handle(widget: widget, vertical: v),
            _slots(l10n),
            IconButton(
              tooltip: l10n.addPenSlot,
              constraints: BoxConstraints(
                minWidth: v ? _hit : KkjLight.componentsPenSlotAddSize,
                minHeight: _hit,
              ),
              iconSize: _icon,
              style: _compact.copyWith(
                minimumSize: WidgetStatePropertyAll(
                  Size(v ? _hit : KkjLight.componentsPenSlotAddSize, _hit),
                ),
              ),
              color: Kk.componentsPenSlotAddIcon,
              icon: const Icon(Icons.add),
              onPressed: widget.onAdd,
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: v ? 0 : KkjLight.componentsToolbarGroupGap,
                vertical: v ? KkjLight.componentsToolbarGroupGap : 0,
              ),
              child: SizedBox(
                width: v ? 18 : 1,
                height: v ? 1 : 18,
                child: ColoredBox(color: Kk.colorBorderHairline),
              ),
            ),
            _HistoryButton(
              icon: Icons.undo,
              tooltip: l10n.undo,
              onPressed: widget.canUndo ? widget.onUndo : null,
            ),
            _HistoryButton(
              icon: Icons.redo,
              tooltip: l10n.redo,
              onPressed: widget.canRedo ? widget.onRedo : null,
            ),
            Builder(
              builder: (_) {
                final partial = widget.eraserMode == EraserMode.partial;
                final mode = partial
                    ? l10n.eraserModePartial
                    : l10n.eraserModeStroke;
                return Semantics(
                  value: mode,
                  child: IconButton(
                    tooltip: '${l10n.eraserTool} ($mode)',
                    isSelected: widget.eraserSelected,
                    constraints: const BoxConstraints(
                      minWidth: _hit,
                      minHeight: _hit,
                    ),
                    style: _compact.copyWith(
                      backgroundColor: WidgetStatePropertyAll(
                        widget.eraserSelected ? Kk.colorAccentSoft : null,
                      ),
                    ),
                    iconSize: _icon,
                    icon: _EraserIcon(partial: partial),
                    onPressed: widget.onEraser,
                  ),
                );
              },
            ),
            IconButton(
              tooltip: l10n.lassoTool,
              isSelected: widget.lassoSelected,
              constraints: const BoxConstraints(
                minWidth: _hit,
                minHeight: _hit,
              ),
              style: _compact.copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  widget.lassoSelected ? Kk.colorAccentSoft : null,
                ),
              ),
              iconSize: _icon,
              icon: const Icon(Icons.highlight_alt),
              onPressed: widget.onLasso,
            ),
            IconButton(
              tooltip: l10n.textTool,
              isSelected: widget.textSelected,
              constraints: const BoxConstraints(
                minWidth: _hit,
                minHeight: _hit,
              ),
              style: _compact.copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  widget.textSelected ? Kk.colorAccentSoft : null,
                ),
              ),
              iconSize: _icon,
              icon: const Icon(Icons.text_fields),
              onPressed: widget.onText,
            ),
            PopupMenuButton<String>(
              tooltip: l10n.shapeTool,
              enabled: widget.onShapePick != null,
              constraints: const BoxConstraints(minWidth: 160),
              onOpened: widget.onShapeOpened,
              onSelected: widget.onShapePick,
              style: _compact.copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(_hit, _hit)),
                backgroundColor: WidgetStatePropertyAll(
                  widget.shapeSelected ? Kk.colorAccentSoft : null,
                ),
              ),
              iconSize: _icon,
              icon: Icon(_shapeIcon(widget.shapeKind)),
              itemBuilder: (_) => [
                for (final k in const ['triangle', 'rect', 'circle'])
                  CheckedPopupMenuItem<String>(
                    value: k,
                    checked: widget.shapeKind == k,
                    child: Text(_shapeName(l10n, k)),
                  ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem<String>(
                  value: 'lock',
                  checked: widget.shapeLock,
                  child: Text(l10n.shapeLockRatio),
                ),
              ],
            ),
            IconButton(
              tooltip: l10n.imageTool,
              constraints: const BoxConstraints(
                minWidth: _hit,
                minHeight: _hit,
              ),
              disabledColor: Kk.colorInkDisabled,
              iconSize: _icon,
              style: _compact,
              icon: const Icon(Icons.image_outlined),
              onPressed: widget.onImage,
            ),
          ],
        ),
      ),
    );
  }
}

IconData _shapeIcon(String kind) => switch (kind) {
  'triangle' => Icons.change_history,
  'circle' => Icons.circle_outlined,
  _ => Icons.crop_square,
};

String _shapeName(AppLocalizations l10n, String kind) => switch (kind) {
  'triangle' => l10n.shapeTriangle,
  'circle' => l10n.shapeCircle,
  _ => l10n.shapeRect,
};

/// The ko/en name of a palette color key (`custom` for any other color).
String penColorName(AppLocalizations l10n, String key) => switch (key) {
  'black' => l10n.colorBlack,
  'darkGray' => l10n.colorDarkGray,
  'red' => l10n.colorRed,
  'orange' => l10n.colorOrange,
  'yellow' => l10n.colorYellow,
  'green' => l10n.colorGreen,
  'teal' => l10n.colorTeal,
  'blue' => l10n.colorBlue,
  'indigo' => l10n.colorIndigo,
  'purple' => l10n.colorPurple,
  'pink' => l10n.colorPink,
  'brown' => l10n.colorBrown,
  'sky' => l10n.colorSky,
  'lavender' => l10n.colorLavender,
  _ => l10n.colorCustom,
};

String _colorName(AppLocalizations l10n, Pen pen) =>
    penColorName(l10n, pen.colorNameKey);

class _ScrollArrow extends StatelessWidget {
  const _ScrollArrow({
    required this.vertical,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final bool vertical;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tooltip,
    button: true,
    onTap: onTap,
    excludeSemantics: true,
    child: Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: vertical ? _PenToolbarState._slotW : _PenToolbarState._arrowW,
          height: vertical ? _PenToolbarState._arrowW : _hit,
          child: Icon(icon, size: 18, color: Kk.componentsPenSlotAddIcon),
        ),
      ),
    ),
  );
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    constraints: const BoxConstraints(minWidth: _hit, minHeight: _hit),
    iconSize: _icon,
    style: _compact,
    icon: Icon(icon),
    disabledColor: Kk.colorInkDisabled,
    onPressed: onPressed,
  );
}

/// The handle: long-press and drag moves the bar, a tap opens the position
/// menu (also a TalkBack custom action).
class _Handle extends StatelessWidget {
  const _Handle({required this.widget, required this.vertical});

  final PenToolbar widget;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).toolbarMove;
    return Semantics(
      button: true,
      label: label,
      onTap: widget.onHandleTap,
      customSemanticsActions: {
        if (widget.onHandleTap != null)
          CustomSemanticsAction(label: label): widget.onHandleTap!,
      },
      excludeSemantics: true,
      child: GestureDetector(
        key: widget.handleKey,
        behavior: HitTestBehavior.opaque,
        onTap: widget.onHandleTap,
        onLongPressStart: (d) =>
            widget.onHandleLongPressStart?.call(d.globalPosition),
        onLongPressMoveUpdate: (d) =>
            widget.onHandleLongPressMoveUpdate?.call(d.globalPosition),
        onLongPressEnd: (d) =>
            widget.onHandleLongPressEnd?.call(d.globalPosition),
        onLongPressCancel: widget.onHandleLongPressCancel,
        child: SizedBox.square(
          dimension: _hit,
          child: Icon(
            vertical ? Icons.more_horiz : Icons.more_vert,
            color: Kk.componentsToolbarGripGlyph,
          ),
        ),
      ),
    );
  }
}

/// A dashed toolbar-shaped outline: where a drag would dock the bar.
class SnapOutline extends StatelessWidget {
  const SnapOutline({super.key, required this.highlighted});

  final bool highlighted;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _DashPainter(highlighted),
      ),
    ),
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.on);

  final bool on;

  @override
  void paint(Canvas canvas, Size s) {
    final rr = RRect.fromRectAndRadius(
      (Offset.zero & s).deflate(1),
      const Radius.circular(KkjLight.componentsToolbarRounded),
    );
    if (on) {
      canvas.drawRRect(rr, Paint()..color = Kk.colorAccentSoft);
    }
    final paint = Paint()
      ..color = on ? Kk.colorAccent : Kk.colorBorderControl
      ..style = PaintingStyle.stroke
      ..strokeWidth = on ? 2 : 1.5;
    for (final m in (Path()..addRRect(rr)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.on != on;
}

class _PenSlot extends StatelessWidget {
  const _PenSlot({
    required this.pen,
    required this.selected,
    required this.vertical,
    required this.fromRight,
  });

  final Pen pen;
  final bool selected;
  final bool vertical;
  final bool fromRight;

  static const _w = KkjLight.componentsPenSlotHitSize;
  static const _nibW = 16.0;
  static const _nibH = 28.8;

  @override
  Widget build(BuildContext context) {
    final nib = CustomPaint(
      size: const Size(_nibW, _nibH),
      painter: _ToolGlyphPainter(
        parseColor(pen.color),
        [_glyphD(pen.tool)],
        20,
        36,
      ),
    );
    // Width number at the nib's lower right (spec/tool-icons.md).
    final number = Text(
      pen.width.toStringAsFixed(1),
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: 9,
        height: 1,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
    final lift = selected ? KkjLight.componentsPenSlotSelectedOffset : 0.0;
    final indicator = DecoratedBox(
      decoration: BoxDecoration(
        color: Kk.componentsPenSlotSelectedIndicator,
        borderRadius: BorderRadius.circular(
          KkjLight.componentsPenSlotSelectedRounded,
        ),
      ),
      child: SizedBox(
        width: vertical
            ? KkjLight.componentsPenSlotSelectedHeight
            : KkjLight.componentsPenSlotSelectedWidth,
        height: vertical
            ? KkjLight.componentsPenSlotSelectedWidth
            : KkjLight.componentsPenSlotSelectedHeight,
      ),
    );
    if (vertical) {
      // Docked at a side: the nib lies on its side and comes in from the
      // edge, tip toward the screen center.
      const edge = -8.0;
      const gap = _nibH + edge + 1;
      return SizedBox(
        width: _w,
        height: _hit,
        child: ClipRect(
          child: Stack(
            children: [
              PositionedDirectional(
                start: fromRight ? null : edge + lift,
                end: fromRight ? edge + lift : null,
                top: (_hit - _nibW) / 2 - 3,
                child: RotatedBox(quarterTurns: fromRight ? 1 : 3, child: nib),
              ),
              Positioned(
                left: fromRight ? null : gap + lift,
                right: fromRight ? gap + lift : null,
                bottom: 4,
                child: number,
              ),
              if (selected)
                Positioned(
                  left: fromRight ? 0 : null,
                  right: fromRight ? null : 0,
                  top: (_hit - KkjLight.componentsPenSlotSelectedWidth) / 2,
                  child: indicator,
                ),
            ],
          ),
        ),
      );
    }
    const along = PenToolbar.slotAlong;
    const pairW = _nibW + 1 + 14; // nib, gap, a "1.5"-sized number
    final left = (along - pairW) / 2;
    return SizedBox(
      width: along,
      height: _hit,
      child: ClipRect(
        child: Stack(
          children: [
            // The nib hangs from the toolbar's top edge: its top is cut off,
            // and the selected pen sits `selected-offset` lower.
            Positioned(left: left, top: -8 + lift, child: nib),
            Positioned(left: left + _nibW + 1, bottom: 3, child: number),
            if (selected)
              Positioned(
                left: (along - KkjLight.componentsPenSlotSelectedWidth) / 2,
                bottom: 0,
                child: indicator,
              ),
          ],
        ),
      ),
    );
  }
}

// Shapes from spec/tool-icons.md: absolute M L H V Z only.
const _penD = 'M3 0V22.3L10 36L17 22.3V0M3 22.3H17';
const _highlighterD = 'M3 0V36L17 28V0M3 22.3H17';
const _fountainD = 'M3 0V18L10 36L17 18V0M3 18H17M10 18V26';
const _pencilD = 'M3 0V28L10 36L17 28V0ZM3 6H17M3 28H17';
const _tapeD = 'M3 8H17V28H3ZM7 14H13M7 22H13';

String _glyphD(String tool) => switch (tool) {
  'highlighter' => _highlighterD,
  'fountain' => _fountainD,
  'pencil' => _pencilD,
  'tape' => _tapeD,
  _ => _penD,
};
const _eraserD = 'M15 3.5L20.5 9L10 19.5L4.5 14ZM8.7 9.8L14.2 15.3';
const _eraserPartialD = 'M3 22H7M10 22H14M17 22H21';

Path _svgPath(String d, double scale) {
  final path = Path();
  var x = 0.0, y = 0.0;
  for (final m in RegExp(r'([MLHVZ])([^MLHVZ]*)').allMatches(d)) {
    final n = RegExp(r'-?[\d.]+')
        .allMatches(m[2]!)
        .map((e) => double.parse(e[0]!) * scale)
        .toList();
    switch (m[1]) {
      case 'M':
        path.moveTo(x = n[0], y = n[1]);
      case 'L':
        path.lineTo(x = n[0], y = n[1]);
      case 'H':
        path.lineTo(x = n[0], y);
      case 'V':
        path.lineTo(x, y = n[0]);
      default:
        path.close();
    }
  }
  return path;
}

/// Draws spec/tool-icons.md shapes scaled to fit [size] from a [vw] x [vh] box.
class _ToolGlyphPainter extends CustomPainter {
  _ToolGlyphPainter(this.color, this.ds, this.vw, this.vh);

  final Color color;
  final List<String> ds;
  final double vw, vh;

  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / vw;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75 * k
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final d in ds) {
      canvas.drawPath(_svgPath(d, k), paint);
    }
  }

  @override
  bool shouldRepaint(_ToolGlyphPainter old) =>
      old.color != color || old.ds.join() != ds.join();
}

/// The eraser icon of spec/tool-icons.md, in the surrounding icon color.
class _EraserIcon extends StatelessWidget {
  const _EraserIcon({required this.partial});

  final bool partial;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    return CustomPaint(
      size: const Size.square(_icon),
      painter: _ToolGlyphPainter(
        color,
        [_eraserD, if (partial) _eraserPartialD],
        24,
        24,
      ),
    );
  }
}

const _cell = 48.0;
const _cols = 6;

/// The pen edit popover (UX-DR18): tool switch, name, palette, recent colors,
/// thickness, pressure, preview, delete. Reads and writes slot [index]
/// through [penSlotsProvider], so every change is stored at once; the canvas
/// below gets no input while it is open.
class PenEditDialog extends ConsumerStatefulWidget {
  const PenEditDialog({super.key, this.index = 0, this.anchor});

  final int index;

  /// Where the tool button and its toolbar are, read at every layout so a
  /// rotation re-places the bubble. Null: centered, no tail.
  final PenBubbleAnchor Function()? anchor;

  @override
  ConsumerState<PenEditDialog> createState() => _PenEditDialogState();
}

class _PenEditDialogState extends ConsumerState<PenEditDialog> {
  bool _advanced =
      false; // advanced columns + preset labels, right of the bubble

  @override
  Widget build(BuildContext context) {
    final anchor = widget.anchor;
    final l10n = AppLocalizations.of(context);
    final slots = ref.watch(penSlotsProvider);
    final i = widget.index.clamp(0, slots.length - 1); // closing: may be gone
    final pen = slots[i];
    final recent = ref.watch(recentPenColorsProvider);
    final canDelete = slots.length > 1;
    final on = pen.usePressure;
    final notifier = ref.read(penSlotsProvider.notifier);
    final theme = Theme.of(context);
    void toggle(bool v) => notifier.setUsePressure(i, v);
    void pick(String hex) {
      notifier.setColor(i, hex);
      ref.read(recentPenColorsProvider.notifier).useColor(hex);
    }

    Future<void> custom() async {
      final hex = await showPenColorPicker(context, pen.color);
      if (!context.mounted) return;
      if (hex != null) pick(hex);
    }

    Widget switchRow(String label, bool value, void Function(bool) set) =>
        Semantics(
          container: true,
          label: label,
          toggled: value,
          onTap: () => set(!value),
          excludeSemantics: true,
          child: InkWell(
            onTap: () => set(!value),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _hit),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  IgnorePointer(
                    child: Switch(value: value, onChanged: set),
                  ),
                ],
              ),
            ),
          ),
        );

    final (lo, hi) = penWidthRange(pen.tool);
    final width = pen.width.clamp(lo, hi);
    final widthText = width.toStringAsFixed(1);
    void step(int d) => notifier.setWidth(i, width + d / 10);
    final palette = [
      for (final hex in ref.watch(penPaletteProvider)[paletteFamily(pen.tool)]!)
        PaletteColor(hex, colorNameKeyFor(hex)),
    ];

    String label(String hex) {
      final key = colorNameKeyFor(hex);
      return key == 'custom'
          ? l10n.customColorSlotLabel(hex.toUpperCase())
          : penColorName(l10n, key);
    }

    final cells = <Widget>[
      for (var k = 0; k < palette.length; k++)
        _ColorCell(
          hex: palette[k].hex,
          label: label(palette[k].hex),
          selected: pen.color.toLowerCase() == palette[k].hex,
          onTap: () => pick(palette[k].hex),
          corners: _corners(palette.length + 1, k),
        ),
      _ColorCell(
        label: l10n.colorCustom,
        selected: false,
        onTap: custom,
        corners: _corners(palette.length + 1, palette.length),
      ),
    ];

    Widget switchButton(String tool, String text) {
      final active = pen.tool == tool;
      return Expanded(
        child: Semantics(
          button: true,
          inMutuallyExclusiveGroup: true,
          checked: active,
          label: text,
          onTap: () => notifier.setTool(i, tool),
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
            onTap: () => notifier.setTool(i, tool),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _cell),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: active ? Kk.colorAccentSoft : null,
                  borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size(12, 21.6),
                    painter: _ToolGlyphPainter(
                      theme.colorScheme.onSurface,
                      [_glyphD(tool)],
                      20,
                      36,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget stepper(IconData icon, String tip, bool enabled, int d) =>
        IconButton(
          tooltip: tip,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(icon),
          disabledColor: Kk.colorInkDisabled,
          onPressed: enabled ? () => step(d) : null,
        );

    void del() => Navigator.of(context).pop(true);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: _PenBubble(
        anchor: anchor,
        leftHanded: ref.watch(leftHandedProvider),
        extra: _advanced
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Material(
                      color: Kk.componentsPopoverBackground,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          KkjLight.componentsPopoverRounded,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: PenAdvancedPanel(index: i),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: KkjTokens.spacing2),
                  Material(
                    type: MaterialType.transparency,
                    child: PenPresets(index: i),
                  ),
                ],
              )
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KkjLight.componentsPopoverPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  container: true,
                  role: SemanticsRole.radioGroup,
                  child: Row(
                    children: [
                      for (final k in const [
                        'pen',
                        'highlighter',
                        'fountain',
                        'pencil',
                        'tape',
                      ])
                        switchButton(k, _kindName(l10n, k)),
                    ],
                  ),
                ),
                const SizedBox(height: KkjTokens.spacing3),
                Semantics(
                  header: true,
                  child: Text(
                    _kindName(l10n, pen.tool),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: KkjTokens.spacing2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(children: cells),
                ),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: KkjTokens.spacing3),
                  Text(l10n.recentColors, style: theme.textTheme.labelMedium),
                  const SizedBox(height: KkjTokens.spacing1),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      children: [
                        for (var k = 0; k < recent.length; k++)
                          _ColorCell(
                            hex: recent[k],
                            label: label(recent[k]),
                            selected: pen.color.toLowerCase() == recent[k],
                            onTap: () => pick(recent[k]),
                            corners: _corners(recent.length, k),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: KkjTokens.spacing3),
                Text(l10n.strokeWidthValue(widthText)),
                Row(
                  children: [
                    stepper(
                      Icons.chevron_left,
                      l10n.widthDecrease,
                      width > lo + 1e-9,
                      -1,
                    ),
                    Expanded(
                      child: Slider(
                        value: width,
                        min: lo,
                        max: hi,
                        divisions: ((hi - lo) * 10).round(),
                        semanticFormatterCallback: (v) => v.toStringAsFixed(1),
                        onChanged: (v) => notifier.setWidth(i, v),
                      ),
                    ),
                    stepper(
                      Icons.chevron_right,
                      l10n.widthIncrease,
                      width < hi - 1e-9,
                      1,
                    ),
                  ],
                ),
                switchRow(l10n.usePressure, on, toggle),
                switchRow(
                  l10n.lineDraw,
                  pen.lineMode,
                  (v) => notifier.setLineMode(i, v),
                ),
                Semantics(
                  button: true,
                  expanded: _advanced,
                  child: TextButton(
                    onPressed: () => setState(() => _advanced = !_advanced),
                    child: Text(l10n.brushAdvanced),
                  ),
                ),
                const SizedBox(height: KkjTokens.spacing3),
                ExcludeSemantics(
                  child: SizedBox(
                    height: 64,
                    child: CustomPaint(painter: PenPreviewPainter(pen)),
                  ),
                ),
                Divider(color: Kk.colorBorderHairline),
                // Closes the popover; the editor removes the slot and offers
                // to undo. The last slot cannot go.
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Semantics(
                    button: true,
                    enabled: canDelete,
                    onTap: canDelete ? del : null,
                    excludeSemantics: true,
                    label: l10n.deletePenSlot,
                    child: InkWell(
                      onTap: canDelete ? del : null,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: _cell),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: canDelete
                                  ? theme.colorScheme.error
                                  : Kk.colorInkDisabled,
                            ),
                            const SizedBox(width: KkjTokens.spacing1),
                            Text(
                              l10n.deletePenSlot,
                              style: TextStyle(
                                color: canDelete
                                    ? theme.colorScheme.error
                                    : Kk.colorInkDisabled,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the pen bubble points: the tool button [tool], on the toolbar [bar].
class PenBubbleAnchor {
  const PenBubbleAnchor(this.tool, this.bar, {required this.vertical});
  final Rect tool, bar;
  final bool vertical;
}

/// Which side of the toolbar the bubble opens on, the bubble's top-left, and
/// where the tail sits along that edge.
class PenBubblePlacement {
  const PenBubblePlacement(this.side, this.topLeft, this.tail);
  final AxisDirection side; // the side of the bar: down = below it
  final Offset topLeft;
  final double?
  tail; // tail centre along the bubble's edge, from its start; null: no tail
}

const penBubbleGap = 12.0; // bar to bubble; the tail takes 8 of it
const penBubbleMargin = 8.0; // bubble to window edge
const _tailLen = 8.0, _tailBase = 16.0;

/// The rules of spec/toolbar-orientation.md: horizontal bar: below it, above
/// when the bar is in the lower half; vertical bar: beside it, on the side
/// away from the window's nearer edge. The bubble is pulled inside the window,
/// the tail keeps pointing at the tool.
AxisDirection penBubbleSide(
  PenBubbleAnchor a,
  Size win, {
  bool leftHanded = false,
}) {
  final s = a.vertical
      ? (a.bar.center.dx < win.width / 2
            ? AxisDirection.right
            : AxisDirection.left)
      : (a.bar.center.dy <= win.height / 2
            ? AxisDirection.down
            : AxisDirection.up);
  // Left-handed: the opposite side of the bar (the fit below keeps it inside).
  return leftHanded ? flipAxisDirection(s) : s;
}

PenBubblePlacement placePenBubble(
  PenBubbleAnchor a,
  Size bubble,
  Size win, {
  bool leftHanded = false,
}) {
  final side = penBubbleSide(a, win, leftHanded: leftHanded);
  const m = penBubbleMargin, edge = _tailBase / 2 + 8;
  double fit(double v, double size, double max) =>
      v.clamp(m, math.max(m, max - m - size)).toDouble();
  final double left, top, c, start, len;
  if (a.vertical) {
    top = fit(a.tool.center.dy - bubble.height / 2, bubble.height, win.height);
    left = fit(
      side == AxisDirection.right
          ? a.bar.right + penBubbleGap
          : a.bar.left - penBubbleGap - bubble.width,
      bubble.width,
      win.width,
    );
    (c, start, len) = (a.tool.center.dy, top, bubble.height);
  } else {
    left = fit(a.tool.center.dx - bubble.width / 2, bubble.width, win.width);
    top = fit(
      side == AxisDirection.down
          ? a.bar.bottom + penBubbleGap
          : a.bar.top - penBubbleGap - bubble.height,
      bubble.height,
      win.height,
    );
    (c, start, len) = (a.tool.center.dx, left, bubble.width);
  }
  final rect = Offset(left, top) & bubble;
  final tip = switch (side) {
    AxisDirection.down => rect.top - _tailLen,
    AxisDirection.up => rect.bottom + _tailLen,
    AxisDirection.right => rect.left - _tailLen,
    AxisDirection.left => rect.right + _tailLen,
  };
  // The pulled bubble covers the bar, or the tail would leave the window: no
  // tail rather than a wrong one.
  final hide =
      rect.overlaps(a.bar) ||
      tip < 0 ||
      tip > (a.vertical ? win.width : win.height);
  return PenBubblePlacement(
    side,
    Offset(left, top),
    hide
        ? null
        : (c - start).clamp(edge, math.max(edge, len - edge)).toDouble(),
  );
}

/// The pen popover as a speech bubble with a tail toward the tool button.
/// The anchor is read after a frame (the toolbar is laid out by then), again
/// whenever the window size changes; until then nothing shows.
class _PenBubble extends StatefulWidget {
  const _PenBubble({
    required this.anchor,
    required this.child,
    required this.leftHanded,
    this.extra,
  });
  final PenBubbleAnchor Function()? anchor;
  final bool leftHanded;
  final Widget child;

  /// Laid out beside the bubble, outside it (advanced columns, presets).
  final Widget? extra;

  @override
  State<_PenBubble> createState() => _PenBubbleState();
}

class _PenBubbleState extends State<_PenBubble> {
  PenBubbleAnchor? _a;
  Size? _size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(
      context,
    ); // a new window size places it again
    if (size != _size) _a = null; // no jump to a stale spot meanwhile
    _size = size;
    if (widget.anchor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _a = widget.anchor!());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.anchor != null && _a == null) return const SizedBox.shrink();
    final layout = _BubbleLayout(_a, widget.leftHanded);
    final extra = widget.extra;
    return CustomMultiChildLayout(
      delegate: layout,
      children: [
        LayoutId(
          id: #bubble,
          child: Material(
            color: Kk.componentsPopoverBackground,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                KkjLight.componentsPopoverRounded,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.child,
          ),
        ),
        if (extra != null) LayoutId(id: #extra, child: extra),
        if (_a != null)
          LayoutId(
            id: #tail,
            child: ExcludeSemantics(
              child: CustomPaint(painter: _TailPainter(layout)),
            ),
          ),
      ],
    );
  }
}

class _BubbleLayout extends MultiChildLayoutDelegate {
  _BubbleLayout(this.anchor, this.leftHanded);
  final PenBubbleAnchor? anchor;
  final bool leftHanded;
  AxisDirection side =
      AxisDirection.down; // set by performLayout, read by the tail painter

  @override
  void performLayout(Size size) {
    final box = layoutChild(
      #bubble,
      BoxConstraints(
        maxWidth: math.max(0, size.width - penBubbleMargin * 2),
        maxHeight: math.max(0, size.height - penBubbleMargin * 2),
      ),
    );
    final a = anchor;
    if (a == null) {
      final tl = Offset(
        (size.width - box.width) / 2,
        (size.height - box.height) / 2,
      );
      positionChild(#bubble, tl);
      _placeExtra(size, tl, box, null);
      return;
    }
    final p = placePenBubble(a, box, size, leftHanded: leftHanded);
    side = p.side;
    positionChild(#bubble, p.topLeft);
    _placeExtra(size, p.topLeft, box, p.side);
    if (!hasChild(#tail)) return;
    final tail = p.tail;
    if (tail == null) {
      layoutChild(#tail, BoxConstraints.tight(Size.zero)); // nothing to paint
      return;
    }
    final horiz = p.side == AxisDirection.down || p.side == AxisDirection.up;
    final t = layoutChild(
      #tail,
      BoxConstraints.tight(
        horiz
            ? const Size(_tailBase, _tailLen)
            : const Size(_tailLen, _tailBase),
      ),
    );
    positionChild(#tail, switch (p.side) {
      AxisDirection.down => Offset(
        p.topLeft.dx + tail - t.width / 2,
        p.topLeft.dy - t.height,
      ),
      AxisDirection.up => Offset(
        p.topLeft.dx + tail - t.width / 2,
        p.topLeft.dy + box.height,
      ),
      AxisDirection.right => Offset(
        p.topLeft.dx - t.width,
        p.topLeft.dy + tail - t.height / 2,
      ),
      AxisDirection.left => Offset(
        p.topLeft.dx + box.width,
        p.topLeft.dy + tail - t.height / 2,
      ),
    });
  }

  /// The extra panel beside the bubble: right of it, or left when there is no
  /// room (or the tail faces right). It scrolls inside the window margin.
  void _placeExtra(Size size, Offset tl, Size box, AxisDirection? side) {
    if (!hasChild(#extra)) return;
    const gap = 8.0;
    final right = size.width - (tl.dx + box.width) - gap - penBubbleMargin;
    final left = tl.dx - gap - penBubbleMargin;
    final onRight = side == AxisDirection.left
        ? false
        : side == AxisDirection.right || right >= 240 || right >= left;
    final avail = math.max(0.0, onRight ? right : left);
    final e = layoutChild(
      #extra,
      BoxConstraints(
        maxWidth: avail,
        maxHeight: math.max(0, size.height - penBubbleMargin * 2),
      ),
    );
    final top = tl.dy
        .clamp(
          penBubbleMargin,
          math.max(penBubbleMargin, size.height - penBubbleMargin - e.height),
        )
        .toDouble();
    positionChild(
      #extra,
      Offset(onRight ? tl.dx + box.width + gap : tl.dx - gap - e.width, top),
    );
  }

  @override
  bool shouldRelayout(_BubbleLayout old) => true;
}

/// A triangle on the bubble's edge facing the bar, pointing at it. The side is
/// the one the layout placed with, read at paint time.
class _TailPainter extends CustomPainter {
  _TailPainter(this.layout);
  final _BubbleLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (layout.side) {
      case AxisDirection.down: // bubble below the bar: tip points up
        path.addPolygon([
          Offset(0, size.height),
          Offset(size.width / 2, 0),
          Offset(size.width, size.height),
        ], true);
      case AxisDirection.up:
        path.addPolygon([
          Offset.zero,
          Offset(size.width / 2, size.height),
          Offset(size.width, 0),
        ], true);
      case AxisDirection.right:
        path.addPolygon([
          Offset(size.width, 0),
          Offset(0, size.height / 2),
          Offset(size.width, size.height),
        ], true);
      case AxisDirection.left:
        path.addPolygon([
          Offset.zero,
          Offset(size.width, size.height / 2),
          Offset(0, size.height),
        ], true);
    }
    canvas.drawPath(path, Paint()..color = Kk.componentsPopoverBackground);
  }

  @override
  bool shouldRepaint(_TailPainter old) => true;
}

/// Rounds only the grid's outer corners: cell [at] of [n] in [_cols] columns.
BorderRadius _corners(int n, int at) {
  const r = Radius.circular(KkjTokens.roundedSm);
  final row = at ~/ _cols, col = at % _cols, rows = (n - 1) ~/ _cols + 1;
  final last = at == n - 1;
  return BorderRadius.only(
    topLeft: row == 0 && col == 0 ? r : Radius.zero,
    topRight: row == 0 && (col == _cols - 1 || last) ? r : Radius.zero,
    bottomLeft: row == rows - 1 && col == 0 ? r : Radius.zero,
    bottomRight: last ? r : Radius.zero,
  );
}

/// One 48dp palette, recent or custom-color cell. [hex] null is the rainbow
/// custom-color chip.
class _ColorCell extends StatelessWidget {
  const _ColorCell({
    this.hex,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.corners,
  });

  final String? hex;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final BorderRadius corners;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: corners,
      onTap: onTap,
      child: SizedBox.square(
        dimension: _cell,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: corners,
            color: hex == null ? null : parseColor(hex),
            gradient: hex == null
                ? const SweepGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  )
                : null,
          ),
          child: selected
              ? Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Kk.componentsPopoverBackground,
                        width: 2,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Kk.colorAccent, width: 2),
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ),
    ),
  );
}

String _kindName(AppLocalizations l10n, String tool) => switch (tool) {
  'highlighter' => l10n.toolHighlighter,
  'fountain' => l10n.toolFountain,
  'pencil' => l10n.toolPencil,
  'tape' => l10n.toolTape,
  _ => l10n.toolPen,
};

const _previewW = 280.0, _previewH = 64.0, _previewScale = 3.0;
const _previewAmp = 12.0, _previewMargin = 24.0; // margin: room for the caps

/// A wave stroke whose pressure rises and falls, drawn through
/// [strokeOutline] with the pen's `usePressure`; flat when it is off. Built in
/// a fixed box and scaled to the paint size, clipped to it.
class PenPreviewPainter extends CustomPainter {
  PenPreviewPainter(this.pen)
    : polygon = pen.isHighlighter ? const [] : _polygon(pen),
      rects = pen.isHighlighter ? _rects(pen) : const [];

  final Pen pen;
  final List<List<double>> polygon;
  final List<List<List<double>>> rects;

  static List<List<double>> _polygon(Pen pen) {
    const n = 40;
    final pts = [
      for (var i = 0; i <= n; i++)
        [
          _previewMargin + (_previewW - 2 * _previewMargin) * i / n,
          _previewH / 2 + _previewAmp * math.sin(2 * math.pi * i / n),
          0.1 + 0.8 * math.sin(math.pi * i / n),
          i * 10,
        ],
    ];
    // A radius is at most 1.75x half the width: keep it inside the box.
    final w = math.min(
      pen.width * _previewScale,
      math.min(
        (_previewH / 2 - 2 - _previewAmp) / 0.875,
        (_previewMargin - 2) / 0.875,
      ),
    );
    return strokeOutlineFor(pen.tool, w, pen.usePressure, pts);
  }

  static List<List<List<double>>> _rects(Pen pen) {
    const n = 40;
    return highlighterPolygons(math.min(pen.width, 28), [
      for (var i = 0; i <= n; i++)
        [
          _previewMargin + (_previewW - 2 * _previewMargin) * i / n,
          _previewH / 2 + _previewAmp * math.sin(2 * math.pi * i / n),
          0.5,
          i * 10,
        ],
    ]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / _previewW, size.height / _previewH);
    canvas
      ..clipRect(Offset.zero & size)
      ..translate(
        (size.width - _previewW * s) / 2,
        (size.height - _previewH * s) / 2,
      )
      ..scale(s);
    // On paper, as it will look on a page (a highlighter multiplies).
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _previewW, _previewH),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    fillStroke(
      canvas,
      pen.isHighlighter ? highlighterPath(rects) : outlinePath(polygon),
      pen.color,
      highlighter: pen.isHighlighter,
    );
  }

  @override
  bool shouldRepaint(PenPreviewPainter old) =>
      old.pen.tool != pen.tool ||
      old.pen.usePressure != pen.usePressure ||
      old.pen.color != pen.color ||
      old.pen.width != pen.width;
}
