import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../export/export_rules.dart';
import '../export/pdf_export.dart';
import '../export/pdf_writer.dart' show ExportCancelled;
import '../l10n/app_localizations.dart';
import '../model/note.dart';
import 'providers.dart';

/// Story 8.2: pick the pages, make the PDF (progress, cancel), then hand it
/// to the share sheet. Reads [note]; nothing of the note is changed.
Future<void> showExportScreen(
  BuildContext context, {
  required Note note,
  required int currentIndex,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ExportScreen(note: note, currentIndex: currentIndex),
);

enum _Phase { choose, running, failed }

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({
    super.key,
    required this.note,
    required this.currentIndex,
  });

  final Note note;

  /// 0-based index of the page on screen.
  final int currentIndex;

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  var _mode = 'all';
  final _text = TextEditingController();
  var _phase = _Phase.choose;
  var _done = 0, _total = 0;
  var _cancel = false;
  ExportFailure? _failure;

  @override
  void dispose() {
    _cancel = true; // the screen is gone: stop making the PDF
    _text.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _range => {
    'mode': _mode,
    'text': _text.text,
    'current': widget.currentIndex + 1,
  };

  String? _error(AppLocalizations l10n) {
    if (_mode != 'custom') return null;
    final r = exportRange({..._range, 'pageCount': widget.note.pages.length});
    return switch (r['error']) {
      null => null,
      'emptyRange' => l10n.exportErrEmpty,
      'invalidFormat' => l10n.exportErrFormat,
      'reversedRange' => l10n.exportErrReversed,
      _ => l10n.exportErrOutOfRange(widget.note.pages.length),
    };
  }

  Future<void> _run() async {
    // Everything needed is read before the first await.
    final store = ref.read(assetStoreProvider);
    final dirOf = ref.read(exportDirProvider);
    final share = ref.read(pdfSharerProvider);
    setState(() {
      _phase = _Phase.running;
      _cancel = false;
      _done = 0;
      _failure = null;
    });
    File? file;
    try {
      file = await exportNotePdf(
        note: widget.note,
        range: _range,
        store: store,
        dir: await dirOf(),
        onProgress: (d, t) {
          if (mounted) {
            setState(() {
              _done = d;
              _total = t;
            });
          }
        },
        cancelled: () => _cancel,
      );
      if (_cancel) return;
      await share(file);
      if (mounted) Navigator.of(context).pop();
    } on ExportCancelled {
      if (mounted) setState(() => _phase = _Phase.choose);
    } on ExportFailure catch (e) {
      if (mounted) {
        setState(() {
          _failure = e;
          _phase = _Phase.failed;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failure = ExportFailure('failed');
          _phase = _Phase.failed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: _phase != _Phase.running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _cancel = true); // back = cancel
      },
      child: AlertDialog(
        title: Text(l10n.exportTitle),
        content: SingleChildScrollView(
          child: switch (_phase) {
            _Phase.choose => _choose(l10n),
            _Phase.running => _running(l10n),
            _Phase.failed => _failed(l10n),
          },
        ),
      ),
    );
  }

  Widget _choose(AppLocalizations l10n) {
    final error = _error(l10n);
    Widget option(String mode, String label) =>
        RadioListTile<String>(value: mode, title: Text(label));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RadioGroup<String>(
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v!),
          child: Column(
            children: [
              option('all', l10n.exportRangeAll),
              option('current', l10n.exportRangeCurrent),
              option('custom', l10n.exportRangeCustom),
            ],
          ),
        ),
        if (_mode == 'custom')
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KkjTokens.spacing4,
              vertical: KkjTokens.spacing2,
            ),
            child: TextField(
              controller: _text,
              autofocus: true,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: l10n.exportRangeLabel,
                errorText: error,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        const SizedBox(height: KkjTokens.spacing4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            const SizedBox(width: KkjTokens.spacing2),
            FilledButton(
              onPressed: error == null ? _run : null,
              child: Text(l10n.exportStart),
            ),
          ],
        ),
      ],
    );
  }

  Widget _running(AppLocalizations l10n) {
    final label = l10n.exportProgress(_done, _total);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A live region: TalkBack reads the change politely.
        Semantics(
          liveRegion: true,
          container: true,
          label: label,
          excludeSemantics: true,
          child: Column(
            children: [
              Text(label),
              const SizedBox(height: KkjTokens.spacing3),
              LinearProgressIndicator(
                value: _total == 0 ? null : _done / _total,
              ),
            ],
          ),
        ),
        const SizedBox(height: KkjTokens.spacing5),
        TextButton(
          onPressed: () => setState(() => _cancel = true),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  Widget _failed(AppLocalizations l10n) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        liveRegion: true,
        child: Text(l10n.exportFailed, textAlign: TextAlign.center),
      ),
      if (_failure?.code == 'assetMissing') ...[
        const SizedBox(height: KkjTokens.spacing2),
        Text(l10n.exportAssetMissing, textAlign: TextAlign.center),
      ],
      const SizedBox(height: KkjTokens.spacing5),
      FilledButton(onPressed: _run, child: Text(l10n.retry)),
    ],
  );
}
