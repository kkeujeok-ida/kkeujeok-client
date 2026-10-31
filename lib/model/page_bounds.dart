import 'dart:ui' show Rect;

import 'number.dart';
import 'select.dart';

const outMargin = 2.0;

/// spec rule `page.outOfBounds`: ids of the elements that extend past an edge
/// of the page by more than [outMargin], in the order of [elements].
List<String> pageOutOfBounds(num width, num height, Iterable<El> elements) {
  final w = width.toDouble(), h = height.toDouble();
  final ids = <String>[];
  for (final e in elements) {
    final b = selectionBounds([e]);
    if (b == null) continue; // no box (an empty stroke) is never outside
    final r = Rect.fromLTRB(
      round2(b.left),
      round2(b.top),
      round2(b.right),
      round2(b.bottom),
    );
    if (r.left < -outMargin ||
        r.top < -outMargin ||
        r.right > w + outMargin ||
        r.bottom > h + outMargin) {
      ids.add(e['id'] as String);
    }
  }
  return ids;
}
