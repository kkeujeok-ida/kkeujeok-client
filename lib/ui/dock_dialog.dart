import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'kk.dart';
import 'pen_toolbar.dart' show PenBubble, PenBubbleAnchor;
import 'providers.dart';
import '../model/toolbar_pos.dart';

/// Toolbar position bubble (same speech bubble as the pen's): four icon
/// buttons, top / right / bottom / left. Pops the picked [ToolbarDock]; the
/// caller docks. [current] is marked (float marks nothing).
class DockDialog extends ConsumerWidget {
  const DockDialog({super.key, required this.current, this.anchor});

  final ToolbarDock current;
  final PenBubbleAnchor Function()? anchor;

  static const _cell = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = [
      (ToolbarDock.top, Icons.align_vertical_top, l10n.dockTop),
      (ToolbarDock.right, Icons.align_horizontal_right, l10n.dockRight),
      (ToolbarDock.bottom, Icons.align_vertical_bottom, l10n.dockBottom),
      (ToolbarDock.left, Icons.align_horizontal_left, l10n.dockLeft),
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: PenBubble(
        anchor: anchor,
        leftHanded: ref.watch(leftHandedProvider),
        child: Padding(
          padding: const EdgeInsets.all(KkjLight.componentsPopoverPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (d, icon, label) in items)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KkjTokens.spacing1,
                  ),
                  child: Semantics(
                    button: true,
                    inMutuallyExclusiveGroup: true,
                    checked: current == d,
                    label: label,
                    onTap: () => Navigator.of(context).pop(d),
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
                      onTap: () => Navigator.of(context).pop(d),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: current == d ? Kk.colorAccentSoft : null,
                          borderRadius: BorderRadius.circular(
                            KkjTokens.roundedSm,
                          ),
                          border: Border.all(color: Kk.colorBorderControl),
                        ),
                        child: SizedBox(
                          width: _cell,
                          height: _cell,
                          child: Icon(icon),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
