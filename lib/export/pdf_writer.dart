import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart' show Matrix4;
import 'package:pdf/pdf.dart';

import '../model/note.dart';
import '../model/pressure_curve.dart';
import '../model/pdf_rules.dart' show patternOf;
import '../model/shape.dart' show shapeRings;
import '../model/text_layout.dart';
import '../model/text_metrics.dart';
import '../render/page_background.dart';
import '../render/page_painter.dart' show parseColor;
import '../render/pencil_texture.dart' show pencilDensity;
import '../render/stroke_outline.dart';
import '../render/text_painter.dart' show textStyleKeys;

// Draws an `export.plan` (spec/export.md) as a PDF. The page is drawn in the
// note's own frame (origin top-left, y down) by one flip; text and images
// turn themselves upright again.

/// Thrown when the user cancels; no PDF is produced.
class ExportCancelled implements Exception {}

/// Thrown when an asset of the plan cannot be read any more.
class ExportAssetMissing implements Exception {
  ExportAssetMissing(this.assets);
  final List<String> assets;
}

PdfColor _color(Object? hex) {
  final c = parseColor(hex);
  return PdfColor(c.r, c.g, c.b);
}

/// Builds the PDF of [plan] (the success output of `exportPlan`) for [note].
/// [readAsset] returns the verified bytes of an image asset or null.
/// [renderRaster] draws a page with a tape as RGBA pixels of the given size
/// (`raster` entries of the plan); null makes the export fail.
/// [onProgress] gets (done, total) pages; [cancelled] is checked per page and
/// the event loop is released between pages. [compress] false keeps the
/// streams readable (tests).
Future<Uint8List> buildPdf({
  required Map<String, dynamic> plan,
  required Note note,
  required Future<Uint8List?> Function(String hash) readAsset,
  required Uint8List regularFont,
  required Uint8List semiBoldFont,
  Future<Uint8List?> Function(Map<String, dynamic> page, int w, int h)?
  renderRaster,
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
  bool compress = true,
}) async {
  final doc = PdfDocument(compress: compress);
  final needed = (plan['fonts'] as List).cast<String>();
  final fonts = <bool, PdfTtfFont>{
    if (needed.contains('Pretendard-Regular'))
      false: PdfTtfFont(doc, ByteData.sublistView(regularFont)),
    if (needed.contains('Pretendard-SemiBold'))
      true: PdfTtfFont(doc, ByteData.sublistView(semiBoldFont)),
  };
  final images = <String, PdfImage>{};
  final pages = (plan['pages'] as List).cast<Map<String, dynamic>>();
  onProgress?.call(0, pages.length);
  for (var n = 0; n < pages.length; n++) {
    if (cancelled?.call() ?? false) throw ExportCancelled();
    final pp = pages[n];
    final src = note.pages.firstWhere((p) => p['id'] == pp['id']);
    final w = (pp['width'] as num).toDouble();
    final h = (pp['height'] as num).toDouble();
    final page = PdfPage(doc, pageFormat: PdfPageFormat(w, h));
    final g = page.getGraphics();
    g.saveContext();
    g.setTransform(Matrix4(1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, h, 0, 1));
    final els = (pp['elements'] as List).cast<Map<String, dynamic>>();
    if (els.length == 1 && els.first['kind'] == 'raster') {
      // A tape page is one flat picture: nothing else (spec "Answer tape").
      final pw = els.first['width_px'] as int,
          ph = els.first['height_px'] as int;
      final rgba = await renderRaster?.call(src, pw, ph);
      if (rgba == null || rgba.length != pw * ph * 4) {
        throw StateError('raster of page $n failed');
      }
      if (cancelled?.call() ?? false) throw ExportCancelled();
      final rgb = Uint8List(pw * ph * 3);
      for (var i = 0, o = 0; i < rgba.length; i += 4, o += 3) {
        rgb[o] = rgba[i];
        rgb[o + 1] = rgba[i + 1];
        rgb[o + 2] = rgba[i + 2];
      }
      final img = PdfImage(
        doc,
        image: rgb,
        width: pw,
        height: ph,
        alpha: false,
      );
      g.setTransform(
        Matrix4.translationValues(0, h, 0) * Matrix4.diagonal3Values(1, -1, 1),
      );
      g.drawImage(img, 0, 0, w, h);
      g.restoreContext();
      onProgress?.call(n + 1, pages.length);
      await Future<void>.delayed(Duration.zero);
      continue;
    }
    g.drawRect(0, 0, w, h);
    g.clipPath();
    // A PDF page is a transparent overlay: the original page goes under it.
    if (pp['background'] != 'pdf') {
      g.setFillColor(_color(pp['paper']));
      g.drawRect(0, 0, w, h);
      g.fillPath();
      _background(g, src, w, h);
    }
    final byId = {
      for (final e in (src['elements'] as List).cast<Map<String, dynamic>>())
        e['id'] as String: e,
    };
    for (final entry in (pp['elements'] as List).cast<Map<String, dynamic>>()) {
      final e = byId[entry['id']]!;
      switch (entry['kind']) {
        case 'pen' || 'fountain':
          _pen(g, e);
        case 'pencil':
          _pen(
            g,
            e,
            alpha: pencilDensity(
              meanPressure(
                e['usePressure'] as bool,
                e['points'] as List,
                PressureCurve.normal, // as the outline: no device setting
              ),
            ).density,
          );
        case 'highlighter':
          _highlighter(g, e);
        case 'text':
          _text(g, e, fonts);
        case 'image':
          final hash = entry['asset'] as String;
          var img = images[hash];
          if (img == null) {
            final bytes = await readAsset(hash);
            if (bytes == null) throw ExportAssetMissing([hash]);
            img = images[hash] = PdfImage.file(doc, bytes: bytes);
          }
          _image(g, e, img);
      }
    }
    g.restoreContext();
    onProgress?.call(n + 1, pages.length);
    await Future<void>.delayed(Duration.zero);
  }
  return doc.save();
}

