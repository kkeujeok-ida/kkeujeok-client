import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/pressure_curve.dart';
import '../render/stroke_outline.dart';
import 'kk.dart';
import 'providers.dart';

/// Settings: the pressure curve (spec/pen-feel.md) as 3 presets or the four
/// control-point values, with a pad to draw a test stroke.
class PressureCurveSection extends ConsumerStatefulWidget {
  const PressureCurveSection({super.key});

  @override
  ConsumerState<PressureCurveSection> createState() =>
      _PressureCurveSectionState();
}

class _PressureCurveSectionState extends ConsumerState<PressureCurveSection> {
  final _pts = <List<double>>[];

  double _pressure(PointerEvent e) {
    if (e.kind != PointerDeviceKind.stylus) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (!(range > 0)) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _add(PointerEvent e) => setState(
    () => _pts.add([e.localPosition.dx, e.localPosition.dy, _pressure(e), 0]),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final curve = ref.watch(pressureCurveProvider);
    final set = ref.read(pressureCurveProvider.notifier).set;
    final names = {
      PressureCurve.soft: l10n.pressureCurveSoft,
      PressureCurve.normal: l10n.pressureCurveNormal,
      PressureCurve.firm: l10n.pressureCurveFirm,
    };
    final labels = [
      l10n.pressureCurveX1,
      l10n.pressureCurveY1,
      l10n.pressureCurveX2,
      l10n.pressureCurveY2,
    ];
    final v = curve.values;
    // Each slider's range keeps x1 <= x2 and y1 <= y2: no invalid curve.
    final lo = [0.0, 0.0, v[0], v[1]];
    final hi = [v[2], v[3], 1.0, 1.0];
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
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<PressureCurve>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              segments: [
                for (final e in names.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: curve.preset == null ? {} : {curve},
              onSelectionChanged: (s) {
                if (s.isNotEmpty) set(s.first);
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
          for (var i = 0; i < 4; i++)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ExcludeSemantics(child: Text(labels[i])),
                ),
                Expanded(
                  flex: 3,
                  child: Semantics(
                    label: labels[i],
                    child: Slider(
                      min: lo[i],
                      max: hi[i],
                      value: v[i].clamp(lo[i], hi[i]),
                      onChanged: (x) {
                        final next = [...v]..[i] = x;
                        set(PressureCurve.fromValues(next));
                      },
                      semanticFormatterCallback: (x) => x.toStringAsFixed(2),
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: ExcludeSemantics(child: Text(v[i].toStringAsFixed(2))),
                ),
              ],
            ),
          Semantics(
            label: l10n.pressureCurvePad,
            child: GestureDetector(
              onPanUpdate: (_) {}, // keeps the list from scrolling away
              child: Listener(
                onPointerDown: (e) {
                  _pts.clear();
                  _add(e);
                },
                onPointerMove: _add,
                child: Container(
                  height: 96,
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(
                    vertical: KkjTokens.spacing2,
                  ),
                  decoration: BoxDecoration(
                    color: Kk.colorSurfaceRaised,
                    border: Border.all(color: Kk.colorBorderControl),
                  ),
                  child: ClipRect(
                    child: CustomPaint(
                      painter: _PadPainter(List.of(_pts), curve),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.pts, this.curve);

  final List<List<double>> pts;
  final PressureCurve curve;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    canvas.drawPath(
      outlinePath(strokeOutline(6, true, pts, curve)),
      Paint()..color = Kk.colorInkPrimary,
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
