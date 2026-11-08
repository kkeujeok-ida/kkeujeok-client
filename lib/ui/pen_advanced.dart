import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../model/brush.dart';
import '../model/pressure_curve.dart';
import 'curve_editor.dart';
import 'providers.dart';

const _linear = [1 / 3, 1 / 3, 2 / 3, 2 / 3];

/// "Advanced" part of the pen popover (spec/brush.md): own pressure curve,
/// tilt curve and target, opacity, texture. Only what Epic 25 draws is shown.
/// The result is stored on the pen as a sparse `brush`; strokes already drawn
/// keep theirs.
class PenAdvanced extends ConsumerStatefulWidget {
  const PenAdvanced({super.key, required this.index});

  final int index;

  @override
  ConsumerState<PenAdvanced> createState() => _PenAdvancedState();
}

class _PenAdvancedState extends ConsumerState<PenAdvanced> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slots = ref.watch(penSlotsProvider);
    final i = widget.index.clamp(0, slots.length - 1);
    final pen = slots[i];
    final b = brushResolve(pen.tool, pen.brush);
    void set(Map<String, Object?> patch) => ref
        .read(penSlotsProvider.notifier)
        .setBrush(i, patchBrush(pen.tool, pen.brush, patch));
    final flat = pen.tool == 'highlighter' || pen.tool == 'tape';
    final own = b.pressureCurve != null;
    Widget radios(
      String label,
      List<(String, String)> items,
      String value,
      void Function(String) pick,
    ) => Semantics(
      container: true,
      label: label,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          for (final e in items) ButtonSegment(value: e.$1, label: Text(e.$2)),
        ],
        selected: {value},
        onSelectionChanged: (s) => pick(s.first),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: TextButton(
            onPressed: () => setState(() => _open = !_open),
            child: Text(l10n.brushAdvanced),
          ),
        ),
        if (_open) ...[
          if (!flat && pen.usePressure) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.brushPressureOwn),
              value: own,
              onChanged: (v) => set({'pressureCurve': v ? _linear : null}),
            ),
            if (own)
              CurveEditor(
                curve: PressureCurve.fromValues(b.pressureCurve!),
                fixedCount: 2,
                onChanged: (c) => set({'pressureCurve': c.values}),
                labels: (
                  graph: l10n.pressureCurveGraph,
                  input: l10n.pressureCurveIn,
                  output: l10n.pressureCurveOut,
                  pad: l10n.pressureCurvePad,
                  add: l10n.pressureCurveAdd,
                  remove: l10n.pressureCurveRemove,
                  reset: l10n.pressureCurveReset,
                ),
              ),
          ],
          if (!flat) ...[
            radios(
              l10n.brushTiltTarget,
              [
                ('none', l10n.brushTiltNone),
                ('size', l10n.brushTiltSize),
                ('opacity', l10n.brushTiltOpacity),
              ],
              b.tiltTarget,
              (v) => set({'tiltTarget': v}),
            ),
            if (b.tiltTarget != 'none')
              CurveEditor(
                curve: PressureCurve.fromValues(b.tiltCurve),
                mode: CurveMode.tilt,
                fixedCount: 2,
                onChanged: (c) => set({'tiltCurve': c.values}),
                labels: (
                  graph: l10n.tiltCurveGraph,
                  input: l10n.tiltCurveIn,
                  output: l10n.tiltCurveOut,
                  pad: l10n.tiltCurvePad,
                  add: '',
                  remove: '',
                  reset: '',
                ),
              ),
          ],
          if (pen.tool != 'tape')
            Row(
              children: [
                Text(l10n.brushOpacity),
                Expanded(
                  child: Slider(
                    min: 0.05,
                    max: 1,
                    divisions: 19,
                    value: b.opacity.clamp(0.05, 1.0),
                    label: '${(b.opacity * 100).round()}%',
                    semanticFormatterCallback: (x) => '${(x * 100).round()}%',
                    onChanged: (x) => set({'opacity': (x * 100).round() / 100}),
                  ),
                ),
              ],
            ),
          if (!flat)
            radios(
              l10n.brushTexture,
              [
                ('none', l10n.brushTexturePlain),
                ('pencil', l10n.brushTexturePencil),
              ],
              b.texture,
              (v) => set({'texture': v}),
            ),
        ],
      ],
    );
  }
}
