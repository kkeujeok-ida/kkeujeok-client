import '../model/note.dart' show copyJsonValue;

/// Spec `merge`: page by page, then page order, then note fields. Pure: no
/// clock, no random number, no input mutated (every input is deep-copied, so
/// the result shares no object with an argument). Works on the JSON maps
/// themselves, because merge also runs on input that did not go through the
/// reader (an unknown `background`, a `lineage`).
typedef Json = Map<String, dynamic>;

const _knownTop = {
  'formatVersion',
  'noteId',
  'meta',
  'metaRev',
  'metaSeq',
  'orderRev',
  'orderSeq',
  'pages',
};
const _knownMeta = ['title', 'coverId'];
const _backgrounds = {'plain', 'lined', 'grid', 'dot'};
const lineageMax = 16;

/// Spec `merge`: `{result: merged, ...}`, `{result: unsupportedVersion}` or
/// `{error: noteIdMismatch | duplicatePageId}`. [ctx] is `{now, orderRev,
/// rev, editedBy, lastSeenRemoteSeq}`.
Map<String, Object?> mergeNotes(
  Json? base,
  Json local,
  Json remote,
  Json ctx,
) => _merge(base, local, remote, ctx, const []);

/// Spec `merge.requeue`: the merge against the queue state at commit time
/// ([localAtCommit]), plus `requeue`: what changed while the network ran.
Map<String, Object?> mergeRequeueNotes({
  required Json? base,
  required Json localAtStart,
  required Json localAtCommit,
  required Json remote,
  required Json ctx,
}) {
  final r = _merge(base, localAtCommit, remote, ctx, [localAtStart]);
  if (r['result'] != 'merged') return r;
  final s = _pages(localAtStart), c = _pages(localAtCommit);
  final pages = <String>[
    for (final id in {...s.keys, ...c.keys})
      if ((s[id] == null) != (c[id] == null) ||
          (s[id] != null && s[id]!['rev'] != c[id]!['rev']))
        id,
  ]..sort(); // Dart orders strings by UTF-16 code unit, as the spec says
  return {
    ...r,
    'requeue': {
      'pages': pages,
      'order': localAtStart['orderRev'] != localAtCommit['orderRev'],
      'meta': localAtStart['metaRev'] != localAtCommit['metaRev'],
    },
  };
}

List<String> lineageOf(Json page) {
  final l = page['lineage'];
  return l is List ? [for (final x in l) x as String] : const [];
}

bool _hasDuplicate(Json? n) {
  if (n == null) return false;
  final ids = [for (final p in (n['pages'] as List).cast<Json>()) p['id']];
  return ids.toSet().length != ids.length;
}

bool _unsupported(Object? v) =>
    v is num && v.isFinite && v == v.truncateToDouble() && v > 1;

