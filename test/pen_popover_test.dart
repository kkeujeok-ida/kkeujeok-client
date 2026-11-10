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
  bubbleTests();
  testWidgets('palette tap sets the slot color, stored, recent first', (
    t,
  ) async {
    final c = await _open(t);
    expect(t.getSize(_cell('Red')), const Size(38, 48));
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

  testWidgets(
    'recent colors are left-aligned; pen palette starts black, green, blue, red, yellow',
    (t) async {
      await _open(t, prefs: {'penRecentColors': '["#e03131"]'});
      expect(_cell('Red').evaluate().length, 2);
      final black = t.getTopLeft(_cell('Black').first).dx;
      expect(t.getTopLeft(_cell('Red').last).dx, black);
      expect(
        t.getTopLeft(find.bySemanticsLabel('Black').first).dx,
        lessThan(t.getTopLeft(_cell('Green').first).dx),
      );
      expect(
        t.getTopLeft(_cell('Blue').first).dx,
        lessThan(t.getTopLeft(_cell('Red').first).dx),
      );
    },
  );

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
    await t.tapAt(
      t.getCenter(
            find.byWidgetPredicate(
              (w) =>
                  w is CustomPaint &&
                  '${w.painter.runtimeType}' == '_WheelPainter',
            ),
          ) +
          const Offset(30, 20),
    );
    await t.pump();
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    final color = c.read(penSlotsProvider).first.color;
    expect(color, matches(RegExp(r'^#[0-9a-f]{6}$')));
    expect(color, isNot('#000000'));
    expect(c.read(recentPenColorsProvider), [color]);

    await t.tap(_cell('Custom'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '#1971C2');
    await t.enterText(find.byType(TextField), '#1971c'); // rejected
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    expect(c.read(penSlotsProvider).first.color, '#1971c2');
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
    expect(find.text('2.0'), findsOneWidget);
    await t.tap(find.byTooltip('Increase thickness'));
    await t.pump();
    expect(find.text('2.1'), findsOneWidget);
    expect(c.read(penSlotsProvider).first.width, 2.1);
    await t.tap(find.byTooltip('Decrease thickness'));
    await t.pump();
    expect(c.read(penSlotsProvider).first.width, 2.0);
    IconButton btn(IconData i) =>
        t.widget<IconButton>(find.widgetWithIcon(IconButton, i).first);
    c.read(penSlotsProvider.notifier).setWidth(0, 0.5);
    await t.pump();
    expect(btn(Icons.chevron_left).onPressed, isNull);
    c.read(penSlotsProvider.notifier).setWidth(0, 99);
    await t.pump();
    expect(c.read(penSlotsProvider).first.width, 10);
    expect(btn(Icons.chevron_right).onPressed, isNull);
    final sl = t.widget<Slider>(find.byType(Slider).first);
    expect((sl.min, sl.max, sl.divisions), (0.5, 10.0, 95));
  });

  testWidgets('switch to highlighter and back: defaults, palette size', (
    t,
  ) async {
    final c = await _open(t);
    await t.tap(find.bySemanticsLabel('Highlighter'));
    await t.pumpAndSettle();
    var p = c.read(penSlotsProvider).first;
    expect(
      (p.tool, p.color, p.width, p.usePressure),
      ('highlighter', '#ffe066', 14.0, false),
    );
    expect(_cell('Sky'), findsOneWidget);
    expect(_cell('Red'), findsNothing);
    final sl = t.widget<Slider>(find.byType(Slider).first);
    expect((sl.min, sl.max), (4.0, 30.0));
    // Same tool again: the width goes back to the default (pen.switchKind).
    c.read(penSlotsProvider.notifier).setWidth(0, 20);
    await t.tap(find.bySemanticsLabel('Highlighter').first);
    await t.pumpAndSettle();
    expect(c.read(penSlotsProvider).first.width, 14);
    await t.tap(find.bySemanticsLabel('Pen').first);
    await t.pumpAndSettle();
    p = c.read(penSlotsProvider).first;
    expect(
      (p.tool, p.color, p.width, p.usePressure),
      ('pen', '#000000', 2.0, true),
    );
    expect(_cell('Red'), findsOneWidget);
  });

  testWidgets('kind buttons switch the slot kind and it is stored', (t) async {
    final c = await _open(t);
    await t.tap(find.bySemanticsLabel('Fountain pen'));
    await t.pumpAndSettle();
    var p = c.read(penSlotsProvider).first;
    expect(
      (p.tool, p.color, p.width, p.usePressure),
      ('fountain', '#000000', 1.5, true),
    );
    final sl = t.widget<Slider>(find.byType(Slider).first);
    expect((sl.min, sl.max), (0.5, 8.0));
    expect(_cell('Red'), findsOneWidget); // the pen palette
    await t.tap(_cell('Red'));
    await t.tap(find.bySemanticsLabel('Answer tape'));
    await t.pumpAndSettle();
    p = c.read(penSlotsProvider).first;
    expect(
      (p.tool, p.color, p.width, p.usePressure),
      ('tape', '#ffe066', 20.0, false), // red is not in the highlighter palette
    );
    expect(_cell('Sky'), findsOneWidget);
    // Restart: the stored slot reads back, the other two are as before.
    final slots = PenSlotsStore(await SharedPreferences.getInstance()).read();
    expect(slots.map((e) => e.tool), ['tape', 'pen', 'highlighter']);
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

PenBubbleAnchor _a(Rect tool, Rect bar, {bool vertical = false}) =>
    PenBubbleAnchor(tool, bar, vertical: vertical);

void bubbleTests() {
  const win = Size(400, 800);
  const bub = Size(320, 400);
  group('placePenBubble', () {
    test('top bar: below it, tail under the tool', () {
      final p = placePenBubble(
        _a(
          const Rect.fromLTWH(100, 12, 48, 48),
          const Rect.fromLTWH(20, 12, 360, 48),
        ),
        bub,
        win,
      );
      expect(p.side, AxisDirection.down);
      expect(p.topLeft.dy, 60 + penBubbleGap);
      expect(p.topLeft.dx + p.tail!, 124); // the tool's centre
    });
    test('bottom bar: above it', () {
      final p = placePenBubble(
        _a(
          const Rect.fromLTWH(180, 740, 48, 48),
          const Rect.fromLTWH(20, 740, 360, 48),
        ),
        bub,
        win,
      );
      expect(p.side, AxisDirection.up);
      expect(p.topLeft.dy + bub.height + penBubbleGap, 740);
    });
    test('vertical: left bar opens right, right bar opens left', () {
      final l = placePenBubble(
        _a(
          const Rect.fromLTWH(12, 300, 48, 48),
          const Rect.fromLTWH(12, 100, 48, 500),
          vertical: true,
        ),
        bub,
        win,
      );
      expect(l.side, AxisDirection.right);
      expect(l.topLeft.dx, 60 + penBubbleGap);
      final r = placePenBubble(
        _a(
          const Rect.fromLTWH(340, 300, 48, 48),
          const Rect.fromLTWH(340, 100, 48, 500),
          vertical: true,
        ),
        bub,
        win,
      );
      expect(r.side, AxisDirection.left);
      expect(r.topLeft.dx + bub.width + penBubbleGap, 340);
    });
    test('edge tool: bubble stays on screen, tail still at the tool', () {
      final p = placePenBubble(
        _a(
          const Rect.fromLTWH(352, 12, 48, 48),
          const Rect.fromLTWH(20, 12, 380, 48),
        ),
        bub,
        win,
      );
      expect(
        p.topLeft.dx + bub.width,
        lessThanOrEqualTo(win.width - penBubbleMargin),
      );
      expect(p.topLeft.dx + p.tail!, 376);
      final v = placePenBubble(
        _a(
          const Rect.fromLTWH(12, 760, 48, 48),
          const Rect.fromLTWH(12, 300, 48, 500),
          vertical: true,
        ),
        bub,
        win,
      );
      expect(
        v.topLeft.dy + bub.height,
        lessThanOrEqualTo(win.height - penBubbleMargin),
      );
      expect(v.topLeft.dy + v.tail!, 776); // clamped 16 off the bubble corner
    });
    test('tall bubble pulled over the bar: no tail', () {
      final p = placePenBubble(
        _a(
          const Rect.fromLTWH(100, 12, 48, 48),
          const Rect.fromLTWH(20, 12, 360, 48),
        ),
        const Size(320, 760),
        win,
      );
      expect(p.tail, isNull);
    });
  });
}
