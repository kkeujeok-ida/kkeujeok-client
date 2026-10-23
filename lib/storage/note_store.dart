import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/kkj_codec.dart';
import '../model/note.dart';
import '../sync/has_unsent.dart';
import 'note_data.dart';
import 'sync_info.dart';

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

/// The message of the [NoteSaveException] `updateSync` throws for a
/// `sync.json` that is there but cannot be read.
const syncUnreadableMessage = 'sync.json is unreadable';
const syncFileName = 'sync.json';
final _baseName = RegExp(r'^base\.(.+)\.kkj$');
final _pathSep = RegExp(r'[/\\]');

/// What [NoteStore.mergeWorking] writes: the new working copy (null = leave
/// it), a change of `sync.json` (null = leave it), the sidecar records to
/// keep, and the value the caller gets back.
typedef MergePlan<T> = ({
  T value,
  Note? note,
  SyncInfo Function(SyncInfo)? sync,
  List<Map<String, Object?>> sidecars,
});

/// What [NoteStore.readSync] knows about one note's sync files.
typedef SyncRead = ({
  SyncInfo info,
  Note? base,
  bool hasUnsent,
  SyncState state,
});

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
/// and rename so an interrupted save leaves the previous version. With
/// [commitSync] the folder also holds the base copy and `sync.json`.
class NoteStore {
  NoteStore(
    this._data, {
    Future<void> Function(File, List<int>)? writeFile,
    this.onWrite,
    this.onStep,
  }) : _writeFile = writeFile ?? _defaultWrite;

  final NoteData _data;
  final Future<void> Function(File, List<int>) _writeFile;

  /// Called after every successful save; its failure is swallowed.
  final Future<void> Function()? onWrite;

  /// Test hook: called right after each file of [commitSync] is renamed
  /// (`working`, `base`, `sync`). Throwing from it simulates a crash there.
  final Future<void> Function(String step)? onStep;

  final _changes = StreamController<({String noteId, bool sync})>.broadcast(
    sync: true,
  );

  /// Fires after a note was saved: `sync` is false for a plain edit of the
  /// working copy, true when `sync.json` (or a received note) was committed.
  /// The sync display follows this.
  Stream<({String noteId, bool sync})> get changes => _changes.stream;

  void _emit(String noteId, {bool sync = true}) {
    if (!_changes.isClosed) _changes.add((noteId: noteId, sync: sync));
  }

  Future<void> _notify() async {
    try {
      await onWrite?.call();
    } catch (_) {}
  }

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

  static String _in(Directory d, String name) =>
      '${d.path}${Platform.pathSeparator}$name';

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
  /// this client cannot read, so it is never overwritten. Writes the working
  /// copy only: base and `sync.json` are not touched.
  Future<void> write(Note note) async {
    await _locked(note.noteId, () async {
      File? tmp;
      // Folders this call made, removed again (if still empty) on failure.
      Directory? created, createdRoot;
      try {
        final file = await _working(note.noteId);
        tmp = File('${file.path}.tmp');
        // ponytail: re-reads the existing file on every save; cache the verdict
        // if large pages make this slow.
        if (await file.exists() &&
            !decodeKkj(await file.readAsBytes()).writable) {
          throw NoteSaveException(
            'existing file is not readable by this client',
          );
        }
        if (!await file.parent.exists()) {
          created = file.parent;
          if (!await file.parent.parent.exists()) {
            createdRoot = file.parent.parent;
          }
        }
        await file.parent.create(recursive: true);
        await _writeFile(tmp, encodeKkj(note));
        await tmp.rename(file.path);
      } on NoteSaveException {
        rethrow;
      } catch (e) {
        // Each step on its own: one failing must not skip the others. Best
        // effort; read() cleans a leftover temp file up later.
        for (final undo in <Future<void> Function()>[
          () async {
            final t = tmp;
            if (t != null && await t.exists()) await t.delete();
          },
          () async => created?.delete(), // fails (kept) unless empty
          () async => createdRoot?.delete(),
        ]) {
          try {
            await undo();
          } catch (_) {}
        }
        throw NoteSaveException('could not write note', e);
      }
    });
    await _notify();
    _emit(note.noteId, sync: false);
  }

