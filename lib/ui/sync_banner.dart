import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'sync_display.dart';

enum _Kind { deleted, newVersion, reauth }

/// The banner that holds the one slot (UX-DR40): a read-only conflict
/// ([higherPriority]) > the open note was deleted elsewhere > the open note
/// is of a newer format > the sign-in needs the person. [noteId] is the open
/// note of the editor; the library has none.
_Kind? _kind(WidgetRef ref, bool higherPriority, String? noteId) {
  if (higherPriority) return null;
  if (noteId != null) {
    final v = ref.watch(noteSyncProvider(noteId));
    if (v.deleted) return _Kind.deleted;
    if (v.newVersion) return _Kind.newVersion;
  }
  return ref.watch(syncProblemsProvider.select((p) => p.reauth))
      ? _Kind.reauth
      : null;
}

/// Whether a banner is on screen.
bool syncBannerShown(
  WidgetRef ref, {
  bool higherPriority = false,
  String? noteId,
}) => _kind(ref, higherPriority, noteId) != null;

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
    this.noteId,
    this.onCloseNote,
  });

  final bool higherPriority;

  /// The note the editor has open (deleted / newer-format banners).
  final String? noteId;

  /// [닫기] of the deleted banner: leaves the editor.
  final VoidCallback? onCloseNote;

  /// Room kept clear at the start for a button floating over the top left.
  final double startInset;

  Future<void> _signIn(WidgetRef ref) async {
    final coordinator = ref.read(uploadCoordinatorProvider);
    final granted = await ref.read(rootFolderProvider.notifier).signInAgain();
    if (granted) unawaited(coordinator.retryAll());
  }

  Future<void> _revive(WidgetRef ref, String id) async {
    await ref.read(noteReceiverProvider).revive(id);
    await ref.read(uploadCoordinatorProvider).syncNow(id);
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
    final kind = _kind(ref, higherPriority, noteId);
    if (kind == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    const small = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(KkjTokens.spacingHitMinAndroid, KkjTokens.spacingHitMinAndroid),
      ),
    );
    final text = switch (kind) {
      _Kind.deleted => l.deletedBanner,
      _Kind.newVersion => l.newVersionBanner,
      _Kind.reauth => l.syncReauthBanner,
    };
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
                    text,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: KkjLight.componentsBannerText),
                  ),
                ),
                if (kind == _Kind.reauth)
                  TextButton(
                    style: small,
                    onPressed: () => _signIn(ref),
                    child: Text(l.driveReauthAction),
                  ),
                if (kind == _Kind.deleted) ...[
                  TextButton(
                    style: small,
                    onPressed: () => _revive(ref, noteId!),
                    child: Text(l.deletedRevive),
                  ),
                  TextButton(
                    style: small,
                    onPressed: onCloseNote,
                    child: Text(l.close),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
