import 'dart:io';

import '../model/kkj_codec.dart';
import '../model/note.dart';
import 'note_data.dart';

/// A save did not happen. The previous file and the in-memory note are intact.
class NoteSaveException implements Exception {
  NoteSaveException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() =>
      'NoteSaveException: $message${cause == null ? '' : ' ($cause)'}';
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

const workingFileName = 'working.kkj';

Future<void> _defaultWrite(File f, List<int> bytes) async {
  final out = await f.open(mode: FileMode.write);
  try {
    await out.writeFrom(bytes);
    await out.flush();
  } finally {
    await out.close();
  }
}

/// Working copies at `notes/<noteId>/working.kkj`, written via a temp file
/// and rename so an interrupted save leaves the previous version.
class NoteStore {
  NoteStore(this._data, {Future<void> Function(File, List<int>)? writeFile})
    : _writeFile = writeFile ?? _defaultWrite;

  final NoteData _data;
  final Future<void> Function(File, List<int>) _writeFile;

  Future<File> _working(String noteId) async {
    if (!_uuid.hasMatch(noteId)) {
      throw ArgumentError.value(noteId, 'noteId', 'not a lowercase UUID');
    }
    final root = await _data.notesDir();
    return File(
      '${root.path}${Platform.pathSeparator}$noteId'
      '${Platform.pathSeparator}$workingFileName',
    );
  }

  // Per-note chain so a save, a read and a list never touch the same temp file
  // at once.
  final _locks = <String, Future<void>>{};

  Future<T> _locked<T>(String noteId, Future<T> Function() body) {
    final run = (_locks[noteId] ?? Future<void>.value()).then((_) => body());
    final done = run.then<void>((_) {}, onError: (Object _) {});
    _locks[noteId] = done;
    done.whenComplete(() {
      if (identical(_locks[noteId], done)) _locks.remove(noteId);
    });
    return run;
  }

  /// Throws [NoteSaveException] for every failure; refuses a folder whose file
  /// this client cannot read, so it is never overwritten.
  Future<void> write(Note note) => _locked(note.noteId, () async {
    File? tmp;
    try {
      final file = await _working(note.noteId);
      tmp = File('${file.path}.tmp');
      // ponytail: re-reads the existing file on every save; cache the verdict
      // if large pages make this slow.
      if (await file.exists() &&
          !decodeKkj(await file.readAsBytes()).writable) {
        throw NoteSaveException('existing file is not readable by this client');
      }
      await file.parent.create(recursive: true);
      await _writeFile(tmp, encodeKkj(note));
      await tmp.rename(file.path);
    } on NoteSaveException {
      rethrow;
    } catch (e) {
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {
        // Best effort; read() cleans it up later.
      }
      throw NoteSaveException('could not write note', e);
    }
  });

  /// Null when there is no working copy for [noteId]. Removes a leftover temp
  /// file from an interrupted save. A file that cannot be read, or whose
  /// inner noteId is not the folder name, is `unreadable`.
  Future<NoteReadResult?> read(String noteId) async {
    final file = await _working(noteId);
    return _locked(noteId, () async {
      try {
        final tmp = File('${file.path}.tmp');
        if (await tmp.exists()) await tmp.delete();
        if (!await file.exists()) return null;
        final r = decodeKkj(await file.readAsBytes());
        if (r.note != null && r.note!.noteId != noteId) {
          return const NoteReadResult(ReadStatus.unreadable);
        }
        return r;
      } on FileSystemException {
        return const NoteReadResult(ReadStatus.unreadable);
      }
    });
  }

  /// One entry per note folder that has a working copy; the id is the folder
  /// name, never read from inside the file.
  Future<List<({String noteId, NoteReadResult result})>> list() async {
    final root = await _data.notesDir();
    final out = <({String noteId, NoteReadResult result})>[];
    if (!await root.exists()) return out;
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final id = e.path.split(RegExp(r'[/\\]')).last;
      if (!_uuid.hasMatch(id)) continue;
      final r = await read(id);
      if (r != null) out.add((noteId: id, result: r));
    }
    return out;
  }
}
