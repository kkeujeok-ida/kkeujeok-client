import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/brush.dart';
import 'package:kkeujeok/model/brush_preset.dart';
import 'package:kkeujeok/model/pen.dart';
import 'package:kkeujeok/storage/pen_slots_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('patchBrush keeps only what differs from the tool default', () {
    expect(patchBrush('pen', null, {'opacity': 0.5}), {'opacity': 0.5});
    expect(patchBrush('pen', {'opacity': 0.5}, {'opacity': 1.0}), isNull);
    expect(patchBrush('highlighter', null, {'opacity': 0.4}), isNull);
    expect(patchBrush('pencil', null, {'texture': 'pencil'}), isNull);
    expect(patchBrush('pen', null, {'texture': 'pencil'}), {
      'texture': 'pencil',
    });
    expect(
      patchBrush(
        'pen',
        {
          'pressureCurve': [0.3, 0.3, 0.6, 0.6],
        },
        {'pressureCurve': null},
      ),
      isNull,
    );
    expect(patchBrush('pen', {'flow': 0.5}, {'opacity': 0.5}), {
      'flow': 0.5,
      'opacity': 0.5,
    });
  });

  test('kind switch drops brush; same kind keeps it', () {
    final p = const Pen(
      color: '#000000',
      width: 2,
      usePressure: true,
    ).withBrush({'opacity': 0.5});
    expect(p.withTool('fountain').brush, isNull);
    expect(p.withTool('pen').brush, {'opacity': 0.5});
    expect(p.withColor('#e03131').brush, {'opacity': 0.5});
  });

  test('slots store keeps brush; a bad brush never wipes the list', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = PenSlotsStore(prefs);
    const base = Pen(color: '#000000', width: 2, usePressure: true);
    await s.write([
      base.withBrush({'opacity': 0.5}),
      base,
    ]);
    final back = PenSlotsStore(prefs).read();
    expect(back[0].brush, {'opacity': 0.5});
    expect(back[1].toJson().containsKey('brush'), false);
    SharedPreferences.setMockInitialValues({
      'penSlots':
          '[{"tool":"pen","color":"#000000","width":2,"usePressure":true,"brush":"x"},'
          '{"tool":"pen","color":"#000000","width":2,"usePressure":true,"brush":{}}]',
    });
    final p2 = await SharedPreferences.getInstance();
    final list = PenSlotsStore(p2).read();
    expect(list.length, 2);
    expect(list.every((p) => p.brush == null), true);
  });

  test('presets: save from a pen, apply, store, bad entries skipped', () async {
    const pen = Pen(color: '#000000', width: 2, usePressure: true);
    final withBrush = pen.withBrush({'opacity': 0.5});
    final p = presetOf('a', '  soft ', withBrush)!;
    expect(p.name, 'soft');
    expect(presetOf('b', '  ', pen), isNull);
    final applied = applyBrushPreset(
      const Pen(
        tool: 'fountain',
        color: '#e03131',
        width: 1,
        usePressure: false,
      ),
      p,
    );
    expect(applied.tool, 'pen');
    expect(applied.brush, {'opacity': 0.5});
    expect(applied.width, 2);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = PenSlotsStore(prefs);
    await s.writePresets([p]);
    expect(PenSlotsStore(prefs).readPresets().single.brush, {'opacity': 0.5});
    expect(
      parsePresets(
        '[{"id":"a","name":"ok","tool":"pen","width":2,"usePressure":true},'
        '{"id":"b","name":"","tool":"pen","width":2,"usePressure":true},7]',
      ).map((e) => e.id),
      ['a'],
    );
    expect(parsePresets('not json'), isEmpty);
  });
}
