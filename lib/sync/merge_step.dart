import '../model/ids.dart';
import '../model/note.dart';
import '../storage/note_store.dart';
import '../storage/sync_info.dart';
import 'merge.dart';

/// What a [MergeStep] answers.
sealed class MergeOutcome {
  const MergeOutcome();
}

/// The versions were merged and the result is the working copy now (the step
/// wrote it through the note's queue); [note] is that copy and [conflicts]
/// the number of conflicts the merge found. Edits made later are not in it.
class Merged extends MergeOutcome {
  const Merged(this.note, {this.conflicts = 0});

  final Note note;
  final int conflicts;
}

/// `remote.formatVersion` is newer than supported: nothing was written, and
/// the Drive file is never overwritten (spec `merge.formatVersion`).
class MergeUnsupported extends MergeOutcome {
  const MergeUnsupported();
}

/// The merge could not run; [code] is a `merge.formatVersion` error code
/// (`noteIdMismatch`, `duplicatePageId`) or `queueBusy`. Nothing was written.
class MergeFailed extends MergeOutcome {
  const MergeFailed(this.code);

  final String code;
}

/// The seam the uploader calls when Drive holds a version that is not ours
/// (spec `sync` steps 1 and 3). [localAtStart] is the working copy the sync
/// started from, [base] is null for a note never uploaded. The step merges
/// against the queue state at commit time (spec `merge.requeue`): whatever
/// was drawn while the network ran is part of the local side.
abstract interface class MergeStep {
  Future<MergeOutcome> merge({
    required Note localAtStart,
    required Note? base,
    required Note remote,
  });
}

/// What a live editor does with a merge: [merge] is called with the live
/// note, synchronously, and answers the note to adopt (null = leave it) with
/// the pages whose undo records go; [record] writes the sidecars and
/// `sync.json` and runs between the calls. The host repeats [merge] when the
/// live note changed while [record] ran, adopts the last result with no
/// `await` between the check and the adoption, saves it through its own
/// queue, and answers false when it gave up (or when the save failed).
/// `lastSeen` is the merge's `lastSeenRemoteSeq` (0: none); the host raises
/// its own to the greatest.
typedef LiveMerge = ({Note note, Set<String> undoDrop, int lastSeen})? Function(
  Note live,
);
typedef MergeHost = Future<bool> Function(
  LiveMerge merge,
  Future<void> Function() record,
);

/// The open editors, by note id.
class MergeHosts {
  final _hosts = <String, MergeHost>{};

  void register(String noteId, MergeHost host) => _hosts[noteId] = host;

  void unregister(String noteId, MergeHost host) {
    if (_hosts[noteId] == host) _hosts.remove(noteId);
  }

  MergeHost? of(String noteId) => _hosts[noteId];
}

/// What `sync.json` and the sidecar files get from one merge output: the new
/// conflicts (never added twice), their sidecars, and `lastSeenRemoteSeq`.
({List<Map<String, Object?>> sidecars, SyncInfo Function(SyncInfo) sync})
mergeRecords(Map<String, Object?> out) {
  final conflicts = (out['conflicts'] as List).cast<Map<String, dynamic>>();
  final sidecars = (out['sidecars'] as List).cast<Map<String, dynamic>>();
  final seen = out['lastSeenRemoteSeq'] as int;
  bool same(Map<String, Object?> a, Map<String, dynamic> b) =>
      a['pageId'] == b['pageId'] &&
      a['kind'] == b['kind'] &&
      a['rev'] == b['rev'] &&
      a['theirsRev'] == b['theirsRev'];
  SyncInfo sync(SyncInfo c) {
    final cs = [...c.conflicts], us = [...c.unsentSidecars];
    var changed = false;
    for (var i = 0; i < conflicts.length; i++) {
      if (cs.any((e) => same(e, conflicts[i]))) continue;
      changed = true;
      cs.add({...conflicts[i]});
      final s = sidecars[i];
      if (!us.any((e) => e['pageId'] == s['pageId'] && e['rev'] == s['rev'])) {
        us.add({'pageId': s['pageId'], 'rev': s['rev']});
      }
    }
    final raise = seen > c.lastSeenRemoteSeq;
    if (!changed && !raise) return c;
    return c.copyWith(
      conflicts: cs,
      unsentSidecars: us,
      extra: raise ? {...c.extra, 'lastSeenRemoteSeq': seen} : null,
    );
  }

  return (
    sidecars: [
      for (final s in sidecars) {...s},
    ],
    sync: sync,
  );
}

