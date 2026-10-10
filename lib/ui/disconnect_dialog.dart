import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';

const _hit = Size(0, KkjTokens.spacingHitMinAndroid);

enum _Step { confirm, busy, revokeFailed, deleteFailed }

/// Confirms, then revokes access and erases the note copies. Pops `true` when
/// the user is disconnected. Back and [Cancel] are the same; both are locked
/// only while the call runs (it ends within the auth timeout).
class DisconnectDialog extends ConsumerStatefulWidget {
  const DisconnectDialog({super.key});

  @override
  ConsumerState<DisconnectDialog> createState() => _DisconnectDialogState();
}

class _DisconnectDialogState extends ConsumerState<DisconnectDialog> {
  _Step _step = _Step.confirm;

  Future<void> _run() async {
    if (_step == _Step.busy) return; // a double tap must not start a second run
    setState(() => _step = _Step.busy);
    final result = await ref.read(authProvider.notifier).disconnect();
    if (!mounted) return;
    if (result == DisconnectResult.done) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(
      () => _step = result == DisconnectResult.revokeFailed
          ? _Step.revokeFailed
          : _Step.deleteFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final busy = _step == _Step.busy;
    final errorStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.error,
    );

    final Widget content = switch (_step) {
      _Step.confirm => Text(l10n.disconnectBody),
      _Step.busy => Center(
        heightFactor: 2,
        child: CircularProgressIndicator(semanticsLabel: l10n.disconnecting),
      ),
      _Step.revokeFailed => Semantics(
        liveRegion: true,
        container: true,
        child: Text(l10n.networkError, style: errorStyle),
      ),
      _Step.deleteFailed => Semantics(
        liveRegion: true,
        container: true,
        child: Text(l10n.disconnectDeleteFailed, style: errorStyle),
      ),
    };

    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(l10n.disconnectTitle),
        content: content,
        actions: busy
            ? null
            : [
                TextButton(
                  autofocus: true, // default focus is the safe choice
                  style: TextButton.styleFrom(minimumSize: _hit),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: _hit,
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: _run,
                  child: Text(
                    _step == _Step.confirm ? l10n.disconnect : l10n.retry,
                  ),
                ),
              ],
      ),
    );
  }
}
