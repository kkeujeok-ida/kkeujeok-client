import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'shell.dart';
import 'unsent_widgets.dart';

const _hit = Size(0, KkjTokens.spacingHitMinAndroid);

enum _View { checking, ok, mismatch, clearFailed }

/// Between sign-in and the shell (Story 3.7): compares the signed-in account
/// with the one that owns the local notes. The shell, and so every upload and
/// receive, is built only once the accounts agree or the old data is gone.
///
/// Not a mismatch, so the shell opens and nothing is deleted: no account
/// known, no device record, an unreadable one, or one without a `sub`.
class AccountGate extends ConsumerStatefulWidget {
  const AccountGate({super.key});

  @override
  ConsumerState<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends ConsumerState<AccountGate> {
  late final String? _sub = ref.read(authGatewayProvider).account?.sub;
  late _View _view = _sub == null ? _View.ok : _View.checking;
  String _oldEmail = '';
  List<String>? _ids; // notes with unsent changes; null = could not check
  String? _message; // the error line of the mismatch dialog
  bool _busy = false; // single-flight over every action

  @override
  void initState() {
    super.initState();
    if (_view == _View.checking) unawaited(_check());
  }

  /// This run is still the one for the signed-in account.
  bool get _current =>
      mounted && ref.read(authGatewayProvider).account?.sub == _sub;

  Future<void> _check() async {
    final device = await ref.read(syncDeviceStoreProvider).read();
    if (!_current) return;
    final tag = device.sub;
    if (tag == null || tag == _sub) {
      setState(() => _view = _View.ok);
      return;
    }
    final ids = await ref.read(unsentIdsProvider)();
    if (!_current) return;
    _oldEmail = device.email ?? '';
    _ids = ids;
    if (ids != null && ids.isEmpty) {
      await _clear();
    } else {
      setState(() => _view = _View.mismatch);
    }
  }

  /// Erases the old account's data; true when the shell may open.
  Future<void> _clear() async {
    if (_busy) return;
    _busy = true;
    final failure = AppLocalizations.of(context).accountClearFailed;
    try {
      final ok = await ref.read(discardLocalDataProvider)();
      if (!_current) return;
      setState(() {
        _message = ok ? null : failure;
        _view = ok ? _View.ok : _View.clearFailed;
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> _goBack() async {
    if (_busy) return;
    _busy = true;
    try {
      // The device record and the notes stay; signing in as the old account
      // continues the upload.
      await ref.read(authProvider.notifier).signOut();
    } finally {
      _busy = false;
    }
  }

  Future<void> _discard() async {
    if (_busy) return;
    _busy = true;
    final failure = AppLocalizations.of(context).accountClearFailed;
    try {
      final ok = await ref.read(discardLocalDataProvider)();
      if (!_current) return;
      setState(() {
        _message = ok ? null : failure;
        if (ok) _view = _View.ok;
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    _busy = true;
    Directory? dir;
    final l10n = AppLocalizations.of(context);
    String? error;
    try {
      final ids = _ids ?? await ref.read(unsentIdsProvider)();
      if (!_current) return;
      if (ids == null) {
        error = l10n.accountMismatchDownloadFailed;
      } else {
        final store = ref.read(noteStoreProvider);
        final files = <File>[];
        for (final id in ids) {
          final bytes = await store.workingBytes(id);
          if (!_current) return;
          if (bytes == null) continue;
          dir ??= await (await ref.read(
            exportDirProvider,
          )()).createTemp('kkj-unsent-');
          files.add(await File('${dir.path}/$id.kkj').writeAsBytes(bytes));
        }
        if (!_current) return;
        if (files.isEmpty) {
          error = l10n.accountMismatchDownloadNone;
        } else {
          await ref.read(noteFilesSharerProvider)(files);
        }
      }
    } catch (_) {
      error = l10n.accountMismatchDownloadFailed;
    } finally {
      try {
        await dir?.delete(recursive: true);
      } catch (_) {}
      _busy = false;
    }
    if (mounted) setState(() => _message = error);
  }

  @override
  Widget build(BuildContext context) => switch (_view) {
    _View.ok => const Shell(),
    _View.checking => const Scaffold(),
    _View.mismatch || _View.clearFailed => _dialog(context),
  };

  Widget _dialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final failed = _view == _View.clearFailed;
    final email = maskEmail(_oldEmail);
    final n = _ids?.length;
    final message = _message;
    final body = failed
        ? null
        : n == null
        ? l10n.accountMismatchBodyUnknown(email)
        : l10n.accountMismatchBody(email, n);
    return PopScope(
      canPop: false, // nothing runs for the new account before a choice
      child: Scaffold(
        body: Center(
          child: AlertDialog(
            scrollable: true,
            title: Text(l10n.accountMismatchTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (body != null) Text(body),
                if (message != null)
                  Semantics(
                    liveRegion: true,
                    container: true,
                    child: Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              FilledButton(
                autofocus: true, // the safe choice
                style: FilledButton.styleFrom(minimumSize: _hit),
                onPressed: _goBack,
                child: Text(l10n.accountMismatchBack),
              ),
              if (failed)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: _hit),
                  onPressed: _clear,
                  child: Text(l10n.retry),
                )
              else ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: _hit),
                  onPressed: _download,
                  child: Text(l10n.accountMismatchDownload),
                ),
                TwoStepButton(
                  label: n == null
                      ? l10n.accountMismatchDiscardUnknown
                      : l10n.accountMismatchDiscard(n),
                  onConfirm: _discard,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
