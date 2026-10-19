import 'dart:io';
import 'dart:math';

import '../storage/note_data.dart';
import '../storage/note_store.dart';
import '../storage/sync_info.dart';
import 'note_uploader.dart';
import 'open_note.dart';
import 'sync_log.dart';
import 'sync_rules.dart';

/// A per-note `upload.lease` file (`<owner token>:<milliseconds>:<pid>`), so the
/// app and the WorkManager task never upload one note together.
///
/// - Created exclusively; its content is then put in place by temp file and
///   rename. In the moment between, the file is empty: an empty or
///   unreadable lease counts by its file time, so it is fresh.
/// - Stale after [staleAfter] without [renew]. A stale lease is moved aside
///   (only one contender succeeds) and taken over only when what was moved
///   is what was judged stale.
/// - A lease written by another process id is stale at once: the app was
///   killed mid-upload and no one is uploading (the WorkManager task runs in
///   the app's own process).
/// - Only the owner token releases or renews it.
class UploadLease {
  UploadLease(
    this._data,
    this._clock, {
    this.staleAfter = const Duration(minutes: 10),
    int? processId,
  }) : _pid = processId ?? pid;

  final NoteData _data;
  final DateTime Function() _clock;
  final Duration staleAfter;
  final int _pid;
  final _held = <String, String>{};
  static final _random = Random.secure();

  Future<File> _file(String noteId) async {
    final root = await _data.notesDir();
    final s = Platform.pathSeparator;
    return File('${root.path}$s$noteId${s}upload.lease');
  }

  static String _newToken() =>
      List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();

