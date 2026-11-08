import 'dart:math' as math;

import 'pen.dart';

// spec rule `pen.straighten` (spec/pen-feel.md): holding the pen still turns
// the stroke into a straight line.
const holdMs = 500;
const holdDistance = 8.0; // dp on Android

/// The still-detection anchor `(t, x, y)`: the first sample, then every
/// sample farther than [holdDistance] from it. Samples are `[t, x, y]`.
(num, double, double)? anchorOf(List<List<num>> samples) {
  if (samples.isEmpty) return null;
  var a = (samples[0][0], samples[0][1].toDouble(), samples[0][2].toDouble());
  for (final s in samples) {
    if (math.sqrt(math.pow(s[1] - a.$2, 2) + math.pow(s[2] - a.$3, 2)) >
        holdDistance) {
      a = (s[0], s[1].toDouble(), s[2].toDouble());
    }
  }
  return a;
}

/// Whether straightening is in effect at [at].
bool straightenActive({
  required bool enabled,
  required String tool,
  required bool palm,
  required bool secondPointer,
  required num at,
  required List<List<num>> samples,
}) {
  if (!enabled || !penTools.contains(tool) || palm || secondPointer) {
    return false;
  }
  final a = anchorOf(samples);
  if (a == null || at - a.$1 < holdMs) return false;
  final f = samples.first, e = samples.last;
  return math.sqrt(math.pow(e[1] - f[1], 2) + math.pow(e[2] - f[2], 2)) >
      holdDistance;
}

/// spec rule `shape.lineSnap`: the end of a hold or line-drawing line snaps to
/// the horizontal or vertical when within 3 degrees of it. [start] and [end]
/// are `[x, y, ...]`; returns the end's `(x, y)`.
(double, double) lineSnapEnd(List<num> start, List<num> end) {
  final dx = (end[0] - start[0]).toDouble(),
      dy = (end[1] - start[1]).toDouble();
  final ax = dx.abs(), ay = dy.abs();
  final t = math.tan(3 * math.pi / 180);
  if (ay <= ax * t) return (end[0].toDouble(), start[1].toDouble());
  if (ax <= ay * t) return (start[0].toDouble(), end[1].toDouble());
  return (end[0].toDouble(), end[1].toDouble());
}
