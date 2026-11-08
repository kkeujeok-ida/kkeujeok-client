import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/pressure_curve.dart';
import 'curve_editor.dart';
import 'kk.dart';
import 'providers.dart';

/// Settings: the pressure curve (spec/pen-feel.md) as 3 presets or a graph
/// with draggable, addable and deletable points, plus a pen-only test pad.
class PressureCurveSection extends ConsumerWidget {
  const PressureCurveSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final curve = ref.watch(pressureCurveProvider);
    final set = ref.read(pressureCurveProvider.notifier).set;
    final names = {
      PressureCurve.soft: l10n.pressureCurveSoft,
      PressureCurve.normal: l10n.pressureCurveNormal,
      PressureCurve.firm: l10n.pressureCurveFirm,
    };
    Widget right(Widget w) => Align(alignment: Alignment.centerRight, child: w);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkjTokens.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KkjTokens.spacing2),
            child: Semantics(
              header: true,
              child: Text(
                l10n.pressureCurve,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
          right(
            SegmentedButton<PressureCurve>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              segments: [
                for (final e in names.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: curve.preset == null ? {} : {curve},
              onSelectionChanged: (s) {
                if (s.isNotEmpty) {
                  set(s.first);
                }
              },
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (st) => st.contains(WidgetState.selected)
                      ? Kk.colorAccentSoft
                      : Kk.colorSurfaceRaised,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (st) => st.contains(WidgetState.selected)
                      ? Kk.colorAccentText
                      : Kk.colorInkPrimary,
                ),
                side: WidgetStatePropertyAll(
                  BorderSide(color: Kk.colorBorderControl),
                ),
              ),
            ),
          ),
          const SizedBox(height: KkjTokens.spacing2),
          CurveEditor(
            curve: curve,
            onChanged: set,
            onReset: () => set(PressureCurve.normal),
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
      ),
    );
  }
}
