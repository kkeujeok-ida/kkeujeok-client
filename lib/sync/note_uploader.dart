import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../drive/drive_client.dart';
import '../drive/duplicates.dart';
import '../drive/note_summary.dart';
import '../model/kkj_codec.dart';
import '../model/note.dart';
import '../storage/note_store.dart';
import '../storage/sync_device_store.dart';
import '../storage/sync_info.dart';
import 'error_class.dart';
import 'has_unsent.dart';
import 'merge_step.dart';
import 'sync_log.dart';
import 'sync_rules.dart';

/// What one [NoteUploader.upload] ended in.
enum UploadOutcome {
  /// Verified and committed (the note may be `pending` again when it was
  /// edited meanwhile).
  uploaded,

  /// Nothing to send, or not allowed now (offline, gate closed, `error`).
  skipped,

  /// The note took the event `failed`; `sync.json` says why.
  failed,
}

/// Resumable chunk: a multiple of 262,144 (spec `sync` step 2).
const resumableChunk = 8388608;

/// A thumbnail PNG over this is not written.
const maxThumbnailBytes = 2097152;

const _kkjMime = 'application/vnd.kkeujeok.kkj';

class _Failure implements Exception {
  _Failure(this.cls, {this.status, this.reason, this.clearVerify = false});

  final String cls;
  final int? status;
  final String? reason;

  /// `pendingVerify` is dropped with the failure (the merge could not run).
  final bool clearVerify;
}

/// Uploads one note at a time (spec `sync` steps 0-5 and "Start"). Everything
/// that touches the outside is injected. A note's calls run one after another
/// (a chain per note id); a second call waits for the first.
///
/// Never throws for a Drive or a local-write failure: those end in the state
/// `error` with a `lastError` and a log entry. Any other exception is a bug
/// (or a simulated crash in a test) and goes to the caller; what is on disk
/// then is what a killed process leaves, and "Start" recovers it.
class NoteUploader {
  NoteUploader({
    required this.store,
    required this.drive,
    required this.device,
    required this.log,
    required this.merge,
    required this.allowed,
    required this.online,
    required this.sleep,
    required this.jitter,
    this.thumbnail,
  });

  final NoteStore store;
  final DriveClient drive;
  final SyncDeviceStore device;
  final SyncLog log;
  final MergeStep merge;

  /// The upload gate (root folder ready, account matches).
  final Future<bool> Function() allowed;

  /// False while the device is known to be offline: no request is made.
  final Future<bool> Function() online;
  final Future<void> Function(Duration) sleep;

  /// A number in [0, 1] for [backoffRule].
  final double Function() jitter;

  /// PNG of a page at the width and height the summary names; null when it
  /// cannot be drawn (the thumbnail is then not written).
  final Future<List<int>?> Function(Map<String, dynamic> page, int w, int h)?
  thumbnail;

  final _chains = <String, Future<void>>{};

  Future<T> _chained<T>(String noteId, Future<T> Function() body) {
    final run = (_chains[noteId] ?? Future<void>.value()).then((_) => body());
    final done = run.then<void>((_) {}, onError: (Object _) {});
    _chains[noteId] = done;
    done.whenComplete(() {
      if (identical(_chains[noteId], done)) _chains.remove(noteId);
    });
    return run;
  }

  /// Uploads [noteId] when it has unsent changes or an unfinished upload.
  Future<UploadOutcome> upload(String noteId) =>
      _chained(noteId, () => _upload(noteId, recoverOnly: false));

  /// "Start": finishes an interrupted upload (`pendingVerify` set). A note
  /// without one is left to [upload].
  Future<UploadOutcome> resume(String noteId) =>
      _chained(noteId, () => _upload(noteId, recoverOnly: true));

  // ---- state -------------------------------------------------------------

  Map<String, Object?> _s(Note n) => {
    'orderRev': n.orderRev,
    'metaRev': n.metaRev,
    'pages': n.pages,
  };

  bool _differs(Note head, Note working) =>
      hasUnsentRule({
        'base': _s(head),
        'working': _s(working),
        'pendingVerify': null,
        'unsentSidecars': const <Object?>[],
      })['hasUnsent'] !=
      false;

