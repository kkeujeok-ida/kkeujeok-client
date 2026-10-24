import 'dart:math' as math;

import '../model/note.dart';
import '../model/note_title.dart';
import '../model/number.dart';
import '../model/select.dart';
import '../model/text_layout.dart';

/// Values the caller injects so results are deterministic.
class Ctx {
  const Ctx({
    required this.rev,
    required this.now,
    required this.editedBy,
    this.lastSeenRemoteSeq = 0,
    this.ids = const [],
  });

  factory Ctx.fromJson(Map<String, dynamic> j) => Ctx(
    rev: j['rev'] as String,
    now: j['now'] as String,
    editedBy: j['editedBy'] as String,
    lastSeenRemoteSeq: (j['lastSeenRemoteSeq'] as num?)?.toInt() ?? 0,
    ids: [for (final i in (j['ids'] as List? ?? const [])) i as String],
  );

  final String rev, now, editedBy;
  final int lastSeenRemoteSeq;

  /// New element ids for `paste`, one per pasted element.
  final List<String> ids;
}

/// Either a new note plus its inverse, or an error code.
class OpResult {
  const OpResult.ok(Note this.note, this.inverse) : error = null;
  const OpResult.error(String this.error) : note = null, inverse = null;

  final Note? note;
  final Map<String, dynamic>? inverse;
  final String? error;
}

OpResult createNote({
  required String title,
  required List<String> existingTitles,
  required String background,
  required String orientation,
  required String noteId,
  required String pageId,
  required String pageRev,
  required String metaRev,
  required String orderRev,
  required String now,
  required String editedBy,
}) {
  final t = normalizeTitle(title, existingTitles);
  if (t == null) return const OpResult.error('titleTooLong');
  final landscape = orientation == 'landscape';
  return OpResult.ok(
    Note.trusted({
      'formatVersion': supportedFormatVersion,
      'noteId': noteId,
      'meta': {'title': t},
      'metaRev': metaRev,
      'metaSeq': 1,
      'orderRev': orderRev,
      'orderSeq': 1,
      'pages': [
        {
          'id': pageId,
          'width': landscape ? 842 : 595,
          'height': landscape ? 595 : 842,
          'background': background,
          'rev': pageRev,
          'seq': 1,
          'editedAt': now,
          'editedBy': editedBy,
          'elements': <Object?>[],
        },
      ],
    }),
    {'op': 'deleteNote', 'noteId': noteId},
  );
}

OpResult applyOp(Note note, Map<String, dynamic> op, Ctx ctx) =>
    switch (op['op']) {
      'addStroke' => addStroke(note, op, ctx),
      'removeStroke' => removeStroke(note, op, ctx),
      'move' => _transformOp(note, op, ctx),
      'scale' => _transformOp(note, op, ctx),
      'rotate' => _transformOp(note, op, ctx),
      'replaceElements' => replaceElements(note, op, ctx),
      'setStrokeColor' => _strokeOp(note, op, ctx),
      'setStrokeWidth' => _strokeOp(note, op, ctx),
      'delete' => _delete(note, op, ctx),
      'insertElements' => insertElements(note, op, ctx),
      'paste' => _paste(note, op, ctx),
      'createTextBox' => _createTextBox(note, op, ctx),
      'editText' => _editText(note, op, ctx),
      'setTextBoxWidth' => _editText(note, op, ctx),
      _ => const OpResult.error('unknownOp'),
    };

OpResult addStroke(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final page = _page(json, op['pageId']);
  if (page == null) return const OpResult.error('pageNotFound');
  if (!isValidStroke(op['stroke'])) {
    return const OpResult.error('invalidStroke');
  }
  final els = page['elements'] as List;
  final stroke = copyJsonValue(op['stroke']) as Map<String, dynamic>;
  roundStroke(stroke);
  if (els.any((e) => (e as Map)['id'] == stroke['id'])) {
    return const OpResult.error('duplicateId');
  }
  var index = els.length;
  if (op.containsKey('index')) {
    final i = op['index'];
    if (i is! num || i != i.truncateToDouble() || i < 0 || i > els.length) {
      return const OpResult.error('indexOutOfRange');
    }
    index = i.toInt();
  }
  els.insert(index, stroke);
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'removeStroke',
    'pageId': op['pageId'],
    'strokeId': stroke['id'],
  });
}

