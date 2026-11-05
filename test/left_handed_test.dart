import 'dart:ui';

import 'package:flutter/painting.dart' show AxisDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/storage/left_handed_store.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:kkeujeok/ui/selection_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('left-handed is off by default and remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LeftHandedStore(await SharedPreferences.getInstance());
    expect(store.read(), isFalse);
    await store.write(true);
    expect(store.read(), isTrue);
  });

  test('pen bubble and selection menu open on the opposite side', () {
    const win = Size(800, 600);
    final top = PenBubbleAnchor(
      const Rect.fromLTWH(100, 0, 40, 40),
      const Rect.fromLTWH(0, 0, 400, 48),
      vertical: false,
    );
    expect(penBubbleSide(top, win), AxisDirection.down);
    expect(penBubbleSide(top, win, leftHanded: true), AxisDirection.up);
    expect(selectionMenuPrefersAbove(leftHanded: false), isTrue);
    expect(selectionMenuPrefersAbove(leftHanded: true), isFalse);
  });
}
