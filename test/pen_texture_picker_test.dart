import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/model/brush_preset.dart';
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
  testWidgets('texture + density: pen stores, none hides slider, '
      'highlighter/tape have no UI, preset keeps both', (t) async {
    final c = await _open(t);
    String tool() => c.read(penSlotsProvider)[0].tool;
    Map? brush() => c.read(penSlotsProvider)[0].brush;
    expect(find.text('Texture'), findsOneWidget);
    expect(find.text('Density'), findsNothing);
    await t.tap(find.text('Pencil stamp'));
    await t.pumpAndSettle();
    expect(brush(), {'texture': 'pencil'});
    expect(find.text('Density'), findsOneWidget);
    final sl = find.descendant(
      of: find
          .ancestor(of: find.text('Density'), matching: find.byType(Row))
          .first,
      matching: find.byType(Slider),
    );
    expect(t.getSize(find.text('None')).height, greaterThan(0));
    t.widget<Slider>(sl).onChanged!(0.4);
    await t.pumpAndSettle();
    expect(brush(), {'texture': 'pencil', 'density': 0.4});
    // preset keeps both
    final p = presetOf('a', 'x', c.read(penSlotsProvider)[0])!;
    expect(p.brush, {'texture': 'pencil', 'density': 0.4});
    // default values drop the fields
    await t.tap(find.text('None'));
    await t.pumpAndSettle();
    expect(brush(), {'density': 0.4});
    expect(find.text('Density'), findsNothing);
    t.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>).first,
    );
    await c.read(penSlotsProvider.notifier).setBrush(0, null);
    await c.read(penSlotsProvider.notifier).setTool(0, 'highlighter');
    await t.pumpAndSettle();
    expect(tool(), 'highlighter');
    expect(find.text('Texture'), findsNothing);
    expect(find.text('Density'), findsNothing);
    await c.read(penSlotsProvider.notifier).setTool(0, 'tape');
    await t.pumpAndSettle();
    expect(find.text('Texture'), findsNothing);
    await c.read(penSlotsProvider.notifier).setTool(0, 'pencil');
    await t.pumpAndSettle();
    expect(find.text('Density'), findsOneWidget); // pencil default texture
    await t.tap(find.text('None'));
    await t.pumpAndSettle();
    expect(brush(), {'texture': 'none'});
  });
}
