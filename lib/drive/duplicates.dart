/// Spec `drive.duplicates`: which of several items with one `kkeujeokId`
/// stays. The caller guarantees well-formed input (spec).
Map<String, Object?> driveDuplicatesRule(Map<String, Object?> input) {
  final id = input['kkeujeokId'] as String;
  if (id.startsWith('asset:')) return {'keep': null, 'merge': <String>[]};
  final items = [
    for (final i in input['items'] as List)
      (id: (i as Map)['id'] as String, at: i['createdTime'] as String),
  ];
  if (items.isEmpty) return {'error': 'noItems'};
  // Dart compares strings by UTF-16 code unit, as the spec says.
  items.sort((a, b) {
    final c = a.at.compareTo(b.at);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return {
    'keep': items.first.id,
    'merge': [for (final i in items.skip(1)) i.id],
  };
}
