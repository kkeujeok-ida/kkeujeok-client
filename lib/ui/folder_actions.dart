import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'snack.dart';

import '../l10n/app_localizations.dart';
import '../library/folder_service.dart';
import 'folder_picker_sheet.dart';
import 'folder_sidebar.dart' show NameDialog, showConfirmDialog;
import 'providers.dart';

/// The folder actions shared by the sidebar (long press) and the folder
/// cards of the library: each asks in a dialog or sheet, runs the change and
/// reports a failure in a snackbar.
void _failed(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(appSnackBar(content: Text(l10n.folderFailed)));
}

/// Asks for a name, creates the folder under [parent]; the new id's result.
Future<FolderResult?> createFolderDialog(
  BuildContext context,
  WidgetRef ref,
  String parent,
) async {
  final l10n = AppLocalizations.of(context);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => NameDialog(
      title: parent == 'root' ? l10n.folderAdd : l10n.folderNewSub,
      confirm: l10n.create,
      initial: '',
    ),
  );
  if (name == null || !context.mounted) return null;
  final r = await ref.read(folderTreeProvider.notifier).create(name, parent);
  if (context.mounted && !r.ok) _failed(context);
  return r;
}

Future<void> renameFolderDialog(
  BuildContext context,
  WidgetRef ref,
  LibraryFolder f,
) async {
  final l10n = AppLocalizations.of(context);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => NameDialog(
      title: l10n.folderRename,
      confirm: l10n.folderSave,
      initial: f.name,
    ),
  );
  if (name == null || !context.mounted) return;
  final r = await ref.read(folderTreeProvider.notifier).rename(f.id, name);
  if (context.mounted && !r.ok) _failed(context);
}

/// Moves [f] to [target]. False when refused.
Future<bool> moveFolderTo(
  BuildContext context,
  WidgetRef ref,
  LibraryFolder f,
  String target,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final tree = ref.read(folderTreeProvider.notifier);
  final r = await tree.move(f.id, target);
  if (!context.mounted) return r.ok;
  if (!r.ok) {
    _failed(context);
    return false;
  }
  if (r.inverse == null) return true; // already there
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(appSnackBar(content: Text(l10n.folderMoved(f.name))));
  return true;
}

Future<void> moveFolderDialog(
  BuildContext context,
  WidgetRef ref,
  LibraryFolder f,
) async {
  final l10n = AppLocalizations.of(context);
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
  if (target == null || !context.mounted) return;
  await moveFolderTo(context, ref, f, target);
}

/// The centered question of a note delete, then the delete.
Future<void> deleteFolderDialog(
  BuildContext context,
  WidgetRef ref,
  LibraryFolder f,
) async {
  final l10n = AppLocalizations.of(context);
  final view = ref.read(folderTreeProvider).value ?? const FolderView();
  final ok = await showConfirmDialog(
    context,
    body: l10n.folderDeleteBody(view.noteCount(f.id)),
    confirm: l10n.folderDeleteConfirm,
  );
  if (!ok || !context.mounted) return;
  final r = await ref.read(folderTreeProvider.notifier).delete(f.id);
  if (context.mounted && !r.ok) _failed(context);
}
