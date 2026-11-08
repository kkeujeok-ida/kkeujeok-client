import 'dart:convert';

import 'package:flutter/material.dart';

import 'kk.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../library/library_rules.dart';

const _coverDir = 'lib/design_tokens/covers/';

typedef CoverEntry = ({String id, String ko, String en, String file});

/// The valid covers of `design_tokens/covers/index.json`, in display order.
/// An unreadable index gives an empty list (no covers offered or drawn).
final coverIndexProvider = FutureProvider<List<CoverEntry>>((ref) async {
  try {
    final text = await rootBundle.loadString('${_coverDir}index.json');
    return libraryCoverEntries(jsonDecode(text));
  } catch (_) {
    return const [];
  }
});

String coverName(BuildContext context, CoverEntry e) =>
    Localizations.localeOf(context).languageCode == 'ko' ? e.ko : e.en;

/// The cover picture; colors are its own, whatever the theme.
class CoverArt extends StatelessWidget {
  const CoverArt(this.file, {super.key});
  final String file;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    '$_coverDir$file',
    fit: BoxFit.cover,
    excludeFromSemantics: true,
  );
}

/// "표지 없음" plus the index covers as one-choice tiles. [selected] is a
/// cover id, or null for none (an id this app does not know selects nothing).
class CoverChoice extends ConsumerWidget {
  const CoverChoice({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final covers = ref.watch(coverIndexProvider).value ?? const [];
    Widget tile(String? id, String name, Widget art) {
      final on = id == selected;
      return Semantics(
        inMutuallyExclusiveGroup: true,
        selected: on,
        enabled: enabled,
        label: on ? l.coverOptionSelected(name) : l.coverOptionUnselected(name),
        excludeSemantics: true,
        onTap: enabled ? () => onChanged(id) : null,
        child: InkWell(
          onTap: enabled ? () => onChanged(id) : null,
          borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
          child: Padding(
            padding: const EdgeInsets.all(KkjTokens.spacing1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 80,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: on ? Kk.colorAccent : Kk.componentsInputBorder,
                      width: on ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
                  ),
                  child: art,
                ),
                const SizedBox(height: KkjTokens.spacing1),
                Text(
                  name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: KkjTokens.spacing3,
      runSpacing: KkjTokens.spacing3,
      children: [
        tile(null, l.coverNone, const Center(child: Icon(Icons.block))),
        for (final c in covers)
          tile(c.id, coverName(context, c), CoverArt(c.file)),
      ],
    );
  }
}

/// Story 7.3 [표지 변경]: resolves to `(id: <cover id or null>)`, or null
/// when dismissed.
Future<({String? id})?> showCoverSheet(
  BuildContext context, {
  required String? selected,
}) => showModalBottomSheet<({String? id})>(
  context: context,
  showDragHandle: true,
  builder: (ctx) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(KkjTokens.spacing4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              AppLocalizations.of(ctx).noteCover,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: KkjTokens.spacing3),
          CoverChoice(
            selected: selected,
            onChanged: (id) => Navigator.of(ctx).pop((id: id)),
          ),
        ],
      ),
    ),
  ),
);
