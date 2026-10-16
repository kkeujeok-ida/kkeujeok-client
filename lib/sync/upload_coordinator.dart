import 'dart:io';

import '../storage/note_data.dart';
import '../storage/note_store.dart';
import '../storage/sync_info.dart';
import 'note_uploader.dart';
import 'open_note.dart';
import 'sync_log.dart';
import 'sync_rules.dart';

/// A per-note `upload.lease` file: exclusive create, stale after
/// [staleAfter], so the app and the WorkManager task never upload one note
/// together.
class UploadLease {
  UploadLease(
    this._data,
    this._clock, {
    this.staleAfter = const Duration(minutes: 10),
  });

  final NoteData _data;
  final DateTime Function() _clock;
  final Duration staleAfter;

  Future<File> _file(String noteId) async {
    final root = await _data.notesDir();
    final s = Platform.pathSeparator;
    return File('${root.path}$s$noteId${s}upload.lease');
  }

  /// False when another holder has a fresh lease (or the note has no
  /// folder). Never throws.
  Future<bool> acquire(String noteId) async {
    try {
      final f = await _file(noteId);
      for (var i = 0; i < 2; i++) {
        try {
          await f.create(exclusive: true);
          await f.writeAsString('${_clock().millisecondsSinceEpoch}');
          return true;
        } on FileSystemException {
          if (!await f.exists()) return false; // no folder
          int? t;
          try {
            t = int.tryParse(await f.readAsString());
          } catch (_) {}
          final age = t == null
              ? staleAfter
              : _clock().difference(DateTime.fromMillisecondsSinceEpoch(t));
          if (age < staleAfter) return false;
          await f.delete(); // stale: taken over, once
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> release(String noteId) async {
    try {
      final f = await _file(noteId);
      if (await f.exists()) await f.delete();
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
  });

  final NoteStore store;
  final NoteUploader uploader;
  final OpenNote openNote;
  final UploadLease lease;
  final SyncLog log;
  final Future<bool> Function() allowed;
  final Future<bool> Function() online;

  /// Asks WorkManager for one task that runs when the network is there.
  final Future<void> Function() schedule;

  /// Set by the open editor: waits until its save queue is on disk.
  Future<void> Function()? flushOpen;

  bool _started = false;

  // `backoff` is the class of a note whose 7 network retries ran out.
  static const _retryClasses = {'backoff', 'quota', 'reauth', 'fatal'};

  Future<bool> _needsUpload(String noteId) async {
    final s = await store.readSync(noteId);
    return s.info.state != SyncState.error &&
        (s.hasUnsent || s.info.pendingVerify != null);
  }

  Future<void> _one(String noteId, {bool recover = false}) async {
    try {
      if (!await _needsUpload(noteId)) return;
      if (!await allowed() || !await online()) {
        await schedule();
        return;
      }
      if (!await lease.acquire(noteId)) return;
      try {
        if (recover) {
          await uploader.resume(noteId);
        } else {
          await uploader.upload(noteId);
        }
      } finally {
        await lease.release(noteId);
      }
    } catch (_) {
      // Whatever went wrong is in `sync.json` and the log, or it was a
      // crash; "Start" repeats the step.
    }
  }

  Future<void> _all({required bool includeOpen, bool recover = false}) async {
    try {
      final open = includeOpen ? null : await openNote.read();
      for (final id in await store.ids()) {
        if (id == open) continue;
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
  /// get `retry`, then unsent notes go (the open one stays).
  Future<void> foreground() async {
    try {
      for (final id in await store.ids()) {
        await _retry(id);
      }
    } catch (_) {}
    await _all(includeOpen: false);
  }

  Future<void> _retry(String noteId) async {
    try {
      final s = await store.readSync(noteId);
      if (s.info.state != SyncState.error) return;
      final cls = s.info.lastError?['class'];
      if (!_retryClasses.contains(cls)) return; // deleted, unreadable: never
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
