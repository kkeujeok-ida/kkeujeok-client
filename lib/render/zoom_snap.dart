import 'page_painter.dart';

/// spec/zoom.md `zoom.snap`: the scale to show for a requested [scale], given
/// the scale [fitScale] where the page width equals the view width.
double zoomSnap(double scale, double fitScale) {
  final f = fitScale.clamp(PageViewport.zoomMin, PageViewport.zoomMax);
  final s = scale.clamp(PageViewport.zoomMin, PageViewport.zoomMax);
  // Two multiplications, not a subtraction: both clients round the same.
  return f * 0.9 <= s && s <= f * 1.1 ? f : s;
}
