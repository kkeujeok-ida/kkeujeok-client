import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/pressure_curve.dart';
import '../render/stroke_outline.dart';
import 'kk.dart';
import 'providers.dart';

const _eps = 0.01; // least gap between neighbouring points
const _graph = 220.0; // graph side, dp

/// Wins the gesture arena at once for [kinds] (all when null), so the list
/// behind does not scroll while the pointer works on the area.
Widget _noScroll({required Widget child, Set<PointerDeviceKind>? kinds}) =>
    RawGestureDetector(
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              () => EagerGestureRecognizer(supportedDevices: kinds),
              (_) {},
            ),
      },
      child: child,
    );

/// Settings: the pressure curve (spec/pen-feel.md) as 3 presets or a graph
/// with draggable, addable and deletable points, plus a pen-only test pad.
class PressureCurveSection extends ConsumerStatefulWidget {
  const PressureCurveSection({super.key});

  @override
  ConsumerState<PressureCurveSection> createState() =>
      _PressureCurveSectionState();
}

class _PressureCurveSectionState extends ConsumerState<PressureCurveSection> {
  final _pts = <List<double>>[];
  int _sel = -1; // selected inner point
  int _drag = -1;
  int _lastTapIdx = -1;
  Duration _lastTapAt = Duration.zero;

