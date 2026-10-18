import 'dart:convert';
import 'dart:io' show FileSystemException;

import 'package:crypto/crypto.dart' as crypto;

import '../drive/drive_client.dart';
import '../drive/duplicates.dart';
import '../drive/note_summary.dart';
import '../model/ids.dart' as mid;
import '../model/kkj_codec.dart';
import '../model/note.dart';
import '../storage/note_store.dart';
import '../storage/sync_device_store.dart';
import '../storage/sync_info.dart';
import 'error_class.dart';
import 'has_unsent.dart';
import 'merge.dart';
import 'merge_step.dart';
import 'note_chain.dart';
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
const _folderMime = 'application/vnd.google-apps.folder';

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
    this.heartbeat,
    NoteChain? chain,
    DateTime Function()? clock,
    String Function()? newRev,
    this.editedBy = mid.deviceEditedBy,
  }) : _clock = clock ?? DateTime.now,
       _newRev = newRev ?? mid.newId,
       _chain = chain ?? NoteChain();

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

  /// Called before every Drive call and between chunks: keeps the upload
  /// lease of the note fresh while a long upload runs.
  final Future<void> Function(String noteId)? heartbeat;

  /// For the `ctx` of the duplicate folds (the merge reads no clock itself).
  final DateTime Function() _clock;
  final String Function() _newRev;
  final String editedBy;

  /// Shared with the receiver: one run per note at a time.
  final NoteChain _chain;

  Future<T> _chained<T>(String noteId, Future<T> Function() body) =>
      _chain.run(noteId, body);

  /// Uploads [noteId] when it has unsent changes or an unfinished upload.
  Future<UploadOutcome> upload(String noteId) =>
      _chained(noteId, () => _upload(noteId, recoverOnly: false));

  /// "Start": finishes an interrupted upload (`pendingVerify` set). A note
  /// without one is left to [upload].
  Future<UploadOutcome> resume(String noteId) =>
      _chained(noteId, () => _upload(noteId, recoverOnly: true));

  /// Story 3.24, restore step 2: uploads [noteId] until `verified`, also
  /// when nothing is unsent (then it only confirms that Drive's head is the
  /// base). Answers the revision id that holds the state now (the
  /// `baseHeadRevisionId` after the commit), or null when it could not be
  /// reached; a failure is in `sync.json` and the log like any upload error.
  Future<String?> uploadVerified(String noteId) => _chained(noteId, () async {
    try {
      var s = await store.readSync(noteId);
      if (s.info.state == SyncState.error) return null;
      if (s.hasUnsent || s.info.pendingVerify != null) {
        if (await _upload(noteId, recoverOnly: false) !=
            UploadOutcome.uploaded) {
          return null;
        }
        s = await store.readSync(noteId);
        return s.info.baseHeadRevisionId;
      }
      final base = s.info.baseHeadRevisionId, fileId = s.info.fileId;
      if (base == null || fileId == null) return null;
      if (!await allowed() || !await online()) return null;
      final f = await _call(
        noteId,
        () => drive.get(fileId, fields: 'headRevisionId,trashed'),
      );
      // Another device's newer head is not the state to pin.
      return !f.trashed && f.headRevisionId == base ? base : null;
    } on _Failure catch (f) {
      await _fail(noteId, f);
      return null;
    } on NoteSaveException {
      return null;
    }
  });

  /// A Drive call outside the upload failed (the pin of a restore, Story
  /// 3.24): handled as a sync error of the note, like an upload failure.
  Future<void> reportFailure(String noteId, DriveError e) =>
      _chained(noteId, () async {
        try {
          await _fail(
            noteId,
            _Failure(
              classifyDriveError(e),
              status: e.status,
              reason: e.kind == 'parse' ? 'parse' : e.reason,
            ),
          );
        } catch (_) {
          // The log or `sync.json` is not writable: nothing more to do here.
        }
      });

  // ---- resolved conflicts (Story 3.21) ------------------------------------

  static bool _sameConflict(JsonMap a, JsonMap b) =>
      a['pageId'] == b['pageId'] &&
      a['kind'] == b['kind'] &&
      a['rev'] == b['rev'] &&
      a['theirsRev'] == b['theirsRev'];

  /// A conflict was settled: its entry takes [conflict] (with `resolvedAt`)
  /// and the state takes the event `resolve`, in one `sync.json` write. The
  /// resolved note was saved before this runs. Throws [NoteSaveException]
  /// when `sync.json` cannot be written or has no such conflict.
  Future<void> resolved(String noteId, JsonMap conflict) =>
      _chained(noteId, () async {
        await _commit(noteId, (c) {
          final list = [
            for (final e in c.conflicts)
              if (_sameConflict(e, conflict)) {...conflict} else e,
          ];
          final found = c.conflicts.any((e) => _sameConflict(e, conflict));
          if (!found) throw NoteSaveException('no such conflict');
          return c.copyWith(conflicts: list);
        }, event: 'resolve');
        // A resolve that left the note as Drive has it (the other device's
        // deleted page removed) has nothing to send: it is saved, not
        // pending.
        final s = await store.readSync(noteId);
        if (s.info.state == SyncState.pending &&
            !s.hasUnsent &&
            s.info.unresolvedConflicts.isEmpty) {
          await store.updateSync(
            noteId,
            (c) => c.copyWith(state: SyncState.synced),
          );
          await log.append('stateChange', {
            'noteId': noteId,
            'from': 'pending',
            'to': 'synced',
          });
        }
      });

  Future<void> _logFailure(String noteId, _Failure f) => log.append('error', {
    'class': f.cls,
    'noteId': noteId,
    'status': ?f.status,
    'reason': ?f.reason,
  });

  /// A failure of the best-effort sidecar work: logged, never thrown; the
  /// next call tries again.
  Future<void> _ignored(String noteId, Object e) async {
    try {
      await _logFailure(
        noteId,
        e is _Failure ? e : _Failure('fatal', reason: 'sidecarSync'),
      );
    } catch (_) {
      // The log itself is not writable: nothing more can be done here.
    }
  }

  Future<void> _flag(String noteId, JsonMap conflict, String key) =>
      store.updateSync(
        noteId,
        (c) => c.copyWith(
          conflicts: [
            for (final e in c.conflicts)
              _sameConflict(e, conflict) ? {...e, key: true} : e,
          ],
        ),
      );

  /// Sets `kkjResolved` on the sidecar files of resolved conflicts once the
  /// resolving upload is verified (nothing unsent). A conflict is flagged
  /// only when its sidecar was found on Drive. A failure is logged per
  /// conflict and retried at the next call. Never throws.
  Future<void> markResolved(String noteId) => _chained(noteId, () async {
    final List<JsonMap> todo;
    try {
      final s = await store.readSync(noteId);
      todo = [
        for (final c in s.info.conflicts)
          if (c['resolvedAt'] != null && c['sidecarMarked'] != true) c,
      ];
      if (todo.isEmpty || s.hasUnsent || s.info.state == SyncState.error) {
        return;
      }
      if (!await allowed() || !await online()) return;
    } catch (e) {
      return _ignored(noteId, e);
    }
    for (final c in todo) {
      try {
        final at = '${c['resolvedAt']}';
        final id = 'sc:$noteId:${c['pageId']}:${c['rev']}';
        final files = await _all(noteId, kkeujeokIdQuery(id));
        for (final f in files) {
          if (f.appProperties['kkjResolved'] == at) continue;
          await _call(
            noteId,
            () => drive.update(f.id, appProperties: {'kkjResolved': at}),
          );
        }
        if (files.isNotEmpty) await _flag(noteId, c, 'sidecarMarked');
      } catch (e) {
        await _ignored(noteId, e);
      }
    }
  });

  /// App start: sidecars resolved more than 30 days ago go to the Drive
  /// trash (there is no hard delete). Best effort, logged per conflict,
  /// never throws.
  Future<void> cleanResolvedSidecars(Iterable<String> noteIds) async {
    final limit = _clock().subtract(const Duration(days: 30));
    for (final noteId in noteIds) {
      await _chained(noteId, () async {
        final List<JsonMap> todo;
        try {
          final s = await store.readSync(noteId);
          todo = [
            for (final c in s.info.conflicts)
              if (c['resolvedAt'] != null && c['sidecarTrashed'] != true) c,
          ];
          if (todo.isEmpty || !await allowed() || !await online()) return;
        } catch (e) {
          return _ignored(noteId, e);
        }
        for (final c in todo) {
          try {
            final id = 'sc:$noteId:${c['pageId']}:${c['rev']}';
            final files = await _all(noteId, kkeujeokIdQuery(id));
            var done = files.isNotEmpty;
            for (final f in files) {
              final at = DateTime.tryParse(
                f.appProperties['kkjResolved'] ?? '',
              );
              if (at == null || at.isAfter(limit)) {
                done = false;
              } else {
                await _call(noteId, () => drive.update(f.id, trashed: true));
              }
            }
            if (done) await _flag(noteId, c, 'sidecarTrashed');
          } catch (e) {
            await _ignored(noteId, e);
          }
        }
      });
    }
  }

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
    } on NoteSaveException catch (e) {
      await _fail(
        noteId,
        _Failure(
          'fatal',
          reason: e.message == syncUnreadableMessage
              ? 'syncUnreadable'
              : 'localWrite',
        ),
      );
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
  ///
  /// [beforeRetry] runs after each wait, before the call is repeated: it can
  /// find that the failed call did happen (a lost answer) and return its
  /// result instead.
  Future<T> _call<T>(
    String noteId,
    Future<T> Function() fn, {
    bool Function(DriveError)? pass,
    Future<T?> Function()? beforeRetry,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        await heartbeat?.call(noteId);
        if (attempt > 0 && beforeRetry != null) {
          final done = await beforeRetry();
          if (done != null) return done;
        }
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
          // Step 0: sidecars of earlier merges go before anything else.
          await _sendSidecars(noteId);
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
              final keep = await _foldDuplicates(noteId, found);
              fileId = keep;
              info = await _commit(noteId, (c) => c.copyWith(fileId: keep));
            }
          }
          if (fileId != null) {
            final id = fileId;
            // The working copy the sync starts from (spec `merge.requeue`).
            final start = (await store.read(noteId))?.note ?? working0;
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
                await _merge(noteId, start, baseNote, remote);
              }
            } else if (baseNote != null) {
              // Head == base: the merge runs all the same, so a page changed
              // here gets its `lineage` (spec `sync` step 1).
              await _merge(noteId, start, baseNote, baseNote, announce: false);
            }
          } else {
            parent = null;
          }
        }
        if (ours == null) {
          // Step 0 again: sidecars a merge of step 1 just made go before the
          // note too. The snapshot is the queue state after that.
          await _sendSidecars(noteId);
          // Step 2.
          final up = await _send(
            noteId,
            fileId: fileId,
            snapshot: (await store.read(noteId))?.note ?? working0,
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
      parent = again.parent;
      round = again.round;
      ours = null;
      uploaded = null;
      skipPre = true;
    }
  }

  /// Merges [remote] into the working copy through the merge step (which
  /// writes the result through the note's queue). Nothing is returned: step 2
  /// reads the queue again, so what was drawn meanwhile is in the upload.
  Future<void> _merge(
    String noteId,
    Note localAtStart,
    Note? base,
    Note remote, {
    bool announce = true,
  }) async {
    final r = await merge.merge(
      localAtStart: localAtStart,
      base: base,
      remote: remote,
    );
    switch (r) {
      case Merged(:final conflicts):
        if (announce) await log.append('merged', {'noteId': noteId});
        if (conflicts > 0) {
          await log.append('conflictFound', {'noteId': noteId});
          await _commit(noteId, (c) => c, event: 'conflictFound');
        }
      case MergeUnsupported():
        throw _Failure(
          'unreadable',
          reason: 'unsupportedVersion',
          clearVerify: true,
        );
      case MergeFailed(:final code):
        throw _Failure('fatal', reason: code, clearVerify: true);
    }
  }

  /// The bytes, MD5 and request metadata (name, summary, thumbnail) of one
  /// note upload.
  Future<({List<int> bytes, String sum, Map<String, Object?> metadata})>
  _package(Note snapshot, String? fileId, JsonMap? intent) async {
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
      try {
        png = await thumbnail!(
          snapshot.pages.first,
          hint['width'] as int,
          hint['height'] as int,
        );
      } catch (_) {
        png = null;
      }
      // Over the limit of `drive-layout` it is not written at all.
      if (png != null && png.length > maxThumbnailBytes) png = null;
    }
    // ponytail: with no thumbnail (render failed, too big, no pages) an update
    // sends no `contentHints`, so Drive keeps the previous thumbnail while
    // the name and properties are new. Drive has no way to delete a hint.
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
    return (bytes: bytes, sum: sum, metadata: metadata);
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
    final pkg = await _package(snapshot, fileId, intent);
    final bytes = pkg.bytes, sum = pkg.sum, metadata = pkg.metadata;

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
    // The whole multipart body counts, the metadata with its thumbnail too.
    final total = bytes.length + utf8.encode(jsonEncode(metadata)).length;
    final kind = uploadKindRule({'size': total})['kind'] as String;
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
        // A create whose answer was lost may have happened: look for the
        // file by its kkeujeokId before creating another.
        beforeRetry: fileId != null ? null : () => _adopt(noteId),
      );
    } else {
      file = await _resumable(noteId, fileId, metadata, bytes);
    }
    final head = file.headRevisionId;
    if (head == null) throw _Failure('fatal', reason: 'noRevisionId');
    final theirs = file.md5Checksum;
    if (theirs != null && theirs != sum) {
      throw _Failure('fatal', reason: 'md5Mismatch');
    }
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

  /// The file with this note's kkeujeokId that stays (with its head), or
  /// null. Several files are folded into one ([_foldDuplicates]).
  Future<DriveFile?> _adopt(String noteId) async {
    final found = await _all(noteId, kkeujeokIdQuery(noteId));
    if (found.isEmpty) return null;
    final keep = await _foldDuplicates(noteId, found);
    final head = await _call(
      noteId,
      () => drive.get(keep, fields: 'headRevisionId'),
    );
    return DriveFile(id: keep, headRevisionId: head.headRevisionId);
  }

  /// Several note files with one `kkeujeokId` (spec `drive-layout`,
  /// "Duplicate cleanup"): `drive.duplicates` keeps one; each other file is
  /// folded into it, `acc = merge(null, duplicate, acc)`, so the kept note's
  /// pages win and a different version of a page goes to a sidecar. Then
  /// `acc` is uploaded as the kept file and the folded files are trashed,
  /// last. A file that cannot be read, or whose merge answers anything but
  /// `merged`, is neither folded nor trashed. Returns the kept file's id.
  Future<String> _foldDuplicates(String noteId, List<DriveFile> found) async {
    final rule = driveDuplicatesRule({
      'kkeujeokId': noteId,
      'items': [
        for (final f in found)
          {
            'id': f.id,
            'createdTime': f.createdTime ?? '9999-12-31T23:59:59.999Z',
          },
      ],
    });
    final keep = rule['keep'] as String;
    final others = (rule['merge'] as List).cast<String>();
    if (others.isEmpty) return keep;

    Future<Note?> read(String id) async {
      final head = (await _call(
        noteId,
        () => drive.get(id, fields: 'headRevisionId'),
      )).headRevisionId;
      if (head == null) return null;
      final bytes = await _call(noteId, () => drive.downloadRevision(id, head));
      final n = decodeKkj(bytes).note;
      return n != null && n.noteId == noteId ? n : null;
    }

    final kept = await read(keep);
    if (kept == null) throw _Failure('unreadable', reason: 'parse');
    var acc = kept;
    final folded = <String>[];
    final records = <Map<String, Object?>>[];
    for (final id in others) {
      final dup = await read(id);
      if (dup == null) continue;
      final out = mergeNotes(null, dup.copyJson(), acc.copyJson(), {
        'now': mid.canonicalNow(_clock()),
        'orderRev': _newRev(),
        'rev': _newRev(),
        'editedBy': editedBy,
        'lastSeenRemoteSeq': 0,
      });
      if (out['result'] != 'merged') continue;
      acc = Note.trusted(out['note'] as Map<String, dynamic>);
      folded.add(id);
      records.add(out);
    }
    if (folded.isEmpty) return keep;
    // The conflicts of the folds belong to this device like any other.
    for (final out in records) {
      final rec = mergeRecords(out);
      if (rec.sidecars.isNotEmpty) {
        await store.writeSidecars(noteId, rec.sidecars);
      }
      await store.updateSync(noteId, rec.sync);
    }
    final pkg = await _package(acc, keep, null);
    final kind = uploadKindRule({
      'size': pkg.bytes.length + utf8.encode(jsonEncode(pkg.metadata)).length,
    })['kind'];
    if (kind == 'simple') {
      await _call(
        noteId,
        () => drive.uploadSimple(
          fileId: keep,
          metadata: pkg.metadata,
          bytes: pkg.bytes,
        ),
      );
    } else {
      await _resumable(noteId, keep, pkg.metadata, pkg.bytes);
    }
    for (final id in folded) {
      await _call(noteId, () => drive.update(id, trashed: true));
    }
    await log.append('duplicatesCleaned', {'count': folded.length});
    return keep;
  }

  Future<void> _deviceUpdate(SyncDevice Function(SyncDevice) change) async {
    try {
      await device.update(change);
    } on FileSystemException {
      throw _Failure('fatal', reason: 'localWrite');
    }
  }

  /// Idempotent creation of one item with a known `kkeujeokId` (spec
  /// `drive-layout`): the intent is saved, the item is looked for, created
  /// when missing, looked for again (a listing that lags falls back to the
  /// id of the create), duplicates are cleaned up, the intent is cleared.
  /// Returns the id of the item that stays.
  Future<String> _ensureItem(
    String noteId, {
    required String kkeujeokId,
    required String kind,
    required String parentId,
    required bool folder,
    required Future<DriveFile> Function() create,
  }) async {
    await _deviceUpdate(
      (d) => d.copyWith(
        createIntents: [
          for (final i in d.createIntents)
            if (i['kkeujeokId'] != kkeujeokId) i,
          {'kkeujeokId': kkeujeokId, 'kind': kind, 'parentId': parentId},
        ],
      ),
    );
    var found = await _all(noteId, kkeujeokIdQuery(kkeujeokId));
    String? id;
    if (found.isEmpty) {
      final made = await _call(noteId, create);
      found = await _all(noteId, kkeujeokIdQuery(kkeujeokId));
      if (found.isEmpty) id = made.id;
    }
    id ??= await _keepOne(noteId, kkeujeokId, found, folder: folder);
    await _deviceUpdate(
      (d) => d.copyWith(
        createIntents: [
          for (final i in d.createIntents)
            if (i['kkeujeokId'] != kkeujeokId) i,
        ],
      ),
    );
    return id;
  }

  /// `drive.duplicates` keeps one; the others of a folder first hand their
  /// children over, then every other item is trashed (last).
  Future<String> _keepOne(
    String noteId,
    String kkeujeokId,
    List<DriveFile> found, {
    required bool folder,
  }) async {
    final rule = driveDuplicatesRule({
      'kkeujeokId': kkeujeokId,
      'items': [
        for (final f in found)
          {
            'id': f.id,
            'createdTime': f.createdTime ?? '9999-12-31T23:59:59.999Z',
          },
      ],
    });
    final keep = rule['keep'] as String;
    final others = (rule['merge'] as List).cast<String>();
    for (final dup in others) {
      if (folder) {
        for (final kid in await _all(noteId, childrenQuery(dup))) {
          await _call(
            noteId,
            () => drive.update(kid.id, addParents: keep, removeParents: dup),
          );
        }
      }
      await _call(noteId, () => drive.update(dup, trashed: true));
    }
    if (others.isNotEmpty) {
      await log.append('duplicatesCleaned', {'count': others.length});
    }
    return keep;
  }

  /// Step 0 (spec `sync`): the sidecars in `unsentSidecars` are uploaded,
  /// each by idempotent creation under `.conflicts/<noteId>`, and removed
  /// from the list when confirmed. A failure ends the upload before the note
  /// is sent.
  Future<void> _sendSidecars(String noteId) async {
    final pending = (await store.readSync(noteId)).info.unsentSidecars;
    if (pending.isEmpty) return;
    final root = (await device.read()).rootFolderId;
    if (root == null) throw _Failure('fatal', reason: 'rootMissing');
    final cf = await _ensureItem(
      noteId,
      kkeujeokId: 'conflicts',
      kind: 'conflicts',
      parentId: root,
      folder: true,
      create: () => drive.create({
        'name': '.conflicts',
        'mimeType': _folderMime,
        'parents': [root],
        'appProperties': {'kkeujeokId': 'conflicts'},
      }),
    );
    await _deviceUpdate((d) => d.copyWith(conflictsFolderId: cf));
    final folder = await _ensureItem(
      noteId,
      kkeujeokId: 'cf:$noteId',
      kind: 'noteConflicts',
      parentId: cf,
      folder: true,
      create: () => drive.create({
        'name': noteId,
        'mimeType': _folderMime,
        'parents': [cf],
        'appProperties': {'kkeujeokId': 'cf:$noteId'},
      }),
    );
    for (final e in pending) {
      final pageId = e['pageId'] as String, rev = e['rev'] as String;
      final sc = await store.readSidecar(noteId, pageId, rev);
      if (sc == null) {
        await log.append('error', {
          'class': 'fatal',
          'noteId': noteId,
          'reason': 'sidecarMissing',
        });
      } else {
        final conflict = (await store.readSync(noteId)).info.conflicts
            .where((c) => c['pageId'] == pageId && c['rev'] == rev)
            .firstOrNull;
        final bytes = utf8.encode(jsonEncode(sc));
        final id = 'sc:$noteId:$pageId:$rev';
        await _ensureItem(
          noteId,
          kkeujeokId: id,
          kind: 'sidecar',
          parentId: folder,
          folder: false,
          create: () => drive.uploadSimple(
            metadata: {
              'name': '$pageId-$rev.json',
              'mimeType': 'application/json',
              'parents': [folder],
              'appProperties': {
                'kkeujeokId': id,
                'kkjEdited': '${sc['editedAt']}',
                'kkjIndex': '${conflict?['originalIndex'] ?? 0}',
                if (conflict?['resolvedAt'] != null)
                  'kkjResolved': '${conflict!['resolvedAt']}',
              },
            },
            bytes: bytes,
          ),
        );
      }
      await _commit(
        noteId,
        (c) => c.copyWith(
          unsentSidecars: [
            for (final x in c.unsentSidecars)
              if (!(x['pageId'] == pageId && x['rev'] == rev)) x,
          ],
        ),
      );
    }
  }

  Future<DriveFile> _resumable(
    String noteId,
    String? fileId,
    Map<String, Object?> metadata,
    List<int> bytes,
  ) async {
    bool gone(DriveError e) =>
        e.kind == 'http' && (e.status == 404 || e.status == 410);
    final size = bytes.length;
    for (var start = 0; start < 3; start++) {
      final uri = await _call(
        noteId,
        () => drive.startResumable(
          fileId: fileId,
          metadata: metadata,
          size: size,
        ),
      );
      await _commit(
        noteId,
        (c) => c.copyWith(resumableSession: {'uri': uri, 'size': size}),
      );
      var offset = 0; // what Drive holds
      var stalled = 0;
      try {
        while (stalled < 3) {
          final r = await _call<ResumableResult>(
            noteId,
            () {
              final end = offset + resumableChunk > size
                  ? size
                  : offset + resumableChunk;
              return drive.putResumable(
                uri,
                size,
                offset,
                bytes.sublist(offset, end),
              );
            },
            pass: gone,
            // A chunk that timed out may have arrived: ask where Drive is.
            beforeRetry: () async {
              final q = await drive.putResumable(uri, size, 0, null);
              offset = q.received;
              return q.file == null ? null : q;
            },
          );
          if (r.file != null) return r.file!;
          // 308: Drive holds [received] bytes, never trusted past that.
          if (r.received >= size) break; // all sent, no file: new session
          stalled = r.received > offset ? 0 : stalled + 1;
          offset = r.received;
        }
      } on DriveError catch (e) {
        if (!gone(e)) rethrow;
      }
      // The session is gone or went nowhere: again from byte 0.
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
        final String? head;
        final List<DriveRevision> revs;
        try {
          head = (await drive.get(
            fileId,
            fields: 'headRevisionId',
          )).headRevisionId;
          revs = await drive.listRevisions(fileId);
        } on DriveError catch (e) {
          // Not the note's fault: kept apart from `unreadable/parse`.
          if (e.kind != 'parse') rethrow;
          throw _Failure('fatal', reason: 'verifyParse');
        }
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
        // The listing may not have caught up: wait before asking again,
        // without using a backoff attempt.
        final w = backoffRule({'attempt': 1, 'jitter': jitter()});
        await sleep(Duration(milliseconds: (w['delayMs'] as int?) ?? 1000));
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
        final ids = (plan['download'] as List).cast<String>();
        for (final id in ids) {
          // Each revision is merged into the working copy the previous one
          // left (spec `sync` step 3); `base` stays the base copy.
          final start =
              (await store.read(noteId))?.note ?? (throw _Failure('fatal'));
          final remote = await _download(noteId, fileId, id);
          await _merge(noteId, start, baseNote, remote);
        }
        return _Again(ids.last, round + 1);
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
    // An edit may have landed between the read above and the commit: look
    // again, now that the base is the uploaded note.
    final after = (await store.read(noteId))?.note;
    if (after != null && _differs(uploaded, after)) {
      await _commit(noteId, (c) => c, event: 'edit');
    }
  }
}

class _Again {
  _Again(this.parent, this.round);

  final String parent;
  final int round;
}
