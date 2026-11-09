import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/brush.dart';
import '../model/brush_preset.dart';
import '../model/curve.dart';
import '../model/ids.dart';
import '../model/pressure_curve.dart';
import 'curve_editor.dart';
import 'providers.dart';

const _linear = [1 / 3, 1 / 3, 2 / 3, 2 / 3];

CurveLabels _labels(String g, String i, String o, String p) =>
    (graph: g, input: i, output: o, pad: p, add: '', remove: '', reset: '');

/// Advanced brush settings (spec/brush.md "Advanced settings layout"): the
/// curve graphs, always open, one column each, to the right of the pen
/// popover. The result is stored on the pen as a sparse `brush`; strokes
/// already drawn keep theirs.
class PenAdvancedPanel extends ConsumerWidget {
  const PenAdvancedPanel({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final slots = ref.watch(penSlotsProvider);
    final i = index.clamp(0, slots.length - 1);
    final pen = slots[i];
    final b = brushResolve(pen.tool, pen.brush);
    void set(Map<String, Object?> patch) => ref
        .read(penSlotsProvider.notifier)
        .setBrush(i, patchBrush(pen.tool, pen.brush, patch));
    final flat = pen.tool == 'highlighter' || pen.tool == 'tape';
    final oc = opacityPressureCurve(pen.brush);
    final cols = <List<Widget>>[
      if (!flat && pen.usePressure)
        [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.brushPressureOwn),
            value: b.pressureCurve != null,
            onChanged: (v) => set({'pressureCurve': v ? _linear : null}),
          ),
          CurveEditor(
            curve: PressureCurve.fromCurve(editPoints(b.pressureCurve)),
            fixedCount: 2,
            pad: false,
            onChanged: (c) => set({'pressureCurve': c.points}),
            labels: _labels(
              l10n.pressureCurveGraph,
              l10n.pressureCurveIn,
              l10n.pressureCurveOut,
              l10n.pressureCurvePad,
            ),
          ),
        ],
      if (pen.tool != 'tape' && pen.usePressure)
        [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.brushOpacityPressure),
            value: oc != null,
            onChanged: (v) => set({
              'opacityPressureCurve': v ? curveToPoints(_linear) : null,
            }),
          ),
          CurveEditor(
            curve: PressureCurve.fromCurve(editPoints(oc)),
            fixedCount: 2,
            pad: false,
            onChanged: (c) => set({'opacityPressureCurve': c.points}),
            labels: _labels(
              l10n.opacityCurveGraph,
              l10n.opacityCurveIn,
              l10n.opacityCurveOut,
              l10n.opacityCurvePad,
            ),
          ),
        ],
      if (!flat)
        [
          Semantics(
            container: true,
            label: l10n.brushTiltTarget,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'none', label: Text(l10n.brushTiltNone)),
                ButtonSegment(value: 'size', label: Text(l10n.brushTiltSize)),
                ButtonSegment(
                  value: 'opacity',
                  label: Text(l10n.brushTiltOpacity),
                ),
              ],
              selected: {b.tiltTarget},
              onSelectionChanged: (s) => set({'tiltTarget': s.first}),
            ),
          ),
          CurveEditor(
            curve: PressureCurve.fromCurve(editPoints(b.tiltCurve)),
            mode: CurveMode.tilt,
            fixedCount: 2,
            pad: false,
            onChanged: (c) => set({'tiltCurve': c.points}),
            labels: _labels(
              l10n.tiltCurveGraph,
              l10n.tiltCurveIn,
              l10n.tiltCurveOut,
              l10n.tiltCurvePad,
            ),
          ),
        ],
    ];
    if (pen.tool != 'tape') {
      if (cols.isEmpty) cols.add([]);
      cols.last.add(
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
      );
    }
    // Graph 220 + sliders 140 fit a 380 column unscaled (spec: >= 160 dp).
    return Semantics(
      container: true,
      label: l10n.brushAdvanced,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in cols)
            SizedBox(
              width: 380,
              child: Padding(
                padding: const EdgeInsets.all(
                  KkjLight.componentsPopoverPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: c,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "save" label and one label per saved preset, outside the popover
/// (Story 25.11). Tap applies a preset to the slot; long press (or the
/// screen-reader actions) renames or deletes it.
class PenPresets extends ConsumerStatefulWidget {
  const PenPresets({super.key, required this.index});

  final int index;

  @override
  ConsumerState<PenPresets> createState() => _PenPresetsState();
}

class _PenPresetsState extends ConsumerState<PenPresets> {
  late List<BrushPreset> _presets = ref
      .read(penSlotsStoreProvider)
      .readPresets();

  void _setPresets(List<BrushPreset> l) {
    setState(() => _presets = l);
    ref.read(penSlotsStoreProvider).writePresets(l);
  }

  Future<String?> _askName(String initial) {
    final l10n = AppLocalizations.of(context);
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: maxPresetName,
          decoration: InputDecoration(hintText: l10n.brushPresetName),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(l10n.brushPresetSave),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final slots = ref.read(penSlotsProvider);
    final pen = slots[widget.index.clamp(0, slots.length - 1)];
    final name = await _askName('');
    if (name == null || !mounted) return;
    final p = presetOf(newId(), name, pen);
    if (p == null || _presets.length >= maxPresets) return;
    _setPresets([..._presets, p]);
  }

  Future<void> _rename(BrushPreset p) async {
    final name = await _askName(p.name);
    if (name == null || name.trim().isEmpty || !mounted) return;
    final n = name.trim();
    _setPresets([
      for (final q in _presets)
        if (q.id == p.id)
          BrushPreset(
            id: q.id,
            name: n.length > maxPresetName ? n.substring(0, maxPresetName) : n,
            tool: q.tool,
            width: q.width,
            usePressure: q.usePressure,
            brush: q.brush,
          )
        else
          q,
    ]);
  }

  void _delete(BrushPreset p) => _setPresets([
    for (final q in _presets)
      if (q.id != p.id) q,
  ]);

  Future<void> _menu(BrushPreset p, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(value: 'rename', child: Text(l10n.brushPresetRename)),
        PopupMenuItem(value: 'delete', child: Text(l10n.brushPresetDelete)),
      ],
    );
    if (v == 'rename') await _rename(p);
    if (v == 'delete') _delete(p);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.brushPresets,
      child: SizedBox(
        width: 180,
        child: Wrap(
          spacing: KkjTokens.spacing1,
          children: [
            ActionChip(
              avatar: const Icon(Icons.add),
              label: Text(l10n.brushPresetSave),
              onPressed: _presets.length >= maxPresets ? null : _save,
            ),
            for (final p in _presets)
              Semantics(
                customSemanticsActions: {
                  CustomSemanticsAction(label: l10n.brushPresetRename): () =>
                      _rename(p),
                  CustomSemanticsAction(label: l10n.brushPresetDelete): () =>
                      _delete(p),
                },
                child: GestureDetector(
                  onLongPressStart: (d) => _menu(p, d.globalPosition),
                  child: ActionChip(
                    label: Text(p.name),
                    onPressed: () => ref
                        .read(penSlotsProvider.notifier)
                        .applyPreset(widget.index, p),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
