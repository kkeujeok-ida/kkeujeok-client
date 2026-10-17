import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'providers.dart';

/// [Export sync log] (Story 3.5), shared by the settings row and the sync
/// popover: writes the log to a file and opens the share sheet. A failure is
/// shown as a snack bar. Everything it needs is read before the first await,
/// so the caller may be gone afterwards.
Future<void> exportSyncLog(WidgetRef ref, BuildContext context) async {
  final log = ref.read(syncLogProvider);
  final version = ref.read(appVersionProvider);
  final exportDir = ref.read(exportDirProvider);
  final share = ref.read(logSharerProvider);
  final messenger = ScaffoldMessenger.of(context);
  final failed = AppLocalizations.of(context).syncLogExportFailed;
  File? file;
  try {
    file = await log.exportJsonl(
      appVersion: await version(),
      now: DateTime.now(),
      into: await exportDir(),
    );
    await share(file);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  } finally {
    try {
      await file?.delete(); // the log's own file stays; this is a copy
    } catch (_) {}
  }
}