Map<String, Object?> _merge(
  Json? base0,
  Json local0,
  Json remote0,
  Json ctx0,
  List<Json> extra,
) {
  // merge.formatVersion, in this order.
  if (_unsupported(remote0['formatVersion'])) {
    return {'result': 'unsupportedVersion'};
  }
  final all = [base0, local0, remote0, ...extra];
  if (all.any((n) => n != null && n['noteId'] != local0['noteId'])) {
    return {'error': 'noteIdMismatch'};
  }
  if (all.any(_hasDuplicate)) return {'error': 'duplicatePageId'};

  final base = copyJsonValue(base0) as Json?;
  final local = copyJsonValue(local0) as Json;
  final remote = copyJsonValue(remote0) as Json;
  final ctx = copyJsonValue(ctx0) as Json;

  final bp = _pages(base), lp = _pages(local), rp = _pages(remote);
  // Processing order U.
  final u = <String>{...lp.keys, ...rp.keys, ...bp.keys}.toList();

  final result = <String, Json>{};
  final conflicts = <Json>[];
  final sidecars = <Json>[];

  void conflict(String id, String kind, Json side, Json? theirs) {
    var index = (local['pages'] as List).indexWhere((p) => p['id'] == id);
    if (index < 0 && base != null) {
      index = (base['pages'] as List).indexWhere((p) => p['id'] == id);
    }
    conflicts.add({
      'pageId': id,
      'kind': kind,
      'rev': side['rev'],
      'theirsRev': theirs?['rev'],
      'detectedAt': ctx['now'],
      'originalIndex': index,
      'resolvedAt': null,
    });
    sidecars.add({
      'noteId': local['noteId'],
      'pageId': id,
      'rev': side['rev'],
      'seq': side['seq'],
      'editedAt': side['editedAt'],
      'editedBy': side['editedBy'],
      'kind': kind,
      'page': side,
    });
  }

  for (final id in u) {
    final b = bp[id], l = lp[id];
    var r = rp[id];
    // merge.staleSeq: an old write that arrived late is not the remote page.
    if (b != null &&
        r != null &&
        r['rev'] != b['rev'] &&
        (r['seq'] as num) < (b['seq'] as num)) {
      r = b;
    }
    Json? out;
    if (b != null) {
      final lSame = l != null && l['rev'] == b['rev'];
      final rSame = r != null && r['rev'] == b['rev'];
      if (l != null && r != null) {
        if (lSame && rSame) {
          out = l;
        } else if (lSame) {
          out = r;
          if (!lineageOf(r).contains(b['rev'])) {
            conflict(id, 'bothEdited', b, r);
          }
        } else if (rSame) {
          out = {
            ...l,
            'lineage': [b['rev'], ...lineageOf(b)].take(lineageMax).toList(),
          };
        } else if (l['rev'] == r['rev']) {
          out = l;
        } else {
          out = r;
          conflict(id, 'bothEdited', l, r);
        }
      } else if (l != null) {
        if (!lSame) conflict(id, 'remoteDeleted', l, null);
      } else if (r != null && !rSame) {
        out = r;
        conflict(id, 'localDeleted', b, r);
      }
    } else if (l != null && r == null) {
      out = l;
    } else if (l == null && r != null) {
      out = r;
    } else if (l != null && r != null) {
      if (l['rev'] == r['rev']) {
        out = l;
      } else {
        out = r;
        conflict(id, 'bothEdited', l, r);
      }
    }
    if (out != null) result[id] = out;
  }

  // merge.order
  final rc =
      base == null ||
      (remote['orderRev'] != base['orderRev'] &&
          !((remote['orderSeq'] as num) < (base['orderSeq'] as num)));
  final cNote = rc ? remote : local, oNote = rc ? local : remote;
  List<String> ids(Json n) => [
    for (final p in (n['pages'] as List).cast<Json>()) p['id'] as String,
  ];
  final c = ids(cNote), o = ids(oNote);
  final order = [
    for (final id in c)
      if (result.containsKey(id)) id,
  ];
  for (var i = 0; i < o.length; i++) {
    final id = o[i];
    if (!result.containsKey(id) || order.contains(id)) continue;
    var at = 0;
    for (var j = i - 1; j >= 0; j--) {
      final k = order.indexOf(o[j]);
      if (k >= 0) {
        at = k + 1;
        break;
      }
    }
    order.insert(at, id);
  }
  final sameOrder =
      order.length == c.length &&
      List.generate(order.length, (i) => order[i] == c[i]).every((x) => x);
  final orderRev = sameOrder ? cNote['orderRev'] : ctx['orderRev'];
  final orderSeq = sameOrder
      ? cNote['orderSeq']
      : (_max(local['orderSeq'], remote['orderSeq']) + 1).toInt();

  // merge.meta
  final metaL = local['metaRev'] != base?['metaRev'];
  final metaR =
      base == null ||
      (remote['metaRev'] != base['metaRev'] &&
          !((remote['metaSeq'] as num) < (base['metaSeq'] as num)));
  final Json win;
  if (metaR && !metaL) {
    win = remote;
  } else if (!metaR) {
    win = local;
  } else if (local['metaRev'] == remote['metaRev']) {
    win = remote;
  } else if (local['metaSeq'] != remote['metaSeq']) {
    win = (local['metaSeq'] as num) > (remote['metaSeq'] as num)
        ? local
        : remote;
  } else {
    win =
        (local['metaRev'] as String).compareTo(remote['metaRev'] as String) > 0
        ? local
        : remote;
  }
  final meta = <String, dynamic>{
    for (final k in _knownMeta)
      if ((win['meta'] as Json).containsKey(k)) k: (win['meta'] as Json)[k],
  };
  for (final src in [local, remote]) {
    (src['meta'] as Json).forEach((k, v) {
      if (!_knownMeta.contains(k)) meta[k] = v;
    });
  }

  // merge.unknownFields (top level) and the result note.
  final note = <String, dynamic>{};
  for (final src in [local, remote]) {
    src.forEach((k, v) {
      if (!_knownTop.contains(k)) note[k] = v;
    });
  }
  note
    ..['formatVersion'] = local['formatVersion']
    ..['noteId'] = local['noteId']
    ..['meta'] = meta
    ..['metaRev'] = win['metaRev']
    ..['metaSeq'] = win['metaSeq']
    ..['orderRev'] = orderRev
    ..['orderSeq'] = orderSeq
    ..['pages'] = [for (final id in order) result[id]!];

  // The output lists, in the order of U.
  final reupload = [
    for (final id in u)
      if (result.containsKey(id) &&
          (rp[id] == null || rp[id]!['rev'] != result[id]!['rev']))
        id,
  ];
  final undoDrop = [
    for (final id in lp.keys)
      if (result[id] == null || result[id]!['rev'] != lp[id]!['rev']) id,
  ];
  final readOnly = [
    for (final id in u)
      if (result.containsKey(id) &&
          !_backgrounds.contains(result[id]!['background']))
        id,
  ];
  var seen = (ctx['lastSeenRemoteSeq'] as num);
  for (final p in rp.values) {
    seen = _max(seen, p['seq']);
  }
  seen = _max(_max(seen, remote['orderSeq']), remote['metaSeq']);

  return {
    'result': 'merged',
    'note': note,
    'conflicts': conflicts,
    'sidecars': sidecars,
    'reupload': {
      'pages': reupload,
      'order': orderRev != remote['orderRev'],
      'meta': win['metaRev'] != remote['metaRev'],
    },
    'lastSeenRemoteSeq': seen.toInt(),
    'undoDrop': undoDrop,
    'readOnlyPages': readOnly,
  };
}

Map<String, Json> _pages(Json? n) => {
  if (n != null)
    for (final p in (n['pages'] as List).cast<Json>()) p['id'] as String: p,
};

num _max(Object? a, Object? b) => (a as num) > (b as num) ? a : b;
