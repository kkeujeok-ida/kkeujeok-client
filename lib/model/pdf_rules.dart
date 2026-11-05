import 'image_rules.dart';
import 'note_title.dart';
import 'number.dart';

// Spec rules of spec/pdf.md: pdf.pageBox, pdf.pageMatrix (+ pagePoint),
// pdf.import, pdf.pageDisplay and the PDF background checks. Pure.

const pdfMaxBytes = 104857600;
const pdfMaxPages = 500;

/// First 5 bytes of a PDF (`%PDF-`) as hex.
const pdfHeadHex = '255044462d';

const _patterns = {'plain', 'lined', 'grid', 'dot'};

bool _num(Object? v) => v is num && v.isFinite;
bool _rect(Object? v) => v is List && v.length == 4 && v.every(_num);

/// A background object with `type: "pdf"`, well formed or not.
bool isPdfRef(Object? bg) => bg is Map && bg['type'] == 'pdf';

/// A well-formed PDF reference; a malformed one is read as `plain`.
bool isPdfBackground(Object? bg) {
  if (!isPdfRef(bg)) return false;
  final m = bg as Map;
  final page = m['page'], box = m['box'], rot = m['rotate'], u = m['userUnit'];
  return isAssetHash(m['asset']) &&
      page is int &&
      page >= 0 &&
      _rect(box) &&
      (box as List)[0] < box[2] &&
      box[1] < box[3] &&
      (rot == 0 || rot == 90 || rot == 180 || rot == 270) &&
      _num(u) &&
      (u as num) > 0;
}

/// The pattern name a page background draws as: the string when known, else
/// `plain` (a PDF reference is drawn as plain until the PDF renderer, 9.4).
String patternOf(Object? bg) =>
    bg is String && _patterns.contains(bg) ? bg : 'plain';

/// True for a background value a client reads: a pattern or a PDF object.
bool isKnownBackground(Object? bg) =>
    (bg is String && _patterns.contains(bg)) || isPdfRef(bg);

List<double>? _norm(Object? r) {
  if (!_rect(r)) return null;
  final v = [for (final n in r as List) (n as num).toDouble()];
  return [
    v[0] < v[2] ? v[0] : v[2],
    v[1] < v[3] ? v[1] : v[3],
    v[0] > v[2] ? v[0] : v[2],
    v[1] > v[3] ? v[1] : v[3],
  ];
}

/// `pdf.pageBox`: `{box, rotate, userUnit, width, height}` or `{error}`.
Map<String, Object?> pdfPageBox(Map<String, Object?> i) {
  final m = _norm(i['mediaBox']);
  if (m == null) return {'error': 'corrupt'};
  final c = i['cropBox'] == null ? m : _norm(i['cropBox']);
  if (c == null) return {'error': 'corrupt'};
  final b = [
    c[0] > m[0] ? c[0] : m[0],
    c[1] > m[1] ? c[1] : m[1],
    c[2] < m[2] ? c[2] : m[2],
    c[3] < m[3] ? c[3] : m[3],
  ];
  if (!(b[2] - b[0] > 0 && b[3] - b[1] > 0)) return {'error': 'corrupt'};
  final rv = i['rotate'];
  final rot = _num(rv) && (rv as num) % 90 == 0 ? ((rv % 360) + 360) % 360 : 0;
  final uv = i['userUnit'];
  var u = _num(uv) && (uv as num) > 0 ? round2(uv.toDouble()) : 1.0;
  if (u <= 0) u = 1;
  final w = b[2] - b[0], h = b[3] - b[1];
  final swap = rot == 90 || rot == 270;
  return {
    'box': [for (final n in b) round2(n)],
    'rotate': rot.toInt(),
    'userUnit': u,
    'width': round2((swap ? h : w) * u),
    'height': round2((swap ? w : h) * u),
  };
}

