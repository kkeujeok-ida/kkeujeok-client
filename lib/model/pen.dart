/// A pen as the toolbar holds it (spec `stroke-geometry.md` default pen).
class Pen {
  const Pen({
    required this.color,
    required this.width,
    required this.usePressure,
    required this.colorNameKey,
  });

  final String color; // `#rrggbb`, written to strokes as is
  final double width; // pt
  final bool usePressure;
  final String colorNameKey; // maps to a ko/en color name in the UI
}

const defaultPen = Pen(
  color: '#000000',
  width: 2.0,
  usePressure: true,
  colorNameKey: 'black',
);

/// The slot list (one slot now; Story 2.14 and Epic 5 extend it).
const defaultPenSlots = <Pen>[defaultPen];
