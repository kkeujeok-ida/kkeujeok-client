// Story 7.5: the folders of the library on the device and in Drive.
//
// The device record keeps three things in `extra` (spec `library` "Offline"):
// `folders` (the cache: id = kkeujeokId, fileId = Drive id or null until it is
// created, name, parentId), `noteParents` (note id -> parent kkeujeokId) and
// `driveOps` (Drive-only changes waiting to be sent, in order). Every change is
// applied to the cache at once and sent when the device is online.
import 'dart:async';

import '../drive/drive_client.dart';
import '../drive/duplicates.dart';
import '../model/ids.dart';
import '../storage/note_store.dart';
import '../storage/sync_device_store.dart';
import '../storage/sync_info.dart';
import '../sync/sync_log.dart';
import 'library_rules.dart';

const _folderMime = 'application/vnd.google-apps.folder';
const _systemIds = {'root', 'assets', 'conflicts', 'trashbin'};

typedef _Map = Map<String, Object?>;

/// A folder the person sees.
class LibraryFolder {
  const LibraryFolder(this.id, this.name, this.parentId);

  final String id;
  final String name;

  /// `root` or the id of another visible folder.
  final String parentId;
}

/// What the library shows: [folders] in cache order, the folder of every
/// known note (`null` = top level) and the notes that are hidden (in the
/// trash, or below a folder that is).
class FolderView {
  const FolderView({
    this.folders = const [],
    this.noteFolder = const {},
    this.hiddenNotes = const {},
  });

  final List<LibraryFolder> folders;
  final Map<String, String?> noteFolder;
  final Set<String> hiddenNotes;

  bool has(String id) => folders.any((f) => f.id == id);

  LibraryFolder? folder(String id) =>
      folders.where((f) => f.id == id).firstOrNull;

  List<LibraryFolder> childrenOf(String parentId) => [
    for (final f in folders)
      if (f.parentId == parentId) f,
  ];

  /// True when [id] is [ancestor] or lies below it.
  bool isInside(String id, String ancestor) {
    String? p = id;
    for (var n = 0; p != null && p != 'root' && n <= folders.length; n++) {
      if (p == ancestor) return true;
      p = folder(p)?.parentId;
    }
    return false;
  }

  /// The notes in [id] and every folder below it.
  int noteCount(String id) => [
    for (final e in noteFolder.entries)
      if (e.value != null && isInside(e.value!, id)) e,
  ].length;
}

/// The answer of a folder change: [error] is a rule code (nothing changed);
/// [inverse] undoes it (`null` when nothing changed).
class FolderResult {
  const FolderResult({this.error, this.id, this.inverse});

  final String? error;
  final String? id;
  final Map<String, Object?>? inverse;

  bool get ok => error == null;
}

class _State {
  _State(this.folders, this.noteParents, this.ops);

  final List<_Map> folders;
  final Map<String, String> noteParents;
  final List<_Map> ops;

  _Map? folder(String id) => folders.where((f) => f['id'] == id).firstOrNull;

  /// `id` and every folder below it.
  Set<String> subtree(String id) {
    final out = {id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final f in folders) {
        if (out.contains(f['parentId']) && out.add(f['id'] as String)) {
          grew = true;
        }
      }
    }
    return out;
  }

  /// The pending-trash overrides the tree sees (`trash.md` "Hiding").
  _Map tree() {
    final trashing = {
      for (final o in ops)
        if (o['kind'] == 'trashFolder') o['id'],
    };
    return libraryTree({
      'folders': [
        for (final f in folders)
          {
            'id': f['id'],
            'parentId': trashing.contains(f['id']) ? 'trashbin' : f['parentId'],
          },
      ],
      'notes': [
        for (final e in noteParents.entries)
          {'noteId': e.key, 'parentId': e.value},
      ],
    });
  }

  /// The visible folders in the shape the rules take.
  List<_Map> visible() {
    final t = tree();
    return [
      for (final v in t['folders'] as List)
        {
          'id': (v as Map)['id'],
          'name': folder(v['id'] as String)!['name'],
          'parentId': v['parentId'],
        },
    ];
  }
}

