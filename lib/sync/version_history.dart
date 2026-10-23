import 'dart:convert';

import '../drive/drive_client.dart';
import '../model/ids.dart';
import '../model/kkj_codec.dart';
import '../model/note.dart';
import '../ops/restore.dart';
import '../storage/note_store.dart';
import '../storage/sync_info.dart';
import 'merge.dart' show Json;
import 'merge_step.dart';
import 'upload_coordinator.dart';
import 'version_list.dart';

/// What Drive lists for the history of a note (spec `version-history`
/// "Reading the list"): the revisions of the note file and the files of the
/// note's `.conflicts` folder.
class VersionData {
  const VersionData(this.headRevisionId, this.revisions, this.sidecars);

  final String? headRevisionId;
  final List<DriveRevision> revisions;
  final List<DriveFile> sidecars;
}

/// What a download of one version showed: [info] is the `info` of
/// `version.list`; [page] is the page to draw as the preview.
class Inspection {
  const Inspection(this.info, {this.page, this.note, this.sidecar});

  final Map<String, Object?> info;
  final Map<String, dynamic>? page;

  /// The parsed note of a revision.
  final Note? note;

  /// The parsed record of a sidecar.
  final Map<String, Object?>? sidecar;

  bool get ok => info['ok'] == true;
}

Inspection _failed(String reason) =>
    Inspection({'ok': false, 'reason': reason});

bool _validPage(Object? p) =>
    p is Map<String, dynamic> &&
    p['width'] is num &&
    p['height'] is num &&
    (p['width'] as num) > 0 &&
    (p['height'] as num) > 0 &&
    (p['width'] as num).isFinite &&
    (p['height'] as num).isFinite &&
    p['elements'] is List;

/// Reads the history of one note from Drive. Throws only [DriveError].
class VersionSource {
  VersionSource(this.drive);

  final DriveClient drive;

  Future<List<DriveFile>> _all(String q, String fields) async {
    final out = <DriveFile>[];
    String? token;
    do {
      final p = await drive.list(q, fields: fields, pageToken: token);
      out.addAll(p.files);
      token = p.nextPageToken;
    } while (token != null);
    return out;
  }

  /// Step 1 and 2 of "Reading the list", in this order.
  Future<VersionData> load(String noteId, String fileId) async {
    final head = (await drive.get(
      fileId,
      fields: 'headRevisionId',
    )).headRevisionId;
    final revisions = await drive.listRevisions(fileId);
    final sidecars = <DriveFile>[];
    for (final folder in await _all(kkeujeokIdQuery('cf:$noteId'), 'id')) {
      sidecars.addAll(await _all(childrenQuery(folder.id), 'id,appProperties'));
    }
    return VersionData(head, revisions, sidecars);
  }

  /// Downloads a revision. A purged one (404) is a result, not an error;
  /// any other [DriveError] goes to the caller (the status stays unknown).
  Future<Inspection> inspectRevision(
    String noteId,
    String fileId,
    String revisionId,
  ) async {
    final List<int> bytes;
    try {
      bytes = await drive.downloadRevision(fileId, revisionId);
    } on DriveError catch (e) {
      if (e.kind == 'http' && e.status == 404) return _failed('purged');
      rethrow;
    }
    final r = decodeKkj(bytes);
    if (r.status == ReadStatus.unsupportedVersion) {
      return _failed('unsupportedVersion');
    }
    final note = r.note;
    if (note == null || note.noteId != noteId || note.pages.isEmpty) {
      return _failed('unreadable');
    }
    return Inspection(
      {
        'ok': true,
        'pages': [
          for (final p in note.pages)
            {'editedAt': p['editedAt'], 'editedBy': p['editedBy']},
        ],
      },
      page: note.pages.firstOrNull,
      note: note,
    );
  }

  /// Downloads a sidecar by its `kkeujeokId` ([pageId], [rev]).
  Future<Inspection> inspectSidecar(
    String noteId,
    String driveFileId,
    String pageId,
    String rev,
  ) async {
    final List<int> bytes;
    try {
      bytes = await drive.downloadFile(driveFileId);
    } on DriveError catch (e) {
      if (e.kind == 'http' && e.status == 404) return _failed('purged');
      rethrow;
    }
    try {
      return inspectSidecarJson(
        jsonDecode(utf8.decode(bytes)),
        noteId,
        pageId,
        rev,
      );
    } catch (_) {
      return _failed('unreadable');
    }
  }
}

/// [j] is the record of ([pageId], [rev]) of the note.
Inspection inspectSidecarJson(
  Object? j,
  String noteId,
  String pageId,
  String rev,
) {
  if (j is Map<String, dynamic> &&
      j['noteId'] == noteId &&
      j['pageId'] == pageId &&
      j['rev'] == rev &&
      j['editedBy'] is String &&
      _validPage(j['page'])) {
    return Inspection(
      {'ok': true, 'editedBy': j['editedBy']},
      page: j['page'] as Map<String, dynamic>,
      sidecar: j,
    );
  }
  return _failed('unreadable');
}

