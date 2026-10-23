/// Specs `version.list` and `version.keepForever` (spec `version.md`): what
/// the history list of a note shows and which revision pins are released.
/// Pure; bad input is `{error: invalidInput}`, never an exception.
const _bad = <String, Object?>{'error': 'invalidInput'};

final _timestamp = RegExp(
  r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d\.\d{3}Z$',
);
final _uuid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
final _sidecarTail = RegExp('^($_uuid):($_uuid)\$');
final _index = RegExp(r'^(0|[1-9]\d*)$');

bool isTimestamp(Object? v) => v is String && _timestamp.hasMatch(v);

/// Milliseconds since 1970-01-01 of a canonical timestamp (the day is not
/// checked against the month, as the spec says).
int timestampMs(String t) {
  int n(int from, int len) => int.parse(t.substring(from, from + len));
  final m = n(5, 2), d = n(8, 2);
  final y = m <= 2 ? n(0, 4) - 1 : n(0, 4);
  final era = (y >= 0 ? y : y - 399) ~/ 400;
  final yoe = y - era * 400;
  final doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) ~/ 5 + d - 1;
  final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
  final days = era * 146097 + doe - 719468;
  return days * 86400000 +
      n(11, 2) * 3600000 +
      n(14, 2) * 60000 +
      n(17, 2) * 1000 +
      n(20, 3);
}

const _thirtyDays = 2592000000;
const _reasons = {'unreadable', 'unsupportedVersion', 'purged'};

/// `info` is valid: null, a failure, or the success shape of its kind.
bool _validInfo(Object? info, {required bool sidecar}) {
  if (info == null) return true;
  if (info is! Map) return false;
  final ok = info['ok'];
  if (ok is! bool) return false;
  if (!ok) return _reasons.contains(info['reason']);
  if (sidecar) return info['editedBy'] is String;
  final pages = info['pages'];
  return pages is List &&
      pages.every(
        (p) => p is Map && p['editedAt'] is String && p['editedBy'] is String,
      );
}

bool _validRevisions(Object? revisions) {
  if (revisions is! List) return false;
  final ids = <String>{};
  for (final r in revisions) {
    if (r is! Map) return false;
    final id = r['id'];
    if (id is! String || id.isEmpty || !ids.add(id)) return false;
    if (!isTimestamp(r['modifiedTime'])) return false;
    if (r.containsKey('keepForever') && r['keepForever'] is! bool) return false;
  }
  return true;
}

String? _device(Object? info, {required bool sidecar}) {
  if (info is! Map || info['ok'] != true) return null;
  if (sidecar) return info['editedBy'] as String;
  String? name, at;
  for (final p in info['pages'] as List) {
    final e = (p as Map)['editedAt'] as String;
    if (at == null || e.compareTo(at) > 0) {
      at = e;
      name = p['editedBy'] as String;
    }
  }
  return name;
}

String _status(Object? info) => info is! Map
    ? 'unknown'
    : info['ok'] == true
    ? 'ok'
    : info['reason'] as String;