class FolderService {
  FolderService({
    required this.drive,
    required this.device,
    required this.store,
    required this.allowed,
    required this.online,
    required this.upload,
    this.isOpen,
    this.log,
    DateTime Function()? clock,
    String Function()? newFolderId,
  }) : _clock = clock ?? DateTime.now,
       _newId = newFolderId ?? newId;

  final DriveClient drive;
  final SyncDeviceStore device;
  final NoteStore store;

  /// The upload gate (root folder ready, account matches).
  final Future<bool> Function() allowed;
  final Future<bool> Function() online;

  /// Uploads one note; true when nothing of it is left unsent.
  final Future<bool> Function(String noteId) upload;

  /// True while the editor shows the note (a remote delete waits for it).
  final Future<bool> Function(String noteId)? isOpen;

  /// Folder changes are logged (`folderOp`); null in tests that do not look.
  final SyncLog? log;
  final DateTime Function() _clock;
  final String Function() _newId;

  Future<void> _tail = Future<void>.value();

  /// Public changes run one after another.
  Future<T> _run<T>(Future<T> Function() body) {
    final r = _tail.then((_) => body());
    _tail = r.then<void>((_) {}, onError: (Object _) {});
    return r;
  }

  /// A change of the device record only: atomic under its lock, so it never
  /// waits for a Drive call in [_run] (a refresh holds the queue for seconds).
  Future<T> _local<T>(Future<T> Function() body) => body();

  // ---- state ---------------------------------------------------------------

