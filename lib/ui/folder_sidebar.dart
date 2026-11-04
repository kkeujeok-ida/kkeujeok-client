import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../library/folder_service.dart';
import '../library/library_rules.dart';
import 'folder_actions.dart';
import 'providers.dart';

enum _Action { rename, move, delete }

/// "모든 노트" and the folder tree of the sidebar (Story 7.5).
class FolderSidebarSection extends ConsumerStatefulWidget {
  const FolderSidebarSection({super.key, this.onSelected});

  /// Called after a folder (or "모든 노트") was chosen: a drawer closes.
  final VoidCallback? onSelected;

  @override
  ConsumerState<FolderSidebarSection> createState() => _SectionState();
}

class _SectionState extends ConsumerState<FolderSidebarSection> {
  final _expanded = <String>{};

  void _select(String? id) {
    ref.read(currentFolderProvider.notifier).select(id);
    widget.onSelected?.call();
  }

  void _act(_Action a, LibraryFolder f) {
    switch (a) {
      case _Action.rename:
        renameFolderDialog(context, ref, f);
      case _Action.move:
        moveFolderDialog(context, ref, f);
      case _Action.delete:
        deleteFolderDialog(context, ref, f);
    }
  }

  List<Widget> _rows(FolderView view, String parent, int depth, String? cur) {
    final out = <Widget>[];
    for (final f in view.childrenOf(parent)) {
      final kids = view.childrenOf(f.id).isNotEmpty;
      final open = kids && _expanded.contains(f.id);
      out.add(
        _FolderRow(
          key: ValueKey('folder-${f.id}'),
          folder: f,
          depth: depth,
          hasChildren: kids,
          expanded: open,
          selected: cur == f.id,
          // A tap opens the folder and unfolds it.
          onTap: () {
            if (kids) setState(() => _expanded.add(f.id));
            _select(f.id);
          },
          onToggle: () => setState(
            () => open ? _expanded.remove(f.id) : _expanded.add(f.id),
          ),
          onAction: (a) => _act(a, f),
        ),
      );
      if (open) out.addAll(_rows(view, f.id, depth + 1, cur));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final view = ref.watch(folderTreeProvider).value ?? const FolderView();
    final cur = ref.watch(effectiveFolderProvider);
    return ListView(
      children: [
        _RowFrame(
          depth: 0,
          selected: cur == null,
          label: l10n.allNotes,
          onTap: () => _select(null),
          child: Row(
            children: [
              const SizedBox(width: KkjTokens.spacingHitMinAndroid),
              Icon(
                Icons.notes_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: KkjTokens.spacing3),
              Expanded(
                child: Text(l10n.allNotes, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
        _RowFrame(
          depth: 0,
          selected: cur == 'root',
          label: l10n.folderTopLevel,
          onTap: () => _select('root'),
          child: Row(
            children: [
              const SizedBox(width: KkjTokens.spacingHitMinAndroid),
              Icon(
                Icons.home_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: KkjTokens.spacing3),
              Expanded(
                child: Text(
                  l10n.folderTopLevel,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        ..._rows(view, 'root', 0, cur),
      ],
    );
  }
}

/// A tappable row at least one touch target high.
class _RowFrame extends StatelessWidget {
  const _RowFrame({
    required this.depth,
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
    this.onLongPress,
  });

  final int depth;
  final bool selected;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: KkjTokens.spacingHitMinAndroid,
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: KkjTokens.spacing2 + depth * KkjTokens.spacing4,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderRow extends StatefulWidget {
  const _FolderRow({
    super.key,
    required this.folder,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
    required this.selected,
    required this.onTap,
    required this.onToggle,
    required this.onAction,
  });

  final LibraryFolder folder;
  final int depth;
  final bool hasChildren;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final void Function(_Action) onAction;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  /// Long press (TalkBack: the "long press" action) opens the menu.
  Future<void> _menu() async {
    final l10n = AppLocalizations.of(context);
    final box = context.findRenderObject() as RenderBox;
    final o = box.localToGlobal(Offset.zero);
    final a = await showMenu<_Action>(
      context: context,
      position: RelativeRect.fromLTRB(
        o.dx + KkjTokens.spacing5,
        o.dy + box.size.height / 2,
        o.dx + box.size.width,
        o.dy + box.size.height,
      ),
      items: [
        PopupMenuItem(value: _Action.rename, child: Text(l10n.folderRename)),
        PopupMenuItem(value: _Action.move, child: Text(l10n.folderMove)),
        PopupMenuItem(value: _Action.delete, child: Text(l10n.folderDelete)),
      ],
    );
    if (a != null) widget.onAction(a);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.folder;
    return _RowFrame(
      depth: widget.depth,
      selected: widget.selected,
      label: f.name,
      onTap: widget.onTap,
      onLongPress: _menu,
      child: Row(
        children: [
          SizedBox(
            width: KkjTokens.spacingHitMinAndroid,
            child: widget.hasChildren
                ? IconButton(
                    tooltip: f.name,
                    constraints: const BoxConstraints(
                      minWidth: KkjTokens.spacingHitMinAndroid,
                      minHeight: KkjTokens.spacingHitMinAndroid,
                    ),
                    icon: Icon(
                      widget.expanded ? Icons.expand_more : Icons.chevron_right,
                    ),
                    onPressed: widget.onToggle,
                  )
                : null,
          ),
          Icon(
            Icons.folder_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: KkjTokens.spacing3),
          Expanded(
            child: Text(
              f.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The centered question shared by note and folder deletes: true = confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String body,
  required String confirm,
}) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(body),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// A name field whose confirm button stays off until `library.folderName`
/// accepts the text.
/// A name asked in a dialog: trimmed, never empty, 100 characters at most.
class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.title,
    required this.confirm,
    required this.initial,
    this.label,
    this.tooLong,
  });

  final String title;
  final String confirm;
  final String initial;

  /// Field label and the too-long message; the folder ones when null.
  final String? label;
  final String? tooLong;

  @override
  State<NameDialog> createState() => NameDialogState();
}

class NameDialogState extends State<NameDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Map<String, Object?> get _check => libraryFolderName({'name': _text.text});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final check = _check;
    final ok = check['ok'] == true;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (ok) Navigator.of(context).pop(check['name']);
        },
        decoration: InputDecoration(
          labelText: widget.label ?? l10n.folderNameLabel,
          errorText: check['reason'] == 'nameTooLong'
              ? widget.tooLong ?? l10n.folderNameTooLong
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: ok ? () => Navigator.of(context).pop(check['name']) : null,
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
