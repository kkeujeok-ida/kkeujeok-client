// spec rule `stroke.smooth` (spec/pen-feel.md): one neighbour-average pass
// over x, y and pressure, at draw time only; stored points never change.

enum SmoothLevel {
  off(0),
  light(0.25),
  normal(0.5),
  strong(0.75);

  const SmoothLevel(this.k);
  final double k;
}

/// Device setting the painter reads (set by the settings provider).
SmoothLevel smoothInUse = SmoothLevel.off;

/// Points are `[x, y, pressure, t]`. The ends and `t` stay, neighbours are the
/// original values. Fewer than 3 points (a straightened line) are unchanged.
/// Returns the same list when nothing changes; the input is never mutated.
List smoothPoints(List points, SmoothLevel level) {
  final k = level.k;
  if (k == 0 || points.length < 3) return points;
  return [
    for (var i = 0; i < points.length; i++)
      if (i == 0 || i == points.length - 1)
        points[i]
      else
        [
          for (var j = 0; j < 4; j++)
            j == 3
                ? points[i][j]
                : (points[i][j] as num) +
                      k *
                          (((points[i - 1][j] as num) +
                                      (points[i + 1][j] as num)) /
                                  2 -
                              (points[i][j] as num)),
        ],
  ];
}
