import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../library/folder_service.dart';

/// The folders of [view] depth first, each with its depth (0 = top level).
List<(LibraryFolder, int)> flattenFolders(FolderView view) {
  final out = <(LibraryFolder, int)>[];
  void walk(String parent, int depth) {
    for (final f in view.childrenOf(parent)) {
      out.add((f, depth));
      if (depth <= view.folders.length) walk(f.id, depth + 1);
    }
  }

  walk('root', 0);
  return out;
}

/// Asks for a folder: the top level or one of [view]. Returns its id (`root`
/// for the top level), or null when dismissed. Folders in [disabled] are
/// shown but cannot be chosen (a folder and its subfolders when moving it);
/// [selected] is marked as the current place. Story 7.7 reuses it for notes.
Future<String?> showFolderPicker(
  BuildContext context, {
  required String title,
  required FolderView view,
  Set<String> disabled = const {},
  String? selected,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KkjTokens.spacing4,
              vertical: KkjTokens.spacing2,
            ),
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _Tile(
                  label: AppLocalizations.of(ctx).folderTopLevel,
                  depth: 0,
                  enabled: true,
                  current: selected == 'root',
                  icon: Icons.home_outlined,
                  onTap: () => Navigator.of(ctx).pop('root'),
                ),
                for (final (f, depth) in flattenFolders(view))
                  _Tile(
                    label: f.name,
                    depth: depth + 1,
                    enabled: !disabled.contains(f.id),
                    current: selected == f.id,
                    icon: Icons.folder_outlined,
                    onTap: () => Navigator.of(ctx).pop(f.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.depth,
    required this.enabled,
    required this.current,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int depth;
  final bool enabled;
  final bool current;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: current,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: KkjTokens.spacingHitMinAndroid,
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: KkjTokens.spacing4 + depth * KkjTokens.spacing4,
              end: KkjTokens.spacing4,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.disabledColor,
                ),
                const SizedBox(width: KkjTokens.spacing3),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: enabled ? null : theme.disabledColor,
                      fontWeight: current ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (current) const Icon(Icons.check, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
