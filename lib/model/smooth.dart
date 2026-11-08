// spec rule `stroke.smooth` (spec/pen-feel.md): densify with Catmull-Rom
// points, then neighbour-average passes, at draw time only; stored points
// never change.

const smoothMax = 10;

/// Device setting the painter reads (0 = off .. [smoothMax]).
int smoothInUse = 0;

/// Points are `[x, y, pressure, t]`. The ends stay; inserted points have the
/// mean `t`. Fewer than 3 points (a straightened line) or level 0 are
/// unchanged (the same list). The input is never mutated.
List smoothPoints(List points, int level) {
  final n = points.length;
  if (level <= 0 || n < 3) return points;
  num at(int i, int j) => points[i.clamp(0, n - 1)][j] as num;
  var cur = <List<num>>[
    for (var i = 0; i < n; i++) ...[
      [for (var j = 0; j < 4; j++) points[i][j] as num],
      if (i < n - 1)
        [
          for (var j = 0; j < 3; j++)
            (-at(i - 1, j) + 9 * at(i, j) + 9 * at(i + 1, j) - at(i + 2, j)) /
                16,
          (at(i, 3) + at(i + 1, 3)) / 2,
        ],
    ],
  ];
  for (var pass = 0; pass < (level + 1) ~/ 2; pass++) {
    final old = cur;
    cur = [
      for (var i = 0; i < old.length; i++)
        if (i == 0 || i == old.length - 1)
          old[i]
        else
          [
            for (var j = 0; j < 4; j++)
              j == 3
                  ? old[i][3]
                  : old[i][j] +
                        0.5 * ((old[i - 1][j] + old[i + 1][j]) / 2 - old[i][j]),
          ],
    ];
  }
  return cur;
}
