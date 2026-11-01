import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../library/folder_service.dart';
import '../library/library_rules.dart';
import 'folder_picker_sheet.dart';
import 'providers.dart';

enum _Action { newSub, rename, move, delete }

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
  String? _confirming; // the folder whose delete asks in place

  FolderTreeNotifier get _tree => ref.read(folderTreeProvider.notifier);

  void _select(String? id) {
    ref.read(currentFolderProvider.notifier).select(id);
    widget.onSelected?.call();
  }

  void _failed() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.folderFailed)));
  }

  Future<String?> _askName(
    String title,
    String confirm, {
    String initial = '',
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        NameDialog(title: title, confirm: confirm, initial: initial),
  );

  Future<void> _create(String parent) async {
    final l10n = AppLocalizations.of(context);
    final name = await _askName(
      parent == 'root' ? l10n.folderAdd : l10n.folderNewSub,
      l10n.create,
    );
    if (name == null || !mounted) return;
    final r = await _tree.create(name, parent);
    if (!mounted) return;
    if (!r.ok) return _failed();
    if (parent != 'root') setState(() => _expanded.add(parent));
  }

  Future<void> _rename(LibraryFolder f) async {
    final l10n = AppLocalizations.of(context);
    final name = await _askName(
      l10n.folderRename,
      l10n.folderSave,
      initial: f.name,
    );
    if (name == null || !mounted) return;
    final r = await _tree.rename(f.id, name);
    if (mounted && !r.ok) _failed();
  }

  Future<void> _move(LibraryFolder f) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final view = ref.read(folderTreeProvider).value ?? const FolderView();
    final target = await showFolderPicker(
      context,
      title: l10n.folderMoveTitle(f.name),
      view: view,
      disabled: {
        for (final g in view.folders)
          if (view.isInside(g.id, f.id)) g.id,
      },
      selected: f.parentId,
    );
    if (target == null || !mounted) return;
    final r = await _tree.move(f.id, target);
    if (!mounted) return;
    if (!r.ok) return _failed();
    final inverse = r.inverse;
    if (inverse == null) return; // already there
    if (target != 'root') setState(() => _expanded.add(target));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.folderMoved(f.name)),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () =>
                ref.read(folderTreeProvider.notifier).undo(inverse),
          ),
        ),
      );
  }

  Future<void> _delete(String id) async {
    setState(() => _confirming = null);
    final r = await _tree.delete(id);
    if (mounted && !r.ok) _failed();
  }

  void _act(_Action a, LibraryFolder f) {
    switch (a) {
      case _Action.newSub:
        _create(f.id);
      case _Action.rename:
        _rename(f);
      case _Action.move:
        _move(f);
      case _Action.delete:
        setState(() => _confirming = f.id);
    }
  }

  List<Widget> _rows(FolderView view, String parent, int depth, String? cur) {
    final out = <Widget>[];
    for (final f in view.childrenOf(parent)) {
      final kids = view.childrenOf(f.id).isNotEmpty;
      final open = kids && _expanded.contains(f.id);
      out.add(
        _confirming == f.id
            ? _ConfirmRow(
                key: ValueKey('confirm-${f.id}'),
                depth: depth,
                count: view.noteCount(f.id),
                onCancel: () => setState(() => _confirming = null),
                onConfirm: () => _delete(f.id),
              )
            : _FolderRow(
                key: ValueKey('folder-${f.id}'),
                folder: f,
                depth: depth,
                hasChildren: kids,
                expanded: open,
                selected: cur == f.id,
                onTap: () => _select(f.id),
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
        ..._rows(view, 'root', 0, cur),
        _RowFrame(
          depth: 0,
          selected: false,
          label: l10n.folderAdd,
          onTap: () => _create('root'),
          child: Row(
            children: [
              const SizedBox(width: KkjTokens.spacingHitMinAndroid),
              Icon(Icons.add, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: KkjTokens.spacing3),
              Expanded(
                child: Text(l10n.folderAdd, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
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
  final _menu = GlobalKey<PopupMenuButtonState<_Action>>();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final f = widget.folder;
    return _RowFrame(
      depth: widget.depth,
      selected: widget.selected,
      label: f.name,
      onTap: widget.onTap,
      onLongPress: () => _menu.currentState?.showButtonMenu(),
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
          PopupMenuButton<_Action>(
            key: _menu,
            tooltip: l10n.folderMenu(f.name),
            constraints: const BoxConstraints(
              minWidth: KkjTokens.spacingHitMinAndroid,
              minHeight: KkjTokens.spacingHitMinAndroid,
            ),
            onSelected: widget.onAction,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _Action.newSub,
                child: Text(l10n.folderNewSub),
              ),
              PopupMenuItem(
                value: _Action.rename,
                child: Text(l10n.folderRename),
              ),
              PopupMenuItem(value: _Action.move, child: Text(l10n.folderMove)),
              PopupMenuItem(
                value: _Action.delete,
                child: Text(l10n.folderDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The delete question that replaces the row: how many notes go with it.
class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({
    super.key,
    required this.depth,
    required this.count,
    required this.onCancel,
    required this.onConfirm,
  });

  final int depth;
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: KkjTokens.spacing4 + depth * KkjTokens.spacing4,
        end: KkjTokens.spacing3,
        top: KkjTokens.spacing2,
        bottom: KkjTokens.spacing2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.folderDeleteBody(count), style: theme.textTheme.bodyMedium),
          const SizedBox(height: KkjTokens.spacing2),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                autofocus: true,
                onPressed: onCancel,
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: onConfirm,
                child: Text(l10n.folderDeleteConfirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
