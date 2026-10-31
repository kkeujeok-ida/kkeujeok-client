import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/pen.dart';
import '../storage/pen_slots_store.dart';
import 'pen_color_picker.dart';
import 'pen_toolbar.dart' show penColorName;
import 'providers.dart';

/// Settings: per tool, add / remove / reorder palette colors or reset them.
/// Every change is stored at once through [penPaletteProvider].
class PenPaletteEditor extends ConsumerWidget {
  const PenPaletteEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palettes = ref.watch(penPaletteProvider);
    final notifier = ref.read(penPaletteProvider.notifier);

    String name(String hex) {
      final key = colorNameKeyFor(hex);
      return key == 'custom'
          ? l10n.customColorSlotLabel(hex.toUpperCase())
          : penColorName(l10n, key);
    }

    Widget swatch(String hex, {double size = 32}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(int.parse('ff${hex.substring(1)}', radix: 16)),
        borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
    );

    Widget section(String tool, String title) {
      final list = palettes[tool]!;
      final full = list.length >= PenSlotsStore.paletteMax;
      void move(int from, int to) {
        final next = [...list];
        next.insert(to, next.removeAt(from));
        notifier.set(tool, next);
      }

      Future<void> add() async {
        final hex = await showPenColorPicker(context, '#000000');
        if (hex != null && !list.contains(hex))
          notifier.set(tool, [...list, hex]);
      }

      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkjTokens.spacing4,
          vertical: KkjTokens.spacing2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            // Only the colors: press and hold to drag one to a new place,
            // tap for the remove menu.
            Wrap(
              children: [
                for (var i = 0; i < list.length; i++)
                  DragTarget<int>(
                    onWillAcceptWithDetails: (d) => d.data != i,
                    onAcceptWithDetails: (d) => move(d.data, i),
                    builder: (context, candidates, _) => Semantics(
                      label: name(list[i]),
                      customSemanticsActions: {
                        if (i > 0)
                          CustomSemanticsAction(
                            label: l10n.paletteEarlier(name(list[i])),
                          ): () =>
                              move(i, i - 1),
                        if (i < list.length - 1)
                          CustomSemanticsAction(
                            label: l10n.paletteLater(name(list[i])),
                          ): () =>
                              move(i, i + 1),
                      },
                      child: LongPressDraggable<int>(
                        data: i,
                        feedback: Material(
                          color: Colors.transparent,
                          child: swatch(list[i], size: 40),
                        ),
                        childWhenDragging: const SizedBox(
                          width: 48,
                          height: 48,
                        ),
                        child: PopupMenuButton<void>(
                          tooltip: name(list[i]),
                          enabled: list.length > 1,
                          padding: EdgeInsets.zero,
                          onSelected: (_) => notifier.set(tool, [
                            for (final c in list)
                              if (c != list[i]) c,
                          ]),
                          itemBuilder: (_) => [
                            PopupMenuItem<void>(
                              child: Text(l10n.paletteRemove(name(list[i]))),
                            ),
                          ],
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    KkjTokens.roundedSm,
                                  ),
                                  boxShadow: candidates.isEmpty
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: theme.colorScheme.primary,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                ),
                                child: swatch(list[i]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
                  ),
                  onPressed: full ? null : add,
                  child: Text(l10n.paletteAdd),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
                  ),
                  onPressed: () => notifier.reset(tool),
                  child: Text(l10n.paletteReset),
                ),
              ],
            ),
            if (full)
              Semantics(
                liveRegion: true,
                child: Text(l10n.paletteFull, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KkjTokens.spacing4,
            KkjTokens.spacing3,
            KkjTokens.spacing4,
            KkjTokens.spacing1,
          ),
          child: Semantics(
            header: true,
            child: Text(
              l10n.palettePenTitle,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ),
        section('pen', l10n.toolPen),
        section('highlighter', l10n.toolHighlighter),
      ],
    );
  }
}
