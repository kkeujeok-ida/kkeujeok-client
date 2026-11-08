// User brush presets (Story 25.6): a device setting, not in the note. A note
// stores the brush parameters its strokes used, so deleting a preset never
// changes a note.
import 'dart:convert';

import 'pen.dart';

const maxPresets = 20;
const maxPresetName = 30;

class BrushPreset {
  const BrushPreset({
    required this.id,
    required this.name,
    required this.tool,
    required this.width,
    required this.usePressure,
    this.brush,
  });

  final String id, name, tool;
  final double width;
  final bool usePressure;
  final Map<String, Object?>? brush;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tool': tool,
    'width': width,
    'usePressure': usePressure,
    if (brush != null) 'brush': brush,
  };
}

/// Invalid entries are skipped, never the whole list.
List<BrushPreset> parsePresets(String? raw) {
  try {
    final list = raw == null ? const [] : jsonDecode(raw);
    if (list is! List) return const [];
    final out = <BrushPreset>[];
    for (final e in list) {
      if (e is! Map) continue;
      final id = e['id'], name = e['name'], tool = e['tool'];
      final width = e['width'], up = e['usePressure'], b = e['brush'];
      if (id is! String || name is! String || name.trim().isEmpty) continue;
      if (tool is! String || !penTools.contains(tool)) continue;
      final (lo, hi) = penWidthRange(tool);
      if (width is! num || !(width >= lo && width <= hi) || up is! bool) {
        continue;
      }
      out.add(
        BrushPreset(
          id: id,
          name: name.length > maxPresetName
              ? name.substring(0, maxPresetName)
              : name,
          tool: tool,
          width: width.toDouble(),
          usePressure: up,
          brush: b is Map && b.isNotEmpty ? b.cast<String, Object?>() : null,
        ),
      );
    }
    return out.take(maxPresets).toList();
  } catch (_) {
    return const [];
  }
}

/// The preset made from [pen]; null for an empty [name].
BrushPreset? presetOf(String id, String name, Pen pen) {
  final n = name.trim();
  if (n.isEmpty) return null;
  return BrushPreset(
    id: id,
    name: n.length > maxPresetName ? n.substring(0, maxPresetName) : n,
    tool: pen.tool,
    width: pen.width,
    usePressure: pen.usePressure,
    brush: pen.brush == null
        ? null
        : (jsonDecode(jsonEncode(pen.brush)) as Map).cast<String, Object?>(),
  );
}

/// [pen] with the preset applied: the kind switches first (the color stays
/// when the kind's palette has it), then the preset's settings.
Pen applyBrushPreset(Pen pen, BrushPreset p) {
  final s = pen.withTool(p.tool);
  return Pen(
    tool: s.tool,
    color: s.color,
    width: p.width,
    usePressure: p.usePressure,
    brush: p.brush,
    lineMode: pen.lineMode,
  );
}
