import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'library_fab.dart' show kkjShadow;

const _hit = KkjTokens.spacingHitMinAndroid;
const _pad = KkjLight.componentsPopoverPadding;

/// Size of [SelectionMenu], so the editor can place it without measuring.
const selectionMenuSize = Size(4 * _hit + 2 * _pad, _hit + 2 * _pad);

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
  });

  final bool ratioLock;
  final VoidCallback onRatioLock, onScaleUp, onScaleDown, onRotate90;

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
        child: Row(
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
      ),
    );
  }
}
