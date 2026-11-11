import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens/build/tokens.dart';
import '../model/brush.dart';
import '../model/curve.dart';
import '../model/pressure_curve.dart';
import '../render/stroke_outline.dart';
import 'kk.dart';

const _eps = 0.01; // least gap between neighbouring points
const _graph = 220.0; // graph side, dp
const _lineGrab = 14.0; // a tap this close to the curve adds a point
const _dropAt = 0.08; // dragged this far out of the graph, a point goes

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

/// The texts of a [CurveEditor].
typedef CurveLabels = ({
  String graph,
  String input,
  String output,
  String pad,
  String add,
  String remove,
  String reset,
});

enum CurveMode { pressure, tilt }

/// A curve graph with draggable, keyboard- and screen-reader-movable points,
/// number sliders and a pen-only test pad (spec/pen-feel.md, spec/brush.md).
/// Controlled: it shows [curve] and reports every change through [onChanged].
class CurveEditor extends StatefulWidget {
  const CurveEditor({
    super.key,
    required this.curve,
    required this.onChanged,
    required this.labels,
    this.mode = CurveMode.pressure,
    this.fixedCount,
    this.onReset,
    this.pad = true,
    this.onTouch,
  });

  final PressureCurve curve;
  final ValueChanged<PressureCurve> onChanged;
  final CurveLabels labels;

  /// `pressure`: the test pad draws with the pen's pressure; `tilt`: with the
  /// pen's tilt as the width.
  final CurveMode mode;

  /// A fixed number of points (no add or remove), e.g. a brush curve.
  final int? fixedCount;
  final VoidCallback? onReset;

  /// false: no test pad (a curve that is not a width).
  final bool pad;

  /// Called at pointer down on the graph, before the edit (a curve switched
  /// off turns on here, spec/brush.md "Curve switches").
  final VoidCallback? onTouch;

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  final _pts = <List<double>>[];
  int _sel = -1; // selected inner point
  int _drag = -1;
  bool _out = false; // the dragged point is past the edge: it will be deleted

  bool get _fixed => widget.fixedCount != null;

  // A point-list curve (spec/brush.md): edited with `brush.curveEdit`, the
  // ends move up and down, x stays 0 and 1; else the inner points of a legacy
  // curve.
  bool get _points => widget.curve.points != null;

  List<(double, double)> get _pl => _points
      ? [for (final q in widget.curve.points!) (q[0], q[1])]
      : widget.curve.inner;

