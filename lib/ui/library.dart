import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/note.dart';
import 'library_fab.dart';
import 'new_note_sheet.dart';
import 'note_editor_stub.dart';
import 'providers.dart';

const double _phoneMaxWidth = 600; // dp: below this the grid has 2 columns

/// The cover grid, its empty state and the round `+`.
class LibraryScreen extends ConsumerStatefulWidget {
  /// [headerStartInset] keeps the header clear of a button the shell floats
  /// at the top-left.
  const LibraryScreen({super.key, this.headerStartInset = 0});

  final double headerStartInset;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  // One sheet or editor route at a time: a second tap while one is opening
  // or open would stack another (and could create a duplicate note).
  bool _busy = false;

  Future<void> _guarded(Future<void> Function() body) async {
    if (_busy) return;
    _busy = true;
    try {
      await body();
    } finally {
      _busy = false;
    }
  }

  Future<void> _push(Note note) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => NoteEditorStub(note: note)));

  Future<void> _newNote() => _guarded(() async {
    // A created note is already in the list; no reload needed.
    final note = await showNewNoteSheet(context);
    if (note != null && mounted) await _afterEditor(_push(note));
  });

  Future<void> _open(Note note) => _guarded(() => _afterEditor(_push(note)));

  /// The list is read again when the person comes back from the editor.
  Future<void> _afterEditor(Future<void> route) async {
    await route;
    if (mounted) ref.read(libraryProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(libraryProvider);
    final failed = async.hasError && !async.hasValue;
    final entries = async.value ?? const <LibraryEntry>[];
    final cards = <Widget>[
      if (failed)
        _ErrorCard(onRetry: () => ref.read(libraryProvider.notifier).reload())
      else if (async.hasValue && entries.isEmpty)
        _NewNoteCard(onTap: _newNote),
      for (final e in entries)
        e.readable
            ? _NoteCard(entry: e, onTap: () => _open(e.note!))
            : const _UnreadableCard(),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: KkjTokens.spacing5 + widget.headerStartInset,
                  end: KkjTokens.spacing5,
                  top: KkjTokens.spacing4,
                  bottom: KkjTokens.spacing3,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.library,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Expanded(child: _Grid(children: cards)),
            ],
          ),
        ),
        Positioned.fill(child: LibraryFab(onNewNote: _newNote)),
      ],
    );
  }
}

/// Rows of equal-width cards. Rows size to their content, so large text
/// never clips a card.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const gap = KkjTokens.spacing5;
    return LayoutBuilder(
      builder: (context, c) {
        final inner = c.maxWidth - 2 * gap;
        final cols = c.maxWidth < _phoneMaxWidth
            ? 2
            : math.max(
                2,
                ((inner + gap) / (KkjTokens.spacingCoverColumnMin + gap))
                    .floor(),
              );
        final rows = (children.length + cols - 1) ~/ cols;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            gap,
            0,
            gap,
            KkjLight.componentsFabSize + 2 * KkjLight.componentsFabInset,
          ),
          itemCount: rows,
          itemBuilder: (context, r) => Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Expanded(
                    child: r * cols + i < children.length
                        ? children[r * cols + i]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

BoxDecoration _coverBox({Color? border}) => BoxDecoration(
  color: KkjLight.componentsCoverCardFallbackBackground,
  borderRadius: BorderRadius.circular(KkjLight.componentsCoverCardRounded),
  border: Border.all(
    color: border ?? KkjLight.componentsCoverCardFallbackBorder,
  ),
  boxShadow: border == null
      ? kkjShadow(KkjLight.componentsCoverCardShadow)
      : null,
);

/// The 3:4 thumbnail place. No stroke rendering yet (Story 2.5 fills it), so
/// it is the blank first page, kept in its own proportions inside the card.
class _Thumb extends StatelessWidget {
  const _Thumb({this.page, this.disabled = false, this.child});

  final Map<String, dynamic>? page;
  final bool disabled;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final w = (page?['width'] as num?)?.toDouble();
    final h = (page?['height'] as num?)?.toDouble();
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: DecoratedBox(
        decoration: _coverBox(
          border: disabled ? KkjLight.colorInkDisabled : null,
        ),
        child:
            child ??
            (w == null || h == null
                ? null
                : Padding(
                    padding: const EdgeInsets.all(KkjTokens.spacing2),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: w / h,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                KkjLight.componentsCoverCardFallbackBackground,
                            border: Border.all(
                              color: KkjLight.componentsCoverCardFallbackBorder,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.entry, required this.onTap});

  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = entry.note!;
    final at = entry.editedAt;
    final date = at == null
        ? null
        : DateFormat.yMd(Localizations.localeOf(context).toString())
              .format(at.toLocal());
    return Semantics(
      button: true,
      label: note.title,
      value: date, // no date text and no semantics date when unknown
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          KkjLight.componentsCoverCardRounded,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Thumb(page: note.pages.isEmpty ? null : note.pages.first),
            const SizedBox(height: KkjTokens.spacing2),
            Text(
              note.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
            if (date != null) Text(date, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// A note this client cannot read: shown dimmed, never opened or touched.
class _UnreadableCard extends StatelessWidget {
  const _UnreadableCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: KkjLight.colorInkDisabled);
    return Semantics(
      label: l10n.cannotOpen,
      enabled: false,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Thumb(disabled: true),
          const SizedBox(height: KkjTokens.spacing2),
          Text(l10n.cannotOpen, style: style),
        ],
      ),
    );
  }
}

/// The empty library's single card: opens the new-note sheet.
class _NewNoteCard extends StatelessWidget {
  const _NewNoteCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = Theme.of(context).textTheme.labelMedium;
    return Semantics(
      button: true,
      label: l10n.newNote,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          KkjLight.componentsCoverCardRounded,
        ),
        child: _Thumb(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, color: KkjLight.colorInkSecondary),
              const SizedBox(height: KkjTokens.spacing2),
              Text(l10n.newNote, style: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the empty-library card when the folder could not be
/// listed.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.loadFailed, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: KkjTokens.spacing3),
          FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}
