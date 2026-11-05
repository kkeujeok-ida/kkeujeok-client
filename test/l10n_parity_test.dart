import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ko and en ARB have the same keys', () {
    Set<String> keys(String f) => {
      for (final k
          in (jsonDecode(File('lib/l10n/$f').readAsStringSync())
                  as Map<String, dynamic>)
              .keys)
        if (!k.startsWith('@')) k,
    };
    expect(keys('app_ko.arb'), keys('app_en.arb'));
  });
}
