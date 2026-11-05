import 'dart:math' as math;

import 'pdf_rules.dart' show isPdfBackground;

// spec/invert.md (All Dark): display-only color rules. Never stored or exported.

typedef Rgb = List<int>;

const paperRgb = <int>[27, 28, 31]; // invert.paper (surface-base-dark)
const lineHex = '#c5ced8', dotHex = '#a0aab5'; // page-background.md

int _round(num x) => (x + 0.5).floor();
double _lin(num c8) {
  final c = c8 / 255;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _gam(double x) => x <= 0.0031308
    ? 12.92 * x
    : 1.055 * math.pow(x, 1 / 2.4).toDouble() - 0.055;

double _cbrt(double x) =>
    x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

Rgb _parse(String hex) => [
  for (var i = 1; i < 7; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
];

({double l, double c, double h}) _oklch(Rgb rgb) {
  final r = _lin(rgb[0]), g = _lin(rgb[1]), b = _lin(rgb[2]);
  final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  final bigL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  final a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  final bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  return (l: bigL, c: math.sqrt(a * a + bb * bb), h: math.atan2(bb, a));
}

List<double> _linear(double bigL, double c, double h) {
  final a = c * math.cos(h), b = c * math.sin(h);
  final l = math.pow(bigL + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
  final m = math.pow(bigL - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
  final s = math.pow(bigL - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  ];
}

bool _inGamut(List<double> v) => v.every((x) => x >= -1e-6 && x <= 1 + 1e-6);

Rgb _toRgb(double bigL, double c, double h) {
  var v = _linear(bigL, c, h);
  if (!_inGamut(v)) {
    var lo = 0.0, hi = c;
    for (var i = 0; i < 30; i++) {
      final mid = (lo + hi) / 2;
      if (_inGamut(_linear(bigL, mid, h))) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    v = _linear(bigL, lo, h);
  }
  return [for (final x in v) _round(_gam(x.clamp(0.0, 1.0)) * 255)];
}

double _luminance(Rgb c) =>
    0.2126 * _lin(c[0]) + 0.7152 * _lin(c[1]) + 0.0722 * _lin(c[2]);

double _ratio(Rgb a, Rgb b) {
  final ya = _luminance(a), yb = _luminance(b);
  return (math.max(ya, yb) + 0.05) / (math.min(ya, yb) + 0.05);
}

/// `invert.color`.
Rgb invertColor(String hex) {
  final k = _oklch(_parse(hex));
  return _toRgb(1 - k.l, k.c, k.h);
}

/// `invert.ink`: pen strokes and text letters.
({Rgb rgb, bool corrected}) invertInk(String hex) {
  final k = _oklch(_parse(hex));
  final inv = _toRgb(1 - k.l, k.c, k.h);
  if (_ratio(inv, paperRgb) >= 3) return (rgb: inv, corrected: false);
  var lo = 1 - k.l, hi = 1.0;
  for (var i = 0; i < 30; i++) {
    final mid = (lo + hi) / 2;
    if (_ratio(_toRgb(mid, k.c, k.h), paperRgb) >= 4.5) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return (rgb: _toRgb(hi, k.c, k.h), corrected: true);
}

/// `invert.highlighter`: 0.4 source-over per stroke, in order, over the paper.
Rgb invertHighlighter(List<String> colors) {
  final below = [for (final c in paperRgb) c.toDouble()];
  for (final h in colors) {
    final c = _parse(h);
    for (var i = 0; i < 3; i++) {
      below[i] = below[i] * 0.6 + c[i] * 0.4;
    }
  }
  return [for (final x in below) _round(x)];
}

/// `invert.background`.
Map<String, Object?> invertBackground(Object? background) => {
  'paper': paperRgb,
  if (background == 'lined' || background == 'grid')
    'line': invertColor(lineHex),
  if (background == 'dot') 'dot': invertColor(dotHex),
};

/// `invert.layers`.
Map<String, Object?> invertLayers(Map<String, Object?> i) {
  const none = {'invert': false, 'how': 'none'};
  final layer = i['layer'];
  if (layer == 'cover' || layer == 'pdf') return none;
  final page = i['page'];
  if (page is Map && isPdfBackground(page['background'])) return none;
  if (layer == 'paper') return {'invert': true, 'how': 'paper'};
  if (layer == 'pattern') return {'invert': true, 'how': 'pattern'};
  final e = i['element'];
  if (e is! Map) return none;
  switch (e['type']) {
    case 'stroke':
      return {
        'invert': true,
        'how': e['tool'] == 'highlighter' ? 'highlighter' : 'ink',
      };
    case 'text':
      return {'invert': true, 'how': 'ink'};
    case 'image':
      return {...none, 'underlay': '#ffffff'};
  }
  return none;
}

/// An ink color string (`#rrggbb` or `#rrggbbaa`) shown in All Dark; the alpha
/// byte is kept. A malformed value is left as is.
String inkHex(String hex) {
  if (!RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(hex)) return hex;
  final rgb = invertInk(hex).rgb;
  return '#${[for (final c in rgb) c.toRadixString(16).padLeft(2, '0')].join()}${hex.substring(7)}';
}
