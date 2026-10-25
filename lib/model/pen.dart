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

  Map<String, Object> toJson() => {
    'tool': tool,
    'color': color,
    'width': width,
    'usePressure': usePressure,
  };
}

/// `black`, `blue` or `yellow` for the default slot colors, else `custom`.
String colorNameKeyFor(String hex) => switch (hex.toLowerCase()) {
  '#000000' => 'black',
  '#1971c2' => 'blue',
  '#ffe066' => 'yellow',
  _ => 'custom',
};

const defaultPen = Pen(color: '#000000', width: 2.0, usePressure: true);

/// The slots a device starts with: black pen, blue pen, yellow highlighter.
const defaultPenSlots = <Pen>[
  defaultPen,
  Pen(color: '#1971c2', width: 2.0, usePressure: true),
  Pen(tool: 'highlighter', color: '#ffe066', width: 14.0, usePressure: false),
];
