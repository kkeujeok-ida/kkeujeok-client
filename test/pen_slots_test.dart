import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/storage/pen_slots_store.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The toolbar wired to the providers the way the editor does it.
class _Harness extends ConsumerWidget {
  const _Harness({this.maxSlotsWidth = double.infinity});

  final double maxSlotsWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(penSlotsProvider.notifier);
    return Align(
      alignment: Alignment.topCenter,
      child: PenToolbar(
        slots: ref.watch(penSlotsProvider),
        selectedSlot: ref.watch(selectedPenSlotProvider),
        maxSlotsWidth: maxSlotsWidth,
        onSlotTap: n.select,
        onAdd: n.add,
        onMove: n.move,
      ),
    );
  }
}

Future<ProviderContainer> _pump(
  WidgetTester t, {
  double width = 1000,
  double maxSlotsWidth = double.infinity,
  Map<String, Object> prefs = const {},
}) async {
  t.view.physicalSize = Size(width, 700);
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
        home: Scaffold(
          body: _Harness(maxSlotsWidth: maxSlotsWidth),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return c;
}

Finder _slot(String label) => find.bySemanticsLabel(label);

void main() {
  testWidgets('first run: black pen, blue pen, yellow highlighter', (t) async {
    final h = t.ensureSemantics();
    final c = await _pump(t);
    expect(_slot('Pen, Black, width 2.0'), findsOneWidget);
    expect(_slot('Pen, Blue, width 2.0'), findsOneWidget);
    expect(_slot('Highlighter, Yellow, width 14.0'), findsOneWidget);
    expect(c.read(selectedPenSlotProvider), 0);
    final sel = t
        .getSemantics(_slot('Pen, Black, width 2.0'))
        .getSemanticsData();
    expect(sel.flagsCollection.isSelected.name, 'isTrue');
    expect(t.getSize(_slot('Pen, Blue, width 2.0')).width, 48);
    expect(find.text('2.0'), findsNWidgets(2));
    expect(find.text('14.0'), findsOneWidget);
    h.dispose();
  });

  testWidgets('tap switches the selected slot', (t) async {
    final c = await _pump(t);
    await t.tap(_slot('Highlighter, Yellow, width 14.0'));
    await t.pump();
    expect(c.read(selectedPenSlotProvider), 2);
  });

  testWidgets('[+] copies the selected slot to the end and selects it', (
    t,
  ) async {
    final c = await _pump(t);
    await t.tap(_slot('Pen, Blue, width 2.0'));
    await t.tap(find.byTooltip('Add pen slot'));
    await t.pumpAndSettle();
    final slots = c.read(penSlotsProvider);
    expect(slots, hasLength(4));
    expect(slots.last.color, '#1971c2');
    expect(c.read(selectedPenSlotProvider), 3);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('penSlots'), contains('#1971c2'));
  });

  testWidgets('[+] at 12 slots still adds; no limit', (t) async {
    final c = await _pump(t, width: 1500);
    for (var i = 0; i < 9; i++) {
      c.read(penSlotsProvider.notifier).add();
    }
    await t.pumpAndSettle();
    expect(c.read(penSlotsProvider), hasLength(12));
    await t.tap(find.byTooltip('Add pen slot'));
    await t.pump();
    expect(c.read(penSlotsProvider), hasLength(13));
  });

  testWidgets('long press then drag reorders; the same slot stays picked', (
    t,
  ) async {
    final c = await _pump(t);
    final from = t.getCenter(_slot('Pen, Black, width 2.0'));
    final to = t.getCenter(_slot('Highlighter, Yellow, width 14.0'));
    final g = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 600));
    for (var k = 1; k <= 10; k++) {
      await g.moveTo(Offset.lerp(from, to + const Offset(20, 0), k / 10)!);
      await t.pump(const Duration(milliseconds: 50));
    }
    await g.up();
    await t.pumpAndSettle();
    expect(c.read(penSlotsProvider).map((p) => p.color), [
      '#1971c2',
      '#ffe066',
      '#000000',
    ]);
    expect(c.read(selectedPenSlotProvider), 2); // the black pen moved to 2
  });

  testWidgets('dropped outside the toolbar: back where it was', (t) async {
    final c = await _pump(t);
    final from = t.getCenter(_slot('Pen, Black, width 2.0'));
    final g = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 600));
    await g.moveTo(const Offset(500, 450));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(c.read(penSlotsProvider), hasLength(3));
    expect(c.read(penSlotsProvider).first.color, '#000000');
  });

  testWidgets('custom actions move a slot (TalkBack)', (t) async {
    final h = t.ensureSemantics();
    final c = await _pump(t);
    final data = t
        .getSemantics(_slot('Pen, Black, width 2.0'))
        .getSemanticsData();
    expect(data.customSemanticsActionIds, hasLength(1)); // later only
    final id = data.customSemanticsActionIds!.single;
    // ignore: deprecated_member_use
    t.binding.pipelineOwner.semanticsOwner!.performAction(
      t.getSemantics(_slot('Pen, Black, width 2.0')).id,
      SemanticsAction.customAction,
      id,
    );
    await t.pumpAndSettle();
    expect(c.read(penSlotsProvider).first.color, '#1971c2');
    expect(c.read(selectedPenSlotProvider), 1);
    h.dispose();
  });

  testWidgets('overflow: only the slot area scrolls; arrows and fade', (
    t,
  ) async {
    final c = await _pump(t, width: 1500, maxSlotsWidth: 150);
    for (var i = 0; i < 6; i++) {
      c.read(penSlotsProvider.notifier).add();
    }
    await t.pumpAndSettle();
    // Adding selected the last slot and scrolled it into view.
    expect(find.byTooltip('Show earlier slots'), findsOneWidget);
    expect(find.byTooltip('Show later slots'), findsNothing);
    c.read(penSlotsProvider.notifier).select(0);
    await t.pumpAndSettle();
    expect(find.byTooltip('Show later slots'), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    final undoAt = t.getTopLeft(find.byTooltip('Undo'));
    await t.tap(find.byTooltip('Show later slots'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Show earlier slots'), findsOneWidget);
    // Controls outside the slot area did not move.
    expect(t.getTopLeft(find.byTooltip('Undo')), undoAt);
    expect(t.getSize(find.byTooltip('Add pen slot')).width, 48);
  });

  test('notifier: remove keeps the selection on the same slot', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [penSlotsStoreProvider.overrideWithValue(PenSlotsStore(sp))],
    );
    addTearDown(c.dispose);
    final n = c.read(penSlotsProvider.notifier);
    n.select(2);
    final gone = n.remove(0)!;
    expect(c.read(selectedPenSlotProvider), 1); // still the highlighter
    expect(c.read(penSlotsProvider).last.tool, 'highlighter');
    n.restore(0, gone.pen, gone.selected);
    expect(c.read(penSlotsProvider).first.color, '#000000');
    expect(c.read(selectedPenSlotProvider), 2);
    // The selected slot removed: the next one takes its place; last -> last.
    n.remove(2);
    expect(c.read(selectedPenSlotProvider), 1);
    n.remove(1);
    expect(c.read(selectedPenSlotProvider), 0);
    expect(n.remove(0), isNull); // the last slot stays
    await Future<void>.delayed(Duration.zero);
    expect(PenSlotsStore(sp).read(), hasLength(1));
  });
}
