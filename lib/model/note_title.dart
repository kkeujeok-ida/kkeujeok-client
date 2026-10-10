// Spec `note.title`.

bool _isTrim(int c) =>
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x20 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

const maxTitleLength = 100;

/// The normalized title, or null when it is longer than 100 code points.
String? normalizeTitle(String title, Iterable<String> existingTitles) {
  final r = title.runes.toList();
  var a = 0, b = r.length;
  while (a < b && _isTrim(r[a])) {
    a++;
  }
  while (b > a && _isTrim(r[b - 1])) {
    b--;
  }
  if (b - a > maxTitleLength) return null;
  if (b > a) return String.fromCharCodes(r.sublist(a, b));
  final taken = existingTitles.toSet();
  var n = 1;
  while (taken.contains('이름 없는 노트 $n')) {
    n++;
  }
  return '이름 없는 노트 $n';
}
