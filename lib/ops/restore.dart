import '../model/note.dart' show copyJsonValue;
import '../sync/merge.dart' show Json, lineageOf, lineageMax;

/// Specs `ops.restoreNote` and `ops.restorePage`: a restore is a new edit of
/// the note, not an operation of the undo history (no inverse). Pure: the
/// inputs are deep-copied and none is changed.
///
/// The result is `{note, inverse: null, undoDrop, conflicts}` or `{error}`.

int _seq(Object? v) => v is num ? v.toInt() : 0;

int _max3(int a, int b, int c) => [a, b, c].reduce((x, y) => x > y ? x : y);

List<String> _lineage(Json basis) =>
    [basis['rev'] as String, ...lineageOf(basis)].take(lineageMax).toList();

List<Json> _resolveAll(
  List<Json> conflicts,
  Object? now,
  bool Function(Json) pick,
) => [
  for (final c in conflicts)
    c['resolvedAt'] == null && pick(c) ? {...c, 'resolvedAt': now} : c,
];

/// Malformed input is `{error: invalidInput}`, never an exception.
Map<String, Object?> restoreNote(
  Json note0,
  Json op0,
  Json ctx0,
  List<Json> conflicts0,
) => _safe(() => _restoreNote(note0, op0, ctx0, conflicts0));

Map<String, Object?> restorePage(
  Json note0,
  Json op0,
  Json ctx0,
  List<Json> conflicts0,
) => _safe(() => _restorePage(note0, op0, ctx0, conflicts0));

Map<String, Object?> _safe(Map<String, Object?> Function() run) {
  try {
    return run();
  } on Object {
    return {'error': 'invalidInput'};
  }
}

Map<String, Object?> _restoreNote(
  Json note0,
  Json op0,
  Json ctx0,
  List<Json> conflicts0,
) {
  final note = copyJsonValue(note0) as Json;
  final version = copyJsonValue(op0['version']) as Json;
  final ctx = copyJsonValue(ctx0) as Json;
  final conflicts = [for (final c in conflicts0) copyJsonValue(c) as Json];
  if (version['noteId'] != note['noteId']) return {'error': 'noteIdMismatch'};
  final vpages = (version['pages'] as List).cast<Json>();
  if (vpages.any((p) => p['id'] is! String || p['rev'] is! String) ||
      (ctx['revs'] as List).length < vpages.length) {
    return {'error': 'invalidInput'};
  }
  final vids = [for (final p in vpages) p['id']];
  if (vids.toSet().length != vids.length) {
    return {'error': 'duplicatePageId'};
  }
  final npages = (note['pages'] as List).cast<Json>();
  final cur = {for (final p in npages) p['id'] as String: p};
  final revs = (ctx['revs'] as List).cast<String>();
  final lastSeen = _seq(ctx['lastSeenRemoteSeq']);

  final pages = <Json>[];
  for (var i = 0; i < vpages.length; i++) {
    final v = vpages[i];
    final c = cur[v['id']];
    pages.add({
      ...v,
      'rev': revs[i],
      'seq':
          _max3(c == null ? 0 : _seq(c['seq']), _seq(v['seq']), lastSeen) + 1,
      'editedAt': ctx['now'],
      'editedBy': ctx['editedBy'],
      'lineage': _lineage(c ?? v),
    });
  }
  note['pages'] = pages;
  note['orderRev'] = ctx['orderRev'];
  note['orderSeq'] =
      (_seq(note['orderSeq']) > lastSeen ? _seq(note['orderSeq']) : lastSeen) +
      1;
  return {
    'note': note,
    'inverse': null,
    'undoDrop': [
      for (final p in npages) p['id'] as String,
      for (final id in vids)
        if (!cur.containsKey(id)) id as String,
    ],
    'conflicts': _resolveAll(conflicts, ctx['now'], (_) => true),
  };
}

Map<String, Object?> _restorePage(
  Json note0,
  Json op0,
  Json ctx0,
  List<Json> conflicts0,
) {
  final note = copyJsonValue(note0) as Json;
  final page = copyJsonValue(op0['page']) as Json;
  final pageId = op0['pageId'] as String;
  final ctx = copyJsonValue(ctx0) as Json;
  final conflicts = [for (final c in conflicts0) copyJsonValue(c) as Json];
  if (page['rev'] is! String || op0['originalIndex'] is! int) return {'error': 'invalidInput'};
  if (page['id'] != pageId) return {'error': 'pageIdMismatch'};
  final pages = (note['pages'] as List).cast<Json>();
  final idx = pages.indexWhere((p) => p['id'] == pageId);
  final cur = idx < 0 ? null : pages[idx];
  final lastSeen = _seq(ctx['lastSeenRemoteSeq']);
  final restored = <String, dynamic>{
    ...page,
    'id': pageId,
    'rev': ctx['rev'],
    'seq':
        _max3(cur == null ? 0 : _seq(cur['seq']), _seq(page['seq']), lastSeen) +
        1,
    'editedAt': ctx['now'],
    'editedBy': ctx['editedBy'],
    'lineage': _lineage(cur ?? page),
  };
  if (cur != null) {
    pages[idx] = restored;
  } else {
    final at = (op0['originalIndex'] as int).clamp(0, pages.length);
    pages.insert(at, restored);
    final s = _seq(note['orderSeq']);
    note['orderRev'] = ctx['orderRev'];
    note['orderSeq'] = (s > lastSeen ? s : lastSeen) + 1;
  }
  return {
    'note': note,
    'inverse': null,
    'undoDrop': [pageId],
    'conflicts': _resolveAll(
      conflicts,
      ctx['now'],
      (c) => c['pageId'] == pageId,
    ),
  };
}
