import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kk.dart';

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
/// "new note" and "new folder" items, turns into ×, and veils what is behind. Place it in a
/// Stack that fills the library.
class LibraryFab extends StatefulWidget {
  const LibraryFab({
    super.key,
    required this.onNewNote,
    required this.onNewFolder,
    this.onImportPdf,
    this.leftHanded = false,
  });

  /// Left-handed: the `+` sits at the bottom left and its items open to the right.
  final bool leftHanded;

  /// Story 9.2; null hides the item.
  final VoidCallback? onImportPdf;
  final VoidCallback onNewNote;
  final VoidCallback onNewFolder;

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

  void _importPdf() {
    _set(false);
    widget.onImportPdf!();
  }

  void _newFolder() {
    _set(false);
    widget.onNewFolder();
  }

  Widget _item(
    String text,
    IconData icon,
    VoidCallback onTap, {
    FocusNode? focus,
  }) {
    final label = Theme.of(context).textTheme.labelMedium!
        .copyWith(color: Kk.componentsFabLabelColor);
    final caption = ExcludeSemantics(child: Text(text, style: label));
    const gap = SizedBox(width: KkjLight.componentsFabItemGap);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.leftHanded) ...[caption, gap],
        Semantics(
          button: true,
          label: text,
          excludeSemantics: true,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Kk.componentsFabItemBackground,
              shape: BoxShape.circle,
              boxShadow: kkjShadow(Kk.componentsFabShadow),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                focusNode: focus,
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox.square(
                  dimension: KkjLight.componentsFabItemSize,
                  child: Icon(icon, color: Kk.componentsFabItemIcon),
                ),
              ),
            ),
          ),
        ),
        if (widget.leftHanded) ...[gap, caption],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shadow = kkjShadow(Kk.componentsFabShadow);
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
                    color: Kk.componentsFabVeil.withValues(
                      alpha: KkjLight.componentsFabVeilOpacity,
                    ),
                  ),
                ),
              ),
            PositionedDirectional(
              start: widget.leftHanded ? KkjLight.componentsFabInset : null,
              end: widget.leftHanded ? null : KkjLight.componentsFabInset,
              bottom: KkjLight.componentsFabInset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: widget.leftHanded
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  if (_open) ...[
                    _item(
                      l10n.folderAdd,
                      Icons.create_new_folder_outlined,
                      _newFolder,
                    ),
                    const SizedBox(height: KkjLight.componentsFabItemGap),
                    if (widget.onImportPdf != null) ...[
                      _item(
                        l10n.pdfImport,
                        Icons.picture_as_pdf_outlined,
                        _importPdf,
                      ),
                      const SizedBox(height: KkjLight.componentsFabItemGap),
                    ],
                    _item(
                      l10n.newNote,
                      Icons.note_add_outlined,
                      _newNote,
                      focus: _itemFocus,
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
                        color: Kk.componentsFabBackground,
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
                              child: Icon(
                                Icons.add,
                                color: Kk.componentsFabIcon,
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
