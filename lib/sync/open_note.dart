import 'dart:io';

import '../storage/atomic_file.dart';

const openNoteFileName = 'open-note.txt';

/// The note the editor has open, as a file in the documents root, so the
/// WorkManager task (maybe another isolate) never uploads it (spec `sync`
/// "Triggers": no upload while a note is open).
///
/// ponytail: a crash leaves the marker; `appStarted` clears it. Between the
/// crash and the next launch the background task skips that one note.
class OpenNote {
  OpenNote(this._dir);

  final Future<Directory> Function() _dir;
  Future<void> _tail = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<File> _file() async {
    final d = await _dir();
    return File('${d.path}${Platform.pathSeparator}$openNoteFileName');
  }

  /// Never throws; a marker that cannot be written only means the note may
  /// be uploaded by the background task.
  Future<void> set(String noteId) => _locked(() async {
    try {
      await writeFileAtomic(await _file(), noteId.codeUnits);
    } catch (_) {}
  });

  /// Removes the marker when it names [noteId], or always without one.
  Future<void> clear([String? noteId]) => _locked(() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      if (noteId == null || await f.readAsString() == noteId) await f.delete();
    } catch (_) {}
  });

  Future<String?> read() => _locked(() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final s = (await f.readAsString()).trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  });
}