  /// One `sync.json` write: [edit] changes the fields, then [event] moves the
  /// state through the state machine. Logs the state change.
  Future<SyncInfo> _commit(
    String noteId,
    SyncInfo Function(SyncInfo c) edit, {
    String? event,
    Note? base,
    bool Function(Note)? unsentOf,
    Future<void> Function()? committed,
  }) async {
    String? from, to;
    final done = await store.updateSync(noteId, (cur) {
      var next = edit(cur);
      from = to = cur.state.name;
      if (event != null) {
        var f = cur.state.name;
        // A synced note that has edits is `pending` (readSync says so too).
        if (f == 'synced' && event == 'upload') f = 'pending';
        final unresolved = [
          for (final c in next.conflicts)
            if (c['resolvedAt'] == null) c,
        ].length;
        final t = transition(
          f,
          event,
          unresolved: unresolved,
          unsent: unsentOf?.call(base ?? _noNote) ?? false,
        );
        from = f;
        if (t != null) {
          to = t;
          next = next.copyWith(
            state: SyncState.values.firstWhere((s) => s.name == t),
          );
        }
      }
      return next;
    }, base: base);
    await committed?.call();
    if (event != null && from != to) {
      await log.append('stateChange', {
        'noteId': noteId,
        'from': from,
        'to': to,
      });
    }
    return done;
  }

  static final Note _noNote = Note.trusted({});

  // ---- the run -----------------------------------------------------------

  Future<UploadOutcome> _upload(
    String noteId, {
    required bool recoverOnly,
  }) async {
    final s = await store.readSync(noteId);
    final working = (await store.read(noteId))?.note;
    if (working == null) return UploadOutcome.skipped; // never touched
    final info = s.info;
    if (info.state == SyncState.error) return UploadOutcome.skipped;
    final unfinished = info.pendingVerify != null;
    if (recoverOnly && !unfinished) return UploadOutcome.skipped;
    if (!unfinished && !s.hasUnsent) return UploadOutcome.skipped;
    if (!await allowed() || !await online()) return UploadOutcome.skipped;

    try {
      if (info.state != SyncState.syncing) {
        await _commit(noteId, (c) => c, event: 'upload');
      }
      await _drive(noteId, working, s);
      return UploadOutcome.uploaded;
    } on _Failure catch (f) {
      await _fail(noteId, f);
      return UploadOutcome.failed;
    } on NoteSaveException {
      await _fail(noteId, _Failure('fatal', reason: 'localWrite'));
      return UploadOutcome.failed;
    }
  }

  Future<void> _fail(String noteId, _Failure f) async {
    await log.append('error', {
      'class': f.cls,
      'noteId': noteId,
      'status': ?f.status,
      'reason': ?f.reason,
    });
    try {
      await _commit(
        noteId,
        (c) => c.copyWith(
          pendingVerify: f.clearVerify ? null : c.pendingVerify,
          lastError: {'class': f.cls, 'status': ?f.status, 'reason': ?f.reason},
        ),
        event: 'failed',
      );
    } on NoteSaveException {
      // The state could not be written; the next start repeats the step.
    }
  }