OpResult removeStroke(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final page = _page(json, op['pageId']);
  if (page == null) return const OpResult.error('pageNotFound');
  final els = page['elements'] as List;
  final index = els.indexWhere((e) => (e as Map)['id'] == op['strokeId']);
  if (index < 0) return const OpResult.error('strokeNotFound');
  final removed = els.removeAt(index);
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'addStroke',
    'pageId': op['pageId'],
    'stroke': removed,
    'index': index,
  });
}

Map<String, dynamic>? _page(Map<String, dynamic> json, Object? id) {
  for (final p in json['pages'] as List) {
    if ((p as Map<String, dynamic>)['id'] == id) return p;
  }
  return null;
}

void _touch(Map<String, dynamic> page, Ctx ctx) {
  final seq = page['seq'] as num;
  final base = seq > ctx.lastSeenRemoteSeq ? seq : ctx.lastSeenRemoteSeq;
  page['rev'] = ctx.rev;
  page['seq'] = base.toInt() + 1;
  page['editedAt'] = ctx.now;
  page['editedBy'] = ctx.editedBy;
}

bool _isStroke(Map e) => e['type'] == 'stroke';
bool _isText(Map e) => e['type'] == 'text';

// A text box has a string `text`; a bare `type: text` box (4.1 fixtures) keeps
// its stored height and is moved like any box element.
bool _isTextBox(Map e) => _isText(e) && e['text'] is String;

// A stored `height` of a text box is ignored and dropped on any write.
Map _noHeight(Map e) => _isTextBox(e) ? (e..remove('height')) : e;

/// Shared front of the selection ops: errors in spec order (own parameter
/// check runs between emptySelection and elementNotFound). Returns the page,
/// the selected elements in page order (as indices), or an error.
(Map<String, dynamic>?, List<int>, String?) _select(
  Map<String, dynamic> json,
  Map<String, dynamic> op,
  String? Function() own,
) {
  final page = _page(json, op['pageId']);
  if (page == null) return (null, const [], 'pageNotFound');
  final ids = {for (final i in (op['ids'] as List? ?? const [])) i};
  if (ids.isEmpty) return (null, const [], 'emptySelection');
  final bad = own();
  if (bad != null) return (null, const [], bad);
  final els = page['elements'] as List;
  final have = {for (final e in els) (e as Map)['id']};
  if (!ids.every(have.contains)) return (null, const [], 'elementNotFound');
  return (
    page,
    [
      for (var i = 0; i < els.length; i++)
        if (ids.contains((els[i] as Map)['id'])) i,
    ],
    null,
  );
}

double _d(Object? v) => (v as num).toDouble();

