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

    Widget section(String tool, String title) => _PaletteSection(
      tool: tool,
      title: title,
      list: palettes[tool]!,
      notifier: notifier,
      name: name,
    );

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

/// One tool's palette: swatches only. Press and hold one, then slide: the
/// others make room where it would land. Tap for the remove menu.
class _PaletteSection extends StatefulWidget {
  const _PaletteSection({
    required this.tool,
    required this.title,
    required this.list,
    required this.notifier,
    required this.name,
  });

  final String tool, title;
  final List<String> list;
  final PenPaletteNotifier notifier;
  final String Function(String hex) name;

  @override
  State<_PaletteSection> createState() => _PaletteSectionState();
}

class _PaletteSectionState extends State<_PaletteSection> {
  static const _cell = 48.0;

  List<GlobalKey> _keys = [];
  int? _from; // index in the stored list
  int _to = 0; // index it would take

  List<String> get _shown {
    final from = _from;
    if (from == null) return widget.list;
    final next = [...widget.list];
    next.insert(_to, next.removeAt(from));
    return next;
  }

  /// The slot (in the shown order) nearest to the finger.
  int _slotAt(Offset global) {
    var best = _to;
    var bestD = double.infinity;
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final c = box.localToGlobal(box.size.center(Offset.zero));
      final d = (c - global).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  void _end() {
    final from = _from;
    if (from != null && from != _to) {
      final next = [...widget.list];
      next.insert(_to, next.removeAt(from));
      widget.notifier.set(widget.tool, next);
    }
    setState(() => _from = null);
  }

  Widget _swatch(String hex, ThemeData theme) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: Color(int.parse('ff${hex.substring(1)}', radix: 16)),
      borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
      border: Border.all(color: theme.colorScheme.outlineVariant),
    ),
  );

  Future<void> _removeMenu(String hex, Offset at, AppLocalizations l10n) async {
    if (widget.list.length <= 1) return;
    final ok = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(
          value: true,
          child: Text(l10n.paletteRemove(widget.name(hex))),
        ),
      ],
    );
    if (ok == true) {
      widget.notifier.set(widget.tool, [
        for (final c in widget.list)
          if (c != hex) c,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final list = widget.list;
    final shown = _shown;
    if (_keys.length != list.length) {
      _keys = List.generate(list.length, (_) => GlobalKey());
    }
    final full = list.length >= PenSlotsStore.paletteMax;
    final textBtn = TextButton.styleFrom(
      minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
      foregroundColor: theme.colorScheme.onSurface,
    );

    Future<void> add() async {
      final hex = await showPenColorPicker(context, '#000000');
      if (hex != null && !list.contains(hex)) {
        widget.notifier.set(widget.tool, [...list, hex]);
      }
    }

    void moveBy(String hex, int d) {
      final i = list.indexOf(hex);
      final j = i + d;
      if (i < 0 || j < 0 || j >= list.length) return;
      final next = [...list];
      next.insert(j, next.removeAt(i));
      widget.notifier.set(widget.tool, next);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkjTokens.spacing4,
        vertical: KkjTokens.spacing2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.labelLarge),
          Wrap(
            children: [
              for (var i = 0; i < shown.length; i++)
                Semantics(
                  key: ValueKey(shown[i]),
                  label: widget.name(shown[i]),
                  customSemanticsActions: {
                    if (list.indexOf(shown[i]) > 0)
                      CustomSemanticsAction(
                        label: l10n.paletteEarlier(widget.name(shown[i])),
                      ): () =>
                          moveBy(shown[i], -1),
                    if (list.indexOf(shown[i]) < list.length - 1)
                      CustomSemanticsAction(
                        label: l10n.paletteLater(widget.name(shown[i])),
                      ): () =>
                          moveBy(shown[i], 1),
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) =>
                        _removeMenu(shown[i], d.globalPosition, l10n),
                    onLongPressStart: (_) => setState(() {
                      _from = list.indexOf(shown[i]);
                      _to = i;
                    }),
                    onLongPressMoveUpdate: (d) =>
                        setState(() => _to = _slotAt(d.globalPosition)),
                    onLongPressEnd: (_) => _end(),
                    onLongPressCancel: () => setState(() => _from = null),
                    child: SizedBox(
                      key: _keys[i],
                      width: _cell,
                      height: _cell,
                      child: Center(
                        // The held color shows where it would land.
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              KkjTokens.roundedSm,
                            ),
                            boxShadow: _from != null && i == _to
                                ? [
                                    BoxShadow(
                                      color: theme.colorScheme.onSurface,
                                      spreadRadius: 3,
                                    ),
                                  ]
                                : null,
                          ),
                          child: _swatch(shown[i], theme),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Wrap(
            children: [
              TextButton(
                style: textBtn,
                onPressed: full ? null : add,
                child: Text(l10n.paletteAdd),
              ),
              TextButton(
                style: textBtn,
                onPressed: () => widget.notifier.reset(widget.tool),
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
}
