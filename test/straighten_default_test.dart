import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/storage/straighten_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<StraightenStore> _store(Map<String, Object> v) async {
  SharedPreferences.setMockInitialValues(v);
  return StraightenStore(await SharedPreferences.getInstance());
}

void main() {
  test('no stored value: on', () async {
    expect((await _store({})).read(), isTrue);
  });
  test('a stored value is kept', () async {
    expect((await _store({'straighten': false})).read(), isFalse);
    expect((await _store({'straighten': true})).read(), isTrue);
  });
}
