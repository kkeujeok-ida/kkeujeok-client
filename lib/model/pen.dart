import 'pen_palette.dart';

/// The five stroke tools (spec `pen.md`).
const penTools = {'pen', 'highlighter', 'fountain', 'pencil', 'tape'};

/// Width range (pt) per tool, spec `pen.palette` / `pen.kinds`.
(double, double) penWidthRange(String tool) => switch (tool) {
  'highlighter' => (4, 30),
  'tape' => (8, 30),
  'fountain' => (0.5, 8),
  'pencil' => (0.5, 6),
  _ => (0.5, 10),
};

/// The kind's own starting pen: default width and `usePressure` (spec
/// `pen.kinds`); the color is black, or yellow for the highlighter family.
Pen defaultPenOf(String tool) => switch (tool) {
  'highlighter' => defaultPenSlots[2],
  'tape' => const Pen(
    tool: 'tape',
    color: '#ffe066',
    width: 20,
    usePressure: false,
  ),
  'fountain' ||
  'pencil' => Pen(tool: tool, color: '#000000', width: 1.5, usePressure: true),
  _ => defaultPen,
};

/// A pen as the toolbar holds it (spec `pen.md` slots).
class Pen {
  const Pen({
    this.tool = 'pen',
    required this.color,
    required this.width,
    required this.usePressure,
  });

  final String tool; // one of [penTools]
  final String color; // `#rrggbb`, written to strokes as is
  final double width; // pt
  final bool usePressure;

  bool get isHighlighter => tool == 'highlighter';

  /// Key of the ko/en color name in the UI.
  String get colorNameKey => colorNameKeyFor(color);

  Pen withUsePressure(bool v) =>
      Pen(tool: tool, color: color, width: width, usePressure: v);

  Pen withColor(String hex) =>
      Pen(tool: tool, color: hex, width: width, usePressure: usePressure);

  /// Kept in the tool's range, in steps of 0.1.
  Pen withWidth(double v) {
    final (lo, hi) = penWidthRange(tool);
    return Pen(
      tool: tool,
      color: color,
      width: ((v.clamp(lo, hi) * 10).round() / 10).clamp(lo, hi),
      usePressure: usePressure,
    );
  }

  /// spec `pen.switchKind`: the kind's default width and `usePressure`; the
  /// color stays when it is in the kind's default palette, else the palette's
  /// first. The same kind resets only the width.
  Pen withTool(String t) {
    final d = defaultPenOf(t);
    if (t == tool) {
      return Pen(
        tool: t,
        color: color,
        width: d.width,
        usePressure: usePressure,
      );
    }
    final c = color.toLowerCase();
    final keep = paletteFor(t).any((p) => p.hex == c);
    return Pen(
      tool: t,
      color: keep ? color : d.color,
      width: d.width,
      usePressure: d.usePressure,
    );
  }

  Map<String, Object> toJson() => {
    'tool': tool,
    'color': color,
    'width': width,
    'usePressure': usePressure,
  };
}

/// Name key of a palette color (`black`, `darkGray`, ...), else `custom`.
String colorNameKeyFor(String hex) {
  final h = hex.toLowerCase();
  for (final c in [...penPalette, ...highlighterPalette]) {
    if (c.hex == h) return c.nameKey;
  }
  return 'custom';
}

const defaultPen = Pen(color: '#000000', width: 2.0, usePressure: true);

/// The slots a device starts with: black pen, blue pen, yellow highlighter.
const defaultPenSlots = <Pen>[
  defaultPen,
  Pen(color: '#1971c2', width: 2.0, usePressure: true),
  Pen(tool: 'highlighter', color: '#ffe066', width: 14.0, usePressure: false),
];