/// A resolved conflict whose sidecar file is on this device: listed even
/// before Drive has the file (or its `kkjResolved`). [props] has the shape of
/// a Drive sidecar's `appProperties`.
class LocalSidecar {
  const LocalSidecar(this.props, this.sidecar);

  final Map<String, String> props;
  final Map<String, Object?> sidecar;

  String get id => props['kkeujeokId']!;
}

/// The resolved conflicts of `sync.json` that have a local sidecar file. A
/// file that cannot be read is left out (the list is best effort).
Future<List<LocalSidecar>> readLocalSidecars(
  NoteStore store,
  String noteId,
  SyncInfo info,
) async {
  final out = <LocalSidecar>[];
  try {
    for (final c in info.conflicts) {
      final at = c['resolvedAt'], pageId = c['pageId'], rev = c['rev'];
      if (at is! String || pageId is! String || rev is! String) continue;
      try {
        final sc = await store.readSidecar(noteId, pageId, rev);
        if (sc == null) continue;
        out.add(
          LocalSidecar({
            'kkeujeokId': 'sc:$noteId:$pageId:$rev',
            'kkjResolved': at,
            'kkjEdited': '${sc['editedAt']}',
            'kkjIndex': '${c['originalIndex'] ?? 0}',
          }, sc),
        );
      } catch (_) {
        continue;
      }
    }
  } catch (_) {
    // no sync record: no local entries
  }
  return out;
}

/// Why a restore did nothing (spec `version-history` "Restoring").
enum RestoreFailure {
  /// Step 1: the version could not be read, or the operation does not apply.
  unreadable,

  /// Step 2: the current state could not be uploaded and verified.
  notSaved,

  /// Step 3: the "복원 전" revision could not be pinned.
  notPinned,

  /// Step 4: the note could not be changed.
  notApplied,

  /// The note was edited after it was uploaded and pinned: nothing was
  /// restored.
  changed,
}

/// Same pages with the same revisions, same order and meta: nothing was
/// edited between the two.
bool _sameState(Note x, Note y) =>
    x.orderRev == y.orderRev &&
    x.metaRev == y.metaRev &&
    x.pages.length == y.pages.length &&
    [
      for (final (i, p) in x.pages.indexed)
        p['id'] == y.pages[i]['id'] && p['rev'] == y.pages[i]['rev'],
    ].every((b) => b);

/// The restore procedure of spec `version-history`: read the version, upload
/// and verify the current state, pin that revision, apply the restore through
/// the note's queue. A failed step stops the restore; the note is not changed
/// by it. Never throws.
class VersionRestorer {
  VersionRestorer({
    required this.drive,
    required this.store,
    required this.coordinator,
    VersionSource? source,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    String Function()? newRev,
    this.editedBy = deviceEditedBy,
  }) : source = source ?? VersionSource(drive),
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _newRev = newRev ?? newId;

  final DriveClient drive;
  final NoteStore store;
  final UploadCoordinator coordinator;
  final VersionSource source;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  final String Function() _newRev;
  final String editedBy;

  /// [entry] is a `version.list` entry. [live] is the note in the queue now;
  /// [apply] is the queue entry point of the open editor.
  Future<RestoreFailure?> restore({
    required String noteId,
    required String fileId,
    required Map<String, Object?> entry,
    required Note Function() live,
    required MergeHost apply,
  }) async {
    try {
      // 1. Read the version, and try the operation on a copy.
      final op = await _read(noteId, fileId, entry);
      if (op == null) return RestoreFailure.unreadable;
      final first = await store.readSync(noteId);
      final trial = _run(live(), op, first.info, first.info.conflicts);
      if (trial['error'] != null) return RestoreFailure.unreadable;

      // 2. Upload and verify the current state.
      final head = await coordinator.uploadForRestore(noteId);
      if (head == null) return RestoreFailure.notSaved;

      // 3. Pin that revision as "복원 전".
      if (!await _pin(noteId, fileId, head)) return RestoreFailure.notPinned;

      // 4. Apply the restore as an item of the note's queue.
      // Only on the note that was uploaded and pinned: an edit saved since
      // then is in neither, so the restore would overwrite it.
      final after = await store.readSync(noteId);
      final info = after.info;
      final uploaded = after.base;
      if (uploaded == null) return RestoreFailure.notApplied; // sync record
      var out = <String, Object?>{};
      var changed = false;
      final applied = await apply((cur) {
        if (!_sameState(uploaded, cur)) {
          changed = true;
          return null;
        }
        out = _run(cur, op, info, info.conflicts);
        if (out['error'] != null) return null;
        return (
          note: Note.trusted(out['note'] as Map<String, dynamic>),
          undoDrop: <String>{...(out['undoDrop'] as List).cast<String>()},
          lastSeen: 0,
        );
      }, () async {});
      if (changed) return RestoreFailure.changed;
      if (!applied || out['error'] != null || out['note'] == null) {
        return RestoreFailure.notApplied;
      }
      // The conflicts the restore resolved: `sync.json` and the state follow
      // (their sidecars get `kkjResolved` with the next upload).
      for (final (i, c) in info.conflicts.indexed) {
        final after = (out['conflicts'] as List)[i] as Map;
        if (c['resolvedAt'] != null || after['resolvedAt'] == null) continue;
        final done = Map<String, Object?>.from(after);
        // A failed write is tried once more; the conflict then stays open and
        // can be settled in the conflict sheet like any other.
        if (!await coordinator.conflictResolved(noteId, done)) {
          await coordinator.conflictResolved(noteId, done);
        }
      }
      return null;
    } catch (_) {
      return RestoreFailure.notApplied;
    }
  }

