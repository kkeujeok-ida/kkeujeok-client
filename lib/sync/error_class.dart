import '../drive/drive_client.dart';

/// Spec `sync.errorClass`. Never throws.
Map<String, Object?> errorClassRule(Map<String, Object?> input) {
  const bad = {'error': 'invalidInput'};
  final reason = input['reason'];
  if (reason != null && reason is! String) return bad;
  switch (input['kind']) {
    case 'network':
      return {'class': 'backoff'};
    case 'parse':
      return {'class': 'unreadable'};
    case 'trashed':
      return {'class': 'deleted'};
    case 'http':
      final s = input['status'];
      if (s is! num || s != s.truncateToDouble() || s < 100 || s > 599) {
        return bad;
      }
      return {'class': _http(s.toInt(), reason as String?)};
    default:
      return bad;
  }
}

String _http(int s, String? reason) {
  if ((s >= 200 && s <= 299) || s == 308) return 'ok';
  if (s == 401) return 'reauth';
  if (s == 400 && reason == 'invalid_grant') return 'reauth';
  if (s == 403) {
    if (reason == 'rateLimitExceeded' || reason == 'userRateLimitExceeded') {
      return 'backoff';
    }
    return reason == 'storageQuotaExceeded' ? 'quota' : 'fatal';
  }
  if (s == 404) return 'deleted';
  if (s == 408 || s == 429 || s >= 500) return 'backoff';
  return 'fatal';
}

/// The class of a failed Drive call; `fatal` for anything unclassifiable.
String classifyDriveError(DriveError e) {
  final c = errorClassRule({
    'kind': e.kind,
    if (e.status != null) 'status': e.status,
    'reason': e.reason,
  })['class'];
  return c is String && c != 'ok' ? c : 'fatal';
}
