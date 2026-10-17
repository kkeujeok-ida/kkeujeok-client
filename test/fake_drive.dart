import 'package:crypto/crypto.dart' as crypto;
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/drive/note_summary.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';

class FakeRevision {
  FakeRevision(this.id, this.modifiedTime, this.bytes);

  final String id;
  final String modifiedTime;
  final List<int> bytes;
}

class FakeItem {
  FakeItem({
    required this.id,
    required this.name,
    required this.parents,
    required this.appProperties,
    required this.createdTime,
    this.trashed = false,
    this.visible = true,
    this.mimeType,
  });

  final String id;
  String name;
  String? mimeType;
  List<String> parents;
  final Map<String, String> appProperties;
  final String createdTime;
  bool trashed;
  bool deleted = false;

  /// False for a file the app did not create: under `drive.file` it is
  /// never listed or readable.
  final bool visible;

  /// Hidden from listings while the fake's lag runs (the listing lags
  /// behind a create).
  bool lagging = false;

  /// Content revisions, oldest first; the last one is the head.
  final revisions = <FakeRevision>[];

  /// The `contentHints.thumbnail` last written (write only, as in Drive).
  Map<String, Object?>? thumbnailHint;
  String? modifiedTime;

  String? get headRevisionId => revisions.isEmpty ? null : revisions.last.id;
  List<int> get bytes => revisions.isEmpty ? const [] : revisions.last.bytes;
  String? get md5Checksum =>
      revisions.isEmpty ? null : crypto.md5.convert(bytes).toString();
}

class _Session {
  _Session(this.fileId, this.metadata, this.size);

  final String? fileId;
  final Map<String, Object?> metadata;
  final int size;
  final received = <int>[];
  bool expired = false;
  DriveFile? done;
}

/// One upload request as the fake saw it.
class FakeUpload {
  FakeUpload(this.kind, this.metadata, this.size, this.fileId);

  /// `simple` or `resumable` (the start of a session).
  final String kind;
  final Map<String, Object?> metadata;
  final int size;
  final String? fileId;
}

/// In-memory Drive: `createdTime`, parents, trashed, `drive.file`
/// visibility, an optionally lagging listing, content revisions with a head
/// and an MD5, resumable sessions that can expire, scripted failures and
/// hooks.
class FakeDrive implements DriveClient {
  FakeDrive({this.pageSize = 1000});

  final List<FakeItem> items = [];
  int pageSize;
  int _seq = 0;
  int _ms = 0;
  int _rev = 0;
  int _sess = 0;
  final _sessions = <String, _Session>{};

  /// Number of `list` calls after a create that do not see what the create
  /// made.
  int lagLists = 0;
  int _lagLeft = 0;

  /// Every call, in order: `list`, `create`, `get:<id>`, `update:<id>:<what>`,
  /// `upload:<id|new>`, `resumable:start:<id|new>`,
  /// `resumable:put:<session>:<offset>`, `resumable:query:<session>`,
  /// `revisions:<id>`, `media:<id>:<revision>`.
  final List<String> calls = [];

  /// Every upload request (simple, or the start of a session).
  final List<FakeUpload> uploads = [];

  /// Number of last chunks that are answered with 308 and all bytes
  /// received, without finishing the upload.
  int withholdFinishes = 0;

  /// Status an expired session answers with (404 or 410).
  int expiredStatus = 404;

  /// Every change Drive reports, oldest first: the file id and whether it
  /// was removed. A page token is an index into this list.
  final List<(String, bool)> changeLog = [];

  /// Number of the next `changes.list` calls that answer [rejectStatus]
  /// (a rejected page token).
  int rejectChanges = 0;
  int rejectStatus = 410;

  /// Changes per `changes.list` page.
  int changesPageSize = 1000;

  /// Failures to throw: popped by the next call whose name starts with the
  /// key (`list`, `create`, `get`, `update`, `upload`, `resumable`,
  /// `revisions`, `media`).
  final Map<String, List<Object>> failures = {};

  /// Runs before each call; may throw (a crash).
  void Function(String call)? before;

  /// Runs after the call changed state and before it answers; may throw.
  void Function(String call)? after;

  String _time() {
    final d = DateTime.utc(
      2026,
      10,
      10,
      4,
      20,
    ).add(Duration(milliseconds: _ms++));
    return d.toIso8601String();
  }

