import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Fixed name of the note data directory under the app documents directory.
/// Epics 2 and 3 store notes here; device settings live elsewhere
/// (SharedPreferences) so they survive its removal.
const noteDataDirName = 'notes';

/// Where the app documents directory is; injected so tests use a temp dir.
typedef DocumentsDir = Future<Directory> Function();

class NoteData {
  NoteData([DocumentsDir documents = getApplicationDocumentsDirectory])
    : _documents = documents;

  final DocumentsDir _documents;

  /// Deletes the note data directory. Nothing stored yet is not an error.
  Future<void> clear() async {
    final root = await _documents();
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}$noteDataDirName',
    );
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on PathNotFoundException {
      // Removed between the check and the delete: nothing left to do.
    }
  }
}
