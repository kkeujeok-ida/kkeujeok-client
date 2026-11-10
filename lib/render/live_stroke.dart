import 'dart:math' as math;

import 'pencil_texture.dart';

/// The points after the Prepare step of spec/stroke-geometry.md: a point
/// closer than 0.01 pt to the last kept one is dropped.
List keptPoints(List points) {
  final out = [];
  for (final p in points) {
    if (out.isNotEmpty) {
      final dx = (p[0] as num) - (out.last[0] as num);
      final dy = (p[1] as num) - (out.last[1] as num);
      if (math.sqrt(dx * dx + dy * dy) < 0.01) continue;
    }
    out.add(p);
  }
  return out;
}

/// spec rule `stroke.liveFreeze`: how many kept points are frozen while the
/// pen is down (all but the last three), and for a pencil [stamps]
/// (`{id, width, usePressure, density?}`) how many `live` stamps lie at or
/// before the length of the frozen polyline.
({int keptCount, int frozenCount, int? frozenStamps}) liveFreeze(
  List points, {
  Map? stamps,
}) {
  final kept = keptPoints(points);
  final frozen = math.max(0, kept.length - 3);
  int? count;
  if (stamps != null) {
    var lk = 0.0;
    for (var i = 1; i < frozen; i++) {
      lk += math.sqrt(
        math.pow((kept[i][0] as num) - (kept[i - 1][0] as num), 2) +
            math.pow((kept[i][1] as num) - (kept[i - 1][1] as num), 2),
      );
    }
    final nominal = <double>[];
    pencilStampsV2(
      id: stamps['id'] as String,
      width: (stamps['width'] as num).toDouble(),
      usePressure: stamps['usePressure'] as bool,
      points: points,
      density: ((stamps['density'] as num?) ?? 1).toDouble(),
      live: true,
      nominal: nominal,
    );
    count = frozen == 0 ? 0 : nominal.where((s) => s <= lk + 1e-9).length;
  }
  return (keptCount: kept.length, frozenCount: frozen, frozenStamps: count);
}
