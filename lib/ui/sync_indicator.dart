import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'log_export.dart';
import 'providers.dart';
import 'sync_display.dart';

/// Google's page for managing Drive storage.
final driveStorageUri = Uri.parse('https://drive.google.com/settings/storage');

IconData syncIcon(SyncLabel l) => switch (l) {
  SyncLabel.saved => Icons.check,
  SyncLabel.pending => Icons.schedule,
  SyncLabel.offline => Icons.cloud_off,
  SyncLabel.saving => Icons.sync,
  SyncLabel.receiving => Icons.arrow_downward,
  SyncLabel.twoVersions => Icons.warning_amber_rounded,
  SyncLabel.notSaved => Icons.error_outline,
};

Color syncIconColor(SyncLabel l) => switch (l) {
  SyncLabel.saved => KkjLight.componentsSyncIndicatorSynced,
  SyncLabel.pending => KkjLight.componentsSyncIndicatorPending,
  SyncLabel.offline => KkjLight.componentsSyncIndicatorOffline,
  SyncLabel.saving => KkjLight.componentsSyncIndicatorSyncing,
  SyncLabel.receiving => KkjLight.componentsSyncIndicatorIncoming,
  SyncLabel.twoVersions => KkjLight.componentsSyncIndicatorConflictIcon,
  SyncLabel.notSaved => KkjLight.componentsSyncIndicatorError,
};

/// The state text of the table (UX-DR38).
String syncText(AppLocalizations l, SyncLabel s) => switch (s) {
  SyncLabel.saved => l.syncStateSaved,
  SyncLabel.pending => l.syncStatePending,
  SyncLabel.offline => l.syncStateOffline,
  SyncLabel.saving => l.syncStateSaving,
  SyncLabel.receiving => l.syncStateReceiving,
  SyncLabel.twoVersions => l.syncStateTwoVersions,
  SyncLabel.notSaved => l.syncStateNotSaved,
};

String _description(AppLocalizations l, NoteSyncView v) => switch (v.label) {
  SyncLabel.saved => l.syncDescSaved,
  SyncLabel.pending => l.syncDescPending,
  SyncLabel.offline => l.syncDescOffline,
  SyncLabel.saving => l.syncDescSaving,
  SyncLabel.receiving => l.syncDescReceiving,
  SyncLabel.twoVersions => l.syncDescTwoVersions,
  SyncLabel.notSaved => v.quota ? l.syncQuotaBody : l.syncErrorBody,
};

/// Turns while `saving`, unless the system asks for no animation (UX-DR87).
class _Spin extends StatefulWidget {
  const _Spin({required this.child});

  final Widget child;

  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _c, child: widget.child);
}

/// The icon of a state; the rotating one for `saving`.
class SyncIcon extends StatelessWidget {
  const SyncIcon(this.label, {super.key, this.size});

  final SyncLabel label;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(syncIcon(label), color: syncIconColor(label), size: size);
    return label == SyncLabel.saving ? _Spin(child: icon) : icon;
  }
}

/// `sync-indicator`: an icon-only button in the editor corner. It opens a
/// popover with the state text and [지금 동기화]; in `error` it offers
/// [다시 시도] and the log export, and for a full Drive [Drive 공간 관리].
class SyncIndicator extends ConsumerStatefulWidget {
  const SyncIndicator({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends ConsumerState<SyncIndicator> {
  static const _announceEvery = Duration(seconds: 10);
  DateTime? _lastAnnounce;
  bool _busy = false;

  void _announce(String text, Assertiveness a) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        text,
        Directionality.of(context),
        assertiveness: a,
      ),
    );
  }

  /// `error` is told at once (assertive). The other changes are polite, at
  /// most once per 10 s; a stroke changes no label, so none is announced.
  void _onChange(NoteSyncView? prev, NoteSyncView next) {
    if (prev == null || !prev.loaded || prev.label == next.label) return;
    final l = AppLocalizations.of(context);
    if (next.isError) {
      _announce(syncText(l, next.label), Assertiveness.assertive);
      return;
    }
    final now = DateTime.now();
    final last = _lastAnnounce;
    if (last != null && now.difference(last) < _announceEvery) return;
    _lastAnnounce = now;
    _announce(syncText(l, next.label), Assertiveness.polite);
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    _busy = true;
    try {
      await body();
    } catch (_) {
      // The coordinator reports failures in sync.json and the log.
    } finally {
      _busy = false;
    }
  }

  Future<void> _manageDrive() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).syncOpenFailed;
    var ok = false;
    try {
      ok = await ref.read(urlOpenerProvider)(driveStorageUri);
    } catch (_) {}
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final id = widget.noteId;
    ref.listen(noteSyncProvider(id), _onChange);
    final v = ref.watch(noteSyncProvider(id));
    // Until the first read ends there is nothing true to say.
    if (!v.loaded) {
      return const SizedBox.square(dimension: KkjTokens.spacingHitMinAndroid);
    }
    const hit = BoxConstraints(
      minWidth: KkjTokens.spacingHitMinAndroid,
      minHeight: KkjTokens.spacingHitMinAndroid,
    );
    const item = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(KkjTokens.spacingHitMinAndroid, KkjTokens.spacingHitMinAndroid),
      ),
    );
    final coordinator = ref.read(uploadCoordinatorProvider);
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(
          KkjLight.componentsPopoverBackground,
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              KkjLight.componentsPopoverRounded,
            ),
          ),
        ),
      ),
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Padding(
              padding: const EdgeInsets.all(KkjLight.componentsPopoverPadding),
              child: Text(_description(l, v)),
            ),
          ),
        ),
        if (v.isError) ...[
          MenuItemButton(
            style: item,
            onPressed: () => _run(() => coordinator.retry(id)),
            child: Text(l.retry),
          ),
          if (v.quota)
            MenuItemButton(
              style: item,
              onPressed: _manageDrive,
              child: Text(l.syncManageDrive),
            ),
          MenuItemButton(
            style: item,
            onPressed: () => exportSyncLog(ref, context),
            child: Text(l.syncLogExport),
          ),
        ] else
          MenuItemButton(
            style: item,
            onPressed: () => _run(() => coordinator.syncNow(id)),
            child: Text(l.syncNow),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        return Semantics(
          button: true,
          label: l.syncIndicatorLabel(syncText(l, v.label)),
          excludeSemantics: true,
          onTap: toggle,
          child: IconButton(
            constraints: hit,
            icon: SyncIcon(v.label),
            onPressed: toggle,
          ),
        );
      },
    );
  }
}
