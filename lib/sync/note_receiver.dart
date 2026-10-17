import 'package:flutter/foundation.dart';

import '../drive/auth_gateway.dart';
import '../drive/drive_client.dart';
import '../drive/note_summary.dart';
import '../model/kkj_codec.dart';
import '../model/note.dart';
import '../storage/note_store.dart';
import '../storage/sync_device_store.dart';
import '../storage/sync_info.dart';
import 'error_class.dart';
import 'has_unsent.dart';
import 'merge_step.dart';
import 'note_chain.dart';
import 'sync_log.dart';
import 'sync_rules.dart';

/// A note another device made that is not on this device yet, drawn from
/// its Drive summary while the file is downloaded.
class RemoteCard {
  const RemoteCard({
    required this.noteId,
    required this.fileId,
    required this.title,
    this.modifiedAt,
  });

  final String noteId;
  final String fileId;
  final String title;

  /// Canonical timestamp or null.
  final String? modifiedAt;
}

/// What the UI shows of a receive (the label is `receiving`, spec `sync`
/// "What is shown").
@immutable
class ReceiveState {
  const ReceiveState({
    this.receiving = const {},
    this.cards = const [],
    this.scanning = false,
    this.version = 0,
    this.revived = 0,
  });

  /// Notes that need a receive and are not settled yet.
  final Set<String> receiving;
  final List<RemoteCard> cards;

  /// The tree is being scanned (first check, or after a rejected token).
  final bool scanning;

  /// Grows whenever a note on disk was changed by a receive.
  final int version;

  /// Grows whenever a deleted note with unsent changes was brought back
  /// (the snackbar of Story 3.17).
  final int revived;

  ReceiveState copyWith({
    Set<String>? receiving,
    List<RemoteCard>? cards,
    bool? scanning,
    int? version,
    int? revived,
  }) => ReceiveState(
    receiving: receiving ?? this.receiving,
    cards: cards ?? this.cards,
    scanning: scanning ?? this.scanning,
    version: version ?? this.version,
    revived: revived ?? this.revived,
  );
}

/// The account changed or the receiver was disposed: end quietly.
class _Stop implements Exception {}

class _Failure implements Exception {
  _Failure(this.cls, {this.status, this.reason, this.head});

  final String cls;
  final int? status;
  final String? reason;

  /// The remote head that could not be read (`unreadable` only): a change
  /// with another head starts the receive over.
  final String? head;
}

/// `trashed` or `removed` when [i] is a note ended by a gone Drive file.
String? _goneKind(SyncInfo i) {
  if (i.state != SyncState.error || i.lastError?['class'] != 'deleted') {
    return null;
  }
  return i.lastError?['reason'] == 'trashed' ? 'trashed' : 'removed';
}

/// An `unreadable` note whose Drive file has another head now.
bool _recoverable(SyncInfo i, String? head) =>
    i.state == SyncState.error &&
    i.lastError?['class'] == 'unreadable' &&
    i.lastError?['head'] is String &&
    i.lastError?['head'] != head;

/// An `error` that a change of the same file ends (Story 3.17).
bool _relinkable(SyncInfo i, DriveFile f) =>
    i.fileId == f.id &&
    i.pendingVerify == null &&
    (_goneKind(i) != null || _recoverable(i, f.headRevisionId));

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

// These end the whole check: the token is not saved, the changes come again.
const _transient = {'backoff', 'quota', 'reauth'};

/// Receives remote changes (spec `sync` "Triggers and polling", "Start",
/// page-token rejection). Every public method completes without throwing.
/// One check runs at a time; one receive per note at a time on [chain].
class NoteReceiver {
  NoteReceiver({
    required this.store,
    required this.drive,
    required this.device,
    required this.log,
    required this.merge,
    required this.hosts,
    required this.allowed,
    required this.online,
    required this.account,
    required this.sleep,
    required this.jitter,
    this.flushOpen,
    this.uploadNote,
    NoteChain? chain,
  }) : chain = chain ?? NoteChain();

