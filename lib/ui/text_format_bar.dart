import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/text_layout.dart';
import '../render/page_painter.dart' show parseColor;
import 'library_fab.dart' show kkjShadow;
import 'selection_menu.dart' show selectionPalette;
import 'text_edit.dart';

const _hit = KkjTokens.spacingHitMinAndroid;
const _pad = KkjLight.componentsPopoverPadding;

/// Width and height of the bar row (the size / color panel adds to it).
const textFormatBarSize = Size(4 * _hit + 2 * _pad, _hit + 2 * _pad);

String _sizeText(num v) => v == v.truncate() ? '${v.toInt()}' : '$v';

/// [size][color][B][I] over the box being edited. A format picked with text
/// selected goes to that text; with none, to what is typed next. The bar never
/// takes focus, so the keyboard stays.
class TextFormatBar extends StatefulWidget {
  const TextFormatBar({
    super.key,
    required this.controller,
    this.panelFirst = false,
  });

  final StyledTextController controller;

  /// The size / color panel goes above the bar (the bar sits under the box).
  final bool panelFirst;

  @override
  State<TextFormatBar> createState() => _TextFormatBarState();
}

enum _Panel { none, size, color }

class _TextFormatBarState extends State<TextFormatBar> {
  _Panel _open = _Panel.none;

  void _toggle(_Panel p) =>
      setState(() => _open = _open == p ? _Panel.none : p);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.controller;
    return ExcludeFocus(
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          Widget button({
            required String label,
            required Widget child,
            required VoidCallback onTap,
            bool? toggled,
          }) => Semantics(
            label: label,
            button: true,
            toggled: toggled,
            excludeSemantics: true,
            onTap: onTap,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(
                KkjLight.componentsPopoverRounded,
              ),
              child: Ink(
                width: _hit,
                height: _hit,
                decoration: BoxDecoration(
                  color: toggled == true ? KkjLight.colorAccentSoft : null,
                  borderRadius: BorderRadius.circular(
                    KkjLight.componentsPopoverRounded,
                  ),
                ),
                child: Center(child: child),
              ),
            ),
          );
          Widget toggle(String key, String name, Widget glyph) {
            final on = c.isOn(key);
            return button(
              label: '$name, ${on ? l10n.on : l10n.off}',
              toggled: on,
              onTap: () => c.toggle(key),
              child: glyph,
            );
          }

          final sv = c.valueOf('size');
          final size = sv is num && sv.isFinite
              ? sv.toDouble().clamp(sizeMin, sizeMax)
              : sizeDefault;
          final color = c.valueOf('color') as String;
          final bar = _box(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                button(
                  label: l10n.fontSizeValue(_sizeText(size)),
                  onTap: () => _toggle(_Panel.size),
                  child: Text(_sizeText(size)),
                ),
                button(
                  label: l10n.textColor,
                  onTap: () => _toggle(_Panel.color),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: parseColor(color),
                      border: Border.all(color: KkjLight.colorBorderHairline),
                    ),
                    child: const SizedBox.square(dimension: 20),
                  ),
                ),
                toggle(
                  'bold',
                  l10n.bold,
                  const Text(
                    'B',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                toggle(
                  'italic',
                  l10n.italic,
                  const Text(
                    'I',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          );
          final panel = switch (_open) {
            _Panel.none => null,
            _Panel.size => _box(
              SizedBox(
                width: 5 * _hit,
                child: Wrap(
                  children: [
                    for (final s in sizeSteps)
                      button(
                        label: l10n.fontSizeValue(_sizeText(s)),
                        toggled: s == size,
                        onTap: () {
                          c.apply('size', s);
                          setState(() => _open = _Panel.none);
                        },
                        child: Text(_sizeText(s)),
                      ),
                  ],
                ),
              ),
            ),
            _Panel.color => _box(
              Wrap(
                children: [
                  for (final k in selectionPalette)
                    button(
                      label: k,
                      toggled: k == color,
                      onTap: () {
                        c.apply('color', k);
                        setState(() => _open = _Panel.none);
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: parseColor(k),
                        ),
                        child: const SizedBox.square(dimension: 24),
                      ),
                    ),
                ],
              ),
            ),
          };
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (panel != null && widget.panelFirst) panel,
              bar,
              if (panel != null && !widget.panelFirst) panel,
            ],
          );
        },
      ),
    );
  }

  Widget _box(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: KkjLight.componentsPopoverBackground,
      borderRadius: BorderRadius.circular(KkjLight.componentsPopoverRounded),
      boxShadow: kkjShadow(KkjLight.componentsPopoverShadow),
    ),
    child: Padding(padding: const EdgeInsets.all(_pad), child: child),
  );
}
