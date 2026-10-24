import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/pen.dart';
import '../render/page_painter.dart' show parseColor;
import 'library_fab.dart' show kkjShadow;

const _hit = KkjTokens.spacingHitMinAndroid;
const _pad = KkjLight.componentsPopoverPadding;

/// Size of [SelectionMenu], so the editor can place it without measuring.
/// Editable: [color] and [width] on top of copy, cut, delete (first row), the
/// step buttons on a second row. Read only: copy alone.
Size selectionMenuSize({required bool edit, required bool strokes}) {
  final top = edit ? (strokes ? 5 : 3) : 1;
  return Size(top * _hit + 2 * _pad, (edit ? 2 : 1) * _hit + 2 * _pad);
}

/// Colors the menu offers: the pen palette the client has (spec default pen).
final selectionPalette = {for (final p in defaultPenSlots) p.color}.toList();

/// Side of the selection box the menu prefers; one value so the left-handed
/// setting (Epic 10) can flip it.
const selectionMenuPrefersAbove = true;

/// Floating menu over the selection: aspect lock and the step buttons.
class SelectionMenu extends StatelessWidget {
  const SelectionMenu({
    super.key,
    required this.ratioLock,
    required this.onRatioLock,
    required this.onScaleUp,
    required this.onScaleDown,
    required this.onRotate90,
    required this.onCopy,
    this.edit = true,
    this.strokes = false,
    this.onColor,
    this.onWidth,
    this.onCut,
    this.onDelete,
  });

  final bool ratioLock, edit, strokes;
  final VoidCallback onRatioLock, onScaleUp, onScaleDown, onRotate90, onCopy;
  final VoidCallback? onColor, onWidth, onCut, onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget button(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool? toggled,
    }) => Semantics(
      label: label,
      button: true,
      toggled: toggled,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: IconButton(
          onPressed: onTap,
          constraints: const BoxConstraints.tightFor(width: _hit, height: _hit),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: toggled == true ? KkjLight.colorAccentSoft : null,
          ),
          icon: Icon(icon),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KkjLight.componentsPopoverBackground,
        borderRadius: BorderRadius.circular(KkjLight.componentsPopoverRounded),
        boxShadow: kkjShadow(KkjLight.componentsPopoverShadow),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (edit && strokes) ...[
                  button(Icons.palette_outlined, l10n.strokeColor, onColor!),
                  button(Icons.line_weight, l10n.strokeWidth, onWidth!),
                ],
                button(Icons.copy, l10n.copy, onCopy),
                if (edit) ...[
                  button(Icons.content_cut, l10n.cut, onCut!),
                  button(Icons.delete_outline, l10n.delete, onDelete!),
                ],
              ],
            ),
            if (edit)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button(
                    ratioLock ? Icons.lock : Icons.lock_open,
                    l10n.ratioLock,
                    onRatioLock,
                    toggled: ratioLock,
                  ),
                  button(Icons.zoom_in, l10n.scaleUp, onScaleUp),
                  button(Icons.zoom_out, l10n.scaleDown, onScaleDown),
                  button(Icons.rotate_right, l10n.rotate90, onRotate90),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Small menu on a blank tap: [paste] (off when [canPaste] is false) and
/// [select all].
class BlankTapMenu extends StatelessWidget {
  const BlankTapMenu({
    super.key,
    required this.canPaste,
    required this.onPaste,
    required this.onSelectAll,
  });

  final bool canPaste;
  final VoidCallback onPaste, onSelectAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget button(String label, VoidCallback? onTap) => TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(minimumSize: const Size(_hit, _hit)),
      child: Text(label),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KkjLight.componentsPopoverBackground,
        borderRadius: BorderRadius.circular(KkjLight.componentsPopoverRounded),
        boxShadow: kkjShadow(KkjLight.componentsPopoverShadow),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_pad),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(l10n.paste, canPaste ? onPaste : null),
            button(l10n.selectAll, onSelectAll),
          ],
        ),
      ),
    );
  }
}

/// Palette popover: the chosen `#rrggbb`, or null when dismissed.
Future<String?> pickStrokeColor(BuildContext context) => showDialog<String>(
  context: context,
  builder: (context) => Dialog(
    backgroundColor: KkjLight.componentsPopoverBackground,
    child: Padding(
      padding: const EdgeInsets.all(_pad),
      child: Wrap(
        children: [
          for (final c in selectionPalette)
            Semantics(
              label: c,
              button: true,
              excludeSemantics: true,
              onTap: () => Navigator.pop(context, c),
              child: InkWell(
                onTap: () => Navigator.pop(context, c),
                child: SizedBox(
                  width: _hit,
                  height: _hit,
                  child: ColoredBox(color: parseColor(c)),
                ),
              ),
            ),
        ],
      ),
    ),
  ),
);

/// Thickness popover (0.5..10 in 0.1 steps): the value when the slider is
/// released, or null when dismissed.
Future<double?> pickStrokeWidth(BuildContext context, double initial) =>
    showDialog<double>(
      context: context,
      builder: (context) {
        var v = initial.clamp(0.5, 10.0);
        return Dialog(
          backgroundColor: KkjLight.componentsPopoverBackground,
          child: StatefulBuilder(
            builder: (context, set) => Padding(
              padding: const EdgeInsets.all(_pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${AppLocalizations.of(context).strokeWidth} '
                    '${v.toStringAsFixed(1)}',
                  ),
                  Slider(
                    value: v,
                    min: 0.5,
                    max: 10,
                    divisions: 95,
                    label: v.toStringAsFixed(1),
                    semanticFormatterCallback: (x) => x.toStringAsFixed(1),
                    onChanged: (x) => set(() => v = x),
                    onChangeEnd: (x) => Navigator.pop(context, x),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
