// The generated Dart tokens must have Light and Dark, with exactly the names
// the web source (kkeujeok-web/design_tokens/source) defines.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/design_tokens/build/tokens.dart';
import 'package:kkeujeok/ui/app.dart';

// Same naming as Style Dictionary's name/camel:
// components.pen-slot.selected-offset -> componentsPenSlotSelectedOffset.
String camel(List<String> path) {
  final parts = path.expand((p) => p.split('-')).toList();
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

void collect(Map<String, dynamic> node, List<String> path, Set<String> out) {
  if (node.containsKey(r'$value')) {
    out.add(camel(path));
    return;
  }
  node.forEach((k, v) => collect(v as Map<String, dynamic>, [...path, k], out));
}

// Top-level groups color and components can differ per theme; the rest cannot.
Set<String> sourceNames(List<String> files, {required bool themed}) {
  final names = <String>{};
  for (final f in files) {
    final json = jsonDecode(
      File('lib/design_tokens/source/$f.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    json.forEach((group, v) {
      final isThemed = group == 'color' || group == 'components';
      if (isThemed == themed) {
        collect({group: v}, [], names);
      }
    });
  }
  return names;
}

Set<String> dartNames(String source, String cls) {
  final start = source.indexOf('class $cls ');
  expect(start, greaterThanOrEqualTo(0), reason: 'class $cls missing');
  final end = source.indexOf('\n}', start);
  return RegExp(r'static const (\w+) =')
      .allMatches(source.substring(start, end))
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  test('lib/design_tokens is present', () {
    // Fails loudly rather than skipping: lib/design_tokens is a symlink (or, on a
    // Windows PC without symlink rights, a junction) to kkeujeok-web.
    expect(
      Directory('lib/design_tokens/source').existsSync(),
      isTrue,
      reason:
          'lib/design_tokens must point to ../../kkeujeok-web/design_tokens',
    );
  });

  test('generated Dart values match the source', () {
    // Literal expectations: a wrong ARGB order, weight or unit in the generator
    // would otherwise only show up on the device.
    expect(KkjLight.colorAccent, const Color(0xFF2F6FEB));
    expect(KkjLight.colorScrim, const Color(0x6B22242A));
    expect(KkjDark.colorAccent, const Color(0xFF7AA5F5));
    expect(KkjDark.colorScrim, const Color(0x99000000));
    expect(KkjTokens.typographyTitleFontWeight, FontWeight.w600);
    expect(KkjTokens.typographyBodyFontSize, 15.0);
    expect(
      KkjLight.componentsPenSlotSelectedDuration,
      const Duration(milliseconds: 150),
    );
  });

  test('Light and Dark have the web source names', () {
    final dart = File('lib/design_tokens/build/tokens.dart').readAsStringSync();
    final light = sourceNames(['common', 'light'], themed: true);
    final dark = sourceNames(['common', 'dark'], themed: true);
    expect(light, isNotEmpty);
    expect(light, dark, reason: 'Light and Dark source names differ');
    expect(dartNames(dart, 'KkjLight'), light);
    expect(dartNames(dart, 'KkjDark'), dark);
    expect(
      dartNames(dart, 'KkjTokens'),
      sourceNames(['common'], themed: false),
    );
  });

  testWidgets('app shows Kkeujeok in Pretendard with Light tokens', (
    tester,
  ) async {
    await tester.pumpWidget(const App());
    final style = tester.widget<Text>(find.text('Kkeujeok')).style!;
    expect(style.fontFamily, 'Pretendard');
    expect(style.color, KkjLight.colorInkPrimary);
    expect(lightTheme().scaffoldBackgroundColor, KkjLight.colorSurfaceBase);
  });
}