  final NoteStore store;
  final DriveClient drive;
  final SyncDeviceStore device;
  final SyncLog log;
  final MergeStep merge;
  final MergeHosts hosts;
  final Future<bool> Function() allowed;
  final Future<bool> Function() online;
  final AuthAccount? Function() account;
  final Future<void> Function(Duration) sleep;
  final double Function() jitter;
  final NoteChain chain;

  /// Waits until the open editor's save queue is on disk.
  final Future<void> Function()? flushOpen;

  /// Uploads a note that was brought back (the coordinator's `noteClosed`).
  final Future<void> Function(String noteId)? uploadNote;

  final state = ValueNotifier<ReceiveState>(const ReceiveState());
  final _counts = <String, int>{};
  Future<void>? _flight;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    state.dispose();
  }

  void _emit(ReceiveState Function(ReceiveState) f) {
    if (!_disposed) state.value = f(state.value);
  }

  void _bump() => _emit((s) => s.copyWith(version: s.version + 1));

  void _mark(Iterable<String> ids, List<RemoteCard> cards) {
    for (final id in ids) {
      _counts[id] = (_counts[id] ?? 0) + 1;
    }
    _emit(
      (s) => s.copyWith(
        receiving: {...s.receiving, ...ids},
        cards: [
          ...cards,
          for (final c in s.cards)
            if (!cards.any((n) => n.noteId == c.noteId)) c,
        ],
      ),
    );
  }

  void _unmark(Iterable<String> ids) {
    final gone = <String>{};
    for (final id in ids) {
      final n = (_counts[id] ?? 1) - 1;
      if (n <= 0) {
        _counts.remove(id);
        gone.add(id);
      } else {
        _counts[id] = n;
      }
    }
    if (gone.isEmpty) return;
    _emit(
      (s) => s.copyWith(
        receiving: {
          for (final id in s.receiving)
            if (!gone.contains(id)) id,
        },
        cards: [
          for (final c in s.cards)
            if (!gone.contains(c.noteId)) c,
        ],
      ),
    );
  }

  /// Ends the run when the account is not the one it started with, or the
  /// gate closed. Called after every await group and before every write.
  Future<void> _guard(String sub) async {
    if (_disposed || account()?.sub != sub || !await allowed()) {
      throw _Stop();
    }
    if (_disposed || account()?.sub != sub) throw _Stop();
  }

  // ---- the check ---------------------------------------------------------

  /// Asks Drive for changes now (app start, foreground, the 20 s timer). A
  /// second call while one runs gets the running one.
  Future<void> check() =>
      _flight ??= _check().whenComplete(() => _flight = null);

  Future<void> _check() async {
    try {
      if (_disposed || !await allowed() || !await online()) return;
      final a = account();
      if (a == null) return;
      if (!await device.adoptAccount(a.sub, a.email)) {
        // Another account's data (Story 3.7) is not ours to touch; no
        // account tag at all means the record cannot be read.
        if ((await device.read()).sub == null) {
          await log.append('error', {
            'class': 'fatal',
            'reason': 'deviceUnreadable',
          });
        }
        return;
      }
      await _guard(a.sub);
      final d = await device.read();
      await _guard(a.sub);
      final token = d.pageToken;
      if (token == null) {
        await _scan(a.sub, d.rootFolderId);
      } else {
        await _follow(a.sub, token, d.rootFolderId);
      }
      await _settleGone(a.sub);
    } on _Stop {
      // Signed out or another account: nothing more is done.
    } on _Failure catch (f) {
      await _logFailure(null, f);
    } catch (_) {
      await log.append('error', {'class': 'fatal', 'reason': 'other'});
    }
  }

  Future<void> _follow(String sub, String start, String? root) async {
    var token = start;
    while (true) {
      final ChangesPage page;
      try {
        page = await _call(
          null,
          () => drive.listChanges(token),
          pass: (e) =>
              e.kind == 'http' && const {400, 404, 410}.contains(e.status),
        );
      } on DriveError {
        await log.append('pageTokenRejected');
        await _scan(sub, root);
        return;
      }
      await _guard(sub);
      await _handle(sub, root, page.changes);
      final next = page.nextPageToken;
      if (next != null) {
        token = next;
        continue;
      }
      final saved = page.newStartPageToken;
      if (saved != null) await _saveToken(sub, saved);
      return;
    }
  }

  /// First check, or a rejected token: the start token first, then every
  /// note file of the tree is handled as a change; the token is saved last.
  Future<void> _scan(String sub, String? root) async {
    _emit((s) => s.copyWith(scanning: true));
    final files = <DriveFile>[];
    final String startToken;
    try {
      startToken = await _call(null, drive.getStartPageToken);
      await _guard(sub);
      String? page;
      do {
        final p = await _call(
          null,
          () => drive.list(
            noteTreeQuery,
            fields: noteFileFields,
            pageToken: page,
          ),
        );
        files.addAll(p.files);
        page = p.nextPageToken;
        await _guard(sub);
      } while (page != null);
    } finally {
      _emit((s) => s.copyWith(scanning: false));
    }
    await _handle(sub, root, [
      for (final f in files) DriveChange(f.id, file: f),
    ]);
    await _sweepUnlisted(sub, {for (final f in files) f.id});
    await _saveToken(sub, startToken);
  }

  Future<void> _saveToken(String sub, String token) async {
    await _guard(sub);
    try {
      await device.update(
        (cur) => cur.sub == sub ? cur.withPageToken(token) : cur,
      );
    } catch (_) {
      await log.append('error', {'class': 'fatal', 'reason': 'localWrite'});
    }
  }

  // ---- one batch of changed files ---------------------------------------

  bool _skip(SyncInfo i, DriveFile f) =>
      i.baseHeadRevisionId == f.headRevisionId ||
      i.state == SyncState.error ||
      i.pendingVerify != null ||
      i.fileId == null ||
      i.fileId != f.id;

  static bool _valid(DriveFile f) =>
      f.mimeType == noteMimeType &&
      !f.trashed &&
      f.headRevisionId != null &&
      _uuid.hasMatch(f.appProperties['kkeujeokId'] ?? '');

  RemoteCard? _card(DriveFile f, String? root) {
    final r = listSummaryRule({
      'op': 'read',
      'file': {
        'appProperties': f.appProperties,
        'name': f.name,
        'md5Checksum': f.md5Checksum,
        'parents': f.parents,
        'modifiedTime': f.modifiedTime,
        'thumbnailLink': f.thumbnailLink,
      },
      'rootFolderId': root,
    });
    final c = r['card'];
    if (r['source'] != 'summary' || c is! Map) return null;
    return RemoteCard(
      noteId: c['noteId'] as String,
      fileId: f.id,
      title: c['title'] as String,
      modifiedAt: c['modifiedAt'] as String?,
    );
  }

  /// Marks every note that needs a receive (the badge shows before any
  /// download), then receives them one after another.
  Future<void> _handle(
    String sub,
    String? root,
    List<DriveChange> changes,
  ) async {
    final last = <String, DriveChange>{};
    for (final c in changes) {
      last[c.fileId] = c;
    }
    final gone = <String>{};
    final goneNotes = <({String id, String fileId, String kind})>[];
    Map<String, String>? owners; // fileId -> local noteId, built on demand
    final work = <DriveFile>[];
    final cards = <RemoteCard>[];
    for (final c in last.values) {
      final f = c.file;
      if (c.removed || f == null || f.trashed) {
        gone.add(c.fileId);
        if (owners == null) {
          owners = {};
          for (final id in await store.ids()) {
            final fid = (await store.readSync(id)).info.fileId;
            if (fid != null) owners[fid] = id;
          }
        }
        final owner = owners[c.fileId];
        if (owner != null) {
          goneNotes.add((
            id: owner,
            fileId: c.fileId,
            kind: c.removed || f == null ? 'removed' : 'trashed',
          ));
        }
        continue;
      }
      if (!_valid(f)) continue;
      final id = f.appProperties['kkeujeokId']!;
      final local = await store.read(id);
      if (local == null) {
        final card = _card(f, root);
        if (card != null) cards.add(card);
      } else if (local.note == null) {
        continue; // unreadable data is never overwritten
      } else {
        final info = (await store.readSync(id)).info;
        if (!_relinkable(info, f) && _skip(info, f)) continue;
      }
      work.add(f);
    }
    await _guard(sub);
    if (gone.isNotEmpty) {
      _emit(
        (s) => s.copyWith(
          cards: [
            for (final c in s.cards)
              if (!gone.contains(c.fileId)) c,
          ],
        ),
      );
    }
    for (final g in goneNotes) {
      await _guard(sub);
      await _goneSafe(sub, g.id, g.fileId, g.kind);
    }
    final ids = [for (final f in work) f.appProperties['kkeujeokId']!];
    _mark(ids, cards);
    final pending = [...ids];
    try {
      for (final f in work) {
        final id = f.appProperties['kkeujeokId']!;
        await _guard(sub);
        try {
          await chain.run(id, () => _receiveOne(sub, f));
        } on _Failure catch (e) {
          await _fail(id, e);
          if (_transient.contains(e.cls)) rethrow;
        } finally {
          pending.remove(id);
          _unmark([id]);
        }
      }
    } finally {
      _unmark(pending); // an aborted batch leaves nothing marked
    }
  }

  // ---- one note ----------------------------------------------------------

  Future<void> _receiveOne(String sub, DriveFile f) async {
    final id = f.appProperties['kkeujeokId']!;
    final head = f.headRevisionId!;
    var announced = false;
    Note? remote;
    for (var tries = 0; tries < 3; tries++) {
      await _guard(sub);
      final cur = await store.read(id);
      if (cur != null && cur.note == null) return;
      if (cur != null) {
        var info = (await store.readSync(id)).info;
        var relinked = false;
        if (_relinkable(info, f)) {
          // The file is live again, or a broken one has another head: look
          // again from a clean state.
          await _clearError(id);
          info = (await store.readSync(id)).info;
          relinked = true;
        }
        if (_skip(info, f)) {
          if (relinked && info.baseHeadRevisionId == head) {
            await _settleWhole(id); // the same file is back: nothing to receive
          }
          return;
        }
      }
      if (cur != null && !announced) {
        await _event(id, 'remoteChange');
        announced = true;
      }
      if (remote == null) {
        final bytes = await _fetch(id, f.id, head);
        final r = decodeKkj(bytes);
        final n = r.note;
        if (n == null || n.noteId != id) {
          final reason = r.status == ReadStatus.unsupportedVersion
              ? 'unsupportedVersion'
              : 'parse';
          if (cur != null) {
            throw _Failure('unreadable', reason: reason, head: head);
          }
          await _guard(sub);
          final done = await _wrapWrite(
            () => store.storeUnreadable(
              id,
              bytes,
              SyncInfo(
                fileId: f.id,
                state: SyncState.error,
                lastError: {
                  'class': 'unreadable',
                  'reason': reason,
                  'head': head,
                },
              ),
            ),
          );
          await _logFailure(id, _Failure('unreadable', reason: reason));
          if (done) {
            _bump();
            return;
          }
          continue;
        }
        remote = n;
      }
      await _guard(sub);
      // The decision is made on what is on disk now, not on the snapshot
      // from before the download.
      final now = await store.read(id);
      if (now == null) {
        if (cur != null) return; // vanished
        if (await _commitNew(id, f.id, head, remote)) return;
        continue;
      }
      final note = now.note;
      final s2 = await store.readSync(id);
      if (note == null || _skip(s2.info, f)) return;
      if (hosts.of(id) == null && !s2.hasUnsent) {
        String? from, to;
        final ok = await _wrapWrite(
          () => store.commitReceive(
            id,
            expected: note,
            working: remote!,
            base: remote,
            change: (c) {
              final r = _settle(c, f.id, head, unsent: false);
              from = r.from;
              to = r.next.state.name;
              return r.next;
            },
          ),
        );
        if (ok) {
          await _advanced(id, head, from, to);
          return;
        }
        continue; // an edit landed: start over from the read
      }
      await _mergeIn(id, f.id, head, note, s2.base, remote);
      return;
    }
  }

  Future<bool> _commitNew(String id, String fileId, String head, Note n) async {
    final ok = await _wrapWrite(
      () => store.commitReceive(
        id,
        expected: null,
        working: n,
        base: n,
        change: (c) => c.copyWith(
          fileId: fileId,
          baseHeadRevisionId: head,
          state: SyncState.synced,
          lastError: null,
        ),
      ),
    );
    if (ok) await _advanced(id, head, null, null);
    return ok;
  }

  Future<void> _mergeIn(
    String id,
    String fileId,
    String head,
    Note localAtStart,
    Note? base,
    Note remote,
  ) async {
    final out = await merge.merge(
      localAtStart: localAtStart,
      base: base,
      remote: remote,
    );
    switch (out) {
      case Merged(:final conflicts):
        await log.append('merged', {'noteId': id});
        if (conflicts > 0) {
          await log.append('conflictFound', {'noteId': id});
          await _event(id, 'conflictFound');
        }
      case MergeUnsupported():
        throw _Failure('unreadable', reason: 'unsupportedVersion', head: head);
      case MergeFailed(:final code):
        throw _Failure('fatal', reason: code);
    }
    final working = (await store.read(id))?.note;
    final unsent = working == null || _differs(remote, working);
    String? from, to;
    await _wrapWrite(
      () => store.updateSync(id, (c) {
        final r = _settle(c, fileId, head, unsent: unsent);
        from = r.from;
        to = r.next.state.name;
        return r.next;
      }, base: remote),
    );
    await _advanced(id, head, from, to);
  }

  bool _differs(Note head, Note working) =>
      hasUnsentRule({
        'base': _sum(head),
        'working': _sum(working),
        'pendingVerify': null,
        'unsentSidecars': const <Object?>[],
      })['hasUnsent'] !=
      false;

  Map<String, Object?> _sum(Note n) => {
    'orderRev': n.orderRev,
    'metaRev': n.metaRev,
    'pages': n.pages,
  };

  /// The `sync.json` after a receive: the base is the head, and the event
  /// `verified` (after `upload` for a `pending` note) picks the state.
  ({SyncInfo next, String from}) _settle(
    SyncInfo c,
    String fileId,
    String head, {
    required bool unsent,
  }) {
    final unresolved = [
      for (final x in c.conflicts)
        if (x['resolvedAt'] == null) x,
    ].length;
    var st = c.state.name;
    if (st == 'pending') st = transition(st, 'upload') ?? st;
    if (st == 'syncing' || st == 'conflict') {
      st =
          transition(st, 'verified', unresolved: unresolved, unsent: unsent) ??
          st;
    }
    return (
      from: c.state.name,
      next: c.copyWith(
        fileId: fileId,
        baseHeadRevisionId: head,
        state: SyncState.values.firstWhere((s) => s.name == st),
        lastError: null,
      ),
    );
  }

  Future<void> _advanced(
    String id,
    String head,
    String? from,
    String? to,
  ) async {
    await log.append('baseAdvanced', {'noteId': id, 'revisionId': head});
    if (from != null && to != null && from != to) {
      await log.append('stateChange', {'noteId': id, 'from': from, 'to': to});
    }
    _bump();
  }

  /// One event on the persisted state (`remoteChange`, `conflictFound`).
  Future<void> _event(String id, String event) async {
    String? from, to;
    await _wrapWrite(
      () => store.updateSync(id, (c) {
        from = to = c.state.name;
        final t = transition(c.state.name, event);
        if (t == null) return c;
        to = t;
        return c.copyWith(
          state: SyncState.values.firstWhere((s) => s.name == t),
        );
      }),
    );
    if (from != to) {
      await log.append('stateChange', {'noteId': id, 'from': from, 'to': to});
    }
  }

  Future<T> _wrapWrite<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on NoteSaveException catch (e) {
      throw _Failure(
        'fatal',
        reason: e.message == syncUnreadableMessage
            ? 'syncUnreadable'
            : 'localWrite',
      );
    }
  }

  Future<List<int>> _fetch(String id, String fileId, String head) async {
    final bytes = await _call(id, () => drive.downloadRevision(fileId, head));
    await log.append('revisionDownloaded', {'noteId': id, 'revisionId': head});
    return bytes;
  }

  Future<void> _logFailure(String? id, _Failure f) => log.append('error', {
    'class': f.cls,
    'noteId': ?id,
    'status': ?f.status,
    'reason': ?f.reason,
  });

  /// The note takes `failed`; its device copy is not touched.
  Future<void> _fail(String id, _Failure f) async {
    await _logFailure(id, f);
    try {
      String? from;
      await store.updateSync(id, (c) {
        from = c.state.name;
        final t = transition(c.state.name, 'failed');
        return c.copyWith(
          state: t == null
              ? c.state
              : SyncState.values.firstWhere((s) => s.name == t),
          lastError: {
            'class': f.cls,
            'status': ?f.status,
            'reason': ?f.reason,
            if (f.cls == 'unreadable') 'head': ?f.head,
          },
        );
      });
      final t = transition(from!, 'failed');
      if (t != null) {
        await log.append('stateChange', {'noteId': id, 'from': from, 'to': t});
      }
    } catch (_) {
      // A note with no folder, or an unreadable `sync.json`: only the log.
    }
  }

  // ---- the Drive file of a note that is here is gone (Story 3.17) --------

  /// `retry` and no `lastError`: the file is live again, or it has another
  /// head than the broken one.
  Future<void> _clearError(String id) async {
    String? from, to;
    await _wrapWrite(
      () => store.updateSync(id, (c) {
        from = to = c.state.name;
        if (c.state != SyncState.error) return c;
        to = transition('error', 'retry');
        return c.copyWith(state: SyncState.pending, lastError: null);
      }),
    );
    if (from != to) {
      await log.append('stateChange', {'noteId': id, 'from': from, 'to': to});
    }
  }

  /// The note is whole again (nothing to receive): `synced`, or `pending`
  /// when it has unsent changes.
  Future<void> _settleWhole(String id) async {
    final unsent = (await store.readSync(id)).hasUnsent;
    String? from, to;
    await _wrapWrite(
      () => store.updateSync(id, (c) {
        from = to = c.state.name;
        if (c.state != SyncState.pending && c.state != SyncState.synced) {
          return c;
        }
        to = unsent ? 'pending' : 'synced';
        return c.copyWith(state: SyncState.values.byName(to!));
      }),
    );
    if (from != to) {
      await log.append('stateChange', {'noteId': id, 'from': from, 'to': to});
    }
    _bump();
  }

  /// `error` + `lastError deleted`: what the banner of an open note and the
  /// next sweep read.
  Future<void> _markGone(String id, String kind) async {
    String? from;
    await _wrapWrite(
      () => store.updateSync(id, (c) {
        from = c.state.name;
        final t = transition(c.state.name, 'failed');
        return c.copyWith(
          state: t == null ? c.state : SyncState.values.byName(t),
          lastError: {'class': 'deleted', 'reason': kind},
        );
      }),
    );
    if (from != 'error') {
      await log.append('stateChange', {
        'noteId': id,
        'from': from,
        'to': 'error',
      });
    }
    _bump();
  }

  bool _keepsLocal(SyncRead s) =>
      s.hasUnsent ||
      s.info.pendingVerify != null ||
      s.info.state == SyncState.conflict ||
      s.info.conflicts.any((c) => c['resolvedAt'] == null);

  /// Puts the note back on Drive (inside the note's chain): untrash, or
  /// forget the file so the next upload creates it again with the same id.
  Future<void> _reviveIn(
    String sub,
    String id,
    String kind,
    String fileId, {
    required bool announce,
  }) async {
    var k = kind;
    if (k == 'trashed') {
      try {
        await _call(
          id,
          () => drive.update(fileId, trashed: false),
          pass: (e) => e.kind == 'http' && e.status == 404,
        );
      } on DriveError {
        k = 'removed'; // deleted for good meanwhile
      }
    }
    await _guard(sub);
    if (k == 'removed') {
      final from = (await store.readSync(id)).info.state.name;
      await _wrapWrite(() => store.resetSync(id));
      if (from != 'pending') {
        await log.append('stateChange', {
          'noteId': id,
          'from': from,
          'to': 'pending',
        });
      }
    } else {
      await _clearError(id);
      await _settleWhole(id);
    }
    if (announce) _emit((s) => s.copyWith(revived: s.revived + 1));
    _bump();
  }

  /// One decision for a note whose file is gone, inside its chain; true =
  /// upload it now. Everything is read again after the last await: unsent
  /// changes (an open note is flushed first) restore it, an open note with
  /// none gets the banner, a closed one is removed (only while its working
  /// copy is unchanged).
  Future<bool> _goneStep(
    String sub,
    String id,
    String fileId,
    String kind,
  ) async {
    for (var tries = 0; tries < 3; tries++) {
      await _guard(sub);
      if (hosts.of(id) != null) {
        try {
          await flushOpen?.call();
        } catch (_) {}
      }
      await _guard(sub);
      final note = (await store.read(id))?.note;
      final s = await store.readSync(id);
      final open = hosts.of(id) != null; // decided after the last await
      if (note == null || s.info.fileId != fileId) return false;
      if (_keepsLocal(s)) {
        await log.append('error', {
          'class': 'deleted',
          'noteId': id,
          'reason': kind,
        });
        await _reviveIn(sub, id, kind, fileId, announce: true);
        return !open;
      }
      if (open) {
        if (_goneKind(s.info) == null) {
          await log.append('error', {
            'class': 'deleted',
            'noteId': id,
            'reason': kind,
          });
          await _markGone(id, kind);
        }
        return false;
      }
      await log.append('error', {
        'class': 'deleted',
        'noteId': id,
        'reason': kind,
      });
      if (await _wrapWrite(() => store.removeNote(id, expected: note))) {
        _bump();
        return false;
      }
    }
    return false;
  }

  Future<void> _fileGone(
    String sub,
    String id,
    String fileId,
    String kind,
  ) async {
    var upload = false;
    await chain.run(id, () async {
      upload = await _goneStep(sub, id, fileId, kind);
    });
    if (upload) {
      try {
        await uploadNote?.call(id);
      } catch (_) {}
    }
  }

  /// [_fileGone] that never fails the batch: a permanent failure is logged,
  /// a transient one ends the check (the change comes again).
  Future<void> _goneSafe(
    String sub,
    String id,
    String fileId,
    String kind,
  ) async {
    try {
      await _fileGone(sub, id, fileId, kind);
    } on _Failure catch (f) {
      await _logFailure(id, f);
      if (_transient.contains(f.cls)) rethrow;
    }
  }

  /// Every note an earlier upload or receive ended as deleted (and an open
  /// one that was already marked) is decided again.
  Future<void> _settleGone(String sub) async {
    for (final id in await store.ids()) {
      await _guard(sub);
      final info = (await store.readSync(id)).info;
      final kind = _goneKind(info);
      if (kind != null && info.fileId != null) {
        await _goneSafe(sub, id, info.fileId!, kind);
      }
    }
  }

  /// After a full listing: a local note whose file the listing does not show
  /// is looked up (it may have been trashed, deleted, or only moved out of
  /// the folder, which keeps it live).
  Future<void> _sweepUnlisted(String sub, Set<String> listed) async {
    for (final id in await store.ids()) {
      await _guard(sub);
      final info = (await store.readSync(id)).info;
      final fileId = info.fileId;
      if (fileId == null ||
          listed.contains(fileId) ||
          info.state == SyncState.syncing ||
          info.pendingVerify != null) {
        continue;
      }
      String? kind;
      try {
        final f = await _call(
          id,
          () => drive.get(fileId, fields: 'headRevisionId,trashed'),
        );
        if (f.trashed) kind = 'trashed';
      } on _Failure catch (e) {
        if (_transient.contains(e.cls)) rethrow;
        if (e.cls != 'deleted') {
          await _logFailure(id, e); // one bad note does not stop the sweep
          continue;
        }
        kind = 'removed';
      }
      if (kind != null) await _goneSafe(sub, id, fileId, kind);
    }
  }

  /// Runs [body] with the account of the run; every failure is logged.
  Future<void> _guarded(
    String? noteId,
    Future<void> Function(String sub) body, {
    bool needsOnline = true,
  }) async {
    try {
      if (_disposed || !await allowed()) return;
      if (needsOnline && !await online()) return;
      final a = account();
      if (a == null) return;
      await body(a.sub);
    } on _Stop {
      // Account changed.
    } on _Failure catch (f) {
      await _logFailure(noteId, f);
    } catch (_) {
      await log.append('error', {'class': 'fatal', 'reason': 'other'});
    }
  }

  /// [다시 살리기] of the deleted banner: the file is untrashed, or created
  /// again by the next upload.
  Future<void> revive(String noteId) => _guarded(noteId, (sub) async {
    final info = (await store.readSync(noteId)).info;
    final kind = _goneKind(info);
    final fileId = info.fileId;
    if (kind == null || fileId == null) return;
    await chain.run(noteId, () async {
      await _guard(sub);
      final now = (await store.readSync(noteId)).info;
      if (_goneKind(now) == null || now.fileId != fileId) return;
      await _reviveIn(sub, noteId, _goneKind(now)!, fileId, announce: false);
    });
  });

  /// The editor of [noteId] is gone: a note still marked `deleted` is
  /// removed when it has nothing unsent, restored when it has.
  Future<void> noteClosed(String noteId) =>
      _guarded(noteId, needsOnline: false, (sub) async {
        final info = (await store.readSync(noteId)).info;
        final kind = _goneKind(info);
        if (kind != null && info.fileId != null) {
          await _fileGone(sub, noteId, info.fileId!, kind);
        }
      });

  // ---- opening a note ----------------------------------------------------

  /// A note was opened: asks Drive for its head once and receives it when it
  /// moved (or sees that its file is gone). The editor blocks strokes while
  /// the note is in the receiving set.
  Future<void> noteOpened(String noteId) => _guarded(noteId, (sub) async {
    final s = await store.readSync(noteId);
    final fileId = s.info.fileId;
    final cls = s.info.lastError?['class'];
    if (fileId == null ||
        s.info.pendingVerify != null ||
        (s.info.state == SyncState.error &&
            cls != 'deleted' &&
            cls != 'unreadable')) {
      return;
    }
    final DriveFile f;
    try {
      f = await _call(
        noteId,
        () => drive.get(fileId, fields: 'headRevisionId,trashed'),
      );
    } on _Failure catch (e) {
      if (e.cls != 'deleted') rethrow;
      return _fileGone(sub, noteId, fileId, 'removed');
    }
    await _guard(sub);
    final head = f.headRevisionId;
    if (f.trashed) return _fileGone(sub, noteId, fileId, 'trashed');
    final probe = DriveFile(
      id: fileId,
      appProperties: {'kkeujeokId': noteId},
      headRevisionId: head,
      mimeType: noteMimeType,
    );
    if (head == null ||
        (head == s.info.baseHeadRevisionId && !_relinkable(s.info, probe))) {
      return;
    }
    await _handle(sub, (await device.read()).rootFolderId, [
      DriveChange(fileId, file: probe),
    ]);
  });

  // ---- calls -------------------------------------------------------------

  /// One Drive call with the retry rules of `sync.errorClass` and
  /// `sync.backoff`. A [DriveError] for which [pass] is true is rethrown.
  Future<T> _call<T>(
    String? noteId,
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
          'noteId': ?noteId,
        });
        await sleep(Duration(milliseconds: delay));
        if (_disposed) throw _Stop();
      }
    }
  }
}
