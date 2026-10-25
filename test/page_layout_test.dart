// Story 5.11: page rectangles per view mode.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/page_view_mode.dart';
import 'package:kkeujeok/ui/page_layout.dart';

const p = Size(100, 200); // portrait
const l = Size(200, 100); // landscape

void main() {
  test('vertical stacks centered with gap 24', () {
    final r = layoutPages([p, l], PageViewMode.vertical);
    expect(r.rects[0], const Rect.fromLTWH(50, 0, 100, 200));
    expect(r.rects[1], const Rect.fromLTWH(0, 224, 200, 100));
    expect((r.w, r.h), (200.0, 324.0));
  });

  test('horizontal: left to right, centered on the tallest', () {
    final r = layoutPages([p, l, p], PageViewMode.horizontal);
    expect(r.rects[0], const Rect.fromLTWH(0, 0, 100, 200));
    expect(r.rects[1], const Rect.fromLTWH(124, 50, 200, 100));
    expect(r.rects[2], const Rect.fromLTWH(348, 0, 100, 200));
    expect((r.w, r.h), (448.0, 200.0));
  });

  List<int> pairs(List<Size> s) {
    final r = layoutPages(s, PageViewMode.twoPage).rects;
    // Page i starts a new pair when the gap to the previous one is 24.
    return [
      for (var i = 0; i < r.length; i++)
        if (i == 0 || r[i].left - r[i - 1].right > 10) i,
    ];
  }

  test('twoPage pairs (1,2)(3,4)(5)', () {
    expect(pairs([p, p, p, p, p]), [0, 2, 4]);
    final r = layoutPages([p, p, p, p, p], PageViewMode.twoPage);
    expect(r.rects[1].left - r.rects[0].right, 4);
    expect(r.rects[2].left - r.rects[1].right, 24);
    expect(r.w, 5 * 100 + 4 + 4 + 24 * 2);
  });

  test('twoPage mixed orientation: (1,2)(3)(4,5), landscape alone', () {
    expect(pairs([p, p, l, p, p]), [0, 2, 3]);
    expect(pairs([l, l, p]), [0, 1, 2]);
    expect(pairs([p, l, p]), [0, 1, 2]);
    final r = layoutPages([p, p, l, p, p], PageViewMode.twoPage);
    expect(r.rects[2].size, l); // sizes are kept
    expect(r.rects[2].top, 50); // centered on the tallest
  });

  test('empty', () {
    expect(layoutPages(const [], PageViewMode.twoPage).rects, isEmpty);
  });

  test('activeIndexOf: 2-D distance, ties to the earlier', () {
    final rects = [
      const Rect.fromLTWH(0, 0, 100, 100),
      const Rect.fromLTWH(200, 0, 100, 100),
    ];
    expect(activeIndexOf(rects, const Offset(140, 50)), 0);
    expect(activeIndexOf(rects, const Offset(150, 50)), 0); // tie
    expect(activeIndexOf(rects, const Offset(151, 50)), 1);
    expect(activeIndexOf(rects, const Offset(250, 900)), 1);
  });

  test('isPhone', () {
    expect(isPhone(const Size(599.9, 900)), isTrue);
    expect(isPhone(const Size(600, 900)), isFalse);
  });

  test('parse falls back to vertical', () {
    expect(PageViewMode.parse('twoPage'), PageViewMode.twoPage);
    expect(PageViewMode.parse('x'), PageViewMode.vertical);
    expect(PageViewMode.parse(3), PageViewMode.vertical);
    expect(PageViewMode.parse(null), PageViewMode.vertical);
  });
}
