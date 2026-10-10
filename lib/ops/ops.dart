import '../model/note.dart';
import '../model/note_title.dart';

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
  const OpResult.ok(Note this.note, Map<String, dynamic> this.inverse)
    : error = null;
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
