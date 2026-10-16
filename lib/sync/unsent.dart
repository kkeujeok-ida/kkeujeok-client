import '../storage/note_store.dart';

/// The ids of the notes that have changes Drive does not have (spec
/// `sync.hasUnsent`); null when the notes cannot be listed, which is
/// "unknown", never "none".
Future<List<String>?> unsentNoteIds(NoteStore store) async {
  try {
    return [
      for (final id in await store.ids())
        if ((await store.readSync(id)).hasUnsent) id,
    ];
  } catch (_) {
    return null;
  }
}
