import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/pen.dart';
import '../model/pen_palette.dart';
import '../render/page_painter.dart' show fillStroke, parseColor;
import '../render/stroke_outline.dart';
import 'library_fab.dart' show kkjShadow;
import 'pen_color_picker.dart';
import 'providers.dart';

/// The floating rounded bar: grip (inert, not in the a11y tree) | pen slots
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
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.onSlotTap,
    this.onAdd,
    this.onMove,
    this.slotFocus,
    this.lassoSelected = false,
    this.onLasso,
    this.textSelected = false,
    this.onText,
    this.onImage,
  });

  /// Width of everything but the slot list: padding, grip, [+], the divider,
  /// undo, redo, lasso, text and image. These never shrink or fold away.
  static const fixedWidth = 277.0;

  final List<Pen> slots;
  final int selectedSlot;

  /// Most width the slot list may take; wider lists scroll inside it.
  final double maxSlotsWidth;
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
  final bool lassoSelected;
  final VoidCallback? onLasso;
  final bool textSelected;
  final VoidCallback? onText;

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

  double get _viewW => math.max(widget.maxSlotsWidth, _slotW);
  double get _width => math.min(widget.slots.length * _slotW, _viewW);
  double get _maxExtent => math.max(0, widget.slots.length * _slotW - _width);

  @override
  void didUpdateWidget(PenToolbar old) {
    super.didUpdateWidget(old);
    if (old.selectedSlot != widget.selectedSlot ||
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
    final left = widget.selectedSlot * _slotW, off = _scroll.offset;
    if (left < off) {
      _goTo(left);
    } else if (left + _slotW > off + _width) {
      _goTo(left + _slotW - _width);
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
    final active = !widget.lassoSelected && !widget.textSelected;
    final selected = active && i == widget.selectedSlot;
    final color = _colorName(l10n, pen);
    final width = pen.width.toStringAsFixed(1);
    return ReorderableDelayedDragStartListener(
      key: ObjectKey(pen), // each slot is its own Pen object
      index: i,
      child: Semantics(
        label: pen.isHighlighter
            ? l10n.highlighterSlotLabel(color, width)
            : l10n.penSlotLabel(color, width),
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
          child: _PenSlot(pen: pen, selected: selected),
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
        return SizedBox(
          width: _width,
          height: _hit,
          child: Stack(
            children: [
              // The edge that has more behind it fades out.
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => LinearGradient(
                  colors: [
                    back ? Colors.transparent : Colors.black,
                    Colors.black,
                    Colors.black,
                    fwd ? Colors.transparent : Colors.black,
                  ],
                  stops: [0, _fade / r.width, 1 - _fade / r.width, 1],
                ).createShader(r),
                child: Listener(
                  onPointerDown: (e) => _pointer = e.position,
                  onPointerMove: (e) => _pointer = e.position,
                  child: ReorderableListView.builder(
                    scrollController: _scroll,
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    padding: EdgeInsets.zero,
                    itemExtent: _slotW,
                    itemCount: widget.slots.length,
                    onReorderItem: _reorder,
                    itemBuilder: (c, i) => _slot(c, i, l10n),
                  ),
                ),
              ),
              if (back)
                Positioned(
                  left: 0,
                  child: _ScrollArrow(
                    icon: Icons.chevron_left,
                    tooltip: l10n.scrollSlotsBack,
                    onTap: () => _goTo(off - _slotW),
                  ),
                ),
              if (fwd)
                Positioned(
                  right: 0,
                  child: _ScrollArrow(
                    icon: Icons.chevron_right,
                    tooltip: l10n.scrollSlotsForward,
                    onTap: () => _goTo(off + _slotW),
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
    final full = widget.slots.length >= maxPenSlots;
    return DecoratedBox(
      key: _bar,
      decoration: BoxDecoration(
        color: KkjLight.componentsToolbarBackground,
        borderRadius: BorderRadius.circular(KkjLight.componentsToolbarRounded),
        boxShadow: kkjShadow(KkjLight.componentsToolbarShadow),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 0,
          horizontal: KkjLight.componentsToolbarPaddingInline,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(child: _Grip()),
            _slots(l10n),
            // At the limit it looks off but still answers with the notice.
            IconButton(
              tooltip: l10n.addPenSlot,
              constraints: const BoxConstraints(
                minWidth: KkjLight.componentsPenSlotAddSize,
                minHeight: _hit,
              ),
              iconSize: _icon,
              style: _compact.copyWith(
                minimumSize: const WidgetStatePropertyAll(
                  Size(KkjLight.componentsPenSlotAddSize, _hit),
                ),
              ),
              color: full
                  ? KkjLight.colorInkDisabled
                  : KkjLight.componentsPenSlotAddIcon,
              icon: const Icon(Icons.add),
              onPressed: widget.onAdd,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: KkjLight.componentsToolbarGroupGap,
              ),
              child: SizedBox(
                width: 1,
                height: 18,
                child: ColoredBox(color: KkjLight.colorBorderHairline),
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
            IconButton(
              tooltip: l10n.lassoTool,
              isSelected: widget.lassoSelected,
              constraints: const BoxConstraints(
                minWidth: _hit,
                minHeight: _hit,
              ),
              style: _compact.copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  widget.lassoSelected ? KkjLight.colorAccentSoft : null,
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
                  widget.textSelected ? KkjLight.colorAccentSoft : null,
                ),
              ),
              iconSize: _icon,
              icon: const Icon(Icons.text_fields),
              onPressed: widget.onText,
            ),
            IconButton(
              tooltip: l10n.imageTool,
              constraints: const BoxConstraints(
                minWidth: _hit,
                minHeight: _hit,
              ),
              disabledColor: KkjLight.colorInkDisabled,
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
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

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
          width: _PenToolbarState._arrowW,
          height: _hit,
          child: Icon(icon, size: 18, color: KkjLight.componentsPenSlotAddIcon),
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
    disabledColor: KkjLight.colorInkDisabled,
    onPressed: onPressed,
  );
}

class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: _hit,
    child: Icon(Icons.more_vert, color: KkjLight.componentsToolbarGripGlyph),
  );
}

class _PenSlot extends StatelessWidget {
  const _PenSlot({required this.pen, required this.selected});

  final Pen pen;
  final bool selected;

  static const _w = KkjLight.componentsPenSlotHitSize;
  static const _nibW = 12.0;
  static const _nibH = 24.0;

  /// 4..10 dp across the tool's own width range.
  double get _dot {
    final (lo, hi) = penWidthRange(pen.tool);
    return 4 + 6 * ((pen.width - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final dot = _dot;
    return SizedBox(
      width: _w,
      height: _hit,
      child: ClipRect(
        child: Stack(
          children: [
            // The nib hangs from the toolbar's top edge: its top is cut off,
            // and the selected pen sits `selected-offset` lower.
            Positioned(
              left: (_w - _nibW) / 2,
              top:
                  -8 +
                  (selected ? KkjLight.componentsPenSlotSelectedOffset : 0),
              child: CustomPaint(
                size: const Size(_nibW, _nibH),
                painter: _NibPainter(parseColor(pen.color), pen.isHighlighter),
              ),
            ),
            Positioned(
              left: (_w - dot) / 2,
              top: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: parseColor(pen.color),
                  border: Border.all(
                    color: KkjLight.componentsPenSlotThicknessDotOutline,
                  ),
                ),
                child: SizedBox.square(dimension: dot),
              ),
            ),
            if (selected) ...[
              const Positioned(
                right: 4,
                top: 10,
                child: Icon(
                  Icons.arrow_drop_down,
                  size: 14,
                  color: KkjLight.componentsPenSlotCaret,
                ),
              ),
              Positioned(
                left: (_w - KkjLight.componentsPenSlotSelectedWidth) / 2,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: KkjLight.componentsPenSlotSelectedIndicator,
                    borderRadius: BorderRadius.circular(
                      KkjLight.componentsPenSlotSelectedRounded,
                    ),
                  ),
                  child: const SizedBox(
                    width: KkjLight.componentsPenSlotSelectedWidth,
                    height: KkjLight.componentsPenSlotSelectedHeight,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A vertical pen in line art, nib down, in the pen's own color.
class _NibPainter extends CustomPainter {
  _NibPainter(this.color, [this.chisel = false]);

  final Color color;
  final bool chisel; // highlighter: a flat, slanted tip

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(w * 0.15, 0)
      ..lineTo(w * 0.15, h * 0.62)
      ..lineTo(chisel ? w * 0.3 : w * 0.5, h)
      ..lineTo(chisel ? w * 0.7 : w * 0.5, h)
      ..lineTo(w * 0.85, h * 0.62)
      ..lineTo(w * 0.85, 0)
      ..moveTo(w * 0.15, h * 0.62)
      ..lineTo(w * 0.85, h * 0.62);
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = KkjLight.componentsPenSlotGlyphStroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_NibPainter old) =>
      old.color != color || old.chisel != chisel;
}

const _cell = 48.0;
const _cols = 6;

/// The pen edit popover (UX-DR18): tool switch, name, palette, recent colors,
/// thickness, pressure, preview, delete. Reads and writes slot [index]
/// through [penSlotsProvider], so every change is stored at once; the canvas
/// below gets no input while it is open.
class PenEditDialog extends ConsumerWidget {
  const PenEditDialog({super.key, this.index = 0});

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final slots = ref.watch(penSlotsProvider);
    final i = index.clamp(0, slots.length - 1); // closing: may be gone
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

    final (lo, hi) = penWidthRange(pen.tool);
    final width = pen.width.clamp(lo, hi);
    final widthText = width.toStringAsFixed(1);
    void step(int d) => notifier.setWidth(i, width + d / 10);
    final palette = paletteFor(pen.tool);

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
                  color: active ? KkjLight.colorAccentSoft : null,
                  borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
                  border: Border.all(color: KkjLight.colorBorderControl),
                ),
                child: Center(child: Text(text)),
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
          disabledColor: KkjLight.colorInkDisabled,
          onPressed: enabled ? () => step(d) : null,
        );

    void del() => Navigator.of(context).pop(true);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: KkjLight.componentsPopoverBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            KkjLight.componentsPopoverRounded,
          ),
        ),
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
                      switchButton('pen', l10n.toolPen),
                      const SizedBox(width: KkjTokens.spacing2),
                      switchButton('highlighter', l10n.toolHighlighter),
                    ],
                  ),
                ),
                const SizedBox(height: KkjTokens.spacing3),
                Semantics(
                  header: true,
                  child: Text(
                    pen.isHighlighter ? l10n.toolHighlighter : l10n.toolPen,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: KkjTokens.spacing2),
                Center(child: Wrap(children: cells)),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: KkjTokens.spacing3),
                  Text(l10n.recentColors, style: theme.textTheme.labelMedium),
                  const SizedBox(height: KkjTokens.spacing1),
                  Center(
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
                Semantics(
                  container: true,
                  label: l10n.usePressure,
                  toggled: on,
                  onTap: () => toggle(!on),
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => toggle(!on),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: _hit),
                      child: Row(
                        children: [
                          Expanded(child: Text(l10n.usePressure)),
                          IgnorePointer(
                            child: Switch(value: on, onChanged: toggle),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: KkjTokens.spacing3),
                ExcludeSemantics(
                  child: SizedBox(
                    height: 64,
                    child: CustomPaint(painter: PenPreviewPainter(pen)),
                  ),
                ),
                const Divider(color: KkjLight.colorBorderHairline),
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
                                  : KkjLight.colorInkDisabled,
                            ),
                            const SizedBox(width: KkjTokens.spacing1),
                            Text(
                              l10n.deletePenSlot,
                              style: TextStyle(
                                color: canDelete
                                    ? theme.colorScheme.error
                                    : KkjLight.colorInkDisabled,
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
                        color: KkjLight.componentsPopoverBackground,
                        width: 2,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: KkjLight.colorAccent,
                          width: 2,
                        ),
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
    return strokeOutline(w, pen.usePressure, pts);
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
