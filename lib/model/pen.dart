import 'pen_palette.dart';

/// Most slots a device can hold; at least one always remains.
const maxPenSlots = 12;

/// Width range (pt) per tool, spec `pen.palette`.
(double, double) penWidthRange(String tool) =>
    tool == 'highlighter' ? (4, 30) : (0.5, 10);

/// A pen as the toolbar holds it (spec `pen.md` slots).
class Pen {
  const Pen({
    this.tool = 'pen',
    required this.color,
    required this.width,
    required this.usePressure,
  });

  final String tool; // `pen` | `highlighter`
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

  /// The other tool starts from its own defaults (ranges and palettes differ).
  Pen withTool(String t) => t == tool
      ? this
      : t == 'highlighter'
      ? defaultPenSlots[2]
      : defaultPen;

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
