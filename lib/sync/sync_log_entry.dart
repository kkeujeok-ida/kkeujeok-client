import '../storage/sync_info.dart' show revisionIdPattern;

/// Spec `synclog.entry`: checks one log entry before it is stored or
/// exported. Never throws.
Map<String, Object?> checkLogEntry(Object? entry) {
  if (entry is! Map) return {'ok': false, 'reason': 'notObject'};
  final keys = [for (final k in entry.keys) k.toString()];

  final spec = entry['event'] is String ? _events[entry['event']] : null;
  final allowed = {
    'at',
    'event',
    ...(spec?.map((f) => f.$1) ??
        _events.values.expand((l) => l.map((f) => f.$1))),
  };
  final unknown = keys.where((k) => !allowed.contains(k)).toList()..sort();
  if (unknown.isNotEmpty) {
    return {'ok': false, 'reason': 'unknownField', 'field': unknown.first};
  }

  for (final f in [
    'at',
    'event',
    if (spec != null) ...spec.where((f) => f.$2).map((f) => f.$1),
  ]) {
    if (!entry.containsKey(f)) {
      return {'ok': false, 'reason': 'missingField', 'field': f};
    }
  }

  for (final f in ['at', 'event', ...?spec?.map((f) => f.$1)]) {
    if (entry.containsKey(f) && !_valid(f, entry[f])) {
      return {'ok': false, 'reason': 'badValue', 'field': f};
    }
  }
  return {'ok': true};
}

// (field, required) in check order.
const _events = <String, List<(String, bool)>>{
  'stateChange': [('noteId', true), ('from', true), ('to', true)],
  'uploadStarted': [('noteId', true), ('kind', true)],
  'uploadFinished': [('noteId', true), ('revisionId', true)],
  'verifyRound': [('noteId', true), ('round', true), ('count', true)],
  'revisionDownloaded': [('noteId', true), ('revisionId', true)],
  'merged': [('noteId', true), ('rev', false)],
  'conflictFound': [('noteId', true), ('rev', false)],
  'baseAdvanced': [('noteId', true), ('revisionId', true)],
  'backoff': [
    ('class', true),
    ('attempt', true),
    ('delayMs', true),
    ('noteId', false),
  ],
  'error': [
    ('class', true),
    ('noteId', false),
    ('status', false),
    ('reason', false),
  ],
  'pageTokenRejected': [],
};

final _at = RegExp(
  r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d\.\d{3}Z$',
);
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _reason = RegExp(r'^[A-Za-z0-9_]{1,64}$');

/// True when [reason] is in the `reason` domain.
bool validLogReason(Object? reason) =>
    reason is String && _reason.hasMatch(reason);

const _states = {'synced', 'pending', 'syncing', 'conflict', 'error'};
const _classes = {
  'backoff',
  'quota',
  'reauth',
  'deleted',
  'unreadable',
  'fatal',
};

bool _int(Object? v, int min, int max) =>
    v is num && v.isFinite && v == v.truncateToDouble() && v >= min && v <= max;

bool _valid(String field, Object? v) => switch (field) {
  'at' => v is String && _at.hasMatch(v),
  'event' => v is String && _events.containsKey(v),
  'noteId' || 'rev' => v is String && _uuid.hasMatch(v),
  'revisionId' => v is String && revisionIdPattern.hasMatch(v),
  'from' || 'to' => v is String && _states.contains(v),
  'kind' => v == 'simple' || v == 'resumable',
  'class' => v is String && _classes.contains(v),
  'status' => _int(v, 100, 599),
  'reason' => validLogReason(v),
  'attempt' => _int(v, 1, 7),
  'delayMs' => _int(v, 0, 32000),
  'round' => _int(v, 1, 3),
  'count' => _int(v, 0, 1 << 53),
  _ => false,
};
