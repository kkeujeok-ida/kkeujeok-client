import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/pen.dart';
import 'package:kkeujeok/storage/pen_slots_store.dart';
import 'package:kkeujeok/storage/session_hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs(Map<String, Object> v) async {
  SharedPreferences.setMockInitialValues(v);
  return SharedPreferences.getInstance();
}

const _hl = Pen(
  tool: 'highlighter',
  color: '#ffe066',
  width: 14,
  usePressure: false,
);

String _slot(String tool, String color, num width, Object up) => jsonEncode({
  'tool': tool,
  'color': color,
  'width': width,
  'usePressure': up,
});

void main() {
  test('nothing stored: the three default slots', () async {
    final s = PenSlotsStore(await _prefs({}));
    expect(s.read().map((p) => p.color), ['#000000', '#1971c2', '#ffe066']);
    expect(s.read().map((p) => p.tool), ['pen', 'pen', 'highlighter']);
    expect(s.read()[2].usePressure, isFalse);
  });

  test('write round-trips through a new store (restart)', () async {
    final p = await _prefs({});
    await PenSlotsStore(p).write([defaultPen.withUsePressure(false), _hl]);
    final back = PenSlotsStore(p).read();
    expect(back, hasLength(2));
    expect(back[0].usePressure, isFalse);
    expect(back[0].width, 2.0);
    expect(back[0].colorNameKey, 'black');
    expect(back[1].tool, 'highlighter');
    expect(back[1].width, 14.0);
    expect(back[1].colorNameKey, 'yellow');
  });

  test('a one-slot list saved before 5.2 (no tool) is a pen', () async {
    final s = PenSlotsStore(
      await _prefs({
        'penSlots': '[{"color":"#000000","width":2.0,"usePressure":false}]',
      }),
    );
    expect(s.read().single.tool, 'pen');
    expect(s.read().single.usePressure, isFalse);
  });

  for (final bad in [
    'not json',
    '{}',
    '[]',
    '[1]',
    '[{"color":"red","width":2,"usePressure":true}]',
    '[{"color":"#000000","width":99,"usePressure":true}]',
    '[{"color":"#000000","width":2,"usePressure":"yes"}]',
    '[${_slot('eraser', '#000000', 2, true)}]',
    '[${_slot('pen', '#000000', 14, true)}]', // too wide for a pen
    '[${_slot('highlighter', '#ffe066', 2, false)}]', // too thin
    '[${List.filled(13, _slot('pen', '#000000', 2, true)).join(',')}]',
  ]) {
    test('corrupt value $bad falls back to the default', () async {
      final s = PenSlotsStore(await _prefs({'penSlots': bad}));
      expect(s.read(), hasLength(3));
      expect(s.read().first.color, '#000000');
    });
  }

  test('12 slots are valid', () async {
    final s = PenSlotsStore(
      await _prefs({
        'penSlots':
            '[${List.filled(12, _slot('pen', '#000000', 2, true)).join(',')}]',
      }),
    );
    expect(s.read(), hasLength(12));
  });

  test('a wrong-typed value does not throw', () async {
    final s = PenSlotsStore(await _prefs({'penSlots': 5}));
    expect(s.read(), hasLength(3));
  });

  test('without preferences the session value is kept', () async {
    final s = PenSlotsStore(null);
    await s.write([defaultPen.withUsePressure(false)]);
    expect(s.read().single.usePressure, isFalse);
  });

  test('stored JSON has tool, color, width, usePressure', () async {
    final p = await _prefs({});
    await PenSlotsStore(p).write([defaultPen.withUsePressure(false)]);
    expect(jsonDecode(p.getString('penSlots')!), [
      {'tool': 'pen', 'color': '#000000', 'width': 2.0, 'usePressure': false},
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

  test('log out (SessionHint clear) keeps the slots', () async {
    final p = await _prefs({});
    await PenSlotsStore(p).write([defaultPen, _hl]);
    await SessionHint(p).set(false);
    expect(PenSlotsStore(p).read(), hasLength(2));
  });
}
