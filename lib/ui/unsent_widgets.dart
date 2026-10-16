import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';

const _hit = Size(0, KkjTokens.spacingHitMinAndroid);

/// First character of the e-mail plus `@…` (`a@…`); `…` when it is empty.
String maskEmail(String email) {
  final t = email.trim();
  return t.isEmpty ? '…' : '${String.fromCharCode(t.runes.first)}@…';
}

/// A destructive button that needs two presses: the first changes its label
/// in place (announced politely), the second runs [onConfirm]. It is never
/// the autofocus button.
class TwoStepButton extends StatefulWidget {
  const TwoStepButton({
    super.key,
    required this.label,
    required this.onConfirm,
  });

  final String label;
  final VoidCallback onConfirm;

  @override
  State<TwoStepButton> createState() => _TwoStepButtonState();
}

class _TwoStepButtonState extends State<TwoStepButton> {
  bool _armed = false;

  void _press() {
    if (!_armed) {
      setState(() => _armed = true);
      return;
    }
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: _hit,
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
        onPressed: _press,
        child: Text(
          _armed ? AppLocalizations.of(context).discardAgain : widget.label,
        ),
      ),
    );
  }
}

enum _Step { confirm, busy, failed }

/// Log out with changes Drive does not have: [count] notes, or null when it
/// could not be checked. Pops `true` once signed out and the local data is
/// erased. Back and [Cancel] are the same, locked only while the work runs.
class UnsentLogoutDialog extends ConsumerStatefulWidget {
  const UnsentLogoutDialog({super.key, required this.count});

  final int? count;

  @override
  ConsumerState<UnsentLogoutDialog> createState() => _UnsentLogoutDialogState();
}

class _UnsentLogoutDialogState extends ConsumerState<UnsentLogoutDialog> {
  _Step _step = _Step.confirm;

  Future<void> _run() async {
    if (_step == _Step.busy) return; // single-flight
    setState(() => _step = _Step.busy);
    // Signed out first, so no receive can fill the folder again after the
    // erase. A failed erase afterwards keeps the notes: nothing is lost.
    await ref.read(authProvider.notifier).signOut();
    final ok = mounted && await ref.read(discardLocalDataProvider)();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _step = _Step.failed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final busy = _step == _Step.busy;
    final n = widget.count;
    final Widget content = switch (_step) {
      _Step.confirm => Text(
        n == null ? l10n.unsentLogoutBodyUnknown : l10n.unsentLogoutBody(n),
      ),
      _Step.busy => Center(
        heightFactor: 2,
        child: CircularProgressIndicator(semanticsLabel: l10n.logOut),
      ),
      _Step.failed => Semantics(
        liveRegion: true,
        container: true,
        child: Text(
          l10n.disconnectDeleteFailed,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    };
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(l10n.unsentLogoutTitle),
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
                if (_step == _Step.confirm)
                  TwoStepButton(
                    label: l10n.unsentLogoutConfirm,
                    onConfirm: _run,
                  )
                else
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: _hit,
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: _run,
                    child: Text(l10n.retry),
                  ),
              ],
      ),
    );
  }
}