// ops.move / ops.scale / ops.rotate (spec/ops.md, spec/transform.md).
OpResult _transformOp(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final name = op['op'];
  final (page, idx, err) = _select(json, op, () {
    if (name == 'scale') {
      final sx = op['sx'], sy = op['sy'];
      if (sx is! num || sy is! num || !(sx > 0) || !(sy > 0)) {
        return 'invalidScale';
      }
    }
    return null;
  });
  if (err != null) return OpResult.error(err);
  final els = page!['elements'] as List;
  final before = [for (final i in idx) _noHeight(copyJsonValue(els[i]) as Map)];
  final bounds = selectionBounds([
    for (final i in idx) els[i] as Map<String, dynamic>,
  ]);
  if (bounds == null) return OpResult.ok(note, null);

  // Maps a point; `turn` is the angle added to box rotation.
  late final (double, double) Function(double, double) f;
  var turn = 0.0;
  var sx = 1.0, sy = 1.0;
  switch (name) {
    case 'move':
      final dx = _d(op['dx']), dy = _d(op['dy']);
      f = (x, y) => (x + dx, y + dy);
    case 'scale':
      sx = _d(op['sx']);
      sy = _d(op['sy']);
      final a = op['anchor'] as List;
      final ax = _d(a[0]), ay = _d(a[1]);
      f = (x, y) => (ax + (x - ax) * sx, ay + (y - ay) * sy);
    default:
      turn = _d(op['angle']);
      final r = turn * math.pi / 180, c = math.cos(r), s = math.sin(r);
      final rx = bounds.center.dx, ry = bounds.center.dy;
      f = (x, y) =>
          (rx + (x - rx) * c - (y - ry) * s, ry + (x - rx) * s + (y - ry) * c);
  }

  for (final i in idx) {
    final e = els[i] as Map<String, dynamic>;
    if (_isStroke(e)) {
      for (final p in (e['points'] as List? ?? const [])) {
        final pt = p as List;
        final (x, y) = f(_d(pt[0]), _d(pt[1]));
        pt[0] = round2(x);
        pt[1] = round2(y);
      }
    } else {
      final text = _isTextBox(e);
      final w = _d(e['width']), h = text ? textHeight(e) : _d(e['height']);
      final (cx, cy) = f(_d(e['x']) + w / 2, _d(e['y']) + h / 2);
      if (text) {
        e.remove('height');
        if (name == 'scale') {
          _scaleText(e, sx, cx, cy);
        } else {
          e['x'] = round2(cx - w / 2);
          e['y'] = round2(cy - h / 2);
          e['width'] = round2(w);
          if (name == 'rotate') e['rotation'] = _turned(e, turn);
        }
        continue;
      }
      final nw = w * sx, nh = h * sy;
      e['x'] = round2(cx - nw / 2);
      e['y'] = round2(cy - nh / 2);
      e['width'] = round2(nw);
      e['height'] = round2(nh);
      if (name == 'rotate') e['rotation'] = _turned(e, turn);
    }
  }
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'replaceElements',
    'pageId': op['pageId'],
    'elements': before,
  });
}

// round2 can reach 360 (359.999), which is stored as 0.
double _turned(Map e, double turn) =>
    round2((((_d(e['rotation'] ?? 0) + turn) % 360) + 360) % 360) % 360;

// spec/transform.md "Text boxes": scale. (cx, cy) is the mapped center.
void _scaleText(Map<String, dynamic> e, double sx, double cx, double cy) {
  double clampSize(double v) => round2(v.clamp(sizeMin, sizeMax));
  final nw = math.max(widthMin, round2(_d(e['width']) * sx));
  e['width'] = nw;
  e['size'] = clampSize(_d(e['size'] ?? sizeDefault) * sx);
  final runs = e['runs'];
  if (runs is List) {
    for (final r in runs) {
      if ((r as Map)['size'] != null) r['size'] = clampSize(_d(r['size']) * sx);
    }
    e['runs'] = normalizeRuns(runs, cpLen(e['text'] as String));
  }
  e['x'] = round2(cx - nw / 2);
  e['y'] = round2(cy - textHeight(e) / 2);
}

/// Inverse-only: each given element replaces the page element with its id.
OpResult replaceElements(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final page = _page(json, op['pageId']);
  if (page == null) return const OpResult.error('pageNotFound');
  final els = page['elements'] as List;
  final given = [for (final e in op['elements'] as List) e as Map];
  final at = <int>[];
  for (final g in given) {
    final i = els.indexWhere((e) => (e as Map)['id'] == g['id']);
    if (i < 0) return const OpResult.error('elementNotFound');
    at.add(i);
  }
  final before = <Object?>[];
  for (var k = 0; k < given.length; k++) {
    before.add(els[at[k]]);
    els[at[k]] = copyJsonValue(given[k]);
  }
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'replaceElements',
    'pageId': op['pageId'],
    'elements': before,
  });
}

