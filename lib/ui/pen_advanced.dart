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
import 'kk.dart';
import 'providers.dart';

/// Palette swatch edge: about 0.7 x the previous 48 dp; the hit area stays 48
/// (spec/brush.md "Sizes").
const paletteSwatch = 34.0;

/// Switch scale: about 0.75 x the Material size; the row stays 48 dp high.
const switchScale = 0.75;

/// A labelled switch row, the whole 48 dp row taps (spec/brush.md "Sizes").
class PenSwitchRow extends StatelessWidget {
  const PenSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    toggled: value,
    onTap: () => onChanged(!value),
    excludeSemantics: true,
    child: InkWell(
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            IgnorePointer(
              child: Transform.scale(
                scale: switchScale,
                alignment: Alignment.centerRight,
                child: Switch(value: value, onChanged: onChanged),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Advanced brush settings (spec/brush.md "Advanced settings layout"): one
/// block per curve (switch, title, graph), always open, in one column below
/// the basic settings. The result is stored on the pen as a sparse `brush`;
/// strokes already drawn keep theirs. A switch only adds its name to
/// `brush.curvesOff`; the points stay.
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
    // Read the latest pen: a touch on a switched-off graph turns it on and the
    // same gesture edits it, two writes in one frame.
    void set(Map<String, Object?> patch) {
      final cur = ref.read(penSlotsProvider);
      final p = cur[i.clamp(0, cur.length - 1)];
      ref
          .read(penSlotsProvider.notifier)
          .setBrush(i, patchBrush(p.tool, p.brush, patch));
    }

    final off = curvesOff(pen.brush);
    // Old tiltTarget/tiltCurve read as the two tilt curves, ignoring the switch.
    final legacy = brushLegacyTilt({
      if (pen.brush != null) ...pen.brush!,
      'curvesOff': <String>[],
    });
    final brush = pen.brush;
    final stored = {
      'pressure': validCurve(brush?['pressureCurve']),
      'sizeTilt': legacy.sizeTiltCurve,
      'opacityPressure': opacityPressureCurve(brush),
      'opacityTilt': legacy.opacityTiltCurve,
      'densityPressure': validCurve(brush?['densityPressureCurve']),
    };
    const press = [
      [0.0, 0.0],
      [1.0, 1.0],
    ];
    const flat = [
      [0.0, 1.0],
      [1.0, 1.0],
    ];

    Widget block(
      String name,
      String field,
      String title,
      CurveMode mode,
      CurveLabels labels,
    ) {
      final curve = stored[name];
      final on = curve != null && !off.contains(name);
      final start = mode == CurveMode.tilt ? flat : press;
      void turnOn() {
        if (on) return;
        final rest = [
          for (final s in curvesOff(ref.read(penSlotsProvider)[i].brush))
            if (s != name) s,
        ];
        set({
          'curvesOff': rest.isEmpty ? null : rest,
          if (curve == null) field: start,
        });
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PenSwitchRow(
            label: title,
            value: on,
            onChanged: (v) => v
                ? turnOn()
                : set({
                    'curvesOff': [...off, name],
                  }),
          ),
          Opacity(
            opacity: on ? 1 : 0.45,
            child: CurveEditor(
              curve: PressureCurve.fromCurve(editPoints(curve) ?? start),
              pad: false,
              onTouch: turnOn,
              onChanged: (c) => set({field: c.points}),
              labels: labels,
            ),
          ),
        ],
      );
    }

    CurveLabels labels(String title, String input, String output) => (
      graph: title,
      input: input,
      output: output,
      pad: '',
      add: '',
      remove: '',
      reset: '',
    );

    final highlighter = pen.tool == 'highlighter';
    final blocks = pen.tool == 'tape'
        ? <Widget>[]
        : [
            block(
              'pressure',
              'pressureCurve',
              l10n.brushCurvePressure,
              CurveMode.pressure,
              labels(
                l10n.brushCurvePressure,
                l10n.pressureCurveIn,
                l10n.pressureCurveOut,
              ),
            ),
            if (!highlighter) ...[
              block(
                'sizeTilt',
                'sizeTiltCurve',
                l10n.brushCurveSizeTilt,
                CurveMode.tilt,
                labels(
                  l10n.brushCurveSizeTilt,
                  l10n.tiltCurveIn,
                  l10n.tiltCurveOut,
                ),
              ),
              block(
                'opacityPressure',
                'opacityPressureCurve',
                l10n.brushCurveOpacityPressure,
                CurveMode.pressure,
                labels(
                  l10n.brushCurveOpacityPressure,
                  l10n.opacityCurveIn,
                  l10n.opacityCurveOut,
                ),
              ),
              block(
                'opacityTilt',
                'opacityTiltCurve',
                l10n.brushCurveOpacityTilt,
                CurveMode.tilt,
                labels(
                  l10n.brushCurveOpacityTilt,
                  l10n.tiltCurveIn,
                  l10n.opacityCurveOut,
                ),
              ),
              if (b.texture == 'pencil')
                block(
                  'densityPressure',
                  'densityPressureCurve',
                  l10n.brushCurveDensityPressure,
                  CurveMode.pressure,
                  labels(
                    l10n.brushCurveDensityPressure,
                    l10n.opacityCurveIn,
                    l10n.brushDensity,
                  ),
                ),
            ],
          ];
    return Semantics(
      container: true,
      label: l10n.brushAdvanced,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final w in blocks) ...[
            w,
            const SizedBox(height: KkjTokens.spacing3),
          ],
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
              shape: const StadiumBorder(),
              side: BorderSide.none,
              backgroundColor: Kk.colorAccent.withValues(alpha: 0.25),
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
                    shape: const StadiumBorder(),
                    side: BorderSide.none,
                    backgroundColor: Kk.colorAccent,
                    labelStyle: TextStyle(color: Kk.colorOnAccent),
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
