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
