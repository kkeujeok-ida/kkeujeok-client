import 'dart:convert';
import 'dart:io';

import 'note.dart';

/// `.kkj` bytes: gzip of UTF-8 JSON. Always written as the supported
/// `formatVersion` (spec `note-format.md`, "Format version 2").
List<int> encodeKkj(Note note) => gzip.encode(
  utf8.encode(
    jsonEncode({...note.toJson(), 'formatVersion': supportedFormatVersion}),
  ),
);

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