  double _pressure(PointerEvent e) {
    final range = e.pressureMax - e.pressureMin;
    if (!(range > 0)) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _add(PointerEvent e) => setState(
    () => _pts.add([e.localPosition.dx, e.localPosition.dy, _pressure(e), 0]),
  );

  PressureCurve get _curve => ref.read(pressureCurveProvider);

  void _set(List<(double, double)> p) => ref
      .read(pressureCurveProvider.notifier)
      .set(
        PressureCurve.fromValues([
          for (final q in p) ...[q.$1, q.$2],
        ]),
      );

  /// Point [i] of [p] moved to [o], held between its neighbours; null when
  /// there is no room.
  (double, double)? _clampAt(List<(double, double)> p, int i, Offset o) {
    final lo = i == 0 ? (0.0, 0.0) : p[i - 1];
    final hi = i == p.length - 1 ? (1.0, 1.0) : p[i + 1];
    if (hi.$1 - lo.$1 < 2 * _eps) return null;
    return (
      (o.dx / _graph).clamp(lo.$1 + _eps, hi.$1 - _eps),
      (1 - o.dy / _graph).clamp(lo.$2, hi.$2),
    );
  }

  int _hit(List<(double, double)> p, Offset o) {
    var best = -1;
    var bd = 22.0;
    for (var i = 0; i < p.length; i++) {
      final d = (Offset(p[i].$1 * _graph, (1 - p[i].$2) * _graph) - o).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  void _remove(int i) {
    final p = _curve.inner..removeAt(i);
    setState(() => _sel = -1);
    _set(p);
  }

  void _down(PointerDownEvent e) {
    final p = _curve.inner;
    var i = _hit(p, e.localPosition);
    if (i >= 0) {
      final again =
          i == _lastTapIdx &&
          e.timeStamp - _lastTapAt < const Duration(milliseconds: 350);
      _lastTapIdx = again ? -1 : i;
      _lastTapAt = e.timeStamp;
      if (again) return _remove(i);
    } else if (p.length < PressureCurve.maxInner) {
      _lastTapIdx = -1;
      final x = e.localPosition.dx / _graph;
      var at = p.indexWhere((q) => q.$1 > x);
      if (at < 0) at = p.length;
      final np = [...p]..insert(at, (x, 1 - e.localPosition.dy / _graph));
      final c = _clampAt(np, at, e.localPosition);
      if (c == null) return;
      _set(np..[at] = c);
      i = at;
    }
    setState(() => _sel = _drag = i);
  }

  void _move(PointerMoveEvent e) {
    final p = _curve.inner;
    if (_drag < 0 || _drag >= p.length) return;
    final c = _clampAt(p, _drag, e.localPosition);
    if (c != null) _set(p..[_drag] = c);
  }

  /// A point on the curve in the widest gap.
  void _addMid() {
    final p = _curve.inner;
    final xs = [0.0, for (final q in p) q.$1, 1.0];
    var g = 0;
    for (var k = 1; k < xs.length - 1; k++) {
      if (xs[k + 1] - xs[k] > xs[g + 1] - xs[g]) g = k;
    }
    final x = (xs[g] + xs[g + 1]) / 2;
    setState(() => _sel = g);
    _set(p..insert(g, (x, _curve.q(x))));
  }

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
    final p = curve.inner;
    final sel = _sel >= 0 && _sel < p.length ? _sel : -1;
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
                  setState(() => _sel = -1);
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
          right(
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: l10n.pressureCurveGraph,
                    child: _noScroll(
                      child: Listener(
                        onPointerDown: _down,
                        onPointerMove: _move,
                        onPointerUp: (_) => _drag = -1,
                        onPointerCancel: (_) => _drag = -1,
                        child: SizedBox(
                          width: _graph,
                          height: _graph,
                          child: CustomPaint(
                            painter: _GraphPainter(curve, sel),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: KkjTokens.spacing2),
                  SizedBox(
                    width: 140,
                    height: _graph,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (sel >= 0)
                          for (final out in [false, true])
                            SizedBox(
                              width: 140,
                              child: Semantics(
                                label: out
                                    ? l10n.pressureCurveOut
                                    : l10n.pressureCurveIn,
                                child: Slider(
                                  min: out
                                      ? (sel == 0 ? 0.0 : p[sel - 1].$2)
                                      : (sel == 0 ? 0.0 : p[sel - 1].$1) + _eps,
                                  max: out
                                      ? (sel == p.length - 1
                                            ? 1.0
                                            : p[sel + 1].$2)
                                      : (sel == p.length - 1
                                                ? 1.0
                                                : p[sel + 1].$1) -
                                            _eps,
                                  value: (out ? p[sel].$2 : p[sel].$1),
                                  onChanged: (x) => _set(
                                    p
                                      ..[sel] = out
                                          ? (p[sel].$1, x)
                                          : (x, p[sel].$2),
                                  ),
                                  semanticFormatterCallback: (x) =>
                                      x.toStringAsFixed(2),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(width: KkjTokens.spacing2),
                  Semantics(
                    label: l10n.pressureCurvePad,
                    child: _noScroll(
                      kinds: {PointerDeviceKind.stylus},
                      child: Listener(
                        onPointerDown: (e) {
                          if (e.kind != PointerDeviceKind.stylus) return;
                          _pts.clear();
                          _add(e);
                        },
                        onPointerMove: (e) {
                          if (e.kind == PointerDeviceKind.stylus) _add(e);
                        },
                        child: Container(
                          height: _graph,
                          width: _graph,
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
            ),
          ),
          right(
            Wrap(
              children: [
                TextButton(
                  onPressed: p.length < PressureCurve.maxInner ? _addMid : null,
                  child: Text(l10n.pressureCurveAdd),
                ),
                TextButton(
                  onPressed: sel >= 0 ? () => _remove(sel) : null,
                  child: Text(l10n.pressureCurveRemove),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _sel = -1);
                    set(PressureCurve.normal);
                  },
                  child: Text(l10n.pressureCurveReset),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.curve, this.sel);

  final PressureCurve curve;
  final int sel;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = Kk.colorSurfaceRaised);
    final line = Paint()
      ..color = Kk.colorBorderControl
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final f = size.width * i / 4;
      canvas.drawLine(Offset(f, 0), Offset(f, size.height), line);
      canvas.drawLine(Offset(0, f), Offset(size.width, f), line);
    }
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Kk.colorBorderControl,
    );
    final path = Path()..moveTo(0, size.height);
    for (var i = 1; i <= 64; i++) {
      final x = i / 64;
      path.lineTo(x * size.width, (1 - curve.q(x)) * size.height);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Kk.colorInkPrimary,
    );
    final p = curve.inner;
    for (var i = 0; i < p.length; i++) {
      final c = Offset(p[i].$1 * size.width, (1 - p[i].$2) * size.height);
      final rad = i == sel ? 8.0 : 6.0;
      canvas.drawCircle(c, rad, Paint()..color = Kk.colorSurfaceRaised);
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = i == sel ? Kk.colorAccentText : Kk.colorInkPrimary,
      );
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) => old.curve != curve || old.sel != sel;
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