void _background(PdfGraphics g, Map<String, dynamic> p, double w, double h) {
  final bg = pageBackground(patternOf(p['background']), w, h);
  final lines = bg['lines'] as List, dots = bg['dots'] as List;
  if (lines.isNotEmpty) {
    g.setStrokeColor(_color(bg['lineColor']));
    g.setLineWidth((bg['lineWidth'] as num).toDouble());
    for (final l in lines) {
      g.moveTo((l[0] as num).toDouble(), (l[1] as num).toDouble());
      g.lineTo((l[2] as num).toDouble(), (l[3] as num).toDouble());
    }
    g.strokePath();
  }
  if (dots.isNotEmpty) {
    g.setFillColor(_color(bg['dotColor']));
    final r = (bg['dotRadius'] as num).toDouble();
    for (final d in dots) {
      g.drawEllipse((d[0] as num).toDouble(), (d[1] as num).toDouble(), r, r);
    }
    g.fillPath();
  }
}

void _poly(PdfGraphics g, List<List<double>> pts) {
  g.moveTo(pts.first[0], pts.first[1]);
  for (final p in pts.skip(1)) {
    g.lineTo(p[0], p[1]);
  }
  g.closePath();
}

// A shape is its two rings in one fill (non-zero), as on screen.
void _rings(PdfGraphics g, List<List<List<double>>> rings) {
  for (final r in rings) {
    if (r.isNotEmpty) _poly(g, r);
  }
}

void _pen(PdfGraphics g, Map<String, dynamic> s, {double? alpha}) {
  final rings = shapeRings(s['shape'], (s['width'] as num).toDouble());
  if (rings != null) {
    if (alpha != null) {
      g.saveContext();
      g.setGraphicState(PdfGraphicState(opacity: alpha));
    }
    g.setFillColor(_color(s['color']));
    _rings(g, rings);
    g.fillPath();
    if (alpha != null) g.restoreContext();
    return;
  }
  final pts = strokeOutlineFor(
    s['tool'] as String?,
    (s['width'] as num).toDouble(),
    s['usePressure'] as bool,
    s['points'] as List,
    PressureCurve.normal, // a file does not depend on a device setting
  );
  if (pts.isEmpty) return;
  if (alpha != null) {
    g.saveContext();
    g.setGraphicState(PdfGraphicState(opacity: alpha));
  }
  g.setFillColor(_color(s['color']));
  _poly(g, pts);
  g.fillPath();
  if (alpha != null) g.restoreContext();
}

