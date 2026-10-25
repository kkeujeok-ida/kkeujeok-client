import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../render/page_painter.dart' show parseColor;

String hexOf(Color c) {
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}';
}

/// Hue, saturation and brightness sliders; pops `#rrggbb` (lower case) on
/// [Apply] and null on [Cancel].
Future<String?> showPenColorPicker(BuildContext context, String initial) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PenColorPicker(initial),
    );

class _PenColorPicker extends StatefulWidget {
  const _PenColorPicker(this.initial);

  final String initial;

  @override
  State<_PenColorPicker> createState() => _PenColorPickerState();
}

class _PenColorPickerState extends State<_PenColorPicker> {
  late HSVColor _c = HSVColor.fromColor(parseColor(widget.initial));
  bool _touched = false; // untouched: Apply returns the initial hex as is

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hex = hexOf(_c.toColor());
    Widget slider(String label, double v, double max, ValueChanged<double> f) =>
        Row(
          children: [
            SizedBox(width: 56, child: Text(label)),
            Expanded(
              child: Semantics(
                label: label,
                child: Slider(value: v, max: max, onChanged: f),
              ),
            ),
          ],
        );
    return AlertDialog(
      backgroundColor: KkjLight.componentsPopoverBackground,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _c.toColor(),
                  borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
                  border: Border.all(color: KkjLight.colorBorderControl),
                ),
                child: const SizedBox.square(dimension: 48),
              ),
              const SizedBox(width: KkjTokens.spacing3),
              Text(hex.toUpperCase()),
            ],
          ),
          slider(
            l10n.colorHue,
            _c.hue,
            360,
            (v) => setState(() {
              _touched = true;
              _c = _c.withHue(v);
            }),
          ),
          slider(
            l10n.colorSaturation,
            _c.saturation,
            1,
            (v) => setState(() {
              _touched = true;
              _c = _c.withSaturation(v);
            }),
          ),
          slider(
            l10n.colorBrightness,
            _c.value,
            1,
            (v) => setState(() {
              _touched = true;
              _c = _c.withValue(v);
            }),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.colorPickerCancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(_touched ? hex : widget.initial.toLowerCase()),
          child: Text(l10n.colorPickerApply),
        ),
      ],
    );
  }
}