  /// Writes the three files of one note as a group: working copy, base copy
  /// (`base.<baseHeadRevisionId>.kkj`), then `sync.json`, the commit marker.
  /// Each goes to a temp file and is renamed. A [base] of null keeps the
  /// base file [info] names (it must exist). Throws [NoteSaveException]; the
  /// previous `sync.json` stays when it does.
  ///
  /// A base file is never overwritten in place while the committed
  /// `sync.json` names it (a crash mid-way would corrupt the base it trusts):
  /// the same [SyncInfo.baseHeadRevisionId] with a different [base] fails;
  /// callers use a new id for a new base.
  Future<void> commitSync(Note working, Note? base, SyncInfo info) async {
    await _locked(working.noteId, () => _commitLocked(working, base, info));
    await _notify();
    _emit(working.noteId);
  }

  /// [commitSync] for a note received from Drive: under the note's lock the
  /// stored working copy must still be [expected] (null: there is none), else
  /// nothing is written and the answer is false. [change] gets the
  /// `sync.json` read under the same lock and returns the one to commit.
  /// Throws [NoteSaveException] like [commitSync].
  ///
  /// [guard] is the `sync.json` the decision was made on: under the lock its
  /// `unsentSidecars`, `pendingVerify`, `baseHeadRevisionId` and `fileId` must
  /// still be the same, and (for a note that exists) the working copy must
  /// not differ from the base now, else the answer is false and the caller
  /// decides again.
  Future<bool> commitReceive(
    String noteId, {
    required Note? expected,
    required SyncInfo guard,
    required Note working,
    required Note base,
    required SyncInfo Function(SyncInfo current) change,
  }) async {
    var done = false;
    final dir = (await _working(noteId)).parent;
    await _locked(noteId, () async {
      final file = File(_in(dir, workingFileName));
      Note? cur;
      if (await file.exists()) {
        cur = decodeKkj(await file.readAsBytes()).note;
        if (expected == null ||
            cur == null ||
            jsonEncode(cur.toJson()) != jsonEncode(expected.toJson())) {
          return;
        }
      } else if (expected != null) {
        return;
      }
      final now = await _loadSyncStrict(dir);
      String key(SyncInfo i) => jsonEncode([
        i.unsentSidecars,
        i.pendingVerify,
        i.baseHeadRevisionId,
        i.fileId,
      ]);
      if (key(now) != key(guard)) return;
      if (cur != null) {
        // hasUnsent from what is on disk under this lock, not a snapshot.
        final id = now.baseHeadRevisionId;
        Note? b;
        if (id != null) {
          try {
            final bf = File(_in(dir, 'base.$id.kkj'));
            if (await bf.exists()) b = decodeKkj(await bf.readAsBytes()).note;
          } catch (_) {}
        }
        Map<String, Object?> s(Note n) => {
          'orderRev': n.orderRev,
          'metaRev': n.metaRev,
          'pages': n.pages,
        };
        if (hasUnsentRule({
              'base': b == null ? null : s(b),
              'working': s(cur),
              'pendingVerify': now.pendingVerify,
              'unsentSidecars': now.unsentSidecars,
            })['hasUnsent'] !=
            false) {
          return;
        }
      }
      await _commitLocked(working, base, change(now));
      done = true;
    });
    if (done) {
      await _notify();
      _emit(noteId);
    }
    return done;
  }