  /// One Drive call with the retry rules of `sync.errorClass` and
  /// `sync.backoff`. A [DriveError] for which [pass] is true is rethrown as
  /// it is.
  Future<T> _call<T>(
    String noteId,
    Future<T> Function() fn, {
    bool Function(DriveError)? pass,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await fn();
      } on DriveError catch (e) {
        if (pass != null && pass(e)) rethrow;
        final cls = classifyDriveError(e);
        final reason = e.kind == 'parse' ? 'parse' : e.reason;
        if (cls != 'backoff') {
          throw _Failure(cls, status: e.status, reason: reason);
        }
        attempt++;
        final plan = backoffRule({'attempt': attempt, 'jitter': jitter()});
        if (plan['retry'] != true) {
          throw _Failure(cls, status: e.status, reason: reason);
        }
        final delay = plan['delayMs'] as int;
        await log.append('backoff', {
          'class': cls,
          'attempt': attempt,
          'delayMs': delay,
          'noteId': noteId,
        });
        await sleep(Duration(milliseconds: delay));
      }
    }
  }

  Future<Note> _download(String noteId, String fileId, String revision) async {
    final bytes = await _call(
      noteId,
      () => drive.downloadRevision(fileId, revision),
    );
    await log.append('revisionDownloaded', {
      'noteId': noteId,
      'revisionId': revision,
    });
    final r = decodeKkj(bytes);
    if (r.note == null || r.note!.noteId != noteId) {
      throw _Failure(
        'unreadable',
        reason: r.status == ReadStatus.unsupportedVersion
            ? 'unsupportedVersion'
            : 'parse',
      );
    }
    return r.note!;
  }

  Future<List<DriveFile>> _all(String noteId, String q) async {
    final out = <DriveFile>[];
    String? token;
    do {
      final p = await _call(noteId, () => drive.list(q, pageToken: token));
      out.addAll(p.files);
      token = p.nextPageToken;
    } while (token != null);
    return out;
  }

  Future<void> _drive(String noteId, Note working0, SyncRead s) async {
    var info = s.info;
    final baseNote = s.base;
    var fileId = info.fileId;
    String? parent;
    var round = 1;
    String? ours;
    Note? uploaded;
    Note? snapshot; // set after a merge; else the working copy at upload time
    var skipPre = false;

    // "Start": an unfinished upload.
    final pv = info.pendingVerify;
    if (pv != null) {
      final o = pv['oursRevisionId'] as String?;
      if (o != null && fileId != null) {
        ours = o;
        parent = pv['parentRevisionId'] as String?;
        round = pv['round'] as int;
        uploaded = await _download(noteId, fileId, o);
      } else if (info.resumableSession != null) {
        final session = info.resumableSession!;
        try {
          final r = await _call(
            noteId,
            () => drive.putResumable(
              session['uri'] as String,
              session['size'] as int,
              0,
              null,
            ),
            pass: (e) =>
                e.kind == 'http' && (e.status == 404 || e.status == 410),
          );
          final f = r.file;
          if (f != null && f.headRevisionId != null) {
            fileId = f.id;
            ours = f.headRevisionId;
            parent = pv['parentRevisionId'] as String?;
            round = pv['round'] as int;
            info = await _commit(
              noteId,
              (c) => c.copyWith(
                fileId: f.id,
                pendingVerify: {...?c.pendingVerify, 'oursRevisionId': ours},
                resumableSession: null,
              ),
            );
            uploaded = await _download(noteId, f.id, ours!);
          }
        } on DriveError {
          // 404 or 410: the session is gone.
        }
        // A session that is not finished is not continued: the bytes it was
        // given are not kept, so the upload starts again at step 1.
      }
    }

    while (true) {
      if (ours == null) {
        if (!skipPre) {
          // Step 1.
          if (fileId == null) {
            final root = (await device.read()).rootFolderId;
            var intent = info.createIntent;
            if (intent == null) {
              if (root == null) throw _Failure('fatal', reason: 'rootMissing');
              intent = {'kkeujeokId': noteId, 'parentId': root};
              info = await _commit(
                noteId,
                (c) => c.copyWith(createIntent: intent),
              );
            }
            final found = await _all(noteId, kkeujeokIdQuery(noteId));
            if (found.isNotEmpty) {
              // Merging duplicate notes is Story 3.1; the earliest is used.
              final keep =
                  driveDuplicatesRule({
                        'kkeujeokId': noteId,
                        'items': [
                          for (final f in found)
                            {
                              'id': f.id,
                              'createdTime':
                                  f.createdTime ?? '9999-12-31T23:59:59.999Z',
                            },
                        ],
                      })['keep']
                      as String;
              fileId = keep;
              info = await _commit(noteId, (c) => c.copyWith(fileId: keep));
            }
          }
          if (fileId != null) {
            final id = fileId;
            final f = await _call(
              noteId,
              () => drive.get(id, fields: 'headRevisionId,trashed'),
            );
            if (f.trashed) throw _Failure('deleted', reason: 'trashed');
            final head = f.headRevisionId;
            if (head == null) throw _Failure('fatal', reason: 'noRevisionId');
            parent = head;
            if (head != info.baseHeadRevisionId) {
              final remote = await _download(noteId, id, head);
              final now = (await store.read(noteId))?.note ?? working0;
              if (!_differs(remote, now)) {
                // Our own upload from before a crash is already there.
                ours = head;
                uploaded = remote;
                parent = info.baseHeadRevisionId;
                round = 1;
                info = await _commit(
                  noteId,
                  (c) => c.copyWith(
                    pendingVerify: {
                      'parentRevisionId': parent,
                      'oursRevisionId': head,
                      'round': 1,
                    },
                  ),
                );
              } else {
                snapshot = await _merge(noteId, now, baseNote, remote);
              }
            }
          } else {
            parent = null;
          }
        }
        if (ours == null) {
          // Step 2.
          final up = await _send(
            noteId,
            fileId: fileId,
            snapshot: snapshot ?? (await store.read(noteId))?.note ?? working0,
            parent: parent,
            round: round,
            intent: info.createIntent,
          );
          fileId = up.fileId;
          ours = up.ours;
          uploaded = up.note;
        }
      }

      // Step 3.
      final id = fileId!;
      final again = await _verify(
        noteId,
        id,
        parent: parent,
        ours: ours,
        round: round,
        baseNote: baseNote,
      );
      if (again == null) {
        await _finish(noteId, id, ours, uploaded!);
        return;
      }
      snapshot = again.snapshot;
      parent = again.parent;
      round = again.round;
      ours = null;
      uploaded = null;
      skipPre = true;
    }
  }

  Future<Note> _merge(
    String noteId,
    Note working,
    Note? base,
    Note remote,
  ) async {
    final r = await merge.merge(working: working, base: base, remote: remote);
    switch (r) {
      case Merged(:final note):
        await log.append('merged', {'noteId': noteId});
        return note;
      case MergeNotImplemented():
        throw _Failure('fatal', reason: 'mergeUnavailable', clearVerify: true);
    }
  }

  /// Step 2: one request that carries content, name and summary.
  Future<({String fileId, String ours, Note note})> _send(
    String noteId, {
    required String? fileId,
    required Note snapshot,
    required String? parent,
    required int round,
    required JsonMap? intent,
  }) async {
    final bytes = encodeKkj(snapshot);
    final sum = crypto.md5.convert(bytes).toString();
    final summary = listSummaryRule({
      'op': 'write',
      'note': snapshot.copyJson(),
      'md5': sum,
    });
    if (summary.containsKey('error')) {
      throw _Failure('fatal', reason: '${summary['error']}');
    }
    final props = summary['appProperties'] as Map;
    final hint = summary['thumbnail'] as Map?;
    List<int>? png;
    if (hint != null && thumbnail != null && snapshot.pages.isNotEmpty) {
      final first = snapshot.pages.first;
      try {
        png = await thumbnail!(
          first,
          hint['width'] as int,
          hint['height'] as int,
        );
      } catch (_) {
        png = null;
      }
      if (png != null && png.length > maxThumbnailBytes) png = null;
    }
    final metadata = <String, Object?>{
      'name': summary['name'],
      'appProperties': {...props},
      if (png != null)
        'contentHints': {
          'thumbnail': {
            'image': base64Url.encode(png),
            'mimeType': 'image/png',
          },
        },
      if (fileId == null) ...{
        'mimeType': _kkjMime,
        'parents': [intent?['parentId']],
      },
    };

    // The intent of this upload is on disk before the request goes out.
    await _commit(
      noteId,
      (c) => c.copyWith(
        pendingVerify: {
          'parentRevisionId': parent,
          'oursRevisionId': null,
          'round': round,
        },
        resumableSession: null,
      ),
    );
    final kind = uploadKindRule({'size': bytes.length})['kind'] as String;
    await log.append('uploadStarted', {'noteId': noteId, 'kind': kind});
    final DriveFile file;
    if (kind == 'simple') {
      file = await _call(
        noteId,
        () => drive.uploadSimple(
          fileId: fileId,
          metadata: metadata,
          bytes: bytes,
        ),
      );
    } else {
      file = await _resumable(noteId, fileId, metadata, bytes);
    }
    final head = file.headRevisionId;
    if (head == null) throw _Failure('fatal', reason: 'noRevisionId');
    await log.append('uploadFinished', {'noteId': noteId, 'revisionId': head});
    await _commit(
      noteId,
      (c) => c.copyWith(
        fileId: file.id,
        pendingVerify: {
          'parentRevisionId': parent,
          'oursRevisionId': head,
          'round': round,
        },
        resumableSession: null,
      ),
    );
    return (fileId: file.id, ours: head, note: snapshot);
  }

  Future<DriveFile> _resumable(
    String noteId,
    String? fileId,
    Map<String, Object?> metadata,
    List<int> bytes,
  ) async {
    bool gone(DriveError e) =>
        e.kind == 'http' && (e.status == 404 || e.status == 410);
    for (var start = 0; start < 3; start++) {
      final uri = await _call(
        noteId,
        () => drive.startResumable(
          fileId: fileId,
          metadata: metadata,
          size: bytes.length,
        ),
      );
      await _commit(
        noteId,
        (c) => c.copyWith(resumableSession: {'uri': uri, 'size': bytes.length}),
      );
      var offset = 0;
      try {
        while (true) {
          final end = offset + resumableChunk > bytes.length
              ? bytes.length
              : offset + resumableChunk;
          final chunk = bytes.sublist(offset, end);
          final from = offset;
          final r = await _call(
            noteId,
            () => drive.putResumable(uri, bytes.length, from, chunk),
            pass: gone,
          );
          if (r.file != null) return r.file!;
          // 308: Drive holds [received] bytes; continue from there.
          offset = r.received > offset ? r.received : end;
          if (offset >= bytes.length) {
            // Everything was sent but Drive did not answer with the file:
            // ask once how far it got.
            final q = await _call(
              noteId,
              () => drive.putResumable(uri, bytes.length, 0, null),
              pass: gone,
            );
            if (q.file != null) return q.file!;
            throw const DriveError('parse');
          }
        }
      } on DriveError catch (e) {
        if (!gone(e)) rethrow;
        // The session is gone: again from byte 0 with a new one.
      }
    }
    throw _Failure('fatal', reason: 'sessionLost');
  }

  /// Step 3. Null when verified; else what the next upload round needs.
  Future<_Again?> _verify(
    String noteId,
    String fileId, {
    required String? parent,
    required String ours,
    required int round,
    required Note? baseNote,
  }) async {
    final plan = await _call(noteId, () async {
      // An `invalidInput` plan is asked once more without using a backoff
      // attempt; a second one counts as a network failure.
      for (var again = 0; again < 2; again++) {
        final head = (await drive.get(
          fileId,
          fields: 'headRevisionId',
        )).headRevisionId;
        final revs = await drive.listRevisions(fileId);
        final p = verifyPlanRule({
          'base': parent,
          'ours': ours,
          'revisions': [
            for (final r in revs) {'id': r.id, 'modifiedTime': r.modifiedTime},
          ],
          'head': head,
          'round': round,
        });
        if (!p.containsKey('error')) return p;
      }
      throw const DriveError('network');
    });
    await log.append('verifyRound', {
      'noteId': noteId,
      'round': round,
      'count': (plan['download'] as List).length,
    });
    switch (plan['result']) {
      case 'verified':
        return null;
      case 'merge':
        var working =
            (await store.read(noteId))?.note ?? (throw _Failure('fatal'));
        final ids = (plan['download'] as List).cast<String>();
        for (final id in ids) {
          final remote = await _download(noteId, fileId, id);
          working = await _merge(noteId, working, baseNote, remote);
        }
        return _Again(working, ids.last, round + 1);
      default:
        throw _Failure('fatal', reason: 'verifyExhausted', clearVerify: true);
    }
  }

  /// Step 5: the base moves together with everything that goes with it.
  Future<void> _finish(
    String noteId,
    String fileId,
    String ours,
    Note uploaded,
  ) async {
    final working = (await store.read(noteId))?.note;
    // `sync.hasUnsent` after the commit: base = uploaded, no pendingVerify.
    bool unsentCheck(Note n) => working == null || _differs(n, working);
    var unsidecars = false;
    await _commit(
      noteId,
      (c) {
        unsidecars = c.unsentSidecars.isNotEmpty;
        return c.copyWith(
          fileId: fileId,
          baseHeadRevisionId: ours,
          pendingVerify: null,
          resumableSession: null,
          createIntent: null,
          lastError: null,
        );
      },
      event: 'verified',
      base: uploaded,
      unsentOf: (n) => unsentCheck(n) || unsidecars,
      committed: () =>
          log.append('baseAdvanced', {'noteId': noteId, 'revisionId': ours}),
    );
  }
}

class _Again {
  _Again(this.snapshot, this.parent, this.round);

  final Note snapshot;
  final String parent;
  final int round;
}
