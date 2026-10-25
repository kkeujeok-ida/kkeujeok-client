import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/storage/pen_slots_store.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Opener extends StatelessWidget {
  const _Opener(this.index);

  final int index;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showDialog<bool>(
      context: context,
      builder: (_) => PenEditDialog(index: index),
    ),
    child: const Text('open'),
  );
}

Future<ProviderContainer> _open(
  WidgetTester t, {
  int index = 0,
  Map<String, Object> prefs = const {},
}) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
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
        home: Scaffold(body: _Opener(index)),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return c;
}

Finder _cell(String label) => find.bySemanticsLabel(label);

bool _selected(WidgetTester t, String label) =>
    t
        .getSemantics(_cell(label).first)
        .getSemanticsData()
        .flagsCollection
        .isSelected
        .name ==
    'isTrue';

void main() {
  testWidgets('palette tap sets the slot color, stored, recent first', (
    t,
  ) async {
    final c = await _open(t);
    expect(t.getSize(_cell('Red')), const Size(48, 48));
    await t.tap(_cell('Red'));
    await t.pumpAndSettle();
    expect(c.read(penSlotsProvider).first.color, '#e03131');
    expect(c.read(recentPenColorsProvider), ['#e03131']);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('penRecentColors'), '["#e03131"]');
    expect(sp.getString('penSlots'), contains('#e03131'));
    expect(find.text('Recent'), findsOneWidget);
  });

  testWidgets('no recent row while empty', (t) async {
    await _open(t);
    expect(find.text('Recent'), findsNothing);
  });

  testWidgets('recent: max 6, no duplicates, oldest drops', (t) async {
    final c = await _open(t);
    for (final n in [
      'Red',
      'Orange',
      'Green',
      'Teal',
      'Indigo',
      'Purple',
      'Pink',
    ]) {
      await t.tap(_cell(n).first);
      await t.pumpAndSettle();
    }
    expect(c.read(recentPenColorsProvider), hasLength(6));
    expect(c.read(recentPenColorsProvider).first, '#d6336c');
    expect(c.read(recentPenColorsProvider), isNot(contains('#e03131')));
    // Picking one already there moves it up.
    await t.tap(_cell('Orange').first);
    await t.pumpAndSettle();
    expect(c.read(recentPenColorsProvider).first, '#f76707');
    expect(c.read(recentPenColorsProvider), hasLength(6));
  });

  testWidgets('custom color: apply sets slot and recent, cancel does not', (
    t,
  ) async {
    final c = await _open(t);
    await t.tap(_cell('Custom'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.read(penSlotsProvider).first.color, '#000000');
    expect(c.read(recentPenColorsProvider), isEmpty);

    await t.tap(_cell('Custom'));
    await t.pumpAndSettle();
    await t.drag(find.byType(Slider).at(2), const Offset(200, 0));
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    final color = c.read(penSlotsProvider).first.color;
    expect(color, matches(RegExp(r'^#[0-9a-f]{6}$')));
    expect(c.read(recentPenColorsProvider), [color]);
  });

  testWidgets('a color outside the palette: named by hex, no cell picked', (
    t,
  ) async {
    final h = t.ensureSemantics();
    await _open(
      t,
      prefs: {
        'penSlots':
            '[{"tool":"pen","color":"#3a7bd5","width":2,"usePressure":true}]',
        'penRecentColors': '["#3a7bd5"]',
      },
    );
    expect(_cell('Custom color #3A7BD5'), findsOneWidget);
    expect(_selected(t, 'Black'), isFalse);
    expect(_selected(t, 'Custom'), isFalse);
    expect(_selected(t, 'Custom color #3A7BD5'), isTrue); // the recent cell
    h.dispose();
  });

  testWidgets('thickness: caption, steps by 0.1, stops at the ends', (t) async {
    final c = await _open(t);
    expect(find.text('Thickness 2.0'), findsOneWidget);
    await t.tap(find.byTooltip('Increase thickness'));
    await t.pump();
    expect(find.text('Thickness 2.1'), findsOneWidget);
    expect(c.read(penSlotsProvider).first.width, 2.1);
    await t.tap(find.byTooltip('Decrease thickness'));
    await t.pump();
    expect(c.read(penSlotsProvider).first.width, 2.0);
    IconButton btn(IconData i) =>
        t.widget<IconButton>(find.widgetWithIcon(IconButton, i));
    c.read(penSlotsProvider.notifier).setWidth(0, 0.5);
    await t.pump();
    expect(btn(Icons.chevron_left).onPressed, isNull);
    c.read(penSlotsProvider.notifier).setWidth(0, 99);
    await t.pump();
    expect(c.read(penSlotsProvider).first.width, 10);
    expect(btn(Icons.chevron_right).onPressed, isNull);
    final sl = t.widget<Slider>(find.byType(Slider));
    expect((sl.min, sl.max, sl.divisions), (0.5, 10.0, 95));
  });

  testWidgets('switch to highlighter and back: defaults, palette size', (
    t,
  ) async {
    final c = await _open(t);
    await t.tap(find.text('Highlighter'));
    await t.pumpAndSettle();
    var p = c.read(penSlotsProvider).first;
    expect(
      (p.tool, p.color, p.width, p.usePressure),
      ('highlighter', '#ffe066', 14.0, false),
    );
    expect(_cell('Sky'), findsOneWidget);
    expect(_cell('Red'), findsNothing);
    final sl = t.widget<Slider>(find.byType(Slider));
    expect((sl.min, sl.max), (4.0, 30.0));
    // Same tool again: nothing changes.
    c.read(penSlotsProvider.notifier).setWidth(0, 20);
    await t.tap(find.text('Highlighter').first);
    await t.pumpAndSettle();
    expect(c.read(penSlotsProvider).first.width, 20);
    await t.tap(find.text('Pen').first);
    await t.pumpAndSettle();
    p = c.read(penSlotsProvider).first;
    expect(
      (p.tool, p.color, p.width, p.usePressure),
      ('pen', '#000000', 2.0, true),
    );
    expect(_cell('Red'), findsOneWidget);
  });

  testWidgets('palette cells name and select for TalkBack', (t) async {
    final h = t.ensureSemantics();
    await _open(t);
    expect(_selected(t, 'Black'), isTrue);
    expect(_selected(t, 'Blue'), isFalse);
    h.dispose();
  });

  testWidgets('restart keeps the slot and the recent colors', (t) async {
    await _open(t);
    final sp = await SharedPreferences.getInstance();
    await PenSlotsStore(sp).writeRecent(['#1971c2']);
    await PenSlotsStore(sp)
        .write([PenSlotsStore(sp).read().first.withColor('#9c36b5')]);
    final s = PenSlotsStore(sp);
    expect(s.read().single.color, '#9c36b5');
    expect(s.readRecent(), ['#1971c2']);
  });
}
