import '../model/image_rules.dart' show isAssetHash;
import '../model/note.dart';
import '../model/note_title.dart' show isTitleTrim;
import '../model/number.dart';
import '../model/select.dart' show selectionBounds;
import '../model/text_layout.dart';
import '../model/pdf_rules.dart' show patternOf;
import '../render/page_background.dart';
import '../render/stroke_outline.dart';

// Spec rules of spec/export.md: export.range, export.fileName, export.plan.
// Pure; the PDF writer draws what the plan lists.

String _trim(String s) {
  final r = s.runes.toList();
  var a = 0, b = r.length;
  while (a < b && isTitleTrim(r[a])) {
    a++;
  }
  while (b > a && isTitleTrim(r[b - 1])) {
    b--;
  }
  return String.fromCharCodes(r.sublist(a, b));
}

/// `export.range`: `{pages}` or `{error}`.
Map<String, dynamic> exportRange(Map<String, dynamic> input) {
  final mode = input['mode'], pageCount = input['pageCount'] as int;
  if (mode == 'all') {
    return {
      'pages': [for (var i = 1; i <= pageCount; i++) i],
    };
  }
  if (mode == 'current') {
    return {
      'pages': [input['current']],
    };
  }
  final t = _trim(input['text'] is String ? input['text'] as String : '');
  if (t.isEmpty) return {'error': 'emptyRange'};
  // \s of the spec is the trim set of note.title.
  const ws = r'[\t\n\v\f\r    -     　﻿]';
  final m = RegExp('^([0-9]+)(?:$ws*-$ws*([0-9]+))?\$').firstMatch(t);
  if (m == null) return {'error': 'invalidFormat'};
  final a = BigInt.parse(m.group(1)!);
  final b = m.group(2) == null ? a : BigInt.parse(m.group(2)!);
  if (a > b) return {'error': 'reversedRange'};
  if (a < BigInt.one || b > BigInt.from(pageCount)) {
    return {'error': 'outOfRange'};
  }
  return {
    'pages': [for (var i = a.toInt(); i <= b.toInt(); i++) i],
  };
}

final _reserved = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
  caseSensitive: false,
);

/// `export.fileName`: `{name}`.
Map<String, dynamic> exportFileName(Map<String, dynamic> input) {
  var s = String.fromCharCodes([
    for (final c in _trim(input['title'] as String).runes)
      r'\/:*?"<>|'.contains(String.fromCharCode(c)) || c <= 0x1f || c == 0x7f
          ? 0x5f
          : c,
  ]);
  s = s.replaceFirst(RegExp(r'[. ]+$'), '');
  if (s.isEmpty) s = '이름 없는 노트';
  if (_reserved.hasMatch(s.split('.').first)) s = '_$s';
  return {'name': '$s.pdf'};
}

bool _visible(Map<String, dynamic> e, num w, num h) {
  final b = selectionBounds([e]);
  if (b == null) return false;
  var x0 = round2(b.left), y0 = round2(b.top);
  var x1 = round2(b.right), y1 = round2(b.bottom);
  if (e['type'] == 'stroke') {
    final g = (e['width'] as num) / 2;
    x0 -= g;
    y0 -= g;
    x1 += g;
    y1 += g;
  }
  return x1 > 0 && y1 > 0 && x0 < w && y0 < h;
}

Map<String, dynamic> _textEntry(Map<String, dynamic> e, Set<String> fonts) {
  final lay = layoutText(e);
  final cps = (e['text'] is String ? e['text'] as String : '').runes.toList();
  final lines = [
    for (final l in lay.lines)
      String.fromCharCodes(cps.sublist(l.start, l.end))
          .replaceFirst(RegExp(r' +$'), ''),
  ];
  final runs = normalizeRuns(
    e['runs'] is List ? e['runs'] as List : const [],
    cps.length,
  );
  final bold = textStyles(e).bold;
  final colors = <String>[];
  for (var i = 0; i < cps.length; i++) {
    if (isTitleTrim(cps[i])) continue;
    Map<String, dynamic>? r;
    for (final x in runs) {
      if ((x['start'] as int) <= i && i < (x['end'] as int)) r = x;
    }
    final color = (r?['color'] ?? e['color'] ?? '#000000') as String;
    if (!colors.contains(color)) colors.add(color);
    fonts.add(bold[i] ? 'Pretendard-SemiBold' : 'Pretendard-Regular');
  }
  return {
    'id': e['id'],
    'kind': 'text',
    'x': e['x'],
    'y': e['y'],
    'width': e['width'],
    'height': round2(lay.height),
    'rotation': e['rotation'] ?? 0,
    'lines': lines,
    'colors': colors,
  };
}

