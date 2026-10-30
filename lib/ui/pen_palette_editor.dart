import 'package:flutter/material.dart';
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

    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(icon),
      onPressed: onTap,
    );

    Widget section(String tool, String title) {
      final list = palettes[tool]!;
      final full = list.length >= PenSlotsStore.paletteMax;
      void move(int i, int d) {
        final next = [...list];
        next.insert(i + d, next.removeAt(i));
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
            Wrap(
              spacing: KkjTokens.spacing2,
              children: [
                for (var i = 0; i < list.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: name(list[i]),
                        child: ExcludeSemantics(
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(
                                  'ff${list[i].substring(1)}',
                                  radix: 16,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(
                                KkjTokens.roundedSm,
                              ),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      btn(
                        Icons.chevron_left,
                        l10n.paletteEarlier(name(list[i])),
                        i == 0 ? null : () => move(i, -1),
                      ),
                      btn(
                        Icons.chevron_right,
                        l10n.paletteLater(name(list[i])),
                        i == list.length - 1 ? null : () => move(i, 1),
                      ),
                      btn(
                        Icons.close,
                        l10n.paletteRemove(name(list[i])),
                        list.length <= 1
                            ? null
                            : () => notifier.set(tool, [
                                for (final c in list)
                                  if (c != list[i]) c,
                              ]),
                      ),
                    ],
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
