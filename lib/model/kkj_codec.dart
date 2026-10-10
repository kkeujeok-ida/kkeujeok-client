import 'dart:convert';
import 'dart:io';

import 'note.dart';

/// `.kkj` bytes: gzip of UTF-8 JSON.
List<int> encodeKkj(Note note) =>
    gzip.encode(utf8.encode(jsonEncode(note.toJson())));

/// Spec `note.formatVersion`; never throws.
NoteReadResult decodeKkj(List<int> bytes) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(gzip.decode(bytes)));
  } catch (_) {
    return const NoteReadResult(ReadStatus.unreadable);
  }
  return Note.parse(json);
}
