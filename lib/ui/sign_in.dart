import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';

const _hit = Size(0, KkjTokens.spacingHitMinAndroid);

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final notifier = ref.read(authProvider.notifier);
    final working = auth.phase == AuthPhase.working;
    final uri = privacyUri(ref.watch(privacyUrlProvider));

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

    // Problem text and its action; the live region announces it politely.
    final errorStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.error,
    );
    final Widget? problem = switch (auth.problem) {
      AuthProblem.none => null,
      AuthProblem.denied => Column(
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              children: [
                Text(
                  l10n.driveDeniedTitle,
                  textAlign: TextAlign.center,
                  style: errorStyle,
                ),
                const SizedBox(height: KkjTokens.spacing2),
                Text(
                  l10n.driveDeniedBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: KkjTokens.spacing2),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: _hit),
            onPressed: working ? null : notifier.requestAccess,
            child: Text(l10n.requestAgain),
          ),
        ],
      ),
      AuthProblem.network => Column(
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: Text(
              l10n.networkError,
              textAlign: TextAlign.center,
              style: errorStyle,
            ),
          ),
          const SizedBox(height: KkjTokens.spacing2),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: _hit),
            onPressed: working ? null : notifier.signIn,
            child: Text(l10n.retry),
          ),
        ],
      ),
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KkjTokens.spacing4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: KkjTokens.spacing7 * 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.productName,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: KkjTokens.spacing4),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: _hit),
                    onPressed: working ? null : notifier.signIn,
                    child: working
                        ? SizedBox.square(
                            dimension: KkjTokens.spacing4,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: l10n.signingIn,
                            ),
                          )
                        : Text(l10n.signInWithGoogle),
                  ),
                  const SizedBox(height: KkjTokens.spacing3),
                  Text(
                    l10n.driveNotice,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (problem != null) ...[
                    const SizedBox(height: KkjTokens.spacing4),
                    problem,
                  ],
                  const SizedBox(height: KkjTokens.spacing4),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: _hit),
                    onPressed: uri == null ? null : openPrivacy,
                    child: Text(l10n.privacyPolicy),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
