// Spec `sync.uploadKind`, `sync.verifyPlan`, `sync.backoff` and
// `sync.stateMachine`. Pure; none of them throws.
import 'dart:math' as math;

const _bad = <String, Object?>{'error': 'invalidInput'};

/// Largest body sent as one multipart request (5 MiB).
const simpleUploadLimit = 5 * 1024 * 1024;

bool _isInt(Object? v) => v is num && v.isFinite && v == v.truncateToDouble();

/// `sync.uploadKind`.
Map<String, Object?> uploadKindRule(Map<String, Object?> input) {
  final s = input['size'];
  if (!_isInt(s) || (s as num) < 0) return const {'error': 'invalidSize'};
  return {'kind': s <= simpleUploadLimit ? 'simple' : 'resumable'};
}

final _timestamp = RegExp(
  r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d\.\d{3}Z$',
);

/// `sync.verifyPlan`.
Map<String, Object?> verifyPlanRule(Map<String, Object?> input) {
  final base = input['base'], ours = input['ours'], head = input['head'];
  final round = input['round'], revs = input['revisions'];
  if (!_isInt(round) || (round as num) < 1 || round > 3) return _bad;
  if (revs is! List || revs.isEmpty) return _bad;
  final listed = <(String, String)>[];
  final ids = <String>{};
  for (final r in revs) {
    if (r is! Map) return _bad;
    final id = r['id'], t = r['modifiedTime'];
    if (id is! String || t is! String || !_timestamp.hasMatch(t)) return _bad;
    if (!ids.add(id)) return _bad;
    listed.add((id, t));
  }
  if (ours is! String || head is! String) return _bad;
  if (!ids.contains(ours) || !ids.contains(head)) return _bad;
  if (base != null && base is! String) return _bad;

  // Stable: equal times keep the input order.
  final order = List<int>.generate(listed.length, (i) => i)
    ..sort((a, b) {
      final c = listed[a].$2.compareTo(listed[b].$2);
      return c != 0 ? c : a.compareTo(b);
    });
  final sorted = [for (final i in order) listed[i].$1];

  final String target;
  final List<String> candidates;
  if (base != null && !ids.contains(base)) {
    target = 'head';
    candidates = head != ours ? [head] : const [];
  } else {
    target = 'base';
    final from = base == null ? 0 : sorted.indexOf(base as String) + 1;
    candidates = [
      for (final id in sorted.skip(from))
        if (id != ours) id,
    ];
  }
  if (candidates.isEmpty) {
    return {'result': 'verified', 'download': <String>[], 'target': null};
  }
  if (round == 3) {
    return {
      'result': 'error',
      'reason': 'verifyExhausted',
      'download': <String>[],
      'target': null,
    };
  }
  return {'result': 'merge', 'download': candidates, 'target': target};
}

/// Retries after the first failure of one call; the 7th failure stops.
const maxBackoffAttempts = 7;

/// `sync.backoff`.
Map<String, Object?> backoffRule(Map<String, Object?> input) {
  final a = input['attempt'], j = input['jitter'];
  if (!_isInt(a) || (a as num) < 1 || a > maxBackoffAttempts) return _bad;
  if (j is! num || !j.isFinite || j < 0 || j > 1) return _bad;
  if (a == maxBackoffAttempts) return const {'retry': false};
  final nominal = 1000.0 * math.pow(2, a - 1);
  final d = (nominal * (0.5 + j.toDouble())).floor();
  return {'retry': true, 'delayMs': math.min(32000, d)};
}

const _states = {'synced', 'pending', 'syncing', 'conflict', 'error'};

String? _next(String state, String event) => switch ((state, event)) {
  ('synced', 'edit') => 'pending',
  ('pending', 'edit') => 'pending',
  ('syncing', 'edit') => 'syncing',
  ('conflict', 'edit') => 'conflict',
  ('error', 'edit') => 'error',
  ('pending', 'upload') => 'syncing',
  ('conflict', 'upload') => 'syncing',
  ('synced', 'remoteChange') => 'syncing',
  ('conflict', 'remoteChange') => 'syncing',
  ('pending', 'remoteChange') => 'pending',
  ('syncing', 'remoteChange') => 'syncing',
  ('error', 'remoteChange') => 'error',
  ('syncing', 'verified') => 'verified',
  ('conflict', 'verified') => 'verified',
  ('synced', 'failed') => 'error',
  ('pending', 'failed') => 'error',
  ('syncing', 'conflictFound') => 'conflict',
  ('syncing', 'failed') => 'error',
  ('conflict', 'resolve') => 'resolve',
  ('error', 'retry') => 'pending',
  _ => null,
};

/// `sync.stateMachine` (`transition` and `display`).
Map<String, Object?> stateMachineRule(Map<String, Object?> input) {
  switch (input['op']) {
    case 'transition':
      final next = _next('${input['state']}', '${input['event']}');
      if (input['state'] is! String ||
          input['event'] is! String ||
          next == null) {
        return const {'error': 'illegalTransition'};
      }
      if (next != 'verified' && next != 'resolve') return {'state': next};
      final u = input['unresolved'];
      if (!_isInt(u) || (u as num) < 0) return _bad;
      if (next == 'resolve') return {'state': u > 0 ? 'conflict' : 'pending'};
      final unsent = input.containsKey('unsent') ? input['unsent'] : false;
      if (unsent is! bool) return _bad;
      return {
        'state': u > 0
            ? 'conflict'
            : unsent
            ? 'pending'
            : 'synced',
      };
    case 'display':
      final s = input['state'], p = input['platform'], o = input['online'];
      if (s is! String || !_states.contains(s)) return _bad;
      if (p != 'android' && p != 'web') return _bad;
      if (o is! bool) return _bad;
      switch (s) {
        case 'synced':
          return const {'label': 'saved'};
        case 'pending':
          return {'label': p == 'android' && !o ? 'offline' : 'pending'};
        case 'syncing':
          final c = input['cause'];
          if (c == 'upload') return const {'label': 'saving'};
          if (c == 'remote') return const {'label': 'receiving'};
          return _bad;
        case 'conflict':
          return const {'label': 'twoVersions'};
        default:
          return const {'label': 'notSaved'};
      }
  }
  return _bad;
}

/// The state after [event], or null for an illegal pair or bad input.
String? transition(
  String state,
  String event, {
  int unresolved = 0,
  bool unsent = false,
}) {
  final r = stateMachineRule({
    'op': 'transition',
    'state': state,
    'event': event,
    'unresolved': unresolved,
    'unsent': unsent,
  });
  return r['state'] as String?;
}
