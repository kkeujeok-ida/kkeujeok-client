import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';

void main() {
  test('empty and garbage bytes are unreadable, not an exception', () {
    expect(decodeKkj([]).status, ReadStatus.unreadable);
    expect(decodeKkj([1, 2, 3]).status, ReadStatus.unreadable);
  });
}
