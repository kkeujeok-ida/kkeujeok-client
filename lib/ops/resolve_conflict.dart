import '../model/note.dart' show copyJsonValue;
import '../model/uuid_v5.dart';
import '../sync/merge.dart' show Json, lineageOf, lineageMax;

/// Namespace of the page ids that `both` makes (spec `merge.resolve`).
const pageIdNamespace = 'b3a1f1a0-6f0e-4d57-9a53-5c1d2e7f9a10';

const _choices = {
  'bothEdited': ['mine', 'theirs', 'both'],
  'localDeleted': ['remove', 'keep'],
  'remoteDeleted': ['remove', 'keep'],
};

/// Spec `merge.resolve`: settles one conflict. Pure: the inputs are
/// deep-copied and none is changed. `{result: resolved, note, conflict,
/// undoDrop}` or `{error: alreadyResolved | invalidChoice | pageNotFound |
/// identicalVersions}`, the first that applies. It is the one edit that has
/// no inverse, so the caller drops the undo records of `undoDrop` pages.
Map<String, Object?> resolveConflict(
  Json note0,
  Json conflict0,
  Json sidecar0,
  Object? choice,
  Json ctx0,
) {
  final note = copyJsonValue(note0) as Json;
  final conflict = copyJsonValue(conflict0) as Json;
  final side = copyJsonValue((sidecar0['page'])) as Json;
  final ctx = copyJsonValue(ctx0) as Json;
  final pageId = conflict['pageId'] as String;
  final kind = conflict['kind'];

  if (conflict['resolvedAt'] != null) return {'error': 'alreadyResolved'};
  final set = _choices[kind];
  if (choice is! String || set == null || !set.contains(choice)) {
    return {'error': 'invalidChoice'};
  }
  final pages = (note['pages'] as List).cast<Json>();
  final idx = pages.indexWhere((p) => p['id'] == pageId);
  final cur = idx < 0 ? null : pages[idx];
  if (cur == null && kind != 'remoteDeleted') return {'error': 'pageNotFound'};
  if (choice == 'both' && cur != null && cur['rev'] == sidecar0['rev']) {
    return {'error': 'identicalVersions'};
  }

  final basis = cur ?? side;
  final lastSeen = ctx['lastSeenRemoteSeq'] as num;
  Json fresh(Json s) => {
    ...s,
    'id': pageId,
    'rev': ctx['rev'],
    'seq':
        ((basis['seq'] as num) > lastSeen ? basis['seq'] as num : lastSeen)
            .toInt() +
        1,
    'editedAt': ctx['now'],
    'editedBy': ctx['editedBy'],
    'lineage': [basis['rev'], ...lineageOf(basis)].take(lineageMax).toList(),
  };
  void renewOrder() {
    final s = note['orderSeq'] as num;
    note['orderRev'] = ctx['orderRev'];
    note['orderSeq'] = (s > lastSeen ? s : lastSeen).toInt() + 1;
  }

  var undoDrop = <String>[pageId];
  if (kind == 'bothEdited') {
    if (choice == 'mine') {
      pages[idx] = fresh(side);
    } else if (choice == 'theirs') {
      pages[idx] = fresh(cur!);
    } else {
      final curHi =
          (cur!['rev'] as String).compareTo(side['rev'] as String) > 0;
      final lo = curHi ? side : cur;
      final newId = uuidV5('$pageId:${lo['rev']}', pageIdNamespace);
      final mine = curHi ? <String, dynamic>{...side, 'id': newId} : side;
      final theirs = curHi ? cur : <String, dynamic>{...cur, 'id': newId};
      pages.removeAt(idx);
      final k = (conflict['originalIndex'] as int).clamp(0, pages.length);
      final have = {for (final p in pages) p['id']};
      pages.insertAll(k, [
        for (final p in [mine, theirs])
          if (!have.contains(p['id'])) p,
      ]);
      renewOrder();
      undoDrop = [pageId, newId];
    }
  } else if (kind == 'localDeleted') {
    if (choice == 'remove') {
      pages.removeAt(idx);
      renewOrder();
    } else {
      pages[idx] = fresh(cur!);
    }
  } else if (choice == 'keep' && cur == null) {
    final k = (conflict['originalIndex'] as int).clamp(0, pages.length);
    pages.insert(k, fresh(side));
    renewOrder();
  }
  return {
    'result': 'resolved',
    'note': note,
    'conflict': {...conflict, 'resolvedAt': ctx['now']},
    'undoDrop': undoDrop,
  };
}
