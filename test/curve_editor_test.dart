import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/pressure_curve.dart';
import 'package:kkeujeok/ui/curve_editor.dart';

const _labels = (
  graph: 'graph',
  input: 'in',
  output: 'out',
  pad: 'pad',
  add: 'add',
  remove: 'remove',
  reset: 'reset',
);

Widget _host(PressureCurve c, List<PressureCurve> log, {int? fixed}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CurveEditor(
            curve: c,
            onChanged: log.add,
            labels: _labels,
            fixedCount: fixed,
            onReset: fixed == null ? () {} : null,
          ),
        ),
      ),
    );

void main() {
  testWidgets('screen reader increase moves the point; keys move it too', (
    t,
  ) async {
    final log = <PressureCurve>[];
    final c = PressureCurve.fromValues([0.2, 0.4, 0.5, 0.8]);
    await t.pumpWidget(_host(c, log));
    final h = t.ensureSemantics();
    final node = t.getSemantics(find.bySemanticsLabel('graph 1'));
    expect(node.value, contains('out 0.40'));
    t.semantics.increase(find.semantics.byLabel('graph 1'));
    await t.pump();
    expect(log.last.values[1], closeTo(0.45, 1e-9));
    h.dispose();
  });

  testWidgets('fixedCount hides add and remove', (t) async {
    await t.pumpWidget(
      _host(PressureCurve.fromValues([0.2, 0.4, 0.5, 0.8]), [], fixed: 2),
    );
    expect(find.text('add'), findsNothing);
    expect(find.text('remove'), findsNothing);
  });

  testWidgets('default shows add, remove, reset; arrow key nudges', (t) async {
    final log = <PressureCurve>[];
    await t.pumpWidget(
      _host(PressureCurve.fromValues([0.2, 0.4, 0.5, 0.8]), log),
    );
    expect(find.text('add'), findsOneWidget);
    expect(find.text('reset'), findsOneWidget);
    // focus the first point and press an arrow key
    final first = find
        .descendant(of: find.byType(CurveEditor), matching: find.byType(Focus))
        .first;
    Focus.of(
      t.element(
        find.descendant(of: first, matching: find.byType(Semantics)).first,
      ),
    ).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(log, isNotEmpty);
    expect(log.last.values[1], closeTo(0.41, 1e-9));
  });
}
