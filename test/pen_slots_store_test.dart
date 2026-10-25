import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/eraser.dart';
import 'package:kkeujeok/model/pen.dart';
import 'package:kkeujeok/model/pen_only.dart';
import 'package:kkeujeok/model/toolbar_pos.dart';
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

  group('recent colors', () {
    test('round-trips and survives log out', () async {
      final p = await _prefs({});
      await PenSlotsStore(p).writeRecent(['#e03131', '#000000']);
      await SessionHint(p).set(false);
      expect(PenSlotsStore(p).readRecent(), ['#e03131', '#000000']);
    });

    test('nothing, broken or more than 6 reads as empty', () async {
      expect(PenSlotsStore(await _prefs({})).readRecent(), isEmpty);
      for (final bad in [
        'nope',
        '{"a":1}',
        '["red"]',
        '[1]',
        jsonEncode(List.filled(7, '#000000')),
      ]) {
        final p = await _prefs({'penRecentColors': bad});
        expect(PenSlotsStore(p).readRecent(), isEmpty, reason: bad);
      }
    });
  });

  group('eraser settings', () {
    test('defaults, round trip, session survives log out', () async {
      final p = await _prefs({});
      final s = PenSlotsStore(p);
      expect(s.readEraser(), const EraserSettings());
      const next = EraserSettings(mode: EraserMode.partial, returnToPen: true);
      await s.writeEraser(next);
      await SessionHint(p).set(false);
      expect(PenSlotsStore(p).readEraser(), next);
    });

    test('broken values read as defaults', () async {
      final p = await _prefs({'eraserMode': 'x', 'eraserReturnToPen': 'yes'});
      expect(PenSlotsStore(p).readEraser(), const EraserSettings());
    });
  });

  group('pen only settings', () {
    test('defaults, round trip, session survives log out', () async {
      final p = await _prefs({});
      final s = PenSlotsStore(p);
      expect(s.readPenOnly(), PenOnlyMode.auto);
      expect(s.readStylusSeen(), isFalse);
      await s.writePenOnly(PenOnlyMode.off);
      await s.writeStylusSeen(true);
      await SessionHint(p).set(false);
      final back = PenSlotsStore(p);
      expect(back.readPenOnly(), PenOnlyMode.off);
      expect(back.readStylusSeen(), isTrue);
    });

    test('broken values read as defaults', () async {
      final p = await _prefs({'penOnlyMode': 'x', 'stylusSeen': 'yes'});
      expect(PenSlotsStore(p).readPenOnly(), PenOnlyMode.auto);
      expect(PenSlotsStore(p).readStylusSeen(), isFalse);
    });
  });
  group('toolbar position', () {
    test('default, round trip (restart), session value wins', () async {
      final p = await _prefs({});
      final s = PenSlotsStore(p);
      expect(s.readToolbar(), ToolbarPos.defaults);
      final pos = ToolbarPos.floating(0.25, 0.75, vertical: true);
      await s.writeToolbar(pos);
      expect(PenSlotsStore(p).readToolbar(), pos);
      final left = const ToolbarPos().applyDock(ToolbarDock.left);
      await s.writeToolbar(left);
      await s.writeToolbar(pos);
      expect(PenSlotsStore(p).readToolbar(), pos); // writes keep their order
      expect(PenSlotsStore(null).readToolbar(), ToolbarPos.defaults);
      final noDisk = PenSlotsStore(null);
      await noDisk.writeToolbar(left);
      expect(noDisk.readToolbar(), left);
    });

    test('broken values read as the default', () async {
      for (final raw in [
        'not json',
        '[]',
        '{"dock":"middle","x":0.5,"y":0,"vertical":false}',
        '{"dock":"float","x":2,"y":0,"vertical":false}',
        '{"dock":"float","x":0.5,"y":0,"vertical":"no"}',
      ]) {
        final p = await _prefs({'toolbarPos': raw});
        expect(
          PenSlotsStore(p).readToolbar(),
          ToolbarPos.defaults,
          reason: raw,
        );
      }
      final p = await _prefs({'toolbarPos': 5});
      expect(PenSlotsStore(p).readToolbar(), ToolbarPos.defaults);
    });
  });
}