/// The real step: merges with [mergeRequeueNotes] against the note as it is
/// when the result is committed. A closed note is merged under its store lock
/// ([NoteStore.mergeWorking]); an open one through its editor's [MergeHosts]
/// entry, so the editor's own queue and undo history stay the only writers of
/// what it shows.
class QueueMergeStep implements MergeStep {
  QueueMergeStep({
    required this.store,
    required this.hosts,
    this.editedBy = deviceEditedBy,
    DateTime Function()? clock,
    String Function()? newRev,
    this.onApplied,
  }) : _clock = clock ?? DateTime.now,
       _newRev = newRev ?? newId;

  final NoteStore store;
  final MergeHosts hosts;
  final String editedBy;
  final DateTime Function() _clock;
  final String Function() _newRev;

  /// Called after a closed note's working copy was replaced: the place to
  /// drop the undo records of [undoDrop] pages from a kept history.
  final void Function(String noteId, Note merged, Set<String> undoDrop)?
  onApplied;

  Json _ctx(int lastSeen) => {
    'now': canonicalNow(_clock()),
    'orderRev': _newRev(),
    'rev': _newRev(),
    'editedBy': editedBy,
    'lastSeenRemoteSeq': lastSeen,
  };

  static MergeOutcome? _early(Map<String, Object?> out) {
    if (out['result'] == 'unsupportedVersion') return const MergeUnsupported();
    if (out['result'] != 'merged') return MergeFailed(out['error'] as String);
    return null;
  }

  @override
  Future<MergeOutcome> merge({
    required Note localAtStart,
    required Note? base,
    required Note remote,
  }) async {
    final noteId = localAtStart.noteId;
    Map<String, Object?> run(Note live, int lastSeen) => mergeRequeueNotes(
      base: base?.copyJson(),
      localAtStart: localAtStart.copyJson(),
      localAtCommit: live.copyJson(),
      remote: remote.copyJson(),
      ctx: _ctx(lastSeen),
    );
    bool unchanged(Note a, Note b) => jsonEqual(a.copyJson(), b.copyJson());

    final host = hosts.of(noteId);
    if (host != null) {
      final lastSeen = (await store.readSync(noteId)).info.lastSeenRemoteSeq;
      var out = <String, Object?>{};
      final ok = await host(
        (live) {
          out = run(live, lastSeen);
          if (_early(out) != null) return null;
          final next = Note.trusted(out['note'] as Json);
          if (unchanged(live, next)) return null;
          return (
            note: next,
            undoDrop: <String>{...(out['undoDrop'] as List).cast<String>()},
            lastSeen: out['lastSeenRemoteSeq'] as int,
          );
        },
        () async {
          if (_early(out) != null) return;
          final rec = mergeRecords(out);
          if (rec.sidecars.isNotEmpty) {
            await store.writeSidecars(noteId, rec.sidecars);
          }
          if ((out['conflicts'] as List).isNotEmpty ||
              (out['lastSeenRemoteSeq'] as int) > lastSeen) {
            await store.updateSync(noteId, rec.sync);
          }
        },
      );
      if (!ok) return const MergeFailed('queueBusy');
      return _early(out) ??
          Merged(
            Note.trusted(out['note'] as Json),
            conflicts: (out['conflicts'] as List).length,
          );
    }

    Note? applied;
    var drop = <String>{};
    final out = await store.mergeWorking<Map<String, Object?>>(noteId, (
      cur,
      info,
    ) {
      final o = run(cur, info.lastSeenRemoteSeq);
      if (_early(o) != null) {
        return (value: o, note: null, sync: null, sidecars: const []);
      }
      final next = Note.trusted(o['note'] as Json);
      final rec = mergeRecords(o);
      final synced = rec.sync(info);
      if (!unchanged(cur, next)) {
        applied = next;
        drop = <String>{...(o['undoDrop'] as List).cast<String>()};
      }
      return (
        value: o,
        note: applied,
        sync: identical(synced, info) ? null : (_) => synced,
        sidecars: rec.sidecars,
      );
    });
    final early = _early(out);
    if (early != null) return early;
    final next = applied;
    if (next != null) onApplied?.call(noteId, next, drop);
    return Merged(
      next ?? Note.trusted(out['note'] as Json),
      conflicts: (out['conflicts'] as List).length,
    );
  }
}
