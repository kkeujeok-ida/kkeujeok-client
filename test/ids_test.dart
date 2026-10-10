import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/ids.dart';

void main() {
  test('newId is a lowercase UUIDv7', () {
    final id = newId();
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('newId ids sort by creation time', () async {
    final a = newId();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final b = newId();
    expect(a.compareTo(b), lessThan(0));
  });

  test('canonicalNow is UTC with exactly 3 ms digits and Z', () {
    final re = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$');
    expect(
      canonicalNow(DateTime.utc(2026, 10, 10, 4, 20)),
      '2026-10-10T04:20:00.000Z',
    );
    expect(
      canonicalNow(DateTime.utc(2026, 10, 10, 4, 20, 0, 5, 678)),
      '2026-10-10T04:20:00.005Z',
    );
    expect(canonicalNow(DateTime.now()), matches(re));
  });
}
