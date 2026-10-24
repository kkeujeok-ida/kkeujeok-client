import 'dart:math' as math;

import 'note.dart' show copyJsonValue, jsonEqual;
import 'number.dart';
import 'text_metrics.dart';

// spec/text.md: constants, normal form of runs, text.layout.

const sizeMin = 8.0, sizeMax = 96.0, sizeDefault = 16.0;
const sizeSteps = <double>[
  8,
  10,
  12,
  14,
  16,
  18,
  20,
  24,
  28,
  32,
  36,
  48,
  64,
  96,
];
const colorDefault = '#000000';
const lineHeight = 1.4, baselineK = 1.1, italicSkew = 0.2, widthMin = 20.0;

final _colorRe = RegExp(r'^#[0-9a-f]{6}$');

Set<int> _set(String s) => s.runes.toSet();
final _forbidStart = _set('.,!?:;)]}%、。，．）」』…”’》〕');
final _noBreakAfter = _set('([{「『“‘《〔');

bool isZeroWidth(int c) =>
    (c >= 0x200b && c <= 0x200f) ||
    (c >= 0xfe00 && c <= 0xfe0f) ||
    (c >= 0xe0100 && c <= 0xe01ef);

bool _cjk(int c) =>
    (c >= 0x1100 && c <= 0x11ff) ||
    (c >= 0x3000 && c <= 0x30ff) ||
    (c >= 0x3130 && c <= 0x318f) ||
    (c >= 0x3400 && c <= 0x4dbf) ||
    (c >= 0x4e00 && c <= 0x9fff) ||
    (c >= 0xac00 && c <= 0xd7a3) ||
    (c >= 0xf900 && c <= 0xfaff) ||
    (c >= 0xff00 && c <= 0xffef) ||
    (c >= 0x20000 && c <= 0x2fa1f);

bool _finite(Object? v) => v is num && v.isFinite;

int cpLen(String s) => s.runes.length;

/// Trim set of `note.title` (spec/ops.md "Text box operations").
bool isBlankText(String t) => t.runes.every(
  (c) =>
      c == 0x20 ||
      c == 0xa0 ||
      c == 0x1680 ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202f ||
      c == 0x205f ||
      c == 0x3000 ||
      c == 0xfeff ||
      (c >= 0x09 && c <= 0x0d) ||
      (c >= 0x2000 && c <= 0x200a),
);

/// `\r\n` and a lone `\r` become `\n`.
String normalizeNewlines(String t) => t.replaceAll(RegExp(r'\r\n?'), '\n');

bool validRuns(Object? runs) {
  if (runs is! List) return false;
  return runs.every((r) {
    if (r is! Map) return false;
    final s = r['start'], e = r['end'];
    if (s is! num || e is! num || s != s.truncate() || e != e.truncate()) {
      return false;
    }
    if (r.containsKey('size')) {
      final size = r['size'];
      if (!_finite(size)) return false;
      final q = round2((size as num).toDouble());
      if (q < sizeMin || q > sizeMax) return false;
    }
    if (r.containsKey('color')) {
      final color = r['color'];
      if (!(color is String && _colorRe.hasMatch(color))) return false;
    }
    if (r.containsKey('bold') && r['bold'] is! bool) return false;
    if (r.containsKey('italic') && r['italic'] is! bool) return false;
    return true;
  });
}

// Code point i gets the merge of every run covering it, later runs winning.
List<Map<String, dynamic>> _styles(List runs, int n) {
  final st = List.generate(n, (_) => <String, dynamic>{});
  for (final r in runs) {
    final m = r as Map;
    final attrs = <String, dynamic>{
      for (final e in m.entries)
        if (e.key != 'start' && e.key != 'end') e.key as String: e.value,
    };
    if (attrs['size'] is num) {
      attrs['size'] = round2((attrs['size'] as num).toDouble());
    }
    final a = (m['start'] as num).toInt(), b = (m['end'] as num).toInt();
    for (var i = math.max(0, a); i < math.min(n, b); i++) {
      for (final e in attrs.entries) {
        st[i][e.key] = copyJsonValue(e.value);
      }
    }
  }
  return st;
}

/// The merged run properties of each of the [n] code points.
List<Map<String, dynamic>> styleList(List runs, int n) => _styles(runs, n);