  static _State _read(SyncDevice d) {
    List<_Map> maps(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is Map) {for (final x in e.entries) '${x.key}': x.value},
    ];
    final np = d.extra['noteParents'];
    return _State(maps(d.extra['folders']), {
      if (np is Map)
        for (final e in np.entries)
          if (e.value is String) '${e.key}': e.value as String,
    }, maps(d.extra['driveOps']));
  }

  static SyncDevice _write(SyncDevice d, _State s) => d.copyWith(
    extra: {
      ...d.extra,
      'folders': s.folders,
      'noteParents': s.noteParents,
      'driveOps': s.ops,
    },
  );

  Future<_State> _load() async => _read(await device.read());

  /// Changes the cache under the device lock.
  Future<void> _mutate(void Function(_State s) change) => device.update((d) {
    final s = _read(d);
    change(s);
    return _write(d, s);
  });

  FolderView _viewOf(_State s) {
    final t = s.tree();
    return FolderView(
      folders: [
        for (final v in t['folders'] as List)
          LibraryFolder(
            (v as Map)['id'] as String,
            s.folder(v['id'] as String)!['name'] as String,
            v['parentId'] as String,
          ),
      ],
      noteFolder: {
        for (final n in t['notes'] as List)
          (n as Map)['noteId'] as String: n['folderId'] as String?,
      },
      hiddenNotes: {...((t['hidden'] as Map)['notes'] as List).cast<String>()},
    );
  }

  /// What the library shows now, from the device record only.
  Future<FolderView> view() async => _viewOf(await _load());

  /// Whether a Drive-only change still waits to be sent.
  Future<bool> hasPending() async {
    final s = await _load();
    return s.ops.isNotEmpty || s.folders.any((f) => f['fileId'] == null);
  }

  /// The Drive folder file id a note belongs in; null = the root. A folder
  /// that is not in Drive yet is created first (this is called by the upload
  /// of a new note and never takes the lock of the changes).
  Future<String?> parentFileId(String noteId) async {
    final s = await _load();
    final p = s.noteParents[noteId];
    if (p == null || p == 'root') return null;
    final f = s.folder(p);
    if (f == null) return null;
    return (f['fileId'] as String?) ?? await _ensureFolder(p);
  }

  /// The note is created in [parentId]: its upload will put it there. Nothing
  /// is queued, the note has no Drive file yet.
  Future<void> assignNote(String noteId, String parentId) async {
    if (parentId == 'root') return;
    await _mutate((s) {
      if (s.folder(parentId) != null) s.noteParents[noteId] = parentId;
    });
  }

  /// The `kkeujeokId` of the folder the note is in (`root` = top level).
  Future<String> parentIdOf(String noteId) async =>
      (await _load()).noteParents[noteId] ?? 'root';

  /// A deleted note's device copy is gone: its parent entry and any queued
  /// change of it are dropped.
  Future<void> forgetNote(String noteId) => _mutate((s) {
    s.noteParents.remove(noteId);
    s.ops.removeWhere((o) => o['kind'] == 'moveNote' && o['noteId'] == noteId);
  });

  /// The Drive id of `.trashbin`, created when missing (Story 14.1); null
  /// while the root is not known.
  Future<String?> trashbinFileId() async {
    final root = (await device.read()).rootFolderId;
    if (root == null) return null;
    return _ensureItem('trashbin', name: '.trashbin', parentFile: root);
  }

  /// True when folder [id] or one above it waits for its move to `.trashbin`
  /// (`trash.restoreNote`: such an origin counts as in the trash).
  Future<bool> trashPending(String id) async {
    final s = await _load();
    final trashing = {
      for (final o in s.ops)
        if (o['kind'] == 'trashFolder') o['id'],
    };
    String? p = id;
    for (var n = 0; p != null && p != 'root' && n <= s.folders.length; n++) {
      if (trashing.contains(p)) return true;
      p = s.folder(p)?['parentId'] as String?;
    }
    return false;
  }

  /// How many notes another device deleted although this one had unsent
  /// changes, and that were revived since the last call (the snackbar).
  Future<int> takeRevived() async {
    var n = 0;
    await device.update((d) {
      final v = d.extra['revivedCount'];
      n = v is int ? v : 0;
      return n == 0 ? d : d.copyWith(extra: {...d.extra, 'revivedCount': 0});
    });
    return n;
  }

  Future<void> _log(String op, String id, {bool done = false}) async {
    try {
      await log?.append('folderOp', {
        'folderId': id,
        'op': op,
        if (done) 'done': true,
      });
    } catch (_) {}
  }

  // ---- changes -------------------------------------------------------------

  static void _enqueue(List<_Map> ops, _Map op) {
    String key(_Map e) => '${e['kind']}\u0000${e['id'] ?? e['noteId']}';
    final i = ops.indexWhere((e) => key(e) == key(op));
    if (i < 0) {
      ops.add(op);
    } else if (op['kind'] == 'trashFolder') {
      // The first delete keeps its date and origin.
    } else if (op['kind'] == 'moveNote' || op['kind'] == 'moveFolder') {
      final keep = ops[i]['removeParent'];
      if (op['addParent'] == keep) {
        ops.removeAt(i);
      } else {
        ops[i] = {...op, 'removeParent': keep};
      }
    } else {
      ops[i] = op;
    }
  }

  Future<FolderResult> _apply(
    _Map Function(_State s) rule, {
    void Function(_State s, _Map result)? onOk,
  }) async {
    late _Map r;
    await _mutate((s) {
      r = rule(s);
      if (r['error'] != null) return;
      onOk?.call(s, r);
      final drive = r['drive'];
      if (drive is Map) {
        _enqueue(s.ops, {for (final e in drive.entries) '${e.key}': e.value});
      }
    });
    return FolderResult(
      error: r['error'] as String?,
      id: (r['drive'] as Map?)?['id'] as String?,
      inverse: (r['inverse'] as Map?)?.cast<String, Object?>(),
    );
  }

  void _syncFolders(_State s, _Map r) {
    final out = {
      for (final f in r['folders'] as List) (f as Map)['id'] as String: f,
    };
    for (final f in s.folders) {
      final n = out[f['id']];
      if (n != null) {
        f['name'] = n['name'];
        f['parentId'] = n['parentId'];
      }
    }
  }

  Future<FolderResult> createFolder(String name, String parentId) async {
    final id = _newId();
    final r = await _local(
      () => _apply(
        (s) => libraryCreateFolder({
          'folders': s.visible(),
          'id': id,
          'name': name,
          'parentId': parentId,
        }),
        onOk: (s, r) {
          final d = r['drive'] as Map;
          s.folders.add({
            'id': id,
            'fileId': null,
            'name': d['name'],
            'parentId': parentId,
          });
        },
      ),
    );
    if (r.ok) await _log('create', id);
    _flushSoon();
    return r;
  }

  Future<FolderResult> renameFolder(String id, String name) async {
    final r = await _local(
      () => _apply(
        (s) => libraryRenameFolder({
          'folders': s.visible(),
          'id': id,
          'name': name,
        }),
        onOk: _syncFolders,
      ),
    );
    if (r.ok && r.inverse != null) await _log('rename', id);
    _flushSoon();
    return r;
  }

  Future<FolderResult> moveFolder(String id, String targetParentId) async {
    final r = await _local(
      () => _apply(
        (s) => libraryMoveFolder({
          'folders': s.visible(),
          'id': id,
          'targetParentId': targetParentId,
        }),
        onOk: _syncFolders,
      ),
    );
    if (r.ok && r.inverse != null) await _log('move', id);
    _flushSoon();
    return r;
  }

  /// [noteId] moves to [targetParentId]; the note file is not touched.
  Future<FolderResult> moveNote(String noteId, String targetParentId) async {
    final r = await _local(
      () => _apply(
        (s) => libraryMoveNote({
          'folders': s.visible(),
          'note': {
            'noteId': noteId,
            'parentId': s.noteParents[noteId] ?? 'root',
          },
          'targetParentId': targetParentId,
        }),
        onOk: (s, r) => s.noteParents[noteId] = r['parentId'] as String,
      ),
    );
    _flushSoon();
    return r;
  }

  /// Deletes [id] with everything in it: the folder is hidden at once and
  /// goes to `.trashbin` when the device is online (`trash.trashFolder`).
  Future<FolderResult> deleteFolder(String id) async {
    final now = canonicalNow(_clock());
    late FolderResult out;
    await _local(() async {
      await _mutate((s) {
        final f = s.visible().where((x) => x['id'] == id).firstOrNull;
        if (f == null) {
          out = const FolderResult(error: 'folderNotFound');
          return;
        }
        _enqueue(s.ops, {
          'kind': 'trashFolder',
          'id': id,
          'trashedAt': now,
          'from': f['parentId'],
        });
        out = FolderResult(id: id);
      });
    });
    if (out.ok) {
      await _log('delete', id);
      _flushSoon();
    }
    return out;
  }

  /// [되돌리기] of a folder delete that is still queued: the entry leaves the
  /// queue and the folder stays. False when it was sent already.
  Future<bool> cancelTrashFolder(String id) async {
    var had = false;
    await _mutate((s) {
      final n = s.ops.length;
      s.ops.removeWhere((o) => o['kind'] == 'trashFolder' && o['id'] == id);
      had = s.ops.length != n;
    });
    return had;
  }

  /// Runs a stored inverse (the [FolderResult.inverse] of an earlier change).
  Future<FolderResult> undo(Map<String, Object?> inverse) =>
      switch (inverse['op']) {
        'moveFolder' => moveFolder(
          inverse['id'] as String,
          inverse['targetParentId'] as String,
        ),
        'renameFolder' => renameFolder(
          inverse['id'] as String,
          inverse['name'] as String,
        ),
        'moveNote' => moveNote(
          inverse['noteId'] as String,
          inverse['targetParentId'] as String,
        ),
        'trashFolder' => deleteFolder(inverse['id'] as String),
        _ => Future.value(const FolderResult(error: 'invalidInput')),
      };

  // ---- Drive ---------------------------------------------------------------

  void _flushSoon() => unawaited(flush().catchError((Object _) => false));

  /// Sends what waits, in order: missing folders first, then the queue. An
  /// entry leaves the queue when Drive confirms it (or the target is gone,
  /// HTTP 404). The first failure stops the run; the rest waits for the next
  /// one. False when something is left.
  Future<bool> flush() => _run(_flush);

  Future<bool> _flush() async {
    try {
      if (!await allowed() || !await online()) return false;
      final root = (await device.read()).rootFolderId;
      if (root == null) return false;
      for (final f in (await _load()).folders) {
        if (f['fileId'] == null) await _ensureFolder(f['id'] as String);
      }
      for (final op in (await _load()).ops) {
        if (!await _send(op, root)) return false;
        await _mutate((s) => s.ops.removeWhere((e) => _same(e, op)));
        final k = switch (op['kind']) {
          'renameFolder' => 'rename',
          'moveFolder' => 'move',
          'trashFolder' => 'delete',
          _ => null,
        };
        if (k != null) await _log(k, op['id'] as String, done: true);
      }
      return true;
    } on DriveError {
      return false;
    }
  }

  static bool _same(_Map a, _Map b) =>
      a['kind'] == b['kind'] &&
      (a['id'] ?? a['noteId']) == (b['id'] ?? b['noteId']);

  /// True when the entry is done and may leave the queue.
  Future<bool> _send(_Map op, String root) async {
    try {
      switch (op['kind']) {
        case 'renameFolder':
          final f = (await _load()).folder(op['id'] as String);
          if (f == null) return true;
          await drive.update(
            await _ensureFolder(f['id'] as String) ?? '',
            name: op['name'] as String,
          );
        case 'moveFolder':
          final s = await _load();
          final f = s.folder(op['id'] as String);
          final to = op['addParent'] as String;
          if (f == null || (to != 'root' && s.folder(to) == null)) return true;
          final target = to == 'root' ? root : await _ensureFolder(to);
          await _moveTo(await _ensureFolder(f['id'] as String), target, root);
        case 'moveNote':
          final s = await _load();
          final to = op['addParent'] as String;
          final noteId = op['noteId'] as String;
          var fileId = (await store.readSync(noteId)).info.fileId;
          // No local Drive file id (not uploaded, or a card not received
          // yet): look it up by `kkeujeokId`. A note that Drive does not
          // have is put in its folder by its upload.
          fileId ??= (await _all(
            kkeujeokIdQuery(noteId),
            fields: 'id,createdTime',
          )).firstOrNull?.id;
          if (fileId == null || (to != 'root' && s.folder(to) == null)) {
            return true;
          }
          await _moveTo(
            fileId,
            to == 'root' ? root : await _ensureFolder(to),
            root,
          );
        case 'trashFolder':
          return await _trash(op, root);
        default:
          return true;
      }
      return true;
    } on DriveError catch (e) {
      if (e.kind == 'http' && e.status == 404) return true;
      rethrow;
    }
  }

  /// Makes [target] the only parent of [fileId].
  Future<void> _moveTo(String? fileId, String? target, String root) async {
    if (fileId == null || target == null) return;
    final cur = (await drive.get(fileId, fields: 'id,parents')).parents;
    if (cur.length == 1 && cur.first == target) return;
    final others = cur.where((p) => p != target).join(',');
    await drive.update(
      fileId,
      addParents: cur.contains(target) ? null : target,
      removeParents: others.isEmpty ? null : others,
    );
  }

  Future<List<DriveFile>> _all(String q, {String? fields}) async {
    final out = <DriveFile>[];
    String? token;
    do {
      final p = await drive.list(q, fields: fields, pageToken: token);
      out.addAll(p.files);
      token = p.nextPageToken;
    } while (token != null);
    return out;
  }

  final _creating = <String, Future<String?>>{};

  /// The Drive id of folder [id] of the cache, created when it is not there
  /// yet (spec `drive-layout` "Idempotent creation": the intent is saved, the
  /// folder is looked for by `kkeujeokId`, created only when missing).
  Future<String?> _ensureFolder(String id) => _creating[id] ??= _create(id)
      .whenComplete(() {
        _creating.remove(
          id,
        ); // a block: returning the future would wait on itself
      });

  Future<String?> _create(String id) async {
    final s = await _load();
    final f = s.folder(id);
    if (f == null) return null;
    if (f['fileId'] is String) return f['fileId'] as String;
    final root = (await device.read()).rootFolderId;
    if (root == null) return null;
    final parent = f['parentId'] as String;
    final parentFile = parent == 'root' || s.folder(parent) == null
        ? root
        : await _ensureFolder(parent) ?? root;
    final fileId = await _ensureItem(
      id,
      name: f['name'] as String,
      parentFile: parentFile,
    );
    await _mutate((s) => s.folder(id)?['fileId'] = fileId);
    return fileId;
  }

  /// Finds or creates the folder with `kkeujeokId` [kid]; the oldest one
  /// stays when there are several (ponytail: the others are not cleaned up
  /// here; `.trashbin` duplicates stay unmerged).
  Future<String> _ensureItem(
    String kid, {
    required String name,
    required String parentFile,
  }) async {
    await device.update(
      (d) => d.copyWith(
        createIntents: [
          for (final i in d.createIntents)
            if (i['kkeujeokId'] != kid) i,
          {'kkeujeokId': kid, 'kind': 'folder', 'parentId': parentFile},
        ],
      ),
    );
    var found = await _all(kkeujeokIdQuery(kid), fields: 'id,createdTime');
    String? fileId;
    if (found.isEmpty) {
      final made = await drive.create({
        'name': name,
        'mimeType': _folderMime,
        'parents': [parentFile],
        'appProperties': {'kkeujeokId': kid},
      });
      found = await _all(kkeujeokIdQuery(kid), fields: 'id,createdTime');
      if (found.isEmpty) fileId = made.id; // the listing lags
    }
    fileId ??=
        driveDuplicatesRule({
              'kkeujeokId': kid,
              'items': [
                for (final f in found)
                  {
                    'id': f.id,
                    'createdTime': f.createdTime ?? '9999-12-31T23:59:59.999Z',
                  },
              ],
            })['keep']
            as String;
    await device.update(
      (d) => d.copyWith(
        createIntents: [
          for (final i in d.createIntents)
            if (i['kkeujeokId'] != kid) i,
        ],
      ),
    );
    return fileId;
  }

  /// The notes at or below the folders of [ids].
  static List<String> _notesIn(_State s, Set<String> ids) => [
    for (final e in s.noteParents.entries)
      if (ids.contains(e.value)) e.key,
  ];

  Future<bool> _unsent(String noteId) async {
    final r = await store.readSync(noteId);
    return r.hasUnsent ||
        r.info.pendingVerify != null ||
        r.info.state == SyncState.conflict;
  }

  /// One `trashFolder` entry (`trash.trashFolder`): upload what is unsent,
  /// move the folder to `.trashbin`, remove the device copies. False while it
  /// must wait: the entry stays and the device copies are kept.
  Future<bool> _trash(_Map op, String root) async {
    final id = op['id'] as String;
    var s = await _load();
    final f = s.folder(id);
    if (f == null) return true;
    final fileId = await _ensureFolder(id);
    if (fileId == null) return true;
    final trashbin = await _ensureItem(
      'trashbin',
      name: '.trashbin',
      parentFile: root,
    );
    final DriveFile cur;
    try {
      cur = await drive.get(fileId, fields: 'id,parents,appProperties');
    } on DriveError catch (e) {
      if (e.kind == 'http' && e.status == 404) {
        await _forget(id, const []);
        return true;
      }
      rethrow;
    }
    final ids = s.subtree(id);
    final notes = _notesIn(s, ids);
    final local = {...await store.ids()};
    final unsent = [
      for (final n in notes)
        if (local.contains(n) && await _unsent(n)) n,
    ];
    final already = cur.parents.contains(trashbin);
    final r = trashFolderRule({
      'id': id,
      'fileId': fileId,
      'parentId': already ? 'trashbin' : f['parentId'],
      'parentFileId': cur.parents.where((p) => p != trashbin).join(','),
      'trashbinFileId': trashbin,
      'now': op['trashedAt'],
      'unsent': unsent.isNotEmpty,
      'online': true,
      'pending': {'trashedAt': op['trashedAt'], 'from': op['from']},
    });
    if (r['error'] != null) return true;
    final steps = (r['steps'] as List).cast<String>();
    if (r['already'] == true) steps.add('removeLocal');
    for (final step in steps) {
      switch (step) {
        case 'upload':
          for (final n in unsent) {
            if (!await upload(n)) return false;
          }
        case 'move':
          final q = r['request'] as Map;
          await drive.update(
            fileId,
            addParents: q['addParents'] as String,
            removeParents: q['removeParents'] as String,
            appProperties: {
              for (final e in (q['appProperties'] as Map).entries)
                '${e.key}': '${e.value}',
            },
          );
        case 'removeLocal':
          s = await _load();
          final kept = <String>[];
          for (final n in _notesIn(s, ids)) {
            if (local.contains(n) && !await _removeLocal(n)) kept.add(n);
          }
          await _forget(id, kept);
      }
    }
    return true;
  }

  Future<bool> _removeLocal(String noteId) async {
    try {
      final note = (await store.read(noteId))?.note;
      return note != null && await store.removeNote(noteId, expected: note);
    } on NoteSaveException {
      return false;
    }
  }

  /// The folder, everything below it and their notes leave the cache. A note
  /// whose device copy could not be removed ([kept]) stays hidden.
  Future<void> _forget(String id, List<String> kept) => _mutate((s) {
    final ids = s.subtree(id);
    for (final n in _notesIn(s, ids)) {
      if (kept.contains(n)) {
        s.noteParents[n] = 'trashbin';
      } else {
        s.noteParents.remove(n);
      }
    }
    s.folders.removeWhere((f) => ids.contains(f['id']));
    s.ops.removeWhere(
      (o) => o['kind'] != 'trashFolder' && ids.contains(o['id']),
    );
  });

  /// `trash.remoteTrashed`: another device moved a note this device has into
  /// `.trashbin`. Nothing unsent: the device copy goes (after the editor
  /// closed). Unsent changes: the note is moved back to `trashedFrom` (else
  /// the top level) and the revive notice is counted. This device's own
  /// pending delete wins.
  Future<void> _remoteTrashed(
    Set<Object?> hidden,
    Set<Object?> hiddenFolders,
    Set<String> local,
    Map<String, DriveFile> files,
    Map<String, DriveFile> folders,
    String root,
  ) async {
    for (final id in hidden) {
      final file = files[id];
      if (id is! String || !local.contains(id) || file == null) continue;
      final r = await store.readSync(id);
      if (r.info.pendingTrash) continue;
      try {
        if (!await _unsent(id)) {
          if (await isOpen?.call(id) ?? false) continue; // next refresh
          await forgetNote(id);
          await _removeLocal(id);
          continue;
        }
        final from = file.appProperties['trashedFrom'];
        final origin = from == null ? null : folders[from];
        // An origin that is itself in the trash is no destination.
        final target = origin == null || hiddenFolders.contains(from)
            ? root
            : origin.id;
        await drive.update(
          file.id,
          addParents: target,
          removeParents: file.parents.join(','),
        );
        await device.update((d) {
          final v = d.extra['revivedCount'];
          return d.copyWith(
            extra: {...d.extra, 'revivedCount': (v is int ? v : 0) + 1},
          );
        });
      } on DriveError {
        // The next refresh repeats it.
      }
    }
  }

  // ---- reading Drive -------------------------------------------------------

  /// Sends what waits, then reads the folders and the note parents from Drive
  /// into the cache (spec `library.tree`: cycles are repaired, trash is
  /// hidden). Changes not sent yet are applied over what Drive says. False
  /// when the device is offline or a call failed (the cache is kept).
  Future<bool> refresh() => _run(() async {
    if (!await allowed() || !await online()) return false;
    await _flush();
    try {
      final root = (await device.read()).rootFolderId;
      if (root == null) return false;
      final folderFiles = await _all(
        folderTreeQuery,
        fields: 'id,name,parents,appProperties,createdTime',
      );
      final noteFiles = await _all(
        noteTreeQuery,
        fields: 'id,name,parents,appProperties',
      );
      final kid = <String, String>{root: 'root'};
      for (final f in folderFiles) {
        final k = f.appProperties['kkeujeokId'];
        if (k != null) kid[f.id] = k;
      }
      String parentOf(DriveFile f) {
        final p = f.parents.firstOrNull;
        return p == null ? 'root' : kid[p] ?? p;
      }

      // `.conflicts/<noteId>` (kkeujeokId `cf:<noteId>`, named by the note id)
      // and anything inside `.assets`/`.conflicts` are system folders, never
      // library folders: they showed as undeletable hash-named folders.
      bool system(DriveFile f) {
        final k = f.appProperties['kkeujeokId'];
        if (k != null && (k.startsWith('cf:') || _systemIds.contains(k))) {
          return true;
        }
        final p = kid[f.parents.firstOrNull];
        return p == 'assets' || p == 'conflicts';
      }

      final byKid = <String, DriveFile>{};
      final sorted = [...folderFiles]
        ..sort((a, b) {
          final c = (a.createdTime ?? '~').compareTo(b.createdTime ?? '~');
          return c != 0 ? c : a.id.compareTo(b.id);
        });
      for (final f in sorted) {
        final k = f.appProperties['kkeujeokId'];
        if (k != null && !system(f)) byKid.putIfAbsent(k, () => f);
      }
      final noteParentDrive = <String, String>{
        for (final n in noteFiles)
          if (n.appProperties['kkeujeokId'] != null)
            n.appProperties['kkeujeokId']!: parentOf(n),
      };
      final t = libraryTree({
        'folders': [
          for (final e in byKid.entries)
            {'id': e.key, 'parentId': parentOf(e.value)},
        ],
        'notes': [
          for (final e in noteParentDrive.entries)
            {'noteId': e.key, 'parentId': e.value},
        ],
      });
      // The repair write of a cycle: the smallest id goes to the top level.
      for (final r in t['repairs'] as List) {
        final f = byKid[(r as Map)['id']]!;
        try {
          await _moveTo(f.id, root, root);
        } on DriveError {
          // The next refresh repeats it; the tree is drawn repaired anyway.
        }
      }
      final local = {...await store.ids()};
      await _remoteTrashed(
        {...(t['hidden'] as Map)['notes'] as List},
        {...(t['hidden'] as Map)['folders'] as List},
        local,
        {for (final n in noteFiles) ?n.appProperties['kkeujeokId']: n},
        byKid,
        root,
      );
      await _mutate((s) {
        final old = {for (final f in s.folders) f['id']: f};
        final folders = <_Map>[
          for (final v in t['folders'] as List)
            {
              'id': (v as Map)['id'],
              'fileId': byKid[v['id']]!.id,
              'name': byKid[v['id']]!.name ?? '',
              'parentId': v['parentId'],
            },
          // Created on this device, not in Drive yet.
          for (final f in s.folders)
            if (f['fileId'] == null && !byKid.containsKey(f['id'])) f,
        ];
        final notes = <String, String>{
          for (final n in t['notes'] as List)
            (n as Map)['noteId'] as String:
                (n['folderId'] as String?) ?? 'root',
          // A note Drive does not have yet keeps its parent.
          for (final e in s.noteParents.entries)
            if (local.contains(e.key) && !noteParentDrive.containsKey(e.key))
              e.key: e.value,
        };
        // Drive-only changes not sent yet win over what Drive says.
        for (final o in s.ops) {
          switch (o['kind']) {
            case 'renameFolder':
              folders
                  .where((f) => f['id'] == o['id'])
                  .forEach((f) => f['name'] = o['name']);
            case 'moveFolder':
              folders
                  .where((f) => f['id'] == o['id'])
                  .forEach((f) => f['parentId'] = o['addParent']);
            case 'moveNote':
              if (notes.containsKey(o['noteId']) ||
                  local.contains(o['noteId'])) {
                notes[o['noteId'] as String] = o['addParent'] as String;
              }
            case 'trashFolder':
              // Its folder is still in Drive's tree: keep it for the move.
              if (!folders.any((f) => f['id'] == o['id']) &&
                  old[o['id']] != null) {
                folders.add(old[o['id']]!);
              }
          }
        }
        s.folders
          ..clear()
          ..addAll(folders);
        s.noteParents
          ..clear()
          ..addAll(notes);
      });
      return true;
    } on DriveError {
      return false;
    }
  });
}