  double _pressure(PointerEvent e) {
    final range = e.pressureMax - e.pressureMin;
    if (!(range > 0)) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _add(PointerEvent e) => setState(() {
    final base = <double>[
      e.localPosition.dx,
      e.localPosition.dy,
      widget.mode == CurveMode.tilt ? 0.5 : _pressure(e),
      0,
    ];
    if (widget.mode == CurveMode.tilt && e.tilt > 0) {
      base.addAll([e.tilt * 180 / 3.141592653589793, 0]);
    }
    _pts.add(base);
  });

  void _set(List<(double, double)> p) => widget.onChanged(
    PressureCurve.fromValues([
      for (final q in p) ...[q.$1, q.$2],
    ]),
  );

  /// Point-list curve after the `brush.curveEdit` op [op].
  List<List<double>> _edit(Map op) => curveEdit(widget.curve.points!, op);

  void _setList(List<List<double>> l) =>
      widget.onChanged(PressureCurve.fromCurve(l));

  /// Legacy curve: point [i] of [p] moved to ([x], [y]), held between its
  /// neighbours; null when there is no room.
  (double, double)? _clampAt(
    List<(double, double)> p,
    int i,
    double x,
    double y,
  ) {
    final lo = i == 0 ? (0.0, 0.0) : p[i - 1];
    final hi = i == p.length - 1 ? (1.0, 1.0) : p[i + 1];
    if (hi.$1 - lo.$1 < 2 * _eps) return null;
    return (x.clamp(lo.$1 + _eps, hi.$1 - _eps), y.clamp(lo.$2, hi.$2));
  }

  int _hit(List<(double, double)> p, Offset o) {
    var best = -1;
    var bd = 16.0; // a tap farther than this from every point is not a grab
    for (var i = 0; i < p.length; i++) {
      final d = (Offset(p[i].$1 * _graph, (1 - p[i].$2) * _graph) - o).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  /// True when [o] (graph dp) lies within [_lineGrab] of the drawn curve.
  bool _onLine(Offset o) {
    const steps = 64;
    Offset at(int k) =>
        Offset(k / steps * _graph, (1 - widget.curve.q(k / steps)) * _graph);
    var a = at(0);
    for (var k = 1; k <= steps; k++) {
      final b = at(k);
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final t = len2 == 0
          ? 0.0
          : (((o - a).dx * ab.dx + (o - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
      if ((a + ab * t - o).distance <= _lineGrab) return true;
      a = b;
    }
    return false;
  }

  /// How far past the graph box [o] is, as a share of its side.
  double _outside(Offset o) {
    double over(double v) => math.max(math.max(-v, v - _graph), 0) / _graph;
    return math.max(over(o.dx), over(o.dy));
  }

  void _remove(int i) {
    if (_fixed || i < 0) return;
    if (_points) {
      final l = _edit({'kind': 'release', 'index': i, 'outside': 1});
      if (l.length == widget.curve.points!.length) return;
      setState(() => _sel = -1);
      return _setList(l);
    }
    final p = _pl..removeAt(i);
    setState(() => _sel = -1);
    _set(p);
  }

  void _down(PointerDownEvent e) {
    widget.onTouch?.call();
    final p = _pl;
    var i = _hit(p, e.localPosition);
    // A point is added only by a tap on the curve itself, not beside it.
    if (i < 0 && !_fixed && _onLine(e.localPosition)) {
      final x = (e.localPosition.dx / _graph).clamp(0.0, 1.0);
      final y = widget.curve.q(x);
      if (_points) {
        final l = _edit({'kind': 'add', 'x': x, 'y': y});
        if (l.length == p.length) return;
        i = l.indexWhere((q) => !p.any((o) => o.$1 == q[0] && o.$2 == q[1]));
        _setList(l);
      } else if (p.length < PressureCurve.maxInner) {
        var at = p.indexWhere((q) => q.$1 > x);
        if (at < 0) at = p.length;
        final np = [...p]..insert(at, (x, y));
        final c = _clampAt(np, at, x, y);
        if (c == null) return;
        _set(np..[at] = c);
        i = at;
      }
    }
    if (i < 0) return;
    setState(() => _sel = _drag = i);
  }

  void _move(PointerMoveEvent e) {
    final p = _pl;
    if (_drag < 0 || _drag >= p.length) return;
    final x = e.localPosition.dx / _graph, y = 1 - e.localPosition.dy / _graph;
    final out = !_fixed && _outside(e.localPosition) > _dropAt;
    if (out != _out) setState(() => _out = out);
    if (_points) {
      return _setList(_edit({'kind': 'move', 'index': _drag, 'x': x, 'y': y}));
    }
    final c = _clampAt(p, _drag, x, y);
    if (c != null) _set(p..[_drag] = c);
  }

  /// Letting go beyond the graph box deletes an inner point (`brush.curveEdit`
  /// release; the legacy curve uses the same distance).
  void _up(PointerEvent e) {
    final i = _drag;
    _drag = -1;
    if (_out) setState(() => _out = false);
    if (i < 0 || _fixed || e is PointerCancelEvent) return;
    final outside = _outside(e.localPosition);
    if (outside <= _dropAt) return;
    if (_points) {
      final l = _edit({'kind': 'release', 'index': i, 'outside': outside});
      if (l.length == widget.curve.points!.length) return;
      setState(() => _sel = -1);
      _setList(l);
    } else if (i < _pl.length) {
      _remove(i);
    }
  }

  /// A point on the curve in the widest gap (legacy curve only).
  void _addMid() {
    final p = _pl;
    final xs = [0.0, for (final q in p) q.$1, 1.0];
    var g = 0;
    for (var k = 1; k < xs.length - 1; k++) {
      if (xs[k + 1] - xs[k] > xs[g + 1] - xs[g]) g = k;
    }
    final x = (xs[g] + xs[g + 1]) / 2;
    setState(() => _sel = g);
    _set(p..insert(g, (x, widget.curve.q(x))));
  }

  /// Point [i] moved by ([dx], [dy]) (arrow keys, screen-reader actions).
  void _nudge(int i, double dx, double dy) {
    final p = _pl;
    if (i < 0 || i >= p.length) return;
    if (_points) {
      return _setList(
        _edit({
          'kind': 'move',
          'index': i,
          'x': p[i].$1 + dx,
          'y': p[i].$2 + dy,
        }),
      );
    }
    final c = _clampAt(p, i, p[i].$1 + dx, p[i].$2 + dy);
    if (c != null) _set(p..[i] = c);
  }

  KeyEventResult _key(int i, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final s = HardwareKeyboard.instance.isShiftPressed ? 0.05 : 0.01;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      _nudge(i, 0, s);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _nudge(i, 0, -s);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _nudge(i, s, 0);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _nudge(i, -s, 0);
    } else if (k == LogicalKeyboardKey.delete ||
        k == LogicalKeyboardKey.backspace) {
      if (_fixed) return KeyEventResult.ignored;
      _remove(i);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.labels;
    final curve = widget.curve;
    final p = _pl;
    final sel = _sel >= 0 && _sel < p.length ? _sel : -1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: widget.pad ? Alignment.centerRight : Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  label: l.graph,
                  child: _noScroll(
                    child: Listener(
                      onPointerDown: _down,
                      onPointerMove: _move,
                      onPointerUp: _up,
                      onPointerCancel: _up,
                      child: SizedBox(
                        width: _graph,
                        height: _graph,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _GraphPainter(
                                  curve,
                                  sel,
                                  _out ? _drag : -1,
                                ),
                              ),
                            ),
                            for (var i = 0; i < p.length; i++)
                              Positioned(
                                left: p[i].$1 * _graph - 22,
                                top: (1 - p[i].$2) * _graph - 22,
                                width: 44,
                                height: 44,
                                child: Focus(
                                  onFocusChange: (f) {
                                    if (f) setState(() => _sel = i);
                                  },
                                  onKeyEvent: (_, e) => _key(i, e),
                                  child: Semantics(
                                    slider: true,
                                    label: '${l.graph} ${i + 1}',
                                    value:
                                        '${l.input} ${p[i].$1.toStringAsFixed(2)}, '
                                        '${l.output} ${p[i].$2.toStringAsFixed(2)}',
                                    increasedValue:
                                        '${l.output} ${(p[i].$2 + 0.05).clamp(0.0, 1.0).toStringAsFixed(2)}',
                                    decreasedValue:
                                        '${l.output} ${(p[i].$2 - 0.05).clamp(0.0, 1.0).toStringAsFixed(2)}',
                                    onIncrease: () => _nudge(i, 0, 0.05),
                                    onDecrease: () => _nudge(i, 0, -0.05),
                                    onTap: () => setState(() => _sel = i),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.pad) ...[
                  const SizedBox(width: KkjTokens.spacing2),
                  Semantics(
                    label: l.pad,
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
                              painter: _PadPainter(
                                List.of(_pts),
                                curve,
                                widget.mode,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            children: [
              // Legacy curve only (the settings screen); a point-list curve
              // adds by touching and removes by dragging out.
              if (!_fixed && !_points) ...[
                TextButton(
                  onPressed: p.length < PressureCurve.maxInner ? _addMid : null,
                  child: Text(l.add),
                ),
                TextButton(
                  onPressed: sel >= 0 ? () => _remove(sel) : null,
                  child: Text(l.remove),
                ),
              ],
              if (widget.onReset != null)
                TextButton(
                  onPressed: () {
                    setState(() => _sel = -1);
                    widget.onReset!();
                  },
                  child: Text(l.reset),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.curve, this.sel, this.fading);

  final PressureCurve curve;
  final int sel;

  /// The point that is about to be deleted: drawn faint.
  final int fading;

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
    final p = curve.points == null
        ? curve.inner
        : [for (final q in curve.points!) (q[0], q[1])];
    for (var i = 0; i < p.length; i++) {
      final c = Offset(p[i].$1 * size.width, (1 - p[i].$2) * size.height);
      final rad = i == sel ? 8.0 : 6.0;
      final k = i == fading ? 0.35 : 1.0;
      canvas.drawCircle(
        c,
        rad,
        Paint()..color = Kk.colorSurfaceRaised.withValues(alpha: k),
      );
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = (i == sel ? Kk.colorAccentText : Kk.colorInkPrimary)
              .withValues(alpha: k),
      );
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.curve != curve || old.sel != sel || old.fading != fading;
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.pts, this.curve, this.mode);

  final List<List<double>> pts;
  final PressureCurve curve;
  final CurveMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    final poly = mode == CurveMode.tilt
        ? strokeOutlineFor(
            'pen',
            6,
            false,
            pts,
            PressureCurve.normal,
            (p) => tiltSizeFactor(p, curve),
          )
        : strokeOutline(6, true, pts, curve);
    canvas.drawPath(outlinePath(poly), Paint()..color = Kk.colorInkPrimary);
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}
