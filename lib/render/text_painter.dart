import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/text_layout.dart';
import '../model/text_metrics.dart';
import 'page_painter.dart' show parseColor;

// Draws a text box line by line from the spec layout (spec/text.md): the
// glyphs of a style group start where the layout widths put them, bold is
// Pretendard SemiBold, italic is a shear of `italicSkew` at the baseline.

const textFontFamily = 'Pretendard';

final _layouts = Expando<TextLayout>('textLayout');

/// Layout of a stored text element, cached per element object (an edit makes
/// a new object).
TextLayout cachedLayout(Map<String, dynamic> e) =>
    _layouts[e] ??= layoutText(e);

/// True when [e] is a text element this painter can draw.
bool drawableText(Object? e) =>
    e is Map<String, dynamic> &&
    e['type'] == 'text' &&
    e['text'] is String &&
    TextMetrics.isLoaded;

final _painters = <String, TextPainter>{};

TextPainter _painter(String text, double size, bool bold, String color) {
  final key = '$size|$bold|$color|$text';
  var p = _painters.remove(key);
  if (p == null) {
    if (_painters.length > 600) _painters.remove(_painters.keys.first);
    p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: textFontFamily,
          fontSize: size,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: parseColor(color),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }
  return _painters[key] = p;
}

/// Paints [e] with its top-left (before rotation) at the canvas origin of
/// the page; rotation is about the box center.
void paintTextBox(Canvas canvas, Map<String, dynamic> e) {
  final lay = cachedLayout(e);
  final text = e['text'] as String;
  final cps = text.runes.toList();
  final (:size, :bold, :base) = textStyles(e);
  final styles = _styleKeys(e, cps.length);
  final m = TextMetrics.instance;
  final x = (e['x'] as num).toDouble(), y = (e['y'] as num).toDouble();
  final w = math.max(widthMin, (e['width'] as num).toDouble());
  final rot = ((e['rotation'] as num?) ?? 0).toDouble();
  canvas.save();
  if (rot != 0) {
    final cx = x + w / 2, cy = y + lay.height / 2;
    canvas
      ..translate(cx, cy)
      ..rotate(rot * math.pi / 180)
      ..translate(-cx, -cy);
  }
  for (final line in lay.lines) {
    var gx = x;
    var i = line.start;
    while (i < line.end) {
      var j = i;
      var width = 0.0;
      while (j < line.end && styles[j] == styles[i]) {
        final c = cps[j];
        if (!isZeroWidth(c)) {
          final f = m.font(bold[j]);
          width += (f.advance(c) * size[j]) / f.upm;
        }
        j++;
      }
      final group = String.fromCharCodes(cps.sublist(i, j));
      if (group.trim().isNotEmpty) {
        final p = _painter(group, size[i], bold[i], styles[i].split('|').last);
        final by = y + line.baseline;
        canvas.save();
        canvas.translate(gx, by);
        if (styles[i].startsWith('i')) {
          canvas.transform(
            (Matrix4.identity()..setEntry(0, 1, -italicSkew)).storage,
          );
        }
        p.paint(
          canvas,
          Offset(
            0,
            -p.computeDistanceToActualBaseline(TextBaseline.alphabetic),
          ),
        );
        canvas.restore();
      }
      gx += width;
      i = j;
    }
  }
  canvas.restore();
}

// A key per code point for what changes how it is drawn: size, bold, italic,
// color. The italic flag rides in the key as its first character.
List<String> _styleKeys(Map<String, dynamic> e, int n) {
  final st = textStyles(e);
  final runs = normalizeRuns(
    e['runs'] is List ? e['runs'] as List : const [],
    n,
  );
  final italic = List<bool>.filled(n, e['italic'] == true);
  final color = List<String>.filled(
    n,
    e['color'] is String ? e['color'] as String : colorDefault,
  );
  for (final r in runs) {
    for (var i = r['start'] as int; i < (r['end'] as int); i++) {
      if (r['italic'] is bool) italic[i] = r['italic'] as bool;
      if (r['color'] is String) color[i] = r['color'] as String;
    }
  }
  return [
    for (var i = 0; i < n; i++)
      '${italic[i] ? 'i' : 'n'}|${st.size[i]}|${st.bold[i]}|${color[i]}',
  ];
}

/// Axis-aligned box of a text element in page coordinates (rotation applied).
Rect textBounds(Map<String, dynamic> e) {
  final x = (e['x'] as num).toDouble(), y = (e['y'] as num).toDouble();
  final w = math.max(widthMin, (e['width'] as num).toDouble());
  final h = cachedLayout(e).height;
  final a = ((e['rotation'] as num?) ?? 0).toDouble() * math.pi / 180;
  final c = Offset(x + w / 2, y + h / 2);
  final cs = math.cos(a), sn = math.sin(a);
  final dx = (w / 2) * cs.abs() + (h / 2) * sn.abs();
  final dy = (w / 2) * sn.abs() + (h / 2) * cs.abs();
  return Rect.fromLTRB(c.dx - dx, c.dy - dy, c.dx + dx, c.dy + dy);
}
