import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/storage/pen_slots_store.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shape bubble: three icon buttons in a row, pick fills one', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final picked = <String>[];
    await t.pumpWidget(
      ProviderScope(
        overrides: [penSlotsStoreProvider.overrideWithValue(PenSlotsStore(sp))],
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
                  builder: (_) =>
                      ShapeToolDialog(kind: 'rect', onPick: picked.add),
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

    final names = ['Triangle', 'Rectangle', 'Circle'];
    final rects = [
      for (final n in names) t.getRect(find.bySemanticsLabel(n).first),
    ];
    for (final r in rects) {
      expect(r.width, greaterThanOrEqualTo(48));
      expect(r.height, greaterThanOrEqualTo(48));
      expect(r.top, rects.first.top); // one horizontal row
    }
    expect(rects[0].left, lessThan(rects[1].left));
    expect(rects[1].left, lessThan(rects[2].left));
    // Icons only: the names are semantics, not visible text.
    for (final n in names) {
      expect(find.text(n), findsNothing);
    }

    await t.tapAt(rects[2].center);
    await t.pumpAndSettle();
    expect(picked, ['circle']);
    final selected = t
        .getSemantics(find.bySemanticsLabel('Circle').first)
        .getSemanticsData()
        .flagsCollection
        .isChecked;
    expect(selected.name, 'isTrue');
  });
}