/// `pdf.pageMatrix`: a page point (pt, top-left origin) to PDF user space.
List<double> pdfPageMatrix(List box, int rotate, num userUnit, List point) {
  final x0 = box[0] as num, y0 = box[1] as num;
  final x1 = box[2] as num, y1 = box[3] as num;
  final a = (point[0] as num) / userUnit, b = (point[1] as num) / userUnit;
  final p = switch (rotate) {
    90 => [x0 + b, y0 + a],
    180 => [x1 - a, y0 + b],
    270 => [x1 - b, y1 - a],
    _ => [x0 + a, y1 - b],
  };
  return [round2(p[0].toDouble()), round2(p[1].toDouble())];
}

/// Inverse of [pdfPageMatrix] (`pagePoint`).
List<double> pdfPagePoint(List box, int rotate, num userUnit, List point) {
  final x0 = box[0] as num, y0 = box[1] as num;
  final x1 = box[2] as num, y1 = box[3] as num;
  final X = point[0] as num, Y = point[1] as num;
  final (a, b) = switch (rotate) {
    90 => (Y - y0, X - x0),
    180 => (x1 - X, Y - y0),
    270 => (y1 - Y, x1 - X),
    _ => (X - x0, y1 - Y),
  };
  return [round2((a * userUnit).toDouble()), round2((b * userUnit).toDouble())];
}

/// The title of an imported file (spec `pdf.import` "Title").
String pdfImportTitle(String fileName) {
  var s = fileName;
  if (s.toLowerCase().endsWith('.pdf')) s = s.substring(0, s.length - 4);
  String trim(String t) {
    final r = t.runes.toList();
    var a = 0, b = r.length;
    while (a < b && isTitleTrim(r[a])) {
      a++;
    }
    while (b > a && isTitleTrim(r[b - 1])) {
      b--;
    }
    return String.fromCharCodes(r.sublist(a, b));
  }

  s = trim(s);
  final r = s.runes.toList();
  if (r.length > maxTitleLength) {
    s = trim(String.fromCharCodes(r.sublist(0, maxTitleLength)));
  }
  return s.isEmpty ? '이름 없는 노트' : s;
}

/// `pdf.import`: `{title, asset, pages}` or `{error}`.
Map<String, Object?> pdfImport(Map<String, Object?> i) {
  final size = i['size'] as num, parse = i['parse'] as Map;
  if (i['head'] != pdfHeadHex) return {'error': 'notPdf'};
  if (size > pdfMaxBytes) return {'error': 'tooLarge'};
  final status = parse['status'];
  if (status == 'encrypted' || (status == 'ok' && parse['encrypted'] == true)) {
    return {'error': 'encrypted'};
  }
  final src = parse['pages'];
  if (status != 'ok' || src is! List || src.isEmpty) {
    return {'error': 'corrupt'};
  }
  if (src.length > pdfMaxPages) return {'error': 'tooManyPages'};
  final hash = i['sha256'] as String;
  final pages = <Map<String, Object?>>[];
  for (var n = 0; n < src.length; n++) {
    final g = pdfPageBox((src[n] as Map).cast<String, Object?>());
    if (g['error'] != null) return g;
    pages.add({
      'width': g['width'],
      'height': g['height'],
      'background': {
        'type': 'pdf',
        'asset': hash,
        'page': n,
        'box': g['box'],
        'rotate': g['rotate'],
        'userUnit': g['userUnit'],
      },
    });
  }
  return {
    'title': pdfImportTitle(i['fileName'] as String),
    'asset': hash,
    'pages': pages,
  };
}

/// `pdf.pageDisplay`.
Map<String, Object?> pdfPageDisplay(Map<String, Object?> i) {
  final page = i['page'] as Map;
  if (!isPdfBackground(page['background'])) {
    return {'layer': 'pattern', 'state': null};
  }
  final s = assetState(
    (page['background'] as Map)['asset'] as String,
    {for (final h in i['local'] as List) h as String},
    {for (final h in i['failed'] as List) h as String},
  );
  return {
    'layer': 'pdf',
    'state': s.name,
    'invertPdf': false,
    'invertElements': false,
  };
}
