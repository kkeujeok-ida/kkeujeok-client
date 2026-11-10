import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/storage/pen_slots_store.dart';
import 'package:kkeujeok/ui/eraser_dialog.dart';
import 'package:kkeujeok/ui/providers.dart';
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

  test('left-handed bubble never covers a bar docked at the flipped edge', () {
    const win = Size(800, 600);
    const bar = Rect.fromLTWH(0, 0, 400, 48);
    final a = PenBubbleAnchor(
      const Rect.fromLTWH(100, 0, 40, 40),
      bar,
      vertical: false,
    );
    const size = Size(300, 200);
    final p = placePenBubble(a, size, win, leftHanded: true);
    expect((p.topLeft & size).overlaps(bar), isFalse);
    expect(p.side, AxisDirection.down); // fell back to the normal side
    expect(p.tail, isNotNull);
    // A bar with room on the flipped side still flips.
    final low = PenBubbleAnchor(
      const Rect.fromLTWH(100, 300, 40, 40),
      const Rect.fromLTWH(0, 300, 400, 48),
      vertical: false,
    );
    expect(
      placePenBubble(low, size, win, leftHanded: true).side,
      AxisDirection.down,
    );
  });

  testWidgets('left-handed: the eraser options open as a speech bubble', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({'leftHanded': true});
    final sp = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          penSlotsStoreProvider.overrideWithValue(PenSlotsStore(sp)),
          leftHandedStoreProvider.overrideWithValue(LeftHandedStore(sp)),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () => showDialog<void>(
                  context: c,
                  useSafeArea: false,
                  builder: (_) => EraserDialog(
                    anchor: () => PenBubbleAnchor(
                      const Rect.fromLTWH(100, 300, 40, 40),
                      const Rect.fromLTWH(0, 300, 400, 48),
                      vertical: false,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(PenBubble), findsOneWidget);
    expect(find.text('Eraser options'), findsOneWidget);
    // Mirrored: below the bar (the right-handed rule puts it above).
    expect(t.getRect(find.text('Eraser options')).top, greaterThan(348));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(PenBubble), findsNothing);
  });
}
