import 'dart:ui' show Offset;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/ui/pen_color_picker.dart';

void main() {
  test('hsv <-> hex matrix', () {
    for (final (hex, h, s, v) in [
      ('#ff0000', 0.0, 1.0, 1.0),
      ('#00ff00', 120.0, 1.0, 1.0),
      ('#0000ff', 240.0, 1.0, 1.0),
      ('#000000', 0.0, 0.0, 0.0),
      ('#ffffff', 0.0, 0.0, 1.0),
    ]) {
      expect(hsvToHex(HSVColor.fromAHSV(1, h, s, v)), hex);
      final c = hexToHsv(hex)!;
      expect([c.hue, c.saturation, c.value], [h, s, v]);
    }
    for (final hex in ['#e03131', '#1971c2', '#0c8599', '#12ab34']) {
      expect(hsvToHex(hexToHsv(hex)!), hex);
    }
  });

  test('upper case accepted, bad input rejected', () {
    expect(hexToHsv('#1971C2')!.toColor(), hexToHsv('#1971c2')!.toColor());
    for (final bad in ['1971c2', '#fff', '#gggggg', '']) {
      expect(hexToHsv(bad), isNull);
    }
  });

  test('withHash and wheelZone', () {
    expect(withHash('ff0000'), '#ff0000');
    expect(withHash('#ff0000'), '#ff0000');
    expect(wheelZone(const Offset(112, 112)), WheelZone.square);
    expect(wheelZone(const Offset(112, 52)), WheelZone.square); // square edge
    expect(wheelZone(const Offset(112, 40)), WheelZone.ring); // hit band
    expect(wheelZone(const Offset(112, 10)), WheelZone.ring);
    expect(
      wheelZone(const Offset(174, 112)),
      WheelZone.none,
    ); // off square, inside the band
    expect(wheelZone(const Offset(0, 0)), WheelZone.none);
  });
}
