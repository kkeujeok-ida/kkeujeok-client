import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../storage/language_store.dart';
import 'providers.dart';

/// A row with a 48dp minimum touch target.
class _Row extends StatelessWidget {
  const _Row({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: KkjTokens.spacingHitMinAndroid,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkjTokens.spacing4,
          vertical: KkjTokens.spacing2,
        ),
        child: Align(alignment: AlignmentDirectional.centerStart, child: child),
      ),
    ),
  );
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // Logout and disconnect join here in Story 1.13; hidden until then.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final choice = ref.watch(languageProvider);
    final privacyUrl = ref.watch(privacyUrlProvider);
    final options = {
      LanguageChoice.system: l10n.languageSystem,
      LanguageChoice.ko: l10n.languageKo,
      LanguageChoice.en: l10n.languageEn,
    };

    final uri = privacyUri(privacyUrl);
    final hasPrivacy = uri != null;

    Future<void> openPrivacy() async {
      final messenger = ScaffoldMessenger.of(context);
      var ok = false;
      try {
        ok = await ref.read(urlOpenerProvider)(uri!);
      } catch (_) {}
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.privacyOpenFailed)));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings, style: theme.textTheme.titleLarge),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KkjTokens.spacing4,
              KkjTokens.spacing3,
              KkjTokens.spacing4,
              KkjTokens.spacing1,
            ),
            child: Semantics(
              header: true,
              child: Text(l10n.language, style: theme.textTheme.labelMedium),
            ),
          ),
          for (final e in options.entries)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: choice == e.key,
              label: e.value,
              excludeSemantics: true,
              onTap: () => ref.read(languageProvider.notifier).select(e.key),
              child: _Row(
                onTap: () => ref.read(languageProvider.notifier).select(e.key),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.value, style: theme.textTheme.bodyMedium),
                    ),
                    if (choice == e.key)
                      Icon(Icons.check, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
          Divider(color: theme.colorScheme.outlineVariant),
          Semantics(
            button: true,
            enabled: hasPrivacy,
            label: l10n.privacyPolicy,
            hint: hasPrivacy ? null : l10n.privacyUnavailable,
            excludeSemantics: true,
            onTap: hasPrivacy ? openPrivacy : null,
            child: _Row(
              onTap: hasPrivacy ? openPrivacy : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.privacyPolicy,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: hasPrivacy ? null : theme.disabledColor,
                    ),
                  ),
                  if (!hasPrivacy)
                    Text(
                      l10n.privacyUnavailable,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