  /// Deletes the whole folder of a note whose Drive file is gone (Story
  /// 3.17), only while its working copy is still [expected] under the note's
  /// lock; false, nothing deleted, when it moved on. Throws
  /// [NoteSaveException].
  Future<bool> removeNote(String noteId, {required Note expected}) async {
    var done = false;
    final dir = (await _working(noteId)).parent;
    await _locked(noteId, () async {
      final file = File(_in(dir, workingFileName));
      if (!await file.exists()) return;
      final cur = decodeKkj(await file.readAsBytes()).note;
      if (cur == null ||
          jsonEncode(cur.toJson()) != jsonEncode(expected.toJson())) {
        return;
      }
      try {
        await dir.delete(recursive: true);
      } catch (e) {
        throw NoteSaveException('could not remove the note', e);
      }
      done = true;
    });
    if (done) _emit(noteId);
    return done;
  }

  /// A downloaded file this client cannot read, kept byte for byte as the
  /// working copy of a note that has none (so it is never replaced), with
  /// [info] as its `sync.json`. False, nothing written, when a working copy
  /// exists. Throws [NoteSaveException].
  Future<bool> storeUnreadable(
    String noteId,
    List<int> bytes,
    SyncInfo info,
  ) async {
    var done = false;
    final dir = (await _working(noteId)).parent;
    await _locked(noteId, () async {
      final tmps = <File>[];
      try {
        final file = File(_in(dir, workingFileName));
        if (await file.exists()) return;
        await dir.create(recursive: true);
        await _put(file, bytes, tmps);
        await _put(
          File(_in(dir, syncFileName)),
          utf8.encode(jsonEncode(info.toJson())),
          tmps,
        );
        done = true;
      } catch (e) {
        await _cleanTmps(tmps);
        throw NoteSaveException('could not write the file', e);
      }
    });
    if (done) {
      await _notify();
      _emit(noteId);
    }
    return done;
  }

  Future<void> _commitLocked(Note working, Note? base, SyncInfo info) async {
    final tmps = <File>[];
    try {
      final workingFile = await _working(working.noteId);
      final dir = workingFile.parent;
      final id = info.baseHeadRevisionId;
      if (id != null && !revisionIdPattern.hasMatch(id)) {
        throw NoteSaveException('baseHeadRevisionId is not a valid id');
      }
      if (id == null && base != null) {
        throw NoteSaveException('a base needs a baseHeadRevisionId');
      }
      if (base != null && base.noteId != working.noteId) {
        throw NoteSaveException('base belongs to another note');
      }
      if (await workingFile.exists() &&
          !decodeKkj(await workingFile.readAsBytes()).writable) {
        throw NoteSaveException('existing file is not readable by this client');
      }
      final baseFile = id == null ? null : File(_in(dir, 'base.$id.kkj'));
      if (base == null && baseFile != null && !await baseFile.exists()) {
        throw NoteSaveException('the base file is missing');
      }
      var writeBase = base != null;
      if (writeBase && baseFile != null && await baseFile.exists()) {
        final committed = await _committedBaseId(dir);
        if (committed == id) {
          final cur = decodeKkj(await baseFile.readAsBytes()).note;
          if (cur == null ||
              jsonEncode(cur.toJson()) != jsonEncode(base.toJson())) {
            throw NoteSaveException(
              'base $id is committed already with other content',
            );
          }
          writeBase = false; // identical: nothing to write
        }
      }
      await dir.create(recursive: true);

      Future<void> put(File f, List<int> bytes, String step) async {
        final t = File('${f.path}.tmp');
        tmps.add(t);
        await _writeFile(t, bytes);
        await t.rename(f.path);
        tmps.remove(t);
        await onStep?.call(step);
      }

      await put(workingFile, encodeKkj(working), 'working');
      if (writeBase) await put(baseFile!, encodeKkj(base!), 'base');
      await put(
        File(_in(dir, syncFileName)),
        utf8.encode(jsonEncode(info.toJson())),
        'sync',
      );
      try {
        await _dropOrphanBases(dir, id);
      } catch (_) {} // already committed; readSync cleans up later
    } on NoteSaveException {
      rethrow;
    } catch (e) {
      for (final t in tmps) {
        try {
          if (await t.exists()) await t.delete();
        } catch (_) {}
      }
      throw NoteSaveException('could not write sync state', e);
    }
  }