  /// The operation for [entry], with the version it restores; null when the
  /// version cannot be read (a network error too).
  Future<Json?> _read(
    String noteId,
    String fileId,
    Map<String, Object?> entry,
  ) async {
    try {
      if (entry['kind'] == 'revision') {
        final r = await source.inspectRevision(
          noteId,
          fileId,
          entry['revisionId'] as String,
        );
        return r.ok
            ? {'op': 'restoreNote', 'version': r.note!.copyJson()}
            : null;
      }
      final pageId = entry['pageId'] as String, rev = entry['rev'] as String;
      final files = await drive.list(
        kkeujeokIdQuery('sc:$noteId:$pageId:$rev'),
        fields: 'id',
      );
      // Not on Drive yet (unsent): the local file is read.
      final r = files.files.isEmpty
          ? inspectSidecarJson(
              await store.readSidecar(noteId, pageId, rev),
              noteId,
              pageId,
              rev,
            )
          : await source.inspectSidecar(
              noteId,
              files.files.first.id,
              pageId,
              rev,
            );
      return r.ok
          ? {
              'op': 'restorePage',
              'pageId': pageId,
              'page': r.page,
              'originalIndex': entry['originalIndex'],
            }
          : null;
    } on DriveError {
      return null;
    } on NoteSaveException {
      return null; // the local record cannot be read
    }
  }

  Map<String, Object?> _run(
    Note cur,
    Json op,
    SyncInfo info,
    List<Json> conflicts,
  ) {
    final version = op['version'] as Json?;
    final ctx = <String, Object?>{
      'now': canonicalNow(_clock()),
      'orderRev': _newRev(),
      'editedBy': editedBy,
      'lastSeenRemoteSeq': info.lastSeenRemoteSeq,
      if (version == null)
        'rev': _newRev()
      else
        'revs': [for (final _ in version['pages'] as List) _newRev()],
    };
    final json = cur.copyJson();
    return version == null
        ? restorePage(json, op, ctx, conflicts)
        : restoreNote(json, op, ctx, conflicts);
  }

  /// Best effort: puts back pins that were released for a pin that failed.
  Future<void> _repin(String fileId, List<String> ids) async {
    for (final id in ids) {
      try {
        await drive.updateRevision(fileId, id, keepForever: true);
      } catch (_) {}
    }
  }

  /// Step 3: pins [revisionId] and releases the oldest pins at the cap.
  /// Any failure is a sync error of the note and ends the restore.
  Future<bool> _pin(String noteId, String fileId, String revisionId) async {
    try {
      Future<Map<String, Object?>> plan() async => keepForeverRule({
        'revisions': [
          for (final v in await drive.listRevisions(fileId))
            {
              'id': v.id,
              'modifiedTime': v.modifiedTime,
              'keepForever': v.keepForever,
            },
        ],
        'target': revisionId,
      });
      var r = await plan();
      // The listing may not have caught up with the verified head: once more.
      if (r['error'] != null) {
        await _delay(const Duration(milliseconds: 500));
        r = await plan();
      }
      if (r['error'] != null) return false;
      final released = <String>[];
      for (final id in (r['release'] as List).cast<String>()) {
        try {
          await drive.updateRevision(fileId, id, keepForever: false);
          released.add(id);
        } on DriveError catch (e) {
          // Already purged by Drive: released all the same.
          if (e.kind == 'http' && e.status == 404) continue;
          await _repin(fileId, released);
          rethrow;
        }
      }
      final mark = r['mark'] as String?;
      if (mark != null) {
        try {
          await drive.updateRevision(fileId, mark, keepForever: true);
        } on DriveError {
          await _repin(fileId, released); // the old pins are not lost
          rethrow;
        }
      }
      return true;
    } on DriveError catch (e) {
      await coordinator.uploader.reportFailure(noteId, e);
      return false;
    }
  }
}
