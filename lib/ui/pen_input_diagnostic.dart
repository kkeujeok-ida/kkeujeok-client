import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'snack.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';

const penDiagMaxEvents = 20;

/// Names the set bits of a pointer `buttons` value (read-only diagnostic).
/// Bit 2 is the stylus barrel button on most pens, bit 4 the second one.
String describeButtons(int b) {
  if (b == 0) return 'none';
  const names = {1: 'primary', 2: 'secondary', 4: 'tertiary', 32: 'eraser'};
  final out = <String>[];
  for (var bit = 1; bit <= b && bit > 0; bit <<= 1) {
    if (b & bit != 0) out.add(names[bit] ?? 'bit$bit');
  }
  return out.join('+');
}

/// Shows what the pen sends. Nothing is stored or sent anywhere.
class PenInputDiagnosticScreen extends StatefulWidget {
  const PenInputDiagnosticScreen({super.key});

  @override
  State<PenInputDiagnosticScreen> createState() => _State();
}

class _State extends State<PenInputDiagnosticScreen> {
  final _events = <String>[]; // newest first

  void _add(String phase, PointerEvent e) {
    final line =
        '$phase kind=${e.kind.name} buttons=${e.buttons} '
        '(${describeButtons(e.buttons)}) pressure='
        '${e.pressure.toStringAsFixed(2)} device=${e.device}';
    setState(() {
      _events.insert(0, line);
      if (_events.length > penDiagMaxEvents) _events.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(l10n.penDiagTitle, style: theme.textTheme.titleLarge),
        ),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.penDiagCopy,
            icon: const Icon(Icons.copy),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _events.join('\n')));
              ScaffoldMessenger.of(context)
                  .showSnackBar(appSnackBar(content: Text(l10n.penDiagCopied)));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(KkjTokens.spacing4),
            child: Text(l10n.penDiagHint, style: theme.textTheme.bodyMedium),
          ),
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _add('down', e),
            onPointerMove: (e) => _add('move', e),
            onPointerUp: (e) => _add('up', e),
            onPointerCancel: (e) => _add('cancel', e),
            child: Container(
              height: 200,
              margin: const EdgeInsets.symmetric(
                horizontal: KkjTokens.spacing4,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
              ),
            ),
          ),
          Expanded(
            child: _events.isEmpty
                ? Center(child: Text(l10n.penDiagEmpty))
                : ListView(
                    padding: const EdgeInsets.all(KkjTokens.spacing4),
                    children: [
                      for (final s in _events)
                        Text(s, style: theme.textTheme.bodySmall),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