  String _id() => 'F${++_seq}';

  FakeItem seed({
    String name = 'Kkeujeok',
    String? kkeujeokId,
    List<String> parents = const ['root'],
    String? createdTime,
    bool trashed = false,
    bool visible = true,
    String? mimeType,
  }) {
    final i = FakeItem(
      mimeType: mimeType,
      id: _id(),
      name: name,
      parents: [...parents],
      appProperties: {'kkeujeokId': ?kkeujeokId},
      createdTime: createdTime ?? _time(),
      trashed: trashed,
      visible: visible,
    );
    items.add(i);
    return i;
  }

  Iterable<FakeItem> roots({bool includeTrashed = false}) => items.where(
    (i) =>
        i.appProperties['kkeujeokId'] == 'root' &&
        !i.deleted &&
        (includeTrashed || !i.trashed),
  );

  /// The live item whose `kkeujeokId` is [id], or null.
  FakeItem? byKkeujeokId(String id) => items
      .where((i) => i.appProperties['kkeujeokId'] == id && !i.deleted)
      .firstOrNull;

  /// A change made by another device: new content, new head.
  FakeRevision foreignRevision(FakeItem item, List<int> bytes) =>
      _addRevision(item, bytes);

  /// Drive drops an old revision (never the head).
  void purgeRevision(FakeItem item, String id) {
    if (item.headRevisionId == id) throw StateError('cannot purge the head');
    item.revisions.removeWhere((r) => r.id == id);
  }

  /// Every open resumable session is gone from now on.
  void expireSessions() {
    for (final s in _sessions.values) {
      s.expired = true;
    }
  }

  void _enter(String call) {
    calls.add(call);
    before?.call(call);
    final key = failures.keys.where(call.startsWith).firstOrNull;
    if (key != null && failures[key]!.isNotEmpty) {
      throw failures[key]!.removeAt(0);
    }
  }

  DriveFile _file(FakeItem i, [String? fields]) {
    bool asked(String f) => fields == null || fields.contains(f);
    return DriveFile(
      id: i.id,
      name: i.name,
      parents: [...i.parents],
      appProperties: {...i.appProperties},
      createdTime: i.createdTime,
      trashed: i.trashed,
      headRevisionId: asked('headRevisionId') ? i.headRevisionId : null,
      md5Checksum: asked('md5Checksum') ? i.md5Checksum : null,
      modifiedTime: i.modifiedTime,
      mimeType: i.mimeType,
    );
  }

  FakeRevision _addRevision(FakeItem i, List<int> bytes) {
    final r = FakeRevision('R${++_rev}', _time(), [...bytes]);
    i.revisions.add(r);
    i.modifiedTime = r.modifiedTime;
    changeLog.add((i.id, false));
    return r;
  }

  /// A note another device made, with the summary an upload writes (or none).
  FakeItem foreignNote(
    Note note, {
    required String parent,
    bool summary = true,
    List<int>? bytes,
  }) {
    final data = bytes ?? encodeKkj(note);
    final sum = crypto.md5.convert(data).toString();
    final w = listSummaryRule({
      'op': 'write',
      'note': note.copyJson(),
      'md5': sum,
    });
    final props = (w['appProperties'] as Map).cast<String, Object?>();
    final i = FakeItem(
      id: _id(),
      name: w['name'] as String,
      parents: [parent],
      appProperties: {
        'kkeujeokId': note.noteId,
        if (summary)
          for (final e in props.entries)
            if (e.value != null) e.key: '${e.value}',
      },
      createdTime: _time(),
      mimeType: noteMimeType,
    );
    items.add(i);
    _addRevision(i, data);
    return i;
  }

  /// Another device deletes the file for good.
  void removeForeign(FakeItem item) {
    item.deleted = true;
    changeLog.add((item.id, true));
  }

  /// Another device trashes or restores the file.
  void trashForeign(FakeItem item, {bool trashed = true}) {
    item.trashed = trashed;
    changeLog.add((item.id, false));
  }

  /// Another device (or the Drive web UI) renames the file: no new revision.
  void renameForeign(FakeItem item, String name) {
    item.name = name;
    changeLog.add((item.id, false));
  }

