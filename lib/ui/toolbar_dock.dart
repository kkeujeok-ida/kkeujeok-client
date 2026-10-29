import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design_tokens/build/tokens.dart';
import '../model/toolbar_pos.dart';

/// A drop within this distance (dp) of an outline docks there (web parity).
const snapRadius = 48.0;

/// Tie order for equally near outlines.
const snapOrder = [
  ToolbarDock.top,
  ToolbarDock.left,
  ToolbarDock.right,
  ToolbarDock.bottom,
];

const _m = KkjTokens.spacing3;

/// The bar [size] (already in the orientation of [dock]) docked at [dock]:
/// centered on its edge of the safe area, [_m] from it.
Rect dockRect(ToolbarDock dock, Size size, Size win, EdgeInsets inset) {
  final cx = (inset.left + win.width - inset.right) / 2;
  final cy = (inset.top + win.height - inset.bottom) / 2;
  final l = inset.left + _m, t = inset.top + _m;
  final r = win.width - inset.right - _m, b = win.height - inset.bottom - _m;
  return switch (dock) {
    ToolbarDock.top || ToolbarDock.float => Rect.fromLTWH(
      cx - size.width / 2,
      t,
      size.width,
      size.height,
    ),
    ToolbarDock.bottom => Rect.fromLTWH(
      cx - size.width / 2,
      b - size.height,
      size.width,
      size.height,
    ),
    ToolbarDock.left => Rect.fromLTWH(
      l,
      cy - size.height / 2,
      size.width,
      size.height,
    ),
    ToolbarDock.right => Rect.fromLTWH(
      r - size.width,
      cy - size.height / 2,
      size.width,
      size.height,
    ),
  };
}

double _distance(Offset p, Rect r) => math.sqrt(
  math.pow(math.max(0, math.max(r.left - p.dx, p.dx - r.right)), 2) +
      math.pow(math.max(0, math.max(r.top - p.dy, p.dy - r.bottom)), 2),
);

/// The first outline (in [snapOrder]) whose area, grown by [snapRadius],
/// holds the [pointer], or null. [bar] is the horizontal size; left and right
/// use [vertical] (default: [bar] turned).
ToolbarDock? dockAtPointer(
  Offset pointer,
  Size bar,
  Size win,
  EdgeInsets inset, {
  Size? vertical,
  EdgeInsets? verticalInset,
}) {
  final v = vertical ?? bar.flipped;
  for (final d in snapOrder) {
    final side = d == ToolbarDock.left || d == ToolbarDock.right;
    final r = dockRect(
      d,
      side ? v : bar,
      win,
      side ? verticalInset ?? inset : inset,
    );
    if (_distance(pointer, r) <= snapRadius) return d;
  }
  return null;
}

/// [center] moved so the bar of [size] lies inside the safe area (display
/// only; the stored ratio is not changed).
Offset clampCenter(Offset center, Size size, Size win, EdgeInsets inset) {
  double fit(double c, double lo, double hi, double len) =>
      hi - lo < len ? (lo + hi) / 2 : c.clamp(lo + len / 2, hi - len / 2);
  return Offset(
    fit(center.dx, inset.left + _m, win.width - inset.right - _m, size.width),
    fit(center.dy, inset.top + _m, win.height - inset.bottom - _m, size.height),
  );
}

/// Where the center of the bar of [size] (in the orientation of [pos]) is
/// shown.
Offset centerOf(ToolbarPos pos, Size size, Size win, EdgeInsets inset) =>
    pos.dock == ToolbarDock.float
    ? clampCenter(
        Offset(pos.x * win.width, pos.y * win.height),
        size,
        win,
        inset,
      )
    : dockRect(pos.dock, size, win, inset).center;

/// [center] as a ratio of the screen, 0..1.
Offset ratioOf(Offset center, Size win) => Offset(
  (center.dx / win.width).clamp(0.0, 1.0),
  (center.dy / win.height).clamp(0.0, 1.0),
);

/// Whether the bar fits the top row between the back button (48) and the
/// more menu (96): [maxWidth] is the row, [minBar] the least the bar needs.
bool topFits(double maxWidth, double minBar) => maxWidth - 144 >= minBar;
