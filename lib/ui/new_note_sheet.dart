import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/note.dart';
import '../model/note_title.dart';
import 'providers.dart';

/// Creates a note from the sheet. Resolves to the new note, or null when the
/// sheet was cancelled.
Future<Note?> showNewNoteSheet(BuildContext context) =>
    showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      // Dragging closes without asking PopScope, so it would cut a save.
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: KkjLight.colorSurfaceRaised,
      barrierColor: KkjLight.colorScrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KkjTokens.roundedLg),
        ),
      ),
      builder: (_) => const _NewNoteSheet(),
    );

/// Stops typing at [max] Unicode code points (`maxLength` counts characters).
class _CodePointLimit extends TextInputFormatter {
  const _CodePointLimit(this.max);
  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue v) {
    if (v.text.runes.length <= max) return v;
    final text = String.fromCharCodes(v.text.runes.take(max));
    int clamp(int o) => o < 0 ? o : (o > text.length ? text.length : o);
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: clamp(v.selection.baseOffset),
        extentOffset: clamp(v.selection.extentOffset),
      ),
      composing: TextRange.empty, // the old range may lie past the new end
    );
  }
}

class _NewNoteSheet extends ConsumerStatefulWidget {
  const _NewNoteSheet();

  @override
  ConsumerState<_NewNoteSheet> createState() => _NewNoteSheetState();
}

class _NewNoteSheetState extends ConsumerState<_NewNoteSheet> {
  final _title = TextEditingController();
  late String _background;
  late String _orientation;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final d = ref.read(newNoteDefaultsStoreProvider).read();
    _background = d.background;
    _orientation = d.orientation;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      final note = await ref
          .read(libraryProvider.notifier)
          .create(
            title: _title.text,
            background: _background,
            orientation: _orientation,
          );
      if (mounted) Navigator.of(context).pop(note);
    } catch (_) {
      // Any failure (also an over-long title) gets the same notice; the sheet
      // stays so the person can try again.
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(KkjLight.componentsInputRounded),
      borderSide: const BorderSide(color: KkjLight.componentsInputBorder),
    );
    final backgrounds = {
      'plain': l10n.backgroundPlain,
      'lined': l10n.backgroundLined,
      'grid': l10n.backgroundGrid,
      'dot': l10n.backgroundDot,
    };
    final orientations = {
      'portrait': l10n.orientationPortrait,
      'landscape': l10n.orientationLandscape,
    };

    return PopScope(
      canPop: !_saving,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: l10n.newNote,
        explicitChildNodes: true,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KkjTokens.spacing5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(l10n.newNote, style: theme.textTheme.titleLarge),
                ),
                const SizedBox(height: KkjTokens.spacing4),
                TextField(
                  controller: _title,
                  enabled: !_saving,
                  maxLength: maxTitleLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  inputFormatters: const [_CodePointLimit(maxTitleLength)],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: l10n.noteTitle,
                    labelStyle: const TextStyle(
                      color: KkjLight.componentsInputPlaceholder,
                    ),
                    counterText: '',
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: const BorderSide(
                        color: KkjLight.colorAccent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: KkjTokens.spacing4),
                _Group(
                  title: l10n.pageBackground,
                  value: _background,
                  options: backgrounds,
                  enabled: !_saving,
                  onChanged: (v) => setState(() => _background = v),
                ),
                const SizedBox(height: KkjTokens.spacing3),
                _Group(
                  title: l10n.pageOrientation,
                  value: _orientation,
                  options: orientations,
                  enabled: !_saving,
                  onChanged: (v) => setState(() => _orientation = v),
                ),
                if (_failed) ...[
                  const SizedBox(height: KkjTokens.spacing3),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.noteSaveFailed,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: KkjLight.colorStatusError,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: KkjTokens.spacing5),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: KkjTokens.spacing3,
                  runSpacing: KkjTokens.spacing3,
                  children: [
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KkjLight.componentsButtonSecondaryText,
                        backgroundColor:
                            KkjLight.componentsButtonSecondaryBackground,
                        side: const BorderSide(
                          color: KkjLight.componentsButtonSecondaryBorder,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            KkjLight.componentsButtonSecondaryRounded,
                          ),
                        ),
                        minimumSize: const Size(
                          KkjTokens.spacingHitMinAndroid,
                          KkjTokens.spacingControlHeightAndroid,
                        ),
                      ),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : _create,
                      style: FilledButton.styleFrom(
                        foregroundColor: KkjLight.componentsButtonPrimaryText,
                        backgroundColor:
                            KkjLight.componentsButtonPrimaryBackground,
                        disabledBackgroundColor: KkjLight.colorInkDisabled,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            KkjLight.componentsButtonPrimaryRounded,
                          ),
                        ),
                        minimumSize: const Size(
                          KkjTokens.spacingHitMinAndroid,
                          KkjTokens.spacingControlHeightAndroid,
                        ),
                      ),
                      child: Text(l10n.create),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled single-choice row. Each option is one 48dp semantic node that
/// reports whether it is selected.
class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String value;
  final Map<String, String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.bodySmall),
        Wrap(
          spacing: KkjTokens.spacing3,
          children: [
            for (final e in options.entries)
              Semantics(
                inMutuallyExclusiveGroup: true,
                selected: e.key == value,
                enabled: enabled,
                label: e.value,
                excludeSemantics: true,
                onTap: enabled ? () => onChanged(e.key) : null,
                child: InkWell(
                  onTap: enabled ? () => onChanged(e.key) : null,
                  borderRadius: BorderRadius.circular(
                    KkjLight.componentsInputRounded,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: KkjTokens.spacingHitMinAndroid,
                      minWidth: KkjTokens.spacingHitMinAndroid,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          e.key == value
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: e.key == value
                              ? KkjLight.colorAccent
                              : KkjLight.componentsInputBorder,
                        ),
                        const SizedBox(width: KkjTokens.spacing2),
                        Text(e.value, style: theme.textTheme.bodyMedium),
                        const SizedBox(width: KkjTokens.spacing2),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
