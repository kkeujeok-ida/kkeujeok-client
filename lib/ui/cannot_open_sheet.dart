import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'log_export.dart';
import 'providers.dart';

/// The sheet of a "열 수 없음" card (Story 3.17, UX-DR69): the remote file
/// cannot be read and was left alone. Nothing in it writes to Drive.
Future<void> showCannotOpenSheet(BuildContext context, String noteId) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: KkjLight.colorSurfaceRaised,
      barrierColor: KkjLight.colorScrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KkjTokens.roundedLg),
        ),
      ),
      builder: (_) => _CannotOpenSheet(noteId),
    );

/// `https://drive.google.com/file/d/<fileId>/view`.
Uri driveFileUri(String fileId) =>
    Uri.https('drive.google.com', '/file/d/$fileId/view');

class _CannotOpenSheet extends ConsumerStatefulWidget {
  const _CannotOpenSheet(this.noteId);

  final String noteId;

  @override
  ConsumerState<_CannotOpenSheet> createState() => _CannotOpenSheetState();
}

class _CannotOpenSheetState extends ConsumerState<_CannotOpenSheet> {
  String? _fileId;

  /// This device's copy has changes Drive does not have and can be read, so
  /// it can be saved as a file.
  bool _download = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(noteStoreProvider);
    final s = await store.readSync(widget.noteId);
    final readable = (await store.read(widget.noteId))?.note != null;
    if (!mounted) return;
    setState(() {
      _fileId = s.info.fileId;
      _download = readable && s.hasUnsent;
    });
  }

  Future<void> _viewInDrive() async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).syncOpenFailed;
    var ok = false;
    try {
      ok = await ref.read(urlOpenerProvider)(driveFileUri(_fileId!));
    } catch (_) {}
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  /// The device copy as `<noteId>.kkj` through the share sheet.
  Future<void> _saveCopy() async {
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).accountMismatchDownloadFailed;
    Directory? dir;
    try {
      final bytes = await ref
          .read(noteStoreProvider)
          .workingBytes(widget.noteId);
      if (bytes == null) throw StateError('no copy');
      dir = await (await ref.read(exportDirProvider)()).createTemp('kkj-copy-');
      final file = await File('${dir.path}/${widget.noteId}.kkj')
          .writeAsBytes(bytes);
      await ref.read(noteFilesSharerProvider)([file]);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      try {
        await dir?.delete(recursive: true);
      } catch (_) {}
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const item = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(0, KkjTokens.spacingHitMinAndroid),
      ),
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: l.cannotOpen,
      explicitChildNodes: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KkjTokens.spacing5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.cannotOpenBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: KkjTokens.spacing4),
            if (_fileId != null)
              FilledButton(
                style: item,
                onPressed: _viewInDrive,
                child: Text(l.cannotOpenViewInDrive),
              ),
            TextButton(
              style: item,
              onPressed: () => exportSyncLog(ref, context),
              child: Text(l.syncLogExport),
            ),
            if (_download)
              TextButton(
                style: item,
                onPressed: _saveCopy,
                child: Text(l.cannotOpenDownload),
              ),
          ],
        ),
      ),
    );
  }
}