Map<String, Object?> versionListRule(Map<String, Object?> input) {
  final now = input['now'], noteId = input['noteId'];
  final head = input['headRevisionId'];
  final revisions = input['revisions'], sidecars = input['sidecars'];
  if (!isTimestamp(now) || noteId is! String) return _bad;
  if (head != null && head is! String) return _bad;
  if (!_validRevisions(revisions) || sidecars is! List) return _bad;
  for (final r in revisions as List) {
    if (!_validInfo((r as Map)['info'], sidecar: false)) return _bad;
  }
  for (final s in sidecars) {
    if (s is! Map) return _bad;
    final p = s['appProperties'];
    if (p != null && p is! Map) return _bad;
    if (!_validInfo(s['info'], sidecar: true)) return _bad;
  }

  // Revisions: newest first, equal times with the later input first.
  final revs = [for (final (i, r) in revisions.indexed) (i, r as Map)]
    ..sort((a, b) {
      final c = (b.$2['modifiedTime'] as String).compareTo(
        a.$2['modifiedTime'] as String,
      );
      return c != 0 ? c : b.$1.compareTo(a.$1);
    });
  final entries = <Map<String, Object?>>[
    for (final (_, r) in revs)
      {
        'kind': 'revision',
        'revisionId': r['id'],
        'at': r['modifiedTime'],
        'deviceName': _device(r['info'], sidecar: false),
        'status': _status(r['info']),
        'current': r['id'] == head,
        'beforeRestore': r['keepForever'] == true,
        'restorable':
            (_status(r['info']) == 'unknown' || _status(r['info']) == 'ok') &&
            r['id'] != head,
      },
  ];

  final nowMs = timestampMs(now as String);
  final seen = <String>{};
  final cars = <Map<String, Object?>>[];
  final prefix = 'sc:$noteId:';
  for (final s in sidecars) {
    final props = (s as Map)['appProperties'] as Map?;
    final id = props?['kkeujeokId'];
    if (id is! String || !id.startsWith(prefix)) continue;
    final m = _sidecarTail.firstMatch(id.substring(prefix.length));
    if (m == null || !seen.add(id)) continue;
    final resolved = props!['kkjResolved'];
    if (!isTimestamp(resolved)) continue;
    if (nowMs - timestampMs(resolved as String) > _thirtyDays) continue;
    final edited = props['kkjEdited'];
    final idx = props['kkjIndex'];
    final status = _status(s['info']);
    cars.add({
      'kind': 'sidecar',
      'pageId': m.group(1),
      'rev': m.group(2),
      'at': isTimestamp(edited) ? edited : resolved,
      'deviceName': _device(s['info'], sidecar: true),
      'status': status,
      'originalIndex': idx is String && _index.hasMatch(idx)
          ? (int.tryParse(idx) ?? 0)
          : 0,
      'restorable': status == 'unknown' || status == 'ok',
    });
  }
  cars.sort((a, b) {
    final c = (a['pageId'] as String).compareTo(b['pageId'] as String);
    return c != 0 ? c : (a['rev'] as String).compareTo(b['rev'] as String);
  });

  // One list, newest first; the sort is stable, so on equal times a revision
  // stays before a sidecar.
  final all = [
    for (final e in [...entries, ...cars]) e,
  ];
  final order = [for (final (i, e) in all.indexed) (i, e)]
    ..sort((a, b) {
      final c = (b.$2['at'] as String).compareTo(a.$2['at'] as String);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return {
    'entries': [for (final (_, e) in order) e],
  };
}

/// False for a sidecar whose `kkeujeokId` was seen before (first wins).
bool _firstOf(Set<Object?> ids, Object? s) {
  final id = ((s as Map)['appProperties'] as Map?)?['kkeujeokId'];
  return id == null || ids.add(id);
}

/// [versionListRule] that drops the items the rule refuses (a bad time or
/// `info`, a repeated id) instead of failing as a whole; the rule itself and
/// its contract stay as they are.
Map<String, Object?> versionListLenient(Map<String, Object?> input) {
  final r = versionListRule(input);
  final revs = input['revisions'], cars = input['sidecars'];
  if (r['error'] == null || revs is! List || cars is! List) return r;
  bool ok(List rs, List ss) =>
      versionListRule({...input, 'revisions': rs, 'sidecars': ss})['error'] ==
      null;
  final ids = <Object?>{}, cids = <Object?>{};
  return versionListRule({
    ...input,
    'revisions': [
      for (final v in revs)
        if (ok([v], const []) && ids.add((v as Map)['id'])) v,
    ],
    'sidecars': [
      for (final s in cars)
        if (ok(const [], [s]) && _firstOf(cids, s)) s,
    ],
  });
}

Map<String, Object?> keepForeverRule(Map<String, Object?> input) {
  final revisions = input['revisions'], target = input['target'];
  if (!_validRevisions(revisions) || target is! String) return _bad;
  final list = (revisions as List).cast<Map>();
  final t = list.where((r) => r['id'] == target).firstOrNull;
  if (t == null) return _bad;
  if (t['keepForever'] == true) return {'mark': null, 'release': <String>[]};
  final pinned =
      [
        for (final (i, r) in list.indexed)
          if (r['keepForever'] == true) (i, r),
      ]..sort((a, b) {
        final c = (a.$2['modifiedTime'] as String).compareTo(
          b.$2['modifiedTime'] as String,
        );
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
  final n = pinned.length - 199;
  return {
    'mark': target,
    'release': [
      for (final (_, r) in pinned.take(n < 0 ? 0 : n)) r['id'] as String,
    ],
  };
}