/// `normalizeRuns(runs, n)` of spec/text.md.
List<Map<String, dynamic>> normalizeRuns(List runs, int n) {
  final st = _styles(runs, n);
  final out = <(int, int, Map<String, dynamic>)>[];
  for (var i = 0; i < n; i++) {
    if (st[i].isEmpty) continue;
    if (out.isNotEmpty && out.last.$2 == i && jsonEqual(out.last.$3, st[i])) {
      out[out.length - 1] = (out.last.$1, i + 1, out.last.$3);
    } else {
      out.add((i, i + 1, st[i]));
    }
  }
  return [
    for (final (s, e, attrs) in out)
      {
        'start': s,
        'end': e,
        for (final k in (attrs.keys.toList()..sort())) k: attrs[k],
      },
  ];
}

class LineBox {
  const LineBox({
    required this.start,
    required this.end,
    required this.width,
    required this.top,
    required this.baseline,
    required this.height,
  });
  final int start, end;
  final double width, top, baseline, height;
}

class TextLayout {
  const TextLayout(this.height, this.lines);
  final double height;
  final List<LineBox> lines;
}

double _fixSize(Object? v) =>
    _finite(v) ? (v as num).toDouble().clamp(sizeMin, sizeMax) : sizeDefault;

/// Per code point size and bold after the clamps of spec/text.md.
({List<double> size, List<bool> bold, double base}) textStyles(
  Map<String, dynamic> e,
) {
  final text = e['text'] is String ? e['text'] as String : '';
  final n = cpLen(text);
  final base = _fixSize(e['size']);
  final st = _styles(e['runs'] is List ? e['runs'] as List : const [], n);
  return (
    size: [for (final s in st) s['size'] == null ? base : _fixSize(s['size'])],
    bold: [
      for (final s in st)
        s['bold'] is bool ? s['bold'] as bool : e['bold'] == true,
    ],
    base: base,
  );
}

/// `text.layout` of a text element.
TextLayout layoutText(Map<String, dynamic> e) {
  final cps = (e['text'] is String ? e['text'] as String : '').runes.toList();
  final n = cps.length;
  final (:size, :bold, :base) = textStyles(e);
  final w = _finite(e['width'])
      ? math.max(widthMin, (e['width'] as num).toDouble())
      : widthMin;
  final m = TextMetrics.instance;
  double adv(int i) {
    if (isZeroWidth(cps[i])) return 0;
    final f = m.font(bold[i]);
    return (f.advance(cps[i]) * size[i]) / f.upm;
  }

  bool canBreakAfter(int i) {
    final c = cps[i], d = cps[i + 1];
    if (_noBreakAfter.contains(c)) return false;
    if (d == 0x20 || d == 0x0a || _forbidStart.contains(d)) return false;
    if (c == 0x20 || c == 0x2d) return true;
    return _cjk(c) || _cjk(d);
  }

  final lines = <LineBox>[];
  var s = 0;
  var top = 0.0;
  for (;;) {
    var x = 0.0, hasContent = false, lastBreak = -1, end = n, forced = false;
    for (var i = s; i < n; i++) {
      if (cps[i] == 0x0a) {
        end = i;
        forced = true;
        break;
      }
      final a = adv(i);
      if (cps[i] == 0x20) {
        x += a;
        if (hasContent && i < n - 1 && canBreakAfter(i)) lastBreak = i + 1;
        continue;
      }
      if (hasContent && x + a > w) {
        end = lastBreak >= 0 ? lastBreak : i;
        break;
      }
      x += a;
      hasContent = true;
      if (i < n - 1 && canBreakAfter(i)) lastBreak = i + 1;
    }
    var acc = 0.0, trimmed = 0.0;
    double? mx;
    for (var k = s; k < end; k++) {
      acc += adv(k);
      if (cps[k] != 0x20) trimmed = acc;
      mx = mx == null ? size[k] : math.max(mx, size[k]);
    }
    if (forced) mx = mx == null ? size[end] : math.max(mx, size[end]);
    mx ??= base;
    final lh = mx * lineHeight;
    lines.add(
      LineBox(
        start: s,
        end: end,
        width: round2(trimmed),
        top: round2(top),
        baseline: round2(top + mx * baselineK),
        height: round2(lh),
      ),
    );
    top += lh;
    if (end >= n && !forced) break;
    s = forced ? end + 1 : end;
  }
  return TextLayout(round2(top), lines);
}

double textHeight(Map<String, dynamic> e) => layoutText(e).height;
