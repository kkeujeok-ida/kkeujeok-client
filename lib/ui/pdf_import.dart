import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/note.dart';
import '../storage/note_store.dart' show NoteSaveException;
import '../storage/pdf_intake.dart';
import 'providers.dart';

/// The system file picker for one PDF: (path, file name), or null when the
/// user chose nothing.
Future<({String path, String name})?> pickPdf() async {
  final f = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  return f?.path == null ? null : (path: f!.path!, name: f.name);
}

/// Story 9.2: the small progress dialog of an import. Pops with the new [Note],
/// an error text (to show in a snackbar), or null when cancelled.
Future<Object?> showPdfImport(
  BuildContext context, {
  required String path,
  required String name,
}) => showDialog<Object>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PdfImportDialog(path: path, name: name),
);

/// The user text for a refusal code of `pdf.import`.
String pdfErrorText(AppLocalizations l, String code) => switch (code) {
  'tooLarge' => l.pdfErrTooLarge,
  'tooManyPages' => l.pdfErrTooManyPages,
  'encrypted' => l.pdfErrEncrypted,
  _ => l.pdfErrUnreadable, // corrupt, notPdf, failed
};

class _PdfImportDialog extends ConsumerStatefulWidget {
  const _PdfImportDialog({required this.path, required this.name});

  final String path, name;

  @override
  ConsumerState<_PdfImportDialog> createState() => _PdfImportDialogState();
}

class _PdfImportDialogState extends ConsumerState<_PdfImportDialog> {
  final _cancel = PdfCancel();
  var _done = 0, _total = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancel.cancel(); // the dialog is gone: stop
    super.dispose();
  }

  Future<void> _run() async {
    final notifier = ref.read(libraryProvider.notifier);
    final l = AppLocalizations.of(context);
    Object? result;
    try {
      result = await notifier.createFromPdf(
        path: widget.path,
        fileName: widget.name,
        cancel: _cancel,
        onProgress: (d, t) {
          if (mounted) {
            setState(() {
              _done = d;
              _total = t;
            });
          }
        },
      );
    } on PdfImportCancelled {
      result = null;
    } on PdfImportException catch (e) {
      result = pdfErrorText(l, e.code);
    } on NoteSaveException {
      result = l.pdfImportSaveFailed;
    } catch (_) {
      result = l.pdfErrUnreadable;
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = l.pdfImportProgress(_done, _total);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel.cancel(); // back = cancel
      },
      child: AlertDialog(
        title: Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Semantics(
          // A live region: TalkBack reads the change politely.
          liveRegion: true,
          container: true,
          label: label,
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(height: KkjTokens.spacing3),
              LinearProgressIndicator(
                value: _total == 0 ? null : _done / _total,
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: _cancel.cancel, child: Text(l.cancel))],
      ),
    );
  }
}
