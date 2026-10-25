enum ToolbarDock { top, left, right, bottom, float }

double _round4(num v) => (v * 10000).round() / 10000;

/// Where the pen toolbar sits: docked at an edge, or floating at a screen
/// ratio. A device setting, same values as the web client.
class ToolbarPos {
  const ToolbarPos({
    this.dock = ToolbarDock.top,
    this.x = 0.5,
    this.y = 0,
    this.vertical = false,
  });

  /// A floating bar centered at ratio ([x], [y]) of the screen.
  ToolbarPos.floating(double x, double y, {required this.vertical})
    : dock = ToolbarDock.float,
      x = _round4(x),
      y = _round4(y);

  static const defaults = ToolbarPos();

  final ToolbarDock dock;

  /// Bar center as a ratio of the screen; used only when [dock] is float.
  final double x, y;
  final bool vertical;

  /// Docked here: left and right are vertical, top and bottom are not.
  ToolbarPos applyDock(ToolbarDock d) => d == ToolbarDock.float
      ? ToolbarPos.floating(x, y, vertical: vertical)
      : ToolbarPos(
          dock: d,
          vertical: d == ToolbarDock.left || d == ToolbarDock.right,
        );

  /// Anything invalid gives [defaults]. A docked position takes its
  /// orientation from the dock.
  static ToolbarPos parse(Object? raw) {
    if (raw is! Map) return defaults;
    final dock = ToolbarDock.values.where((d) => d.name == raw['dock']);
    final x = raw['x'], y = raw['y'], v = raw['vertical'];
    if (dock.isEmpty || v is! bool) return defaults;
    if (x is! num || y is! num) return defaults;
    if (!(x >= 0 && x <= 1 && y >= 0 && y <= 1)) return defaults;
    final d = dock.first;
    if (d == ToolbarDock.float) {
      return ToolbarPos.floating(x.toDouble(), y.toDouble(), vertical: v);
    }
    return defaults.applyDock(d);
  }

  Map<String, Object> toJson() => {
    'dock': dock.name,
    'x': x,
    'y': y,
    'vertical': vertical,
  };

  @override
  bool operator ==(Object other) =>
      other is ToolbarPos &&
      other.dock == dock &&
      other.x == x &&
      other.y == y &&
      other.vertical == vertical;

  @override
  int get hashCode => Object.hash(dock, x, y, vertical);
}