  /// Another device (or the Drive web UI) moves the file to [parent].
  void moveForeign(FakeItem item, String parent) {
    item.parents
      ..clear()
      ..add(parent);
    changeLog.add((item.id, false));
  }

  void _applyMetadata(FakeItem i, Map<String, Object?> m) {
    if (m['name'] is String) i.name = m['name'] as String;
    final props = m['appProperties'];
    if (props is Map) {
      props.forEach((k, v) {
        if (v == null) {
          i.appProperties.remove('$k'); // null removes
        } else {
          i.appProperties['$k'] = '$v';
        }
      });
    }
    final hints = m['contentHints'];
    if (hints is Map && hints['thumbnail'] is Map) {
      i.thumbnailHint = (hints['thumbnail'] as Map).cast<String, Object?>();
    }
  }

  DriveFile _write(String? fileId, Map<String, Object?> m, List<int> bytes) {
    final FakeItem i;
    if (fileId == null) {
      i = FakeItem(
        id: _id(),
        name: m['name'] as String,
        parents: [...(m['parents'] as List).cast<String>()],
        appProperties: {},
        createdTime: _time(),
        mimeType: m['mimeType'] as String?,
      );
      if (lagLists > 0) {
        i.lagging = true;
        _lagLeft = lagLists;
      }
      items.add(i);
    } else {
      i = _find(fileId)!;
      if (m.containsKey('parents')) {
        throw StateError('an upload must not send parents');
      }
    }
    _applyMetadata(i, m);
    _addRevision(i, bytes);
    return _file(i, 'id,headRevisionId,md5Checksum');
  }

  @override
  Future<DrivePage> list(String q, {String? fields, String? pageToken}) async {
    _enter('list');
    final lagging = _lagLeft > 0;
    if (pageToken == null && lagging) _lagLeft--;
    Iterable<FakeItem> m = items.where(
      (i) => i.visible && !i.deleted && !i.trashed && !(lagging && i.lagging),
    );
    final prop = RegExp(r"key='kkeujeokId' and value='((?:\\.|[^'\\])*)'")
        .firstMatch(q);
    final parent = RegExp(r"^'((?:\\.|[^'\\])*)' in parents").firstMatch(q);
    String un(String s) =>
        s.replaceAllMapped(RegExp(r'\\(.)'), (x) => x.group(1)!);
    if (prop != null) {
      final v = un(prop.group(1)!);
      m = m.where((i) => i.appProperties['kkeujeokId'] == v);
    } else if (parent != null) {
      final v = un(parent.group(1)!);
      m = m.where((i) => i.parents.contains(v));
    } else if (q == noteTreeQuery) {
      m = m.where((i) => i.mimeType == noteMimeType);
    } else {
      throw StateError('unsupported q: $q');
    }
    final all = m.toList();
    final from = pageToken == null ? 0 : int.parse(pageToken);
    final to = from + pageSize;
    return DrivePage(
      all.skip(from).take(pageSize).map((i) => _file(i, fields)).toList(),
      to < all.length ? '$to' : null,
    );
  }

  @override
  Future<DriveFile> create(Map<String, Object?> metadata) async {
    _enter('create');
    final i = FakeItem(
      id: _id(),
      name: metadata['name'] as String,
      parents: [...(metadata['parents'] as List).cast<String>()],
      appProperties: {
        for (final e in (metadata['appProperties'] as Map).entries)
          '${e.key}': '${e.value}',
      },
      createdTime: _time(),
      mimeType: metadata['mimeType'] as String?,
    );
    if (lagLists > 0) {
      i.lagging = true;
      _lagLeft = lagLists;
    }
    items.add(i);
    changeLog.add((i.id, false));
    after?.call('create');
    return _file(i);
  }

  FakeItem? _find(String id) =>
      items.where((i) => i.id == id && i.visible && !i.deleted).firstOrNull;

  @override
  Future<DriveFile> get(String id, {String? fields}) async {
    _enter('get:$id');
    final i = _find(id);
    if (i == null) throw const DriveError('http', status: 404);
    return _file(i, fields);
  }