final _colorRe = RegExp(r'^#[0-9a-f]{6}$');

// ops.setStrokeColor / ops.setStrokeWidth: strokes only.
OpResult _strokeOp(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final color = op['op'] == 'setStrokeColor';
  double width = 0;
  final (page, idx, err) = _select(json, op, () {
    if (color) {
      final c = op['color'];
      return c is String && _colorRe.hasMatch(c) ? null : 'invalidColor';
    }
    final w = op['width'];
    if (w is! num || !w.isFinite || w.abs() > 100) return 'invalidWidth';
    width = (w * 10).round() / 10; // Dart rounds half away from zero
    return width >= 0.5 && width <= 10 ? null : 'invalidWidth';
  });
  if (err != null) return OpResult.error(err);
  final els = page!['elements'] as List;
  final strokes = [
    for (final i in idx)
      if (_isStroke(els[i] as Map)) i,
  ];
  if (strokes.isEmpty) return OpResult.ok(note, null);
  final before = [for (final i in strokes) copyJsonValue(els[i]) as Map];
  for (final i in strokes) {
    (els[i] as Map<String, dynamic>)[color ? 'color' : 'width'] = color
        ? op['color']
        : width;
  }
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'replaceElements',
    'pageId': op['pageId'],
    'elements': before,
  });
}

OpResult _delete(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final (page, idx, err) = _select(json, op, () => null);
  if (err != null) return OpResult.error(err);
  final els = page!['elements'] as List;
  final items = [
    for (final i in idx) {'index': i, 'element': _noHeight(els[i] as Map)},
  ];
  for (final i in idx.reversed) {
    els.removeAt(i);
  }
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'insertElements',
    'pageId': op['pageId'],
    'items': items,
  });
}

/// Inverse-only: puts elements back at their indices, in the given order.
OpResult insertElements(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final page = _page(json, op['pageId']);
  if (page == null) return const OpResult.error('pageNotFound');
  final els = page['elements'] as List;
  final items = [for (final i in op['items'] as List) i as Map];
  final ids = <Object?>{for (final e in els) (e as Map)['id']};
  for (final it in items) {
    if (!ids.add((it['element'] as Map)['id'])) {
      return const OpResult.error('duplicateId');
    }
  }
  var n = els.length;
  for (final it in items) {
    final i = it['index'];
    if (i is! num || i != i.truncateToDouble() || i < 0 || i > n) {
      return const OpResult.error('indexOutOfRange');
    }
    els.insert(i.toInt(), copyJsonValue(it['element']));
    n++;
  }
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'delete',
    'pageId': op['pageId'],
    'ids': [for (final it in items) (it['element'] as Map)['id']],
  });
}

// ops.paste: copies with new ids, centered, nudged off equal boxes.
OpResult _paste(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final page = _page(json, op['pageId']);
  if (page == null) return const OpResult.error('pageNotFound');
  final src = [for (final e in op['elements'] as List? ?? const []) e as Map];
  if (src.isEmpty) return const OpResult.error('emptySelection');
  final els = page['elements'] as List;
  final copies = [
    for (var i = 0; i < src.length; i++)
      (_noHeight(copyJsonValue(src[i]) as Map) as Map<String, dynamic>)
        ..['id'] = ctx.ids[i],
  ];
  var dx = 0.0, dy = 0.0;
  final c = (op['target'] as Map?)?['center'] as List?;
  final union = selectionBounds(copies);
  if (c != null && union != null) {
    dx = _d(c[0]) - union.center.dx;
    dy = _d(c[1]) - union.center.dy;
  }
  List<double>? key(Map<String, dynamic> e) {
    final b = selectionBounds([e]);
    return b == null
        ? null
        : [b.left, b.top, b.right, b.bottom].map(round2).toList();
  }

  bool same(List<double>? a, List<double>? b) =>
      a != null &&
      b != null &&
      a[0] == b[0] &&
      a[1] == b[1] &&
      a[2] == b[2] &&
      a[3] == b[3];

  final taken = [for (final e in els) key(e as Map<String, dynamic>)];
  List<Map<String, dynamic>> shifted(double sx, double sy) {
    final out = <Map<String, dynamic>>[];
    for (final s in copies) {
      final e = copyJsonValue(s) as Map<String, dynamic>;
      if (_isStroke(e)) {
        for (final p in (e['points'] as List? ?? const [])) {
          (p as List)[0] = round2(_d(p[0]) + sx);
          p[1] = round2(_d(p[1]) + sy);
        }
      } else if (selectionBounds([e]) != null) {
        e['x'] = round2(_d(e['x']) + sx);
        e['y'] = round2(_d(e['y']) + sy);
      }
      out.add(e);
    }
    return out;
  }

  var out = shifted(dx, dy);
  for (var k = 1; k <= 20; k++) {
    if (!out.any((e) => taken.any((t) => same(key(e), t)))) break;
    out = shifted(dx + 12 * k, dy + 12 * k);
  }
  els.addAll(out);
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'delete',
    'pageId': op['pageId'],
    'ids': [for (final e in out) e['id']],
  });
}

