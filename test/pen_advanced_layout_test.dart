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
  t.view.physicalSize = const Size(1800, 3200);
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

Map? _brush(ProviderContainer c) => c.read(penSlotsProvider)[0].brush;

/// The graph box of the [n]th editor (scaled down when the column is narrow).
Rect _graph(WidgetTester t, int n) => t.getRect(
  find
      .descendant(
        of: find.byType(CurveEditor).at(n),
        matching: find.byType(CustomPaint),
      )
      .first,
);

Offset _at(Rect g, double x, double y) =>
    Offset(g.left + x * g.width, g.top + (1 - y) * g.height);

Future<void> _tapGraph(WidgetTester t, int n, double x, double y) async {
  await t.tapAt(_at(_graph(t, n), x, y));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('curves beside the bubble, two a row, scrolling up and down, '
      'presets in one column, no popup', (t) async {
    await _open(t);
    expect(find.byType(CurveEditor), findsNothing);
    final bubble = t.getRect(find.byType(SingleChildScrollView).first);
    await t.tap(find.text('Advanced brush settings'));
    await t.pumpAndSettle();
    // pen without texture: width/opacity pressure + both tilts (no density)
    expect(find.byType(CurveEditor), findsNWidgets(4));
    final editors = [
      for (var k = 0; k < 4; k++) t.getRect(find.byType(CurveEditor).at(k)),
    ];
    expect(editors[0].top, editors[1].top);
    expect(editors[2].top, editors[3].top);
    expect(editors[2].top, greaterThan(editors[0].bottom - 1));
    expect(editors[0].left, greaterThan(bubble.right));
    expect(find.text('Width pressure curve'), findsOneWidget);
    expect(find.text('Density pressure curve'), findsNothing);
    for (final e in t.widgetList<CurveEditor>(find.byType(CurveEditor))) {
      expect(e.pad, false);
    }
    final horizontal = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(horizontal, findsNothing);
    // tapping a point shows no slider
    await _tapGraph(t, 0, 0.5, 0.5);
    expect(
      find.descendant(
        of: find.byType(CurveEditor),
        matching: find.byType(Slider),
      ),
      findsNothing,
    );
    final save = find.widgetWithText(ActionChip, 'Save preset');
    expect(t.getTopLeft(save).dx, greaterThan(bubble.right));
  });

  testWidgets('palette: cells are 37 dp, 8 per row', (
    t,
  ) async {
    await _open(t);
    final wrap = find
        .ancestor(of: find.bySemanticsLabel('Red'), matching: find.byType(Wrap))
        .first;
    final cells = find.descendant(of: wrap, matching: find.byType(InkWell));
    final tops = <double>[
      for (var k = 0; k < t.widgetList(cells).length; k++)
        t.getTopLeft(cells.at(k)).dy,
    ];
    final firstRow = tops.where((y) => y == tops.first).length;
    expect(firstRow, 8);
    expect(t.getSize(cells.first).width, 37);
  });

  testWidgets('basic rows: one line, advanced button top right', (t) async {
    await _open(t);
    final name = t.getRect(find.text('Pen').last);
    final btn = t.getRect(find.text('Advanced brush settings'));
    expect((btn.center.dy - name.center.dy).abs(), lessThan(8));
    expect(btn.left, greaterThan(name.right));
    double rowY(String label) => t.getRect(find.text(label)).center.dy;
    for (final l in ['Width', 'Opacity']) {
      final row = find
          .ancestor(of: find.text(l), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: row, matching: find.byType(Slider)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byType(IconButton)),
        findsNWidgets(2),
      );
    }
    expect(rowY('Opacity'), greaterThan(rowY('Width')));
    expect(find.text('Texture'), findsNothing);
    expect(find.text('Density'), findsNothing);
  });

  testWidgets('switch off keeps the points, on brings them back, touching '
      'an off graph turns it on', (t) async {
    final c = await _open(t);
    await t.tap(find.text('Advanced brush settings'));
    await t.pumpAndSettle();
    // all curves start off; touching the graph turns it on with the start
    // line; a touch beside the line adds no point
    await _tapGraph(t, 0, 0.5, 0.9);
    expect(_brush(c), {
      'pressureCurve': [
        [0.0, 0.0],
        [1.0, 1.0],
      ],
    });
    // a tap on the line adds a point
    await _tapGraph(t, 0, 0.5, 0.5);
    final pts = _brush(c)!['pressureCurve'] as List;
    expect(pts.length, 3);
    expect(pts[1][1], closeTo(0.5, 0.02));
    // off: name added, points stay
    await t.tap(find.text('Width pressure curve'));
    await t.pumpAndSettle();
    expect(_brush(c)!['curvesOff'], ['pressure']);
    expect(_brush(c)!['pressureCurve'], pts);
    // on again: name gone, same points
    await t.tap(find.text('Width pressure curve'));
    await t.pumpAndSettle();
    expect(_brush(c)!.containsKey('curvesOff'), false);
    expect(_brush(c)!['pressureCurve'], pts);
    // off, then a touch on the graph turns it on again and edits
    await t.tap(find.text('Width pressure curve'));
    await t.pumpAndSettle();
    await _tapGraph(t, 0, 0.8, 0.8);
    expect(_brush(c)!.containsKey('curvesOff'), false);
    expect((_brush(c)!['pressureCurve'] as List).length, 4);
    // a tilt curve starts from the constant 1
    await _tapGraph(t, 1, 0.5, 0.97);
    expect(_brush(c)!['sizeTiltCurve'], [
      [0.0, 1.0],
      closeTo2(0.5, 1.0),
      [1.0, 1.0],
    ]);
  });

  testWidgets('dragging an inner point out of the graph deletes it', (t) async {
    final c = await _open(t);
    await t.tap(find.text('Advanced brush settings'));
    await t.pumpAndSettle();
    await _tapGraph(t, 0, 0.5, 0.9); // on
    await _tapGraph(t, 0, 0.5, 0.5); // add, on the line
    expect((_brush(c)!['pressureCurve'] as List).length, 3);
    final g = _graph(t, 0);
    final gest = await t.startGesture(_at(g, 0.5, 0.5));
    await gest.moveTo(_at(g, 0.5, 0.5) + const Offset(0, -400));
    await gest.up();
    await t.pumpAndSettle();
    expect((_brush(c)!['pressureCurve'] as List).length, 2);
  });

  testWidgets('highlighter: width curve only; tape: no advanced', (t) async {
    final c = await _open(t);
    await c.read(penSlotsProvider.notifier).setTool(0, 'highlighter');
    await t.pumpAndSettle();
    await t.tap(find.text('Advanced brush settings'));
    await t.pumpAndSettle();
    expect(find.byType(CurveEditor), findsOneWidget);
    expect(find.text('Width pressure curve'), findsOneWidget);
    await c.read(penSlotsProvider.notifier).setTool(0, 'tape');
    await t.pumpAndSettle();
    expect(find.text('Advanced brush settings'), findsNothing);
    expect(find.byType(CurveEditor), findsNothing);
  });

  testWidgets('preset round trip keeps curves and curvesOff; chips are '
      'capsules', (t) async {
    final c = await _open(t);
    await t.tap(find.text('Advanced brush settings'));
    await t.pumpAndSettle();
    await _tapGraph(t, 0, 0.5, 0.9);
    await _tapGraph(t, 0, 0.5, 0.5);
    await t.tap(find.text('Width pressure curve'));
    await t.pumpAndSettle();
    final before = Map.of(_brush(c)!);
    final save = find.widgetWithText(ActionChip, 'Save preset');
    expect(t.widget<ActionChip>(save).shape, isA<StadiumBorder>());
    await t.tap(save);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Mine');
    await t.tap(find.text('Save preset').last);
    await t.pumpAndSettle();
    final chip = find.widgetWithText(ActionChip, 'Mine');
    expect(t.widget<ActionChip>(chip).shape, isA<StadiumBorder>());
    final sp = await SharedPreferences.getInstance();
    final saved = parsePresets(sp.getString('brushPresets')).single;
    expect(saved.brush, before);
    await c.read(penSlotsProvider.notifier).setBrush(0, null);
    await t.pumpAndSettle();
    await t.tap(chip);
    await t.pumpAndSettle();
    expect(_brush(c), before);

    await t.longPress(chip);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete preset'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, 'Mine'), findsNothing);
  });
}

/// Matches a 2-number point near ([x], [y]).
Matcher closeTo2(double x, double y) => predicate(
  (p) =>
      p is List &&
      p.length == 2 &&
      (p[0] - x).abs() < 0.02 &&
      (p[1] - y).abs() < 0.02,
  'point near ($x, $y)',
);