  @override
  Future<DriveFile> update(
    String id, {
    String? addParents,
    String? removeParents,
    bool? trashed,
    Map<String, String>? appProperties,
  }) async {
    final what = switch (trashed) {
      true => 'trash',
      false => 'untrash',
      null => appProperties != null ? 'props' : 'move',
    };
    _enter('update:$id:$what');
    final i = _find(id);
    if (i == null) throw const DriveError('http', status: 404);
    if (addParents != null) i.parents.add(addParents);
    if (removeParents != null) i.parents.remove(removeParents);
    if (trashed != null) i.trashed = trashed;
    if (appProperties != null) i.appProperties.addAll(appProperties);
    changeLog.add((i.id, false));
    after?.call('update:$id:$what');
    return _file(i);
  }

  @override
  Future<DriveFile> uploadSimple({
    String? fileId,
    required Map<String, Object?> metadata,
    required List<int> bytes,
  }) async {
    final call = 'upload:${fileId ?? 'new'}';
    _enter(call);
    uploads.add(FakeUpload('simple', metadata, bytes.length, fileId));
    if (fileId != null && _find(fileId) == null) {
      throw const DriveError('http', status: 404);
    }
    final f = _write(fileId, metadata, bytes);
    after?.call(call);
    return f;
  }

  @override
  Future<String> startResumable({
    String? fileId,
    required Map<String, Object?> metadata,
    required int size,
  }) async {
    _enter('resumable:start:${fileId ?? 'new'}');
    uploads.add(FakeUpload('resumable', metadata, size, fileId));
    if (fileId != null && _find(fileId) == null) {
      throw const DriveError('http', status: 404);
    }
    final id = 'S${++_sess}';
    _sessions[id] = _Session(fileId, metadata, size);
    return 'https://fake.example/upload/$id';
  }

  @override
  Future<ResumableResult> putResumable(
    String uri,
    int size,
    int offset,
    List<int>? chunk,
  ) async {
    final id = uri.split('/').last;
    _enter(chunk == null ? 'resumable:query:$id' : 'resumable:put:$id:$offset');
    final s = _sessions[id];
    if (s == null || s.expired) {
      throw DriveError('http', status: expiredStatus);
    }
    if (s.done != null) return ResumableResult(file: s.done);
    if (chunk != null) {
      if (offset != s.received.length) {
        return ResumableResult(received: s.received.length);
      }
      s.received.addAll(chunk);
    }
    if (s.received.length >= s.size && withholdFinishes > 0) {
      withholdFinishes--; // all bytes there, yet no file in the answer
      return ResumableResult(received: s.size);
    }
    if (s.received.length >= s.size) {
      s.done = _write(s.fileId, s.metadata, s.received);
      after?.call('resumable:done:$id');
      return ResumableResult(file: s.done);
    }
    after?.call('resumable:put:$id:$offset');
    return ResumableResult(received: s.received.length);
  }

  @override
  Future<List<DriveRevision>> listRevisions(String fileId) async {
    _enter('revisions:$fileId');
    final i = _find(fileId);
    if (i == null) throw const DriveError('http', status: 404);
    return [for (final r in i.revisions) DriveRevision(r.id, r.modifiedTime)];
  }

  @override
  Future<List<int>> downloadRevision(String fileId, String revisionId) async {
    _enter('media:$fileId:$revisionId');
    final i = _find(fileId);
    final r = i?.revisions.where((r) => r.id == revisionId).firstOrNull;
    if (r == null) throw const DriveError('http', status: 404);
    return [...r.bytes];
  }

  @override
  Future<String> getStartPageToken() async {
    _enter('changes:start');
    return '${changeLog.length}';
  }

  @override
  Future<ChangesPage> listChanges(String pageToken) async {
    _enter('changes:$pageToken');
    if (rejectChanges > 0) {
      rejectChanges--;
      throw DriveError('http', status: rejectStatus);
    }
    final from = int.tryParse(pageToken);
    if (from == null || from < 0 || from > changeLog.length) {
      throw const DriveError('http', status: 410);
    }
    final to = from + changesPageSize;
    final out = <DriveChange>[];
    for (final (id, removed) in changeLog.skip(from).take(changesPageSize)) {
      final i = items.where((x) => x.id == id && x.visible).firstOrNull;
      if (i == null) continue;
      out.add(
        removed || i.deleted
            ? DriveChange(id, removed: true)
            : DriveChange(id, file: _file(i, noteFileFields)),
      );
    }
    return to < changeLog.length
        ? ChangesPage(out, nextPageToken: '$to')
        : ChangesPage(out, newStartPageToken: '${changeLog.length}');
  }
}
