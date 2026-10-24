
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
    required Listenable repaint,
  }) : super(repaint: repaint);

  final PageViewport viewport;
  final Rect? box;
  final List<Offset> Function() lasso;

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
    final outline = Path()..addRect(r);
    for (final m in outline.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 8) {
        canvas.drawPath(m.extractPath(d, d + 4), line);
      }
    }
    final top = Offset(r.center.dx, r.top - selectionRotateGap);
    canvas.drawLine(Offset(r.center.dx, r.top), top, line);
    final fill = Paint()..color = KkjLight.componentsSelectionHandleFill;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight, top]) {
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
