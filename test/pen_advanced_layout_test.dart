import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/storage/pen_slots_store.dart';
import 'package:kkeujeok/ui/curve_editor.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _open(WidgetTester t) async {
  t.view.physicalSize = const Size(1800, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [penSlotsStoreProvider.overrideWithValue(PenSlotsStore(sp))],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
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
            builder: (ctx) => TextButton(
              onPressed: () => showDialog<bool>(
                context: ctx,
                builder: (_) => const PenEditDialog(),
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
  return c;
}

void main() {
  testWidgets('advanced: graphs open to the right, no pad/texture, presets '
      'outside', (t) async {
    final c = await _open(t);
    expect(find.byType(CurveEditor), findsNothing);
    final bubble = t.getRect(find.byType(SingleChildScrollView).first);
    await t.tap(find.text('Advanced brush settings'));
    await t.pumpAndSettle();
    expect(find.byType(CurveEditor), findsNWidgets(3));
    expect(t.getRect(find.byType(SingleChildScrollView).first), bubble);
    for (final e in t.widgetList<CurveEditor>(find.byType(CurveEditor))) {
      expect(e.pad, false);
    }
    expect(t.getSize(find.byType(CurveEditor).first).width, greaterThan(160));
    expect(
      t.getTopLeft(find.byType(CurveEditor).first).dx,
      greaterThan(bubble.right),
    );
    expect(find.text('Texture'), findsOneWidget); // basic settings only
    expect(find.text('Pencil grain'), findsNothing);
    final save = find.widgetWithText(ActionChip, 'Save current pen as preset');
    expect(
      t.getTopLeft(save).dx,
      greaterThan(t.getTopLeft(find.byType(CurveEditor).first).dx),
    );

    await t.tap(save);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Mine');
    await t.tap(find.text('Save current pen as preset').last);
    await t.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'Mine'), findsOneWidget);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('brushPresets'), contains('Mine'));

    await t.longPress(find.widgetWithText(ActionChip, 'Mine'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete preset'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'Mine'), findsNothing);
    expect(c.read(penSlotsProvider), isNotEmpty);
  });
}

