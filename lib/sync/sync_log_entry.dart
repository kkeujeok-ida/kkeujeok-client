import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException;

import '../drive/drive_client.dart' show DriveError;
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
    if (entry.containsKey(f) && !_valid(f, entry[f], entry['event'])) {
      return {'ok': false, 'reason': 'badValue', 'field': f};
    }
  }
  return {'ok': true};
}

// (field, required) in check order.
const _events = <String, List<(String, bool)>>{
  'stateChange': [
    ('noteId', true),
    ('from', true),
    ('to', true),
    ('reason', false),
  ],
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
    ('scope', false),
    ('reason', false),
    ('stage', false),
  ],
  'error': [
    ('class', true),
    ('noteId', false),
    ('status', false),
    ('reason', false),
    ('scope', false),
    ('cause', false),
    ('exception', false),
  ],
  'conflictResolved': [('noteId', true), ('choice', true)],
  'pageTokenRejected': [],
  'duplicatesCleaned': [('count', true)],
  'folderOp': [('folderId', true), ('op', true), ('done', false)],
  'repeatedFailure': [('noteId', true), ('count', true), ('reason', false)],
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

final _exception = RegExp(r'^[A-Za-z0-9_.$:]{1,64}$');
const logStages = {'download', 'upload', 'verify', 'merge'};
const logCauses = {'network', 'auth', 'quota', 'server', 'unknown'};

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

bool _valid(String field, Object? v, Object? event) => switch (field) {
  'at' => v is String && _at.hasMatch(v),
  'event' => v is String && _events.containsKey(v),
  'noteId' || 'rev' || 'folderId' => v is String && _uuid.hasMatch(v),
  'revisionId' => v is String && revisionIdPattern.hasMatch(v),
  'from' || 'to' => v is String && _states.contains(v),
  'kind' => v == 'simple' || v == 'resumable',
  'class' => v is String && _classes.contains(v),
  'status' => _int(v, 100, 599),
  'cause' => v is String && logCauses.contains(v),
  'exception' => v is String && _exception.hasMatch(v),
  'scope' => v == 'global' || v == 'note',
  'op' => v == 'create' || v == 'move' || v == 'rename' || v == 'delete',
  'done' => v == true,
  'choice' => v == 'local' || v == 'remote' || v == 'both',
  'reason' => validLogReason(v),
  'stage' => v is String && logStages.contains(v),
  'attempt' => _int(v, 1, 7),
  'delayMs' => _int(v, 0, 32000),
  'round' => _int(v, 1, 3),
  'count' => _int(v, event == 'duplicatesCleaned' ? 1 : 0, 1 << 53),
  _ => false,
};

final _quotaReason = RegExp(
  r'quota|ratelimit|limitexceeded',
  caseSensitive: false,
);

/// The `reason` of a `backoff` entry: Drive's reason, else what the failure
/// was (`network`, `http429`, ...). The log writer turns a bad one into `other`.
String backoffReason(DriveError e) =>
    e.reason ?? (e.status != null ? 'http${e.status}' : e.kind);

/// The `cause`, `exception` and `scope` of an `error` entry, from what the
/// caller has in hand: the error class, HTTP status, reason and the thrown
/// [error]. Only a type name goes to the log, never a message.
Map<String, Object?> logWhy(
  String cls, {
  int? status,
  String? reason,
  Object? error,
  String? noteId,
}) {
  final kind = error is DriveError ? error.kind : null;
  // package:http's ClientException is matched by name (not a direct dependency).
  final network =
      kind == 'network' ||
      error is SocketException ||
      error is TimeoutException ||
      '${error.runtimeType}' == 'ClientException';
  final cause = network
      ? 'network'
      : cls == 'quota' ||
            status == 429 ||
            (reason != null && _quotaReason.hasMatch(reason))
      ? 'quota'
      : cls == 'reauth' || status == 401 || status == 403
      ? 'auth'
      : status != null && status >= 500
      ? 'server'
      : 'unknown';
  return {
    'cause': cause,
    if (error != null)
      'exception': error is DriveError
          ? 'DriveError.$kind'
          : '${error.runtimeType}',
    'scope': noteId == null ? 'global' : 'note',
  };
}
