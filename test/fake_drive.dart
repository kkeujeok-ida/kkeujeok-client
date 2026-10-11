import 'package:kkeujeok/drive/drive_client.dart';

class FakeItem {
  FakeItem({
    required this.id,
    required this.name,
    required this.parents,
    required this.appProperties,
    required this.createdTime,
    this.trashed = false,
    this.visible = true,
  });

  final String id;
  String name;
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
}

/// In-memory Drive: `createdTime`, parents, trashed, `drive.file`
/// visibility, an optionally lagging listing, scripted failures and hooks.
class FakeDrive implements DriveClient {
  FakeDrive({this.pageSize = 1000});

  final List<FakeItem> items = [];
  int pageSize;
  int _seq = 0;
  int _ms = 0;

  /// Number of `list` calls after a create that do not see what the create
  /// made.
  int lagLists = 0;
  int _lagLeft = 0;

  /// Every call, in order: `list`, `create`, `get:<id>`, `update:<id>:<what>`.
  final List<String> calls = [];

  /// Failures to throw: popped by the next call whose name starts with the
  /// key (`list`, `create`, `get`, `update`).
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
  }) {
    final i = FakeItem(
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

  void _enter(String call) {
    calls.add(call);
    before?.call(call);
    final key = failures.keys.where(call.startsWith).firstOrNull;
    if (key != null && failures[key]!.isNotEmpty) {
      throw failures[key]!.removeAt(0);
    }
  }

  DriveFile _file(FakeItem i) => DriveFile(
    id: i.id,
    name: i.name,
    parents: [...i.parents],
    appProperties: {...i.appProperties},
    createdTime: i.createdTime,
    trashed: i.trashed,
  );

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
    } else {
      throw StateError('unsupported q: $q');
    }
    final all = m.toList();
    final from = pageToken == null ? 0 : int.parse(pageToken);
    final to = from + pageSize;
    return DrivePage(
      all.skip(from).take(pageSize).map(_file).toList(),
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
    );
    if (lagLists > 0) {
      i.lagging = true;
      _lagLeft = lagLists;
    }
    items.add(i);
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
    return _file(i);
  }

  @override
  Future<DriveFile> update(
    String id, {
    String? addParents,
    String? removeParents,
    bool? trashed,
  }) async {
    final what = trashed == true ? 'trash' : 'move';
    _enter('update:$id:$what');
    final i = _find(id);
    if (i == null) throw const DriveError('http', status: 404);
    if (addParents != null) i.parents.add(addParents);
    if (removeParents != null) i.parents.remove(removeParents);
    if (trashed != null) i.trashed = trashed;
    after?.call('update:$id:$what');
    return _file(i);
  }
}
