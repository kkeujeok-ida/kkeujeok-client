import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../storage/language_store.dart';
import 'disconnect_dialog.dart';
import 'providers.dart';
import 'unsent_widgets.dart';

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

/// [Export sync log]: writes the log to a file and opens the share sheet.
/// A tap while one export runs is ignored.
class _ExportLogRow extends ConsumerStatefulWidget {
  const _ExportLogRow();

  @override
  ConsumerState<_ExportLogRow> createState() => _ExportLogRowState();
}

class _ExportLogRowState extends ConsumerState<_ExportLogRow> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    // Everything the export needs is read before the first await.
    final log = ref.read(syncLogProvider);
    final version = ref.read(appVersionProvider);
    final exportDir = ref.read(exportDirProvider);
    final share = ref.read(logSharerProvider);
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).syncLogExportFailed;
    setState(() => _busy = true);
    File? file;
    try {
      file = await log.exportJsonl(
        appVersion: await version(),
        now: DateTime.now(),
        into: await exportDir(),
      );
      await share(file);
    } catch (_) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      try {
        await file?.delete(); // the log's own file stays; this is a copy
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = AppLocalizations.of(context).syncLogExport;
    final onTap = _busy ? null : _export;
    return Semantics(
      button: true,
      enabled: !_busy,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: _Row(
        onTap: onTap,
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _busy ? theme.disabledColor : null,
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _counting = false; // single-flight: one unsent count at a time

  /// The notes with unsent changes, or null (unknown). Null `busy` result
  /// means a count is already running or this screen was left meanwhile.
  Future<({List<String>? ids})?> _count() async {
    if (_counting) return null;
    _counting = true;
    try {
      final ids = await ref.read(unsentIdsProvider)();
      return (ids: ids);
    } finally {
      _counting = false;
    }
  }

  Future<void> _logOut() async {
    final nav = Navigator.of(context);
    final counted = await _count();
    if (counted == null || !mounted) return;
    final ids = counted.ids;
    if (ids != null && ids.isEmpty) {
      await ref.read(authProvider.notifier).signOut();
      nav.popUntil((r) => r.isFirst);
      return;
    }
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => UnsentLogoutDialog(count: ids?.length),
    );
    // A failed erase leaves the session ended: nothing to stay on.
    if (done == true || ref.read(authProvider).phase != AuthPhase.signedIn) {
      nav.popUntil((r) => r.isFirst);
    }
  }

  Future<void> _disconnect() async {
    final nav = Navigator.of(context);
    final counted = await _count();
    if (counted == null || !mounted) return;
    final ids = counted.ids;
    final warn = ids == null || ids.isNotEmpty;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => DisconnectDialog(warn: warn, unsent: ids?.length),
    );
    if (done == true) nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
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

    final signedIn = ref.watch(authProvider).phase == AuthPhase.signedIn;

    // The sign-in screen replaces the shell underneath; drop what is above it.
    Widget action(String label, VoidCallback onTap, {Color? color}) =>
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: _Row(
            onTap: onTap,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        );

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
          const _ExportLogRow(),
          if (signedIn) ...[
            Divider(color: theme.colorScheme.outlineVariant),
            action(l10n.logOut, _logOut),
            action(
              l10n.disconnect,
              _disconnect,
              color: theme.colorScheme.error,
            ),
          ],
        ],
      ),
    );
  }
}
