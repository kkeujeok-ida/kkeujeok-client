import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/pen.dart';
import '../render/page_painter.dart' show parseColor;
import '../render/stroke_outline.dart';
import 'library_fab.dart' show kkjShadow;
import 'providers.dart';

/// The floating rounded bar: grip (inert, not in the a11y tree) | one pen
/// slot. Tapping the selected slot opens the pen edit popover.
/// Touch size of a toolbar button: tighter than the 48 dp default so the bar is short.
const _hit = 34.0;
const _icon = 20.0;

/// A button as small as its icon: no 48 dp tap-target padding around it.
final _compact = IconButton.styleFrom(
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  padding: EdgeInsets.zero,
  minimumSize: const Size(_hit, _hit),
);

class PenToolbar extends StatelessWidget {
  const PenToolbar({
    super.key,
    required this.pen,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.onPenTap,
    this.slotFocus,
    this.lassoSelected = false,
    this.onLasso,
    this.textSelected = false,
    this.onText,
    this.onImage,
  });

  final Pen pen;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onPenTap;
  final FocusNode? slotFocus;
  final bool lassoSelected;
  final VoidCallback? onLasso;
  final bool textSelected;
  final VoidCallback? onText;

  /// [이미지]: opens the gallery / camera choice. Null disables it.
  final VoidCallback? onImage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = switch (pen.colorNameKey) {
      'black' => l10n.colorBlack,
      final k => throw ArgumentError.value(k, 'colorNameKey'),
    };
    return DecoratedBox(
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
            Semantics(
              label: l10n.penSlotLabel(color, pen.width.toStringAsFixed(1)),
              button: true,
              selected: !lassoSelected && !textSelected,
              onTap: onPenTap,
              excludeSemantics: true,
              child: InkResponse(
                focusNode: slotFocus,
                onTap: onPenTap,
                containedInkWell: true,
                highlightShape: BoxShape.rectangle,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                borderRadius: BorderRadius.circular(
                  KkjLight.componentsToolbarRounded,
                ),
                child: _PenSlot(pen: pen),
              ),
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
            IconButton(
              tooltip: l10n.lassoTool,
              isSelected: lassoSelected,
              constraints: const BoxConstraints(
                minWidth: _hit,
                minHeight: _hit,
              ),
              style: _compact.copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  lassoSelected ? KkjLight.colorAccentSoft : null,
                ),
              ),
              iconSize: _icon,
              icon: const Icon(Icons.highlight_alt),
              onPressed: onLasso,
            ),
            IconButton(
              tooltip: l10n.textTool,
              isSelected: textSelected,
              constraints: const BoxConstraints(
                minWidth: _hit,
                minHeight: _hit,
              ),
              style: _compact.copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  textSelected ? KkjLight.colorAccentSoft : null,
                ),
              ),
              iconSize: _icon,
              icon: const Icon(Icons.text_fields),
              onPressed: onText,
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
              onPressed: onImage,
            ),
            _HistoryButton(
              icon: Icons.undo,
              tooltip: l10n.undo,
              onPressed: canUndo ? onUndo : null,
            ),
            _HistoryButton(
              icon: Icons.redo,
              tooltip: l10n.redo,
              onPressed: canRedo ? onRedo : null,
            ),
          ],
        ),
      ),
    );
  }
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
    constraints: const BoxConstraints(
      minWidth: _hit,
      minHeight: _hit,
    ),
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
  const _PenSlot({required this.pen});

  final Pen pen;

  // A little wider than a button: the caret sits right of the nib.
  static const _w = _hit + 6;
  static const _nibW = 12.0;
  static const _nibH = 24.0;

  @override
  Widget build(BuildContext context) {
    final center = (_hit - _nibW) / 2;
    return SizedBox(
      width: _w,
      height: _hit,
      child: ClipRect(
        child: Stack(
          children: [
            // The nib hangs from the toolbar's top edge: its top is cut off,
            // and the selected pen sits `selected-offset` lower.
            Positioned(
              left: center,
              top: -8 + KkjLight.componentsPenSlotSelectedOffset,
              child: CustomPaint(
                size: const Size(_nibW, _nibH),
                painter: _NibPainter(parseColor(pen.color)),
              ),
            ),
            Positioned(
              left: (_hit - 6) / 2,
              top: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: parseColor(pen.color),
                  border: Border.all(
                    color: KkjLight.componentsPenSlotThicknessDotOutline,
                  ),
                ),
                child: const SizedBox.square(dimension: 6),
              ),
            ),
            const Positioned(
              right: 0,
              top: 10,
              child: Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: KkjLight.componentsPenSlotCaret,
              ),
            ),
            Positioned(
              left: (_hit - KkjLight.componentsPenSlotSelectedWidth) / 2,
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
        ),
      ),
    );
  }
}

/// A vertical pen in line art, nib down, in the pen's own color.
class _NibPainter extends CustomPainter {
  _NibPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(w * 0.15, 0)
      ..lineTo(w * 0.15, h * 0.62)
      ..lineTo(w * 0.5, h)
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
  bool shouldRepaint(_NibPainter old) => old.color != color;
}

/// The pen edit popover: tool name, "use pressure" switch, preview stroke.
/// Reads and writes slot [index] through [penSlotsProvider]; the canvas below
/// gets no input while it is open.
class PenEditDialog extends ConsumerWidget {
  const PenEditDialog({super.key, this.index = 0});

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pen = ref.watch(penSlotsProvider)[index];
    final on = pen.usePressure;
    void toggle(bool v) =>
        ref.read(penSlotsProvider.notifier).setUsePressure(index, v);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Dialog(
        backgroundColor: KkjLight.componentsPopoverBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            KkjLight.componentsPopoverRounded,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(KkjLight.componentsPopoverPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.penEditTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: KkjTokens.spacing3),
                Semantics(
                  container: true,
                  label: l10n.usePressure,
                  toggled: on,
                  onTap: () => toggle(!on),
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => toggle(!on),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: _hit,
                      ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _previewW = 280.0, _previewH = 64.0, _previewScale = 3.0;
const _previewAmp = 12.0, _previewMargin = 24.0; // margin: room for the caps

/// A wave stroke whose pressure rises and falls, drawn through
/// [strokeOutline] with the pen's `usePressure`; flat when it is off. Built in
/// a fixed box and scaled to the paint size, clipped to it.
class PenPreviewPainter extends CustomPainter {
  PenPreviewPainter(this.pen) : polygon = _polygon(pen);

  final Pen pen;
  final List<List<double>> polygon;

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
    canvas.drawPath(
      outlinePath(polygon),
      Paint()..color = parseColor(pen.color),
    );
  }

  @override
  bool shouldRepaint(PenPreviewPainter old) =>
      old.pen.usePressure != pen.usePressure ||
      old.pen.color != pen.color ||
      old.pen.width != pen.width;
}