void _highlighter(PdfGraphics g, Map<String, dynamic> s) {
  final rings = shapeRings(s['shape'], (s['width'] as num).toDouble());
  if (rings != null) {
    g.saveContext();
    g.setGraphicState(
      const PdfGraphicState(opacity: 0.4, blendMode: PdfBlendMode.multiply),
    );
    g.setFillColor(_color(s['color']));
    _rings(g, rings);
    g.fillPath();
    g.restoreContext();
    return;
  }
  final polys = highlighterPolygons(
    (s['width'] as num).toDouble(),
    s['points'] as List,
  );
  if (polys.isEmpty) return;
  g.saveContext();
  g.setGraphicState(
    const PdfGraphicState(opacity: 0.4, blendMode: PdfBlendMode.multiply),
  );
  g.setFillColor(_color(s['color']));
  for (final poly in polys) {
    // One direction for all rectangles, so the union fills (non-zero rule).
    var area = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      area += a[0] * b[1] - b[0] * a[1];
    }
    _poly(g, area < 0 ? poly.reversed.toList() : poly);
  }
  g.fillPath();
  g.restoreContext();
}

// Turns the frame clockwise by [deg] about (cx, cy).
void _rotate(PdfGraphics g, double deg, double cx, double cy) {
  if (deg == 0) return;
  g.setTransform(
    Matrix4.translationValues(cx, cy, 0) *
        Matrix4.rotationZ(deg * math.pi / 180) *
        Matrix4.translationValues(-cx, -cy, 0),
  );
}

void _text(PdfGraphics g, Map<String, dynamic> e, Map<bool, PdfTtfFont> fonts) {
  final lay = layoutText(e);
  final cps = (e['text'] as String).runes.toList();
  final (:size, :bold, :base) = textStyles(e);
  final styles = textStyleKeys(e, cps.length);
  final m = TextMetrics.instance;
  final x = (e['x'] as num).toDouble(), y = (e['y'] as num).toDouble();
  final w = math.max(widthMin, (e['width'] as num).toDouble());
  g.saveContext();
  _rotate(
    g,
    ((e['rotation'] as num?) ?? 0).toDouble(),
    x + w / 2,
    y + lay.height / 2,
  );
  for (final line in lay.lines) {
    var end = line.end; // trailing spaces are not text of the line
    while (end > line.start && cps[end - 1] == 0x20) {
      end--;
    }
    var gx = x;
    var i = line.start;
    while (i < end) {
      var j = i;
      var width = 0.0;
      final shown = <int>[];
      while (j < end && styles[j] == styles[i]) {
        final c = cps[j];
        if (!isZeroWidth(c)) {
          final f = m.font(bold[j]);
          width += (f.advance(c) * size[j]) / f.upm;
          shown.add(c);
        }
        j++;
      }
      final text = String.fromCharCodes(shown);
      if (text.trim().isNotEmpty) {
        g.saveContext();
        final t = Matrix4.translationValues(gx, y + line.baseline, 0);
        if (styles[i].startsWith('i')) t.setEntry(0, 1, -italicSkew);
        g.setTransform(t * Matrix4.diagonal3Values(1, -1, 1));
        g.setFillColor(_color(styles[i].split('|').last));
        g.drawString(fonts[bold[i]]!, size[i], text, 0, 0);
        g.restoreContext();
      }
      gx += width;
      i = j;
    }
  }
  g.restoreContext();
}

void _image(PdfGraphics g, Map<String, dynamic> e, PdfImage img) {
  final x = (e['x'] as num).toDouble(), y = (e['y'] as num).toDouble();
  final w = (e['width'] as num).toDouble(), h = (e['height'] as num).toDouble();
  g.saveContext();
  _rotate(g, ((e['rotation'] as num?) ?? 0).toDouble(), x + w / 2, y + h / 2);
  g.setTransform(
    Matrix4.translationValues(x, y + h, 0) * Matrix4.diagonal3Values(1, -1, 1),
  );
  g.drawImage(img, 0, 0, w, h);
  g.restoreContext();
}
