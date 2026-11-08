import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';

String id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

void main() {
  test('empty and garbage bytes are unreadable, not an exception', () {
    expect(decodeKkj([]).status, ReadStatus.unreadable);
    expect(decodeKkj([1, 2, 3]).status, ReadStatus.unreadable);
  });

  test('encode always writes the supported formatVersion', () {
    final r = createNote(
      title: 't',
      existingTitles: const [],
      background: 'plain',
      orientation: 'portrait',
      noteId: id(1),
      pageId: id(2),
      pageRev: id(3),
      metaRev: id(4),
      orderRev: id(5),
      now: '2026-11-08T00:00:00.000Z',
      editedBy: 'Pixel',
    );
    final json = r.note!.toJson()..['formatVersion'] = 1;
    final back = decodeKkj(encodeKkj(Note.trusted(json)));
    expect(back.note!.toJson()['formatVersion'], supportedFormatVersion);
  });
}