  /// The base id the `sync.json` on disk names; null when there is none or
  /// it is not valid.
  Future<String?> _committedBaseId(Directory dir) async {
    try {
      return SyncInfo.fromJson(
        jsonDecode(await File(_in(dir, syncFileName)).readAsString()),
      )?.baseHeadRevisionId;
    } catch (_) {
      return null;
    }
  }

  /// Best effort: a file that cannot be deleted is left for the next call.
  Future<void> _dropOrphanBases(Directory dir, String? keep) async {
    await for (final e in dir.list()) {
      final m = _baseName.firstMatch(e.path.split(_pathSep).last);
      if (e is File && m != null && m.group(1) != keep) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  }

  /// Forgets the Drive file of one note: `sync.json` becomes pending with no
  /// fileId, base, pendingVerify, resumableSession, createIntent or
  /// lastError; conflicts, unsent sidecars and unknown keys stay. Only
  /// `sync.json` is written (under the note's lock), so a newer edit of the
  /// working copy is never touched, and the note need not be readable.
  /// Throws [NoteSaveException]; a note without a folder is skipped.
  Future<void> resetSync(String noteId) async {
    final dir = (await _working(noteId)).parent;
    await _locked(noteId, () async {
      final tmp = File('${_in(dir, syncFileName)}.tmp');
      try {
        if (!await dir.exists()) return;
        SyncInfo? old;
        try {
          old = SyncInfo.fromJson(
            jsonDecode(await File(_in(dir, syncFileName)).readAsString()),
          );
        } catch (_) {}
        final next = SyncInfo(
          conflicts: old?.conflicts ?? const [],
          unsentSidecars: old?.unsentSidecars ?? const [],
          extra: old?.extra ?? const {},
        );
        await _writeFile(tmp, utf8.encode(jsonEncode(next.toJson())));
        await tmp.rename(_in(dir, syncFileName));
        try {
          await _dropOrphanBases(dir, null);
        } catch (_) {}
      } catch (e) {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        throw NoteSaveException('could not reset sync state', e);
      }
    });
  }

  /// Changes one note's `sync.json` (and its base copy) without touching the
  /// working copy. [change] gets the `sync.json` read under the note's lock,
  /// so no snapshot taken earlier can overwrite a newer write. [base], when
  /// given, becomes `base.<id>.kkj` for the [SyncInfo.baseHeadRevisionId] that
  /// [change] returns; it is written before `sync.json`, the commit marker.
  /// Returns what was committed. Throws [NoteSaveException]; the previous
  /// `sync.json` stays when it does.
  Future<SyncInfo> updateSync(
    String noteId,
    SyncInfo Function(SyncInfo current) change, {
    Note? base,
  }) async {
    final dir = (await _working(noteId)).parent;
    late SyncInfo committed;
    await _locked(noteId, () async {
      final tmps = <File>[];
      try {
        if (!await dir.exists()) {
          throw NoteSaveException('the note has no folder');
        }
        // No file is "none". A file that is there but cannot be read is
        // never replaced by an empty record: that would drop the fileId and
        // the base. The caller logs the failure.
        var old = const SyncInfo();
        final syncF = File(_in(dir, syncFileName));
        if (await syncF.exists()) {
          SyncInfo? read;
          try {
            read = SyncInfo.fromJson(jsonDecode(await syncF.readAsString()));
          } catch (_) {}
          if (read == null) throw NoteSaveException(syncUnreadableMessage);
          old = read;
        }
        var next = change(old);
        var id = next.baseHeadRevisionId;
        // The base file the old record names is gone and no new base comes:
        // forget it (as readSync does) so the note recovers instead of
        // failing every commit.
        if (base == null &&
            id != null &&
            id == old.baseHeadRevisionId &&
            !await File(_in(dir, 'base.$id.kkj')).exists()) {
          next = next.copyWith(baseHeadRevisionId: null);
          id = null;
        }
        if (id != null && !revisionIdPattern.hasMatch(id)) {
          throw NoteSaveException('baseHeadRevisionId is not a valid id');
        }
        if (id == null && base != null) {
          throw NoteSaveException('a base needs a baseHeadRevisionId');
        }
        if (base != null && base.noteId != noteId) {
          throw NoteSaveException('base belongs to another note');
        }
        final baseFile = id == null ? null : File(_in(dir, 'base.$id.kkj'));
        if (base == null && baseFile != null && !await baseFile.exists()) {
          throw NoteSaveException('the base file is missing');
        }
        Future<void> put(File f, List<int> bytes) async {
          final t = File('${f.path}.tmp');
          tmps.add(t);
          await _writeFile(t, bytes);
          await t.rename(f.path);
          tmps.remove(t);
        }

        if (base != null && baseFile != null) {
          var write = true;
          if (await baseFile.exists() && await _committedBaseId(dir) == id) {
            final cur = decodeKkj(await baseFile.readAsBytes()).note;
            if (cur == null ||
                jsonEncode(cur.toJson()) != jsonEncode(base.toJson())) {
              throw NoteSaveException(
                'base $id is committed already with other content',
              );
            }
            write = false;
          }
          if (write) {
            await put(baseFile, encodeKkj(base));
            await onStep?.call('base');
          }
        }
        await put(
          File(_in(dir, syncFileName)),
          utf8.encode(jsonEncode(next.toJson())),
        );
        await onStep?.call('sync');
        try {
          await _dropOrphanBases(dir, id);
        } catch (_) {}
        committed = next;
      } catch (e) {
        for (final t in tmps) {
          try {
            if (await t.exists()) await t.delete();
          } catch (_) {}
        }
        if (e is NoteSaveException) rethrow;
        throw NoteSaveException('could not write sync state', e);
      }
    });
    await _notify();
    _emit(noteId);
    return committed;
  }

  /// `sync.json` for a write under the lock: no file is "none"; a file that
  /// is there but cannot be read is never replaced (it would drop the
  /// fileId and the base).
  Future<SyncInfo> _loadSyncStrict(Directory dir) async {
    final f = File(_in(dir, syncFileName));
    if (!await f.exists()) return const SyncInfo();
    SyncInfo? read;
    try {
      read = SyncInfo.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {}
    if (read == null) throw NoteSaveException(syncUnreadableMessage);
    return read;
  }

  static String _sidecarName(String pageId, String rev) =>
      '${Uri.encodeComponent(pageId)}-${Uri.encodeComponent(rev)}.json';

  Future<void> _put(File f, List<int> bytes, List<File> tmps) async {
    final t = File('${f.path}.tmp');
    tmps.add(t);
    await _writeFile(t, bytes);
    await t.rename(f.path);
    tmps.remove(t);
  }

  Future<void> _putSidecars(
    Directory dir,
    List<Map<String, Object?>> sidecars,
    List<File> tmps,
  ) async {
    if (sidecars.isEmpty) return;
    final sub = Directory(_in(dir, 'sidecars'));
    await sub.create(recursive: true);
    for (final sc in sidecars) {
      await _put(
        File(
          _in(sub, _sidecarName(sc['pageId'] as String, sc['rev'] as String)),
        ),
        utf8.encode(jsonEncode(sc)),
        tmps,
      );
    }
  }

  Future<void> _cleanTmps(List<File> tmps) async {
    for (final t in tmps) {
      try {
        if (await t.exists()) await t.delete();
      } catch (_) {}
    }
  }

  /// Keeps the sidecar records (spec `merge.conflictSidecar`) beside the note,
  /// at `sidecars/<pageId>-<rev>.json`, until they are uploaded. Writing the
  /// same record again is harmless. Throws [NoteSaveException].
  Future<void> writeSidecars(
    String noteId,
    List<Map<String, Object?>> sidecars,
  ) async {
    final dir = (await _working(noteId)).parent;
    await _locked(noteId, () async {
      final tmps = <File>[];
      try {
        if (!await dir.exists()) {
          throw NoteSaveException('the note has no folder');
        }
        await _putSidecars(dir, sidecars, tmps);
      } catch (e) {
        await _cleanTmps(tmps);
        if (e is NoteSaveException) rethrow;
        throw NoteSaveException('could not write sidecar', e);
      }
    });
  }

  /// The sidecar record kept for ([pageId], [rev]); null when it is missing
  /// or cannot be read.
  Future<Map<String, Object?>?> readSidecar(
    String noteId,
    String pageId,
    String rev,
  ) async {
    final dir = (await _working(noteId)).parent;
    return _locked(noteId, () async {
      try {
        final j = jsonDecode(
          await File(
            _in(Directory(_in(dir, 'sidecars')), _sidecarName(pageId, rev)),
          ).readAsString(),
        );
        return j is Map
            ? {for (final e in j.entries) '${e.key}': e.value}
            : null;
      } catch (_) {
        return null;
      }
    });
  }

  /// Applies a merge to the working copy as one item of the note's queue
  /// (spec `merge.requeue`, AD-16): [plan] gets the working copy and
  /// `sync.json` as they are inside the lock, never an earlier snapshot, and
  /// says what to write. Written in this order: the sidecars, `sync.json`,
  /// the working copy. Nothing is written when [plan] throws. Throws
  /// [NoteSaveException] when the working copy or `sync.json` cannot be read
  /// or a write fails (the earlier files stay as they were written).
  Future<T> mergeWorking<T>(
    String noteId,
    MergePlan<T> Function(Note current, SyncInfo info) plan,
  ) async {
    late T value;
    final dir = (await _working(noteId)).parent;
    await _locked(noteId, () async {
      final tmps = <File>[];
      try {
        final file = File(_in(dir, workingFileName));
        if (!await file.exists()) {
          throw NoteSaveException('the note has no working copy');
        }
        final r = decodeKkj(await file.readAsBytes());
        final cur = r.note;
        if (!r.writable || cur == null || cur.noteId != noteId) {
          throw NoteSaveException(
            'existing file is not readable by this client',
          );
        }
        final info = await _loadSyncStrict(dir);
        final p = plan(cur, info);
        value = p.value;
        await _putSidecars(dir, p.sidecars, tmps);
        final sync = p.sync;
        if (sync != null) {
          await _put(
            File(_in(dir, syncFileName)),
            utf8.encode(jsonEncode(sync(info).toJson())),
            tmps,
          );
        }
        final next = p.note;
        if (next != null) await _put(file, encodeKkj(next), tmps);
      } catch (e) {
        await _cleanTmps(tmps);
        if (e is NoteSaveException) rethrow;
        throw NoteSaveException('could not write the merge', e);
      }
    });
    await _notify();
    _emit(noteId);
    return value;
  }

  /// The title changed in Drive (spec `drive.remoteTitle`): under the note's
  /// lock [pick] gets the working copy, the base copy and `sync.json` and
  /// returns the new title, or null to do nothing. The title goes into the
  /// working copy first, then into the base copy; `metaRev`, pages and
  /// `sync.json` stay as they are. A base that is ahead of the working copy
  /// would make the app "win" and rename the file back, hence the order.
  /// Returns whether it wrote. Throws [NoteSaveException].
  Future<bool> retitle(
    String noteId,
    String? Function(Note working, Note base, SyncInfo info) pick,
  ) async {
    var done = false;
    final dir = (await _working(noteId)).parent;
    await _locked(noteId, () async {
      final tmps = <File>[];
      try {
        final work = File(_in(dir, workingFileName));
        if (!await work.exists()) return;
        final w = decodeKkj(await work.readAsBytes());
        if (!w.writable || w.note == null || w.note!.noteId != noteId) return;
        final info = await _loadSyncStrict(dir);
        final id = info.baseHeadRevisionId;
        if (id == null) return;
        final baseF = File(_in(dir, 'base.$id.kkj'));
        if (!await baseF.exists()) return;
        final b = decodeKkj(await baseF.readAsBytes());
        if (b.note == null || b.note!.noteId != noteId) return;
        final title = pick(w.note!, b.note!, info);
        if (title == null) return;
        Note withTitle(Note n) {
          final j = n.copyJson();
          (j['meta'] as Map<String, dynamic>)['title'] = title;
          return Note.trusted(j);
        }

        await _put(work, encodeKkj(withTitle(w.note!)), tmps);
        await _put(baseF, encodeKkj(withTitle(b.note!)), tmps);
        done = true;
      } catch (e) {
        await _cleanTmps(tmps);
        if (e is NoteSaveException) rethrow;
        throw NoteSaveException('could not write the title', e);
      }
    });
    if (done) {
      await _notify();
      _emit(noteId);
    }
    return done;
  }

  /// Never throws. A missing or broken `sync.json` is "none": state
  /// `pending`, no base, and no base file is removed. Otherwise only the
  /// base it names is read and the others are removed. Leftover temp files
  /// are always removed.
  Future<SyncRead> readSync(String noteId) async {
    const none = (
      info: SyncInfo(),
      base: null,
      hasUnsent: true,
      state: SyncState.pending,
    );
    try {
      final dir = (await _working(noteId)).parent;
      return await _locked(noteId, () async {
        if (!await dir.exists()) return none;
        try {
          await for (final e in dir.list()) {
            // Only leftovers: a fresh one may be a write in flight in the
            // other isolate (the WorkManager task has its own lock).
            if (e is File &&
                e.path.endsWith('.tmp') &&
                DateTime.now().difference(await e.lastModified()) >
                    const Duration(minutes: 1)) {
              try {
                await e.delete();
              } catch (_) {}
            }
          }
        } catch (_) {}
        SyncInfo? info;
        try {
          info = SyncInfo.fromJson(
            jsonDecode(await File(_in(dir, syncFileName)).readAsString()),
          );
        } catch (_) {}
        if (info != null) {
          try {
            await _dropOrphanBases(dir, info.baseHeadRevisionId);
          } catch (_) {}
        }
        info ??= const SyncInfo();

        Note? readNote(String name) {
          try {
            final r = decodeKkj(File(_in(dir, name)).readAsBytesSync());
            return r.note?.noteId == noteId ? r.note : null;
          } catch (_) {
            return null;
          }
        }

        final id = info.baseHeadRevisionId;
        final base = id == null ? null : readNote('base.$id.kkj');
        final working = readNote(workingFileName);
        Map<String, Object?> s(Note n) => {
          'orderRev': n.orderRev,
          'metaRev': n.metaRev,
          'pages': n.pages,
        };
        // A working copy that cannot be read (missing, corrupt, newer
        // version, other note) is never "safe": unsent, pending.
        final unsent =
            working == null ||
            hasUnsentRule({
                  'base': base == null ? null : s(base),
                  'working': s(working),
                  'pendingVerify': info.pendingVerify,
                  'unsentSidecars': info.unsentSidecars,
                })['hasUnsent'] !=
                false;
        return (
          info: info,
          base: base,
          hasUnsent: unsent,
          state: working == null || (info.state == SyncState.synced && unsent)
              ? SyncState.pending
              : info.state,
        );
      });
    } catch (_) {
      return none;
    }
  }

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

  /// The raw bytes of the working copy, readable or not (for a file export);
  /// null when there is none or it cannot be read.
  Future<List<int>?> workingBytes(String noteId) async {
    try {
      final file = await _working(noteId);
      return await _locked(noteId, () async {
        return await file.exists() ? await file.readAsBytes() : null;
      });
    } catch (_) {
      return null;
    }
  }

  /// The ids of the note folders, without reading any file.
  Future<List<String>> ids() async {
    final root = await _data.notesDir();
    if (!await root.exists()) return const [];
    return [
      await for (final e in root.list())
        if (e is Directory && _uuid.hasMatch(e.path.split(_pathSep).last))
          e.path.split(_pathSep).last,
    ];
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
