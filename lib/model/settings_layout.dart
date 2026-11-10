// settings.sections / settings.activeSection (spec/settings.md).

const _sections = <(String, List<String>)>[
  ('general', ['language', 'theme']),
  ('input', ['leftHanded', 'penOnly', 'straighten', 'smooth', 'pressureCurve']),
  ('tools', ['visibleTools', 'penPalette']),
  ('support', ['help', 'privacy', 'exportLog', 'penDiag']),
  ('account', ['logOut', 'disconnect']),
];

/// Shown sections in order; `account` needs [signedIn], `penDiag` is Android only.
List<({String id, List<String> items})> settingsSections({
  required bool signedIn,
  required String platform,
}) => [
  for (final (id, items) in _sections)
    if (id != 'account' || signedIn)
      (
        id: id,
        items: [
          for (final i in items)
            if (i != 'penDiag' || platform == 'android') i,
        ],
      ),
];

/// Active section id: the last heading at or above the viewport top (+offset);
/// at the scroll end the last one; the first when none qualifies.
String activeSettingsSection(
  List<({String id, double top})> headings, {
  required double viewportTop,
  required double offset,
  required bool atEnd,
}) {
  if (atEnd) return headings.last.id;
  var active = headings.first.id;
  for (final h in headings) {
    if (h.top <= viewportTop + offset) active = h.id;
  }
  return active;
}

/// settings.search: items whose text contains every query term (lowercase);
/// no terms shows all. `counts` has a key for every section in [items].
({List<String> visible, Map<String, int> counts}) searchSettings(
  String query,
  List<({String id, String section, String text})> items,
) {
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty);
  final visible = <String>[];
  final counts = <String, int>{};
  for (final i in items) {
    final text = i.text.toLowerCase();
    final hit = terms.every(text.contains);
    counts[i.section] = (counts[i.section] ?? 0) + (hit ? 1 : 0);
    if (hit) visible.add(i.id);
  }
  return (visible: visible, counts: counts);
}
