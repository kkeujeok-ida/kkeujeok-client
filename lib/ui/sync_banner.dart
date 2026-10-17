import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'sync_display.dart';

/// Whether the re-login banner is on screen: the sign-in needs the person
/// and no banner of a higher priority (a read-only conflict) holds the slot.
bool syncBannerShown(WidgetRef ref, {bool higherPriority = false}) =>
    !higherPriority && ref.watch(syncProblemsProvider.select((p) => p.reauth));

/// The one `banner` slot of the library and the editor, at the top and the
/// full width, pushing the content down: "로그인이 만료됐어요" with
/// [다시 로그인]. A higher priority banner ([higherPriority], read-only
/// conflict) takes the slot. It also gives the once-per-run notice that Drive
/// is full.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({
    super.key,
    this.higherPriority = false,
    this.startInset = 0,
  });

  final bool higherPriority;

  /// Room kept clear at the start for a button floating over the top left.
  final double startInset;

  Future<void> _signIn(WidgetRef ref) async {
    final coordinator = ref.read(uploadCoordinatorProvider);
    final granted = await ref.read(rootFolderProvider.notifier).signInAgain();
    if (granted) unawaited(coordinator.retryAll());
  }

  void _quotaNotice(BuildContext context, WidgetRef ref) {
    final flag = ref.read(quotaNoticeProvider);
    if (flag.shown) return;
    flag.shown = true;
    final text = AppLocalizations.of(context).syncQuotaBody;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: ExcludeSemantics(child: Text(text))));
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        text,
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(syncProblemsProvider.select((p) => p.quota), (_, on) {
      if (on) _quotaNotice(context, ref);
    });
    if (!syncBannerShown(ref, higherPriority: higherPriority)) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      sortKey: const OrdinalSortKey(0),
      child: ColoredBox(
        color: KkjLight.componentsBannerBackground,
        child: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top,
            left: MediaQuery.paddingOf(context).left + startInset,
            right: MediaQuery.paddingOf(context).right,
          ),
          child: Padding(
            padding: const EdgeInsets.all(KkjLight.componentsBannerPadding),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.syncReauthBanner,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: KkjLight.componentsBannerText),
                  ),
                ),
                TextButton(
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(
                      Size(
                        KkjTokens.spacingHitMinAndroid,
                        KkjTokens.spacingHitMinAndroid,
                      ),
                    ),
                  ),
                  onPressed: () => _signIn(ref),
                  child: Text(l.driveReauthAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
