/// Spec `sync.hasUnsent`: whether a note has changes Drive does not have.
/// Never throws; bad input is `{error: invalidInput}`. The order of the
/// `pages` array is not compared (the order of pages is `orderRev`).
Map<String, Object?> hasUnsentRule(Map<String, Object?> input) {
  const bad = <String, Object?>{'error': 'invalidInput'};
  final base = input['base'], working = input['working'];
  final pv = input['pendingVerify'], sidecars = input['unsentSidecars'];
  if (base != null && !_validS(base)) return bad;
  if (working == null || !_validS(working)) return bad;
  if (pv != null && pv is! Map) return bad;
  if (sidecars is! List) return bad;

  Map<Object?, Object?>? pages(Object? s) => s == null
      ? null
      : {
          for (final p in (s as Map)['pages'] as List)
            (p as Map)['id']: p['rev'],
        };
  final b = base as Map?, w = working as Map;
  var unsent = b == null || pv != null || sidecars.isNotEmpty;
  if (!unsent) {
    unsent = w['orderRev'] != b['orderRev'] || w['metaRev'] != b['metaRev'];
  }
  if (!unsent) {
    final bp = pages(b)!, wp = pages(w)!;
    unsent =
        bp.length != wp.length ||
        wp.entries.any((e) => !bp.containsKey(e.key) || bp[e.key] != e.value);
  }
  return {'hasUnsent': unsent};
}

bool _validS(Object? s) {
  if (s is! Map || s['orderRev'] is! String || s['metaRev'] is! String) {
    return false;
  }
  final pages = s['pages'];
  if (pages is! List) return false;
  final ids = <String>{};
  return pages.every(
    (p) =>
        p is Map && p['id'] is String && p['rev'] is String && ids.add(p['id']),
  );
}
