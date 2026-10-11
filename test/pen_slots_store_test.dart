import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/pen.dart';
import 'package:kkeujeok/storage/pen_slots_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs(Map<String, Object> v) async {
  SharedPreferences.setMockInitialValues(v);
  return SharedPreferences.getInstance();
}

void main() {
  test('nothing stored: the default slots', () async {
    final s = PenSlotsStore(await _prefs({}));
    expect(s.read().single.usePressure, isTrue);
    expect(s.read().single.color, '#000000');
  });

  test('write round-trips through a new store (restart)', () async {
    final p = await _prefs({});
    await PenSlotsStore(p).write([defaultPen.withUsePressure(false)]);
    final back = PenSlotsStore(p).read().single;
    expect(back.usePressure, isFalse);
    expect(back.width, 2.0);
    expect(back.colorNameKey, 'black');
  });

  for (final bad in [
    'not json',
    '{}',
    '[]',
    '[1]',
    '[{"color":"red","width":2,"usePressure":true}]',
    '[{"color":"#000000","width":99,"usePressure":true}]',
    '[{"color":"#000000","width":2,"usePressure":"yes"}]',
  ]) {
    test('corrupt value $bad falls back to the default', () async {
      final s = PenSlotsStore(await _prefs({'penSlots': bad}));
      expect(s.read().single.usePressure, isTrue);
    });
  }

  test('a wrong-typed value does not throw', () async {
    final s = PenSlotsStore(await _prefs({'penSlots': 5}));
    expect(s.read().single.usePressure, isTrue);
  });

  test('without preferences the session value is kept', () async {
    final s = PenSlotsStore(null);
    await s.write([defaultPen.withUsePressure(false)]);
    expect(s.read().single.usePressure, isFalse);
  });

  test('stored JSON has color, width, usePressure', () async {
    final p = await _prefs({});
    await PenSlotsStore(p).write([defaultPen.withUsePressure(false)]);
    expect(jsonDecode(p.getString('penSlots')!), [
      {'color': '#000000', 'width': 2.0, 'usePressure': false},
    ]);
  });

  test('rapid writes persist the last value', () async {
    final p = await _prefs({});
    final s = PenSlotsStore(p);
    final done = [
      s.write([defaultPen.withUsePressure(false)]),
      s.write([defaultPen.withUsePressure(true)]),
      s.write([defaultPen.withUsePressure(false)]),
    ];
    await Future.wait(done);
    expect(PenSlotsStore(p).read().single.usePressure, isFalse);
    expect(s.read().single.usePressure, isFalse);
  });
}
