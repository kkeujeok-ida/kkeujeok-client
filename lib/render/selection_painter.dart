import 'package:flutter/widgets.dart';

import '../design_tokens/build/tokens.dart';
import 'page_painter.dart' show PageViewport;

const selectionHandleRadius = 6.0;
const selectionRotateGap = 28.0; // screen px above the box top

/// The lasso line being drawn and the selection box, in screen space over the
/// pages, so both go on past the page edge. [box] and [lasso] are in
/// document coordinates.
class SelectionPainter extends CustomPainter {
  SelectionPainter({
    required this.viewport,
    required this.box,
    required this.lasso,
    required this.preview,
    required Listenable repaint,
    this.widthHandles,
  }) : super(repaint: repaint);

  final PageViewport viewport;
  final Rect? box;
  final List<Offset> Function() lasso;

  /// The box a drag would leave (document coordinates, turned by the angle in
  /// radians about its center); null when nothing is being dragged. While it
  /// is set it is drawn instead of the box and its handles.
  final (Rect, double)? Function() preview;

  /// The two side handles of a single selected text box (document
  /// coordinates), if any.
  final List<Offset> Function()? widthHandles;

  Offset _s(Offset d) => viewport.offset + d * viewport.scale;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = lasso();
    if (pts.length > 1) {
      canvas.drawPath(
        Path()..addPolygon([for (final p in pts) _s(p)], false),
        Paint()
          ..color = KkjLight.componentsSelectionOutline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final b = box;
    if (b == null) return;
    final r = Rect.fromPoints(_s(b.topLeft), _s(b.bottomRight));
    final line = Paint()
      ..color = KkjLight.componentsSelectionOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final pv = preview();
    if (pv != null) {
      final (pb, angle) = pv;
      final pr = Rect.fromPoints(_s(pb.topLeft), _s(pb.bottomRight));
      canvas
        ..save()
        ..translate(pr.center.dx, pr.center.dy)
        ..rotate(angle)
        ..translate(-pr.center.dx, -pr.center.dy)
        ..drawRect(pr, line)
        ..restore();
      return;
    }
    final outline = Path()..addRect(r);
    for (final m in outline.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 8) {
        canvas.drawPath(m.extractPath(d, d + 4), line);
      }
    }
    final top = Offset(r.center.dx, r.top - selectionRotateGap);
    canvas.drawLine(Offset(r.center.dx, r.top), top, line);
    final fill = Paint()..color = KkjLight.componentsSelectionHandleFill;
    for (final c in [
      r.topLeft,
      r.topRight,
      r.bottomLeft,
      r.bottomRight,
      top,
      for (final h in widthHandles?.call() ?? const <Offset>[]) _s(h),
    ]) {
      canvas
        ..drawCircle(c, selectionHandleRadius, fill)
        ..drawCircle(
          c,
          selectionHandleRadius,
          Paint()
            ..color = KkjLight.componentsSelectionHandleBorder
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }
  }

  @override
  bool shouldRepaint(SelectionPainter old) => true;
}
