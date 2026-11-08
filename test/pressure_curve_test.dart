import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/pressure_curve.dart';
import 'package:kkeujeok/render/stroke_outline.dart';
import 'package:kkeujeok/storage/pressure_curve_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('invalid values count as normal', () {
    expect(PressureCurve.fromJson([0.8, 0.1, 0.2, 0.5]), PressureCurve.normal);
    expect(PressureCurve.fromJson([2, 0, 0, 0]), PressureCurve.normal);
    expect(PressureCurve.fromJson([0.3, 0.6, 0.6]), PressureCurve.normal);
    expect(PressureCurve.fromJson('bogus'), PressureCurve.normal);
    expect(PressureCurve.fromJson([0.2, 0.4, 0.5, 0.8]), PressureCurve.soft);
    expect(PressureCurve.soft.q(0), 0);
  });

  test('store: remembered, bad value is normal, default normal', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = PressureCurveStore(prefs);
    expect(store.read(), PressureCurve.normal);
    await store.write(PressureCurve.firm);
    expect(PressureCurveStore(prefs).read(), PressureCurve.firm);
    await store.write(PressureCurve.fromValues([0.1, 0.2, 0.3, 0.4, 0.9, 0.9]));
    expect(store.read().values, [0.1, 0.2, 0.3, 0.4, 0.9, 0.9]);
    await prefs.setString('pressureCurve', '[0.9,0,0.1,0]');
    expect(store.read(), PressureCurve.normal);
    await prefs.setString('pressureCurve', 'not json');
    expect(store.read(), PressureCurve.normal);
  });

  test('curve changes width; off and mouse (all 0.5) do not', () {
    List pts(double p) => [for (var i = 0; i < 5; i++) [i * 5.0, 0.0, p, i]];
    final a = strokeOutline(4, true, pts(0.3875), PressureCurve.normal);
    expect(strokeOutline(4, true, pts(0.3875), PressureCurve.soft), isNot(a));
    expect(
      strokeOutline(4, false, pts(0.3875), PressureCurve.soft),
      strokeOutline(4, false, pts(0.3875), PressureCurve.firm),
    );
    expect(
      strokeOutline(4, true, pts(0.5), PressureCurve.soft),
      strokeOutline(4, true, pts(0.5), PressureCurve.firm),
    );
  });
}
