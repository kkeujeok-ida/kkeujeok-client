import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';

final _shadowRe = RegExp(
  r'^\s*(-?\d+(?:\.\d+)?)(?:px)?\s+(-?\d+(?:\.\d+)?)(?:px)?\s+'
  r'(\d+(?:\.\d+)?)(?:px)?\s+#([0-9a-fA-F]{8})\s*$',
);

/// A token shadow string such as `0 2px 12px #22242A29` (offset x, y, blur,
/// #RRGGBBAA). Anything else, such as several shadows or a spread, gives no
/// shadow rather than an error.
List<BoxShadow> kkjShadow(String css) {
  final m = _shadowRe.firstMatch(css);
  if (m == null) return const [];
  final rgba = m.group(4)!;
  return [
    BoxShadow(
      offset: Offset(double.parse(m.group(1)!), double.parse(m.group(2)!)),
      blurRadius: double.parse(m.group(3)!),
      color: Color(
        int.parse(rgba.substring(0, 6), radix: 16) |
            (int.parse(rgba.substring(6), radix: 16) << 24),
      ),
    ),
  ];
}

/// The round `+` at the library's bottom right. Expanded it shows the
/// "new note" item, turns into ×, and veils what is behind. Place it in a
/// Stack that fills the library.
class LibraryFab extends StatefulWidget {
  const LibraryFab({super.key, required this.onNewNote});

  final VoidCallback onNewNote;

  @override
  State<LibraryFab> createState() => _LibraryFabState();
}

class _LibraryFabState extends State<LibraryFab> {
  bool _open = false;
  final _fabFocus = FocusNode(debugLabel: 'fab');
  final _itemFocus = FocusNode(debugLabel: 'fab-item');

  @override
  void dispose() {
    _fabFocus.dispose();
    _itemFocus.dispose();
    super.dispose();
  }

  void _set(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
    // Open: first item takes focus; closed: back to the button.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (open ? _itemFocus : _fabFocus).requestFocus();
    });
  }

  void _newNote() {
    _set(false);
    widget.onNewNote();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = Theme.of(context).textTheme.labelMedium!
        .copyWith(color: KkjLight.componentsFabLabelColor);
    final shadow = kkjShadow(KkjLight.componentsFabShadow);
    final still = MediaQuery.disableAnimationsOf(context);

    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _set(false);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => _set(false),
        },
        child: Stack(
          children: [
            if (_open)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _set(false),
                  child: ColoredBox(
                    color: KkjLight.componentsFabVeil.withValues(
                      alpha: KkjLight.componentsFabVeilOpacity,
                    ),
                  ),
                ),
              ),
            PositionedDirectional(
              end: KkjLight.componentsFabInset,
              bottom: KkjLight.componentsFabInset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_open) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Text(l10n.newNote, style: label),
                        ),
                        const SizedBox(width: KkjLight.componentsFabItemGap),
                        Semantics(
                          button: true,
                          label: l10n.newNote,
                          excludeSemantics: true,
                          onTap: _newNote,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: KkjLight.componentsFabItemBackground,
                              shape: BoxShape.circle,
                              boxShadow: shadow,
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                focusNode: _itemFocus,
                                customBorder: const CircleBorder(),
                                onTap: _newNote,
                                child: const SizedBox.square(
                                  dimension: KkjLight.componentsFabItemSize,
                                  child: Icon(
                                    Icons.note_add_outlined,
                                    color: KkjLight.componentsFabItemIcon,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: KkjLight.componentsFabItemGap),
                  ],
                  Semantics(
                    button: true,
                    label: _open ? l10n.closeMenu : l10n.addNote,
                    excludeSemantics: true,
                    onTap: () => _set(!_open),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: KkjLight.componentsFabBackground,
                        shape: BoxShape.circle,
                        boxShadow: shadow,
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          focusNode: _fabFocus,
                          customBorder: const CircleBorder(),
                          onTap: () => _set(!_open),
                          child: SizedBox.square(
                            dimension: KkjLight.componentsFabSize,
                            child: AnimatedRotation(
                              turns: _open ? 0.125 : 0, // + -> x
                              duration: still
                                  ? Duration.zero
                                  : const Duration(milliseconds: 150),
                              child: const Icon(
                                Icons.add,
                                color: KkjLight.componentsFabIcon,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
