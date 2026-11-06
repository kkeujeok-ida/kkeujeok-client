// Spec `trash` (Story 14.2): the rules after the move into `.trashbin`.
// `trashNote` and `trashFolder` live in `library_rules.dart`.
import 'library_rules.dart' show RuleJson;

const _noteMime = 'application/vnd.kkeujeok.kkj';
const _folderMime = 'application/vnd.google-apps.folder';
final _ts = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');

/// `trash.restoreNote` and `trash.restoreFolder`.
RuleJson trashRestoreRule(RuleJson i) {
  final item = (i['item'] as Map).cast<String, Object?>();
  if (item['trashed'] == true) return {'gone': true};
  if (item['parentId'] != 'trashbin') return {'already': true};
  final props = item['appProperties'];
  final f = props is Map ? props['trashedFrom'] : null;
  final from = f is String && f != '' ? f : 'root';
  final origin = (i['origin'] as Map?)?.cast<String, Object?>();
  var toOrigin = false;
  var fallback = false;
  if (from != 'root') {
    if (from != 'trashbin' && origin != null && origin['inTrash'] != true) {
      toOrigin = true;
    } else {
      fallback = true;
    }
  }
  return {
    'destination': toOrigin ? 'origin' : 'root',
    'rootFallback': fallback,
    'request': {
      'fileId': item['fileId'],
      'addParents': toOrigin ? origin!['fileId'] : i['rootFileId'],
      'removeParents': item['parentFileId'],
      'appProperties': {'trashedFrom': null, 'trashedAt': null},
    },
  };
}

/// `trash.purgeItem`.
RuleJson trashPurgeRule(RuleJson i) {
  final item = (i['item'] as Map).cast<String, Object?>();
  if (item['trashed'] == true) return {'already': true};
  if (item['parentId'] != 'trashbin') return {'error': 'notInTrash'};
  return {
    'request': {'fileId': item['fileId'], 'trashed': true},
  };
}

/// `trash.emptyTrash`.
RuleJson trashEmptyRule(RuleJson i) {
  final failed = {for (final f in i['failed'] as List) f};
  final requests = <Object?>[], remaining = <Object?>[], done = <Object?>[];
  for (final e in i['items'] as List) {
    final it = (e as Map).cast<String, Object?>();
    final already = it['trashed'] == true;
    if (!already) {
      requests.add({'id': it['id'], 'fileId': it['fileId'], 'trashed': true});
    }
    if (!already && failed.contains(it['id'])) {
      remaining.add(it['id']);
    } else {
      done.add(it['id']);
    }
  }
  return {'requests': requests, 'remaining': remaining, 'done': done};
}

/// `trash.list`.
RuleJson trashListRule(RuleJson i) {
  final counts = (i['noteCounts'] as Map).cast<String, Object?>();
  final out = <RuleJson>[];
  for (final e in i['items'] as List) {
    final f = (e as Map).cast<String, Object?>();
    final p = ((f['appProperties'] as Map?) ?? const {})
        .cast<String, Object?>();
    final id = p['kkeujeokId'];
    if (id is! String || id.isEmpty) continue;
    final kind = f['mimeType'] == _noteMime
        ? 'note'
        : f['mimeType'] == _folderMime
        ? 'folder'
        : null;
    if (kind == null) continue;
    final at = p['trashedAt'], from = p['trashedFrom'];
    out.add({
      'kind': kind,
      'id': id,
      'fileId': f['id'],
      'trashedAt': at is String && _ts.hasMatch(at) ? at : f['modifiedTime'],
      'trashedFrom': from is String && from != '' ? from : null,
      if (kind == 'folder') 'noteCount': counts[id] ?? 0,
    });
  }
  out.sort((a, b) {
    final c = (b['trashedAt'] as String).compareTo(a['trashedAt'] as String);
    return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
  });
  return {'entries': out};
}

const _actions = {
  'edit',
  'metaChange',
  'upload',
  'download',
  'restore',
  'purge',
};
const _allowed = {
  'library': {'edit', 'metaChange', 'upload', 'download'},
  'pendingTrash': {'upload', 'download', 'restore'},
  'trashed': {'download', 'restore', 'purge'},
};

/// `trash.access`.
RuleJson trashAccessRule(RuleJson i) {
  final set = _allowed[i['state']];
  if (set == null || !_actions.contains(i['action'])) {
    return {'error': 'invalidInput'};
  }
  return {'allowed': set.contains(i['action'])};
}

/// `trash.remoteTrashed`.
RuleJson trashRemoteTrashedRule(RuleJson i) {
  if (i['pending'] == true) {
    return {
      'local': 'remove',
      'restore': false,
      'banner': false,
      'notify': false,
    };
  }
  if (i['unsent'] == true) {
    return {'local': 'keep', 'restore': true, 'banner': false, 'notify': true};
  }
  return {
    'local': 'remove',
    'restore': false,
    'banner': i['open'] == true,
    'notify': false,
  };
}