// ---- text box operations (spec/ops.md "Text box operations") ----

bool _widthOk(Object? w) =>
    w is num && w.isFinite && round2(w.toDouble()) >= widthMin;

OpResult _createTextBox(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final page = _page(json, op['pageId']);
  if (page == null) return const OpResult.error('pageNotFound');
  if (!_widthOk(op['width'])) return const OpResult.error('invalidWidth');
  final runs = op.containsKey('runs') ? op['runs'] : const [];
  if (!validRuns(runs)) return const OpResult.error('invalidRuns');
  final text = normalizeNewlines(op['text'] as String);
  if (isBlankText(text)) return OpResult.ok(note, null);
  final id = ctx.ids[0];
  (page['elements'] as List).add({
    'id': id,
    'type': 'text',
    'x': round2(_d(op['x'])),
    'y': round2(_d(op['y'])),
    'width': round2(_d(op['width'])),
    'rotation': 0,
    'text': text,
    'runs': normalizeRuns(runs as List, cpLen(text)),
    'size': sizeDefault,
    'color': colorDefault,
    'bold': false,
    'italic': false,
  });
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'delete',
    'pageId': op['pageId'],
    'ids': [id],
  });
}

// editText and setTextBoxWidth share the error order and the lookup.
OpResult _editText(Note note, Map<String, dynamic> op, Ctx ctx) {
  final width = op['op'] == 'setTextBoxWidth';
  final json = note.copyJson();
  final page = _page(json, op['pageId']);
  if (page == null) return const OpResult.error('pageNotFound');
  if (width ? !_widthOk(op['width']) : !validRuns(op['runs'])) {
    return OpResult.error(width ? 'invalidWidth' : 'invalidRuns');
  }
  final els = page['elements'] as List;
  final index = els.indexWhere((e) => (e as Map)['id'] == op['id']);
  if (index < 0) return const OpResult.error('elementNotFound');
  final e = els[index] as Map<String, dynamic>;
  if (!_isText(e)) return const OpResult.error('notTextBox');
  final before = copyJsonValue(e) as Map;
  e.remove('height');
  final String? text = width ? null : normalizeNewlines(op['text'] as String);
  _touch(page, ctx);
  if (width) {
    e['width'] = round2(_d(op['width']));
  } else if (isBlankText(text!)) {
    els.removeAt(index);
    return OpResult.ok(Note.trusted(json), {
      'op': 'insertElements',
      'pageId': op['pageId'],
      'items': [
        {'index': index, 'element': before},
      ],
    });
  } else {
    e['text'] = text;
    e['runs'] = normalizeRuns(op['runs'] as List, cpLen(text));
  }
  return OpResult.ok(Note.trusted(json), {
    'op': 'replaceElements',
    'pageId': op['pageId'],
    'elements': [before],
  });
}
