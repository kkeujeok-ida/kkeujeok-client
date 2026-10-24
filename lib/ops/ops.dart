import 'dart:math' as math;

import '../model/note.dart';
import '../model/note_title.dart';
import '../model/number.dart';
import '../model/select.dart';

/// Values the caller injects so results are deterministic.
class Ctx {
  const Ctx({
    required this.rev,
    required this.now,
    required this.editedBy,
    this.lastSeenRemoteSeq = 0,
  });

  factory Ctx.fromJson(Map<String, dynamic> j) => Ctx(
    rev: j['rev'] as String,
    now: j['now'] as String,
    editedBy: j['editedBy'] as String,
    lastSeenRemoteSeq: (j['lastSeenRemoteSeq'] as num?)?.toInt() ?? 0,
  );

  final String rev, now, editedBy;
  final int lastSeenRemoteSeq;
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
  final before = [for (final i in idx) copyJsonValue(els[i]) as Map];
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
      final w = _d(e['width']), h = _d(e['height']);
      final (cx, cy) = f(_d(e['x']) + w / 2, _d(e['y']) + h / 2);
      final nw = w * sx, nh = h * sy;
      e['x'] = round2(cx - nw / 2);
      e['y'] = round2(cy - nh / 2);
      e['width'] = round2(nw);
      e['height'] = round2(nh);
      if (name == 'rotate') {
        // round2 can reach 360 (359.999), which is stored as 0.
        e['rotation'] =
            round2((((_d(e['rotation'] ?? 0) + turn) % 360) + 360) % 360) %
            360;
      }
    }
  }
  _touch(page, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'replaceElements',
    'pageId': op['pageId'],
    'elements': before,
  });
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
