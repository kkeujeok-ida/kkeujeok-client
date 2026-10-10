import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/pen.dart';
import '../render/page_painter.dart' show parseColor;
import 'library_fab.dart' show kkjShadow;

/// The floating rounded bar: grip (inert, not in the a11y tree) | one pen
/// slot. The slot is selected and does nothing yet (popover is Story 2.14).
class PenToolbar extends StatelessWidget {
  const PenToolbar({super.key, required this.pen});

  final Pen pen;

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
          vertical: KkjLight.componentsToolbarPaddingBlock,
          horizontal: KkjLight.componentsToolbarPaddingInline,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(child: _Grip()),
            Semantics(
              label: l10n.penSlotLabel(color, pen.width.toStringAsFixed(1)),
              button: true,
              selected: true,
              excludeSemantics: true,
              child: _PenSlot(pen: pen),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: KkjLight.componentsToolbarGripSize,
    child: Icon(Icons.more_vert, color: KkjLight.componentsToolbarGripGlyph),
  );
}

class _PenSlot extends StatelessWidget {
  const _PenSlot({required this.pen});

  final Pen pen;

  @override
  Widget build(BuildContext context) {
    const hit = KkjLight.componentsPenSlotHitSize;
    return SizedBox.square(
      dimension: hit,
      child: ClipRect(
        child: Stack(
          children: [
            // The nib hangs from the toolbar's top edge: its top is cut off,
            // and the selected pen sits `selected-offset` lower.
            Positioned(
              left: (hit - KkjLight.componentsPenSlotGlyphWidth) / 2,
              top:
                  -KkjTokens.spacing2 +
                  KkjLight.componentsPenSlotSelectedOffset,
              child: CustomPaint(
                size: const Size(
                  KkjLight.componentsPenSlotGlyphWidth,
                  KkjLight.componentsPenSlotGlyphHeight,
                ),
                painter: _NibPainter(parseColor(pen.color)),
              ),
            ),
            Positioned(
              left: (hit - 8) / 2,
              top: 33,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: parseColor(pen.color),
                  border: Border.all(
                    color: KkjLight.componentsPenSlotThicknessDotOutline,
                  ),
                ),
                child: const SizedBox.square(dimension: 8),
              ),
            ),
            const Positioned(
              right: 2,
              top: 20,
              child: Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: KkjLight.componentsPenSlotCaret,
              ),
            ),
            Positioned(
              left: (hit - KkjLight.componentsPenSlotSelectedWidth) / 2,
              bottom: 1,
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