  Future<String?> _text(File f) async {
    try {
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  ({String token, int ms, int? pid})? _parse(String? text) {
    final m = RegExp(r'^([0-9a-f]{16}):(\d+)(?::(\d+))?$')
        .firstMatch(text ?? '');
    if (m == null) return null;
    final p = m.group(3);
    return (
      token: m.group(1)!,
      ms: int.parse(m.group(2)!),
      pid: p == null ? null : int.parse(p),
    );
  }

  Future<void> _put(File f, String token) async {
    final tmp = File('${f.path}.$token.tmp');
    await tmp.writeAsString('$token:${_clock().millisecondsSinceEpoch}:$_pid');
    await tmp.rename(f.path);
  }

  Future<bool> _fresh(File f, String? text) async {
    final p = _parse(text);
    if (p != null) {
      if (p.pid != null && p.pid != _pid) return false;
      return _clock().difference(DateTime.fromMillisecondsSinceEpoch(p.ms)) <
          staleAfter;
    }
    try {
      return DateTime.now().difference(await f.lastModified()) < staleAfter;
    } catch (_) {
      return true; // cannot tell: leave it alone
    }
  }

  /// False when another holder has a fresh lease (or the note has no
  /// folder). Never throws.
  Future<bool> acquire(String noteId) async {
    try {
      final f = await _file(noteId);
      final token = _newToken();
      for (var i = 0; i < 3; i++) {
        try {
          await f.create(exclusive: true);
          await _put(f, token);
          _held[noteId] = token;
          return true;
        } on FileSystemException {
          if (!await f.exists()) {
            if (!await f.parent.exists()) return false; // no folder
            continue; // released meanwhile
          }
          final judged = await _text(f);
          if (await _fresh(f, judged)) return false;
          final aside = File('${f.path}.$token.stale');
          try {
            await f.rename(aside.path);
          } on FileSystemException {
            continue; // someone else moved it first
          }
          final moved = await _text(aside);
          if (moved != judged) {
            // A live lease was taken by mistake: put it back if free.
            try {
              if (await f.exists()) {
                await aside.delete();
              } else {
                await aside.rename(f.path);
              }
            } catch (_) {}
            return false;
          }
          await aside.delete();
        }
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _mine(File f, String noteId) async {
    final t = _held[noteId];
    return t != null && _parse(await _text(f))?.token == t;
  }

  /// Keeps the lease fresh while a long upload runs. Never throws.
  Future<void> renew(String noteId) async {
    try {
      final f = await _file(noteId);
      if (await _mine(f, noteId)) await _put(f, _held[noteId]!);
    } catch (_) {}
  }

  /// Frees the lease, only when this holder owns it. Never throws.
  Future<void> release(String noteId) async {
    try {
      final f = await _file(noteId);
      if (await _mine(f, noteId)) await f.delete();
      _held.remove(noteId);
    } catch (_) {}
  }
}

/// The upload triggers of spec `sync` "Triggers and polling". Every method
/// completes without throwing.
class UploadCoordinator {
  UploadCoordinator({
    required this.store,
    required this.uploader,
    required this.openNote,
    required this.lease,
    required this.log,
    required this.allowed,
    required this.online,
    required this.schedule,
    this.receive,
  });

  final NoteStore store;
  final NoteUploader uploader;
  final OpenNote openNote;
  final UploadLease lease;
  final SyncLog log;
  final Future<bool> Function() allowed;
  final Future<bool> Function() online;

  /// Asks WorkManager for one task that runs when the network is there.
  /// Never throws for the caller's sake: failures are swallowed here.
  final Future<void> Function() schedule;

  /// Asks Drive for remote changes (`changes.list`), for [syncNow].
  final Future<void> Function()? receive;

  /// Set by the open editor: waits until its save queue is on disk.
  Future<void> Function()? flushOpen;

  bool _started = false;

  Future<void> _schedule() async {
    try {
      await schedule();
    } catch (_) {}
  }

  // `backoff` is the class of a note whose 7 network retries ran out.
  static const _retryClasses = {
    'backoff',
    'quota',
    'reauth',
    'fatal',
    'unreadable',
  };

  // These end the same way again at the next trigger, so they are retried
  // once per app process, not at every trigger.
  static const _retryOnce = {
    'verifyExhausted',
    'sessionLost',
    'noteIdMismatch',
    'duplicatePageId',
    'verifyParse',
    'parse',
  };
  final _retried = <String>{};

  /// (upload needed, a resolved sidecar still to mark), from one read.
  Future<(bool, bool, bool)> _needs(String noteId) async {
    final s = await store.readSync(noteId);
    return (
      s.info.state == SyncState.syncing &&
          !s.hasUnsent &&
          s.info.pendingVerify == null,
      s.info.state != SyncState.error &&
          (s.hasUnsent || s.info.pendingVerify != null),
      s.info.conflicts.any(
        (c) => c['resolvedAt'] != null && c['sidecarMarked'] != true,
      ),
    );
  }

  Future<void> _one(String noteId, {bool recover = false}) async {
    try {
      final (stuck, upload, mark) = await _needs(noteId);
      if (stuck) {
        // Story 11.2: `syncing` with nothing to send ends here, offline too.
        if (!await lease.acquire(noteId)) {
          await _schedule();
          return;
        }
        try {
          await uploader.settleStuck(noteId);
        } finally {
          await lease.release(noteId);
        }
      }
      if (!upload) {
        if (mark) await uploader.markResolved(noteId);
        return;
      }
      if (!await allowed() || !await online()) {
        await _schedule();
        return;
      }
      if (!await lease.acquire(noteId)) {
        // Another holder is uploading it, or its lease is not stale yet: the
        // trigger is not dropped, a task comes back later.
        await _schedule();
        return;
      }
      try {
        final o = recover
            ? await uploader.resume(noteId)
            : await uploader.upload(noteId);
        if (o == UploadOutcome.failed &&
            (await store.readSync(noteId)).info.lastError?['class'] ==
                'backoff') {
          await _schedule(); // try again when the network is back
        }
        if (mark) await uploader.markResolved(noteId);
      } finally {
        await lease.release(noteId);
      }
    } catch (_) {
      // Whatever went wrong is in `sync.json` and the log, or it was a
      // crash; "Start" repeats the step.
    }
  }

  Future<void> _all({
    required bool includeOpen,
    bool recover = false,
    bool retryErrors = true,
  }) async {
    try {
      final open = includeOpen ? null : await openNote.read();
      for (final id in await store.ids()) {
        if (id == open) continue;
        if (retryErrors) await _retry(id);
        await _one(id, recover: recover);
      }
    } catch (_) {}
  }

  /// The note was closed: it is uploaded when it has unsent changes.
  Future<void> noteClosed(String noteId) => _one(noteId);

  /// The app went to the background: the open note's queue is flushed, then
  /// every unsent note, the open one too, is uploaded.
  Future<void> appBackgrounded() async {
    try {
      await flushOpen?.call();
    } catch (_) {}
    await _all(includeOpen: true);
  }

  /// "Start": interrupted uploads are finished first, then unsent notes go.
  Future<void> appStarted() async {
    _started = true;
    await openNote.clear(); // nothing is open when the app starts
    await _all(includeOpen: true, recover: true);
    await _all(includeOpen: true);
    try {
      await uploader.cleanResolvedSidecars(await store.ids());
    } catch (_) {}
  }

  /// A conflict was settled in the editor (Story 3.21): its `sync.json`
  /// entry and the state follow. False when that could not be written.
  Future<bool> conflictResolved(
    String noteId,
    Map<String, Object?> conflict,
  ) async {
    try {
      await uploader.resolved(noteId, conflict);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Restore step 2 (Story 3.24): the open note's queue reaches the disk,
  /// then the note is uploaded and verified. Answers the revision id that
  /// holds the state, or null when that failed (nothing may be restored then).
  /// Never throws.
  Future<String?> uploadForRestore(String noteId) async {
    try {
      try {
        await flushOpen?.call();
      } catch (_) {
        return null; // the last strokes may not be on disk: pin nothing
      }
      await _retry(noteId, manual: true); // a note still in `error` ends below
      if (!await allowed() || !await online()) return null;
      if (!await lease.acquire(noteId)) return null;
      try {
        return await uploader.uploadVerified(noteId);
      } finally {
        await lease.release(noteId);
      }
    } catch (_) {
      return null;
    }
  }

  /// Interrupted uploads, then unsent notes, except the open one: the
  /// WorkManager task, and what waited while the gate was closed.
  Future<void> uploadUnsent() async {
    await _all(includeOpen: false, recover: true);
    await _all(includeOpen: false);
  }

  /// The upload gate opened (root folder ready): the first time this is
  /// [appStarted], later it uploads what waited.
  Future<void> rootReady() => _started ? uploadUnsent() : appStarted();

  /// Back to the foreground: notes in `error` of a class that can recover
  /// get `retry` (as at every other upload trigger), then unsent notes go
  /// (the open one stays).
  Future<void> foreground() async {
    try {
      // The open note is not uploaded, but its `error` is cleared so the
      // display and the next close or background upload go on.
      final open = await openNote.read();
      if (open != null) await _retry(open);
    } catch (_) {}
    await _all(includeOpen: false);
  }

  /// The connection came back: unsent notes except the open one go, a note
  /// in `error` waits for its own retry (a full Drive is not hammered).
  Future<void> reconnected() => _all(includeOpen: false, retryErrors: false);

  /// [지금 동기화]: the open note's queue reaches the disk, the note is
  /// uploaded without closing it, then Drive is asked for changes. A note in
  /// `error` gets `retry` first, as for [다시 시도].
  Future<void> syncNow(String noteId) async {
    try {
      await flushOpen?.call();
    } catch (_) {}
    await _retry(noteId, manual: true);
    await _one(noteId);
    try {
      await receive?.call();
    } catch (_) {}
  }

  /// [다시 시도]: `error` to `pending` for this note, then it uploads.
  Future<void> retry(String noteId) async {
    await _retry(noteId, manual: true);
    await _one(noteId);
  }

  /// After a finished sign-in: every note in `error` of a class that can
  /// recover gets `retry`, then unsent notes go (the open one stays; it
  /// uploads when closed).
  Future<void> retryAll() async {
    try {
      for (final id in await store.ids()) {
        await _retry(id, manual: true);
      }
    } catch (_) {}
    await _all(includeOpen: false);
  }

  Future<void> _retry(String noteId, {bool manual = false}) async {
    try {
      final s = await store.readSync(noteId);
      if (s.info.state != SyncState.error) return;
      final err = s.info.lastError;
      if (!_retryClasses.contains(err?['class'])) return; // deleted etc.
      // An `unreadable` note is retried only when its upload awaits a
      // verify (Story 11.1): the retry reads Drive and never overwrites it.
      if (err?['class'] == 'unreadable' && s.info.pendingVerify == null) {
        return;
      }
      if (!manual &&
          _retryOnce.contains(err?['reason']) &&
          !_retried.add(noteId)) {
        return;
      }
      var moved = false;
      await store.updateSync(noteId, (cur) {
        final t = cur.state == SyncState.error
            ? transition('error', 'retry')
            : null;
        moved = t != null;
        return t == null ? cur : cur.copyWith(state: SyncState.pending);
      });
      if (moved) {
        await log.append('stateChange', {
          'noteId': noteId,
          'from': 'error',
          'to': 'pending',
        });
      }
    } catch (_) {}
  }
}