/// `export.plan`: the PDF content, or `{error}` (range error, or
/// `assetMissing` with the missing hashes).
Map<String, dynamic> exportPlan(
  Note note,
  Map<String, dynamic> range,
  Iterable<String> localAssets,
) {
  final r = exportRange({...range, 'pageCount': note.pages.length});
  if (r['error'] != null) return r;
  final fonts = <String>{}, assets = <String>{};
  final pages = <Map<String, dynamic>>[];
  for (final n in r['pages'] as List) {
    final p = note.pages[(n as int) - 1];
    final w = p['width'] as num, h = p['height'] as num;
    final bg = pageBackground(patternOf(p['background']), w, h);
    final nLines = (bg['lines'] as List).length;
    final nDots = (bg['dots'] as List).length;
    final elements = <Map<String, dynamic>>[], omitted = <String>[];
    var min = 1 + (nLines + nDots > 0 ? 1 : 0);
    var max = 1 + nLines + nDots, images = 0;
    for (final e in (p['elements'] as List).cast<Map<String, dynamic>>()) {
      if (!_visible(e, w, h)) {
        omitted.add(e['id'] as String);
        continue;
      }
      switch (e['type']) {
        case 'stroke':
          final hl = e['tool'] == 'highlighter';
          final polys = hl
              ? highlighterPolygons(
                  (e['width'] as num).toDouble(),
                  e['points'] as List,
                ).length
              : 1;
          min += 1;
          max += polys;
          elements.add(
            hl
                ? {
                    'id': e['id'],
                    'kind': 'highlighter',
                    'color': e['color'],
                    'polygons': polys,
                    'opacity': 0.4,
                    'blend': 'multiply',
                  }
                : {
                    'id': e['id'],
                    'kind': 'pen',
                    'color': e['color'],
                    'polygons': 1,
                  },
          );
        case 'text':
          elements.add(_textEntry(e, fonts));
        case 'image':
          images++;
          assets.add(e['asset'] as String);
          elements.add({
            'id': e['id'],
            'kind': 'image',
            'x': e['x'],
            'y': e['y'],
            'width': e['width'],
            'height': e['height'],
            'rotation': e['rotation'] ?? 0,
            'asset': e['asset'],
            'ext': e['ext'],
          });
      }
    }
    pages.add({
      'number': n,
      'id': p['id'],
      'width': w,
      'height': h,
      'orientation': w > h ? 'landscape' : 'portrait',
      'paper': bg['paper'],
      'background': const {'lined', 'grid', 'dot'}.contains(p['background'])
          ? p['background']
          : 'plain',
      'lines': nLines,
      'dots': nDots,
      'shapes': {'min': min, 'max': max},
      'images': images,
      'omitted': omitted,
      'elements': elements,
    });
  }
  final local = localAssets.toSet();
  final missing = [
    for (final h in assets)
      if (!isAssetHash(h) || !local.contains(h)) h,
  ]..sort();
  if (missing.isNotEmpty) return {'error': 'assetMissing', 'assets': missing};
  return {
    'fileName': exportFileName({'title': note.title})['name'],
    'fonts': [
      for (final f in const ['Pretendard-Regular', 'Pretendard-SemiBold'])
        if (fonts.contains(f)) f,
    ],
    'assets': assets.toList()..sort(),
    'pages': pages,
  };
}
