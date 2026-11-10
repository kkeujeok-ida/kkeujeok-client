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

/// The 220 dp graph of the [n]th editor (centered in its column).
Rect _graph(WidgetTester t, int n) {
  final r = t.getRect(find.byType(CurveEditor).at(n));
  return Rect.fromLTWH(r.center.dx - 110, r.top, 220, 220);
}

Offset _at(Rect g, double x, double y) =>
    Offset(g.left + x * g.width, g.top + (1 - y) * g.height);

Future<void> _tapGraph(WidgetTester t, int n, double x, double y) async {
  await t.tapAt(_at(_graph(t, n), x, y));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('one column below the basic settings, no sideways scroll, '
      'presets outside, no popup', (t) async {
    await _open(t);
    expect(find.byType(CurveEditor), findsNothing);
    final bubble = t.getRect(find.byType(SingleChildScrollView).first);
    await t.tap(find.text('Advanced brush settings'));
    await t.pumpAndSettle();
    // pen without texture: width/opacity pressure + both tilts (no density)
    expect(find.byType(CurveEditor), findsNWidgets(4));
    expect(
      t.getRect(find.byType(SingleChildScrollView).first).width,
      bubble.width,
    );
    final editors = [
      for (var k = 0; k < 4; k++) t.getRect(find.byType(CurveEditor).at(k)),
    ];
    for (var k = 1; k < 4; k++) {
      expect(editors[k].left, editors[0].left);
      expect(editors[k].top, greaterThan(editors[k - 1].bottom - 1));
    }
    expect(editors[0].right, lessThanOrEqualTo(bubble.right));
    expect(find.text('Width pressure curve'), findsOneWidget);
    expect(find.text('Density pressure curve'), findsNothing);
    for (final e in t.widgetList<CurveEditor>(find.byType(CurveEditor))) {
      expect(e.pad, false);
    }
    expect(t.getSize(find.byType(CurveEditor).first).width, greaterThan(160));
    final horizontal = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(horizontal, findsNothing);
    // below the basic settings (after the switches)
    expect(
      editors[0].top,
      greaterThan(t.getRect(find.text('Draw straight lines')).bottom),
    );
    // tapping a point shows no slider
    await _tapGraph(t, 0, 0.5, 0.9);
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

  testWidgets('palette: swatches are 38 dp wide, more than 6 per row', (
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
    expect(firstRow, greaterThan(6)); // 48 dp cells fit 6 in 320
    expect(t.getSize(cells.first).width, 38);
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
    expect(rowY('Opacity'), lessThan(t.getRect(find.text('Texture')).top));
  });

  testWidgets('switch off keeps the points, on brings them back, touching '
      'an off graph turns it on', (t) async {
    final c = await _open(t);
    await t.tap(find.text('Advanced brush settings'));
    await t.pumpAndSettle();
    // all curves start off; touching the graph turns it on with the start line
    await _tapGraph(t, 0, 0.5, 0.5);
    expect(_brush(c), {
      'pressureCurve': [
        [0.0, 0.0],
        [1.0, 1.0],
      ],
    });
    // a tap off the line adds a point
    await _tapGraph(t, 0, 0.5, 0.9);
    final pts = _brush(c)!['pressureCurve'] as List;
    expect(pts.length, 3);
    expect(pts[1][1], closeTo(0.9, 0.02));
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
    await _tapGraph(t, 0, 0.8, 0.1);
    expect(_brush(c)!.containsKey('curvesOff'), false);
    expect((_brush(c)!['pressureCurve'] as List).length, 4);
    // a tilt curve starts from the constant 1
    await _tapGraph(t, 1, 0.5, 0.2);
    expect(_brush(c)!['sizeTiltCurve'], [
      [0.0, 1.0],
      closeTo2(0.5, 0.2),
      [1.0, 1.0],
    ]);
  });

  testWidgets('dragging an inner point out of the graph deletes it', (t) async {
    final c = await _open(t);
    await t.tap(find.text('Advanced brush settings'));
    await t.pumpAndSettle();
    await _tapGraph(t, 0, 0.5, 0.5); // on
    await _tapGraph(t, 0, 0.5, 0.9); // add
    expect((_brush(c)!['pressureCurve'] as List).length, 3);
    final g = _graph(t, 0);
    final gest = await t.startGesture(_at(g, 0.5, 0.9));
    await gest.moveTo(_at(g, 0.5, 0.9) + const Offset(0, -260));
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
    await _tapGraph(t, 0, 0.5, 0.5);
    await _tapGraph(t, 0, 0.5, 0.9);
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
