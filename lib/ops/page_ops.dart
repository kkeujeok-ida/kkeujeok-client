import '../model/note.dart';
import 'ops.dart';

/// Page operations (spec/ops.md "Page operations"); mirrors test/tools/pages.js.
const pageOpNames = {
  'addPage',
  'deletePage',
  'insertPages',
  'duplicatePage',
  'movePages',
  'setPageOrder',
  'setPageBackground',
  'setPageOrientation',
};

const _backgrounds = ['plain', 'lined', 'grid', 'dot'];

OpResult _err(String code) => OpResult.error(code);
OpResult _unchanged(Note n) => OpResult.ok(n, null);

int _max(num a, int b) => (a > b ? a : b).toInt();

void _stamp(Map<String, dynamic> page, Ctx ctx, String rev) {
  page['rev'] = rev;
  page['seq'] = _max((page['seq'] as num?) ?? 0, ctx.lastSeenRemoteSeq) + 1;
  page['editedAt'] = ctx.now;
  page['editedBy'] = ctx.editedBy;
}

void _renewOrder(Map<String, dynamic> note, Ctx ctx) {
  note['orderRev'] = ctx.orderRev;
  note['orderSeq'] = _max(note['orderSeq'] as num, ctx.lastSeenRemoteSeq) + 1;
}

List<Map<String, dynamic>> _pagesOf(Map<String, dynamic> json) =>
    (json['pages'] as List).cast<Map<String, dynamic>>();

bool _hasDup(List l) => l.toSet().length != l.length;

bool _isInt(Object? v) => v is num && v == v.truncateToDouble();

List<String> _ids(Object? v) => [for (final i in v as List) i as String];

OpResult applyPageOp(Note note, Map<String, dynamic> op, Ctx ctx) =>
    switch (op['op']) {
      'addPage' => _addPage(note, op, ctx),
      'deletePage' => _deletePage(note, op, ctx),
      'insertPages' => _insertPages(note, op, ctx),
      'duplicatePage' => _duplicatePage(note, op, ctx),
      'movePages' => _movePages(note, op, ctx),
      'setPageOrder' => _setPageOrder(note, op, ctx),
      'setPageBackground' => _setPageBackground(note, op, ctx),
      'setPageOrientation' => _setPageOrientation(note, op, ctx),
      _ => _err('unknownOp'),
    };

OpResult _addPage(Note note, Map<String, dynamic> op, Ctx ctx) {
  final n = note.pages.length;
  final index = op['index'];
  if (!_isInt(index) || (index as num) < 0 || index > n) {
    return _err('indexOutOfRange');
  }
  final i = index.toInt();
  final ref = note.pages[i > 0 ? i - 1 : 0];
  final json = note.copyJson();
  final page = <String, dynamic>{
    'id': ctx.pageIds[0],
    'width': ref['width'],
    'height': ref['height'],
    'background': _backgrounds.contains(ref['background'])
        ? ref['background']
        : 'plain',
    'rev': '',
    'seq': 0,
    'editedAt': '',
    'editedBy': '',
    'elements': <Object?>[],
  };
  _stamp(page, ctx, ctx.revs[0]);
  _pagesOf(json).insert(i, page);
  _renewOrder(json, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'deletePage',
    'pageIds': [page['id']],
  });
}

OpResult _deletePage(Note note, Map<String, dynamic> op, Ctx ctx) {
  final ids = _ids(op['pageIds']);
  final have = {for (final p in note.pages) p['id']};
  if (ids.any((i) => !have.contains(i))) return _err('pageNotFound');
  if (_hasDup(ids)) return _err('duplicateId');
  if (ids.isEmpty) return _unchanged(note);
  if (ids.length == note.pages.length) return _err('lastPage');
  final gone = ids.toSet();
  final json = note.copyJson();
  final pages = _pagesOf(json);
  final items = <Map<String, dynamic>>[];
  for (var i = 0; i < pages.length; i++) {
    if (gone.contains(pages[i]['id'])) {
      items.add({'page': pages[i], 'index': i});
    }
  }
  pages.removeWhere((p) => gone.contains(p['id']));
  _renewOrder(json, ctx);
  return OpResult.ok(Note.trusted(json), {'op': 'insertPages', 'items': items});
}

OpResult _insertPages(Note note, Map<String, dynamic> op, Ctx ctx) {
  final items = (op['items'] as List).cast<Map>();
  final json = note.copyJson();
  final pages = _pagesOf(json);
  final seen = {for (final p in pages) p['id']};
  for (final it in items) {
    if (!seen.add((it['page'] as Map)['id'])) return _err('duplicateId');
  }
  var len = pages.length;
  for (final it in items) {
    final i = it['index'];
    if (!_isInt(i) || (i as num) < 0 || i > len) {
      return _err('indexOutOfRange');
    }
    len++;
  }
  if (items.isEmpty) return _unchanged(note);
  for (var k = 0; k < items.length; k++) {
    final p = copyJsonValue(items[k]['page']) as Map<String, dynamic>;
    _stamp(p, ctx, ctx.revs[k]);
    pages.insert((items[k]['index'] as num).toInt(), p);
  }
  _renewOrder(json, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'deletePage',
    'pageIds': [for (final it in items) (it['page'] as Map)['id']],
  });
}

OpResult _duplicatePage(Note note, Map<String, dynamic> op, Ctx ctx) {
  final ids = _ids(op['pageIds']);
  final have = {for (final p in note.pages) p['id']};
  if (ids.any((i) => !have.contains(i))) return _err('pageNotFound');
  if (_hasDup(ids)) return _err('duplicateId');
  if (ids.isEmpty) return _unchanged(note);
  final pick = ids.toSet();
  final json = note.copyJson();
  final pages = <Map<String, dynamic>>[];
  final copyIds = <String>[];
  var i = 0, e = 0;
  for (final page in _pagesOf(json)) {
    pages.add(page);
    if (!pick.contains(page['id'])) continue;
    final copy = copyJsonValue(page) as Map<String, dynamic>;
    copy.remove('lineage');
    copy['id'] = ctx.pageIds[i];
    copy['seq'] = 0;
    _stamp(copy, ctx, ctx.revs[i]);
    for (final el in copy['elements'] as List) {
      (el as Map)['id'] = ctx.elementIds[e++];
    }
    copyIds.add(copy['id'] as String);
    pages.add(copy);
    i++;
  }
  json['pages'] = pages;
  _renewOrder(json, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'deletePage',
    'pageIds': copyIds,
  });
}

OpResult _reorder(Note note, List<String> order, Ctx ctx) {
  final old = [for (final p in note.pages) p['id'] as String];
  if (_sameList(order, old)) return _unchanged(note);
  final json = note.copyJson();
  final byId = {for (final p in _pagesOf(json)) p['id'] as String: p};
  json['pages'] = [for (final id in order) byId[id]!];
  _renewOrder(json, ctx);
  return OpResult.ok(Note.trusted(json), {
    'op': 'setPageOrder',
    'pageIds': old,
  });
}

bool _sameList(List a, List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

OpResult _movePages(Note note, Map<String, dynamic> op, Ctx ctx) {
  final ids = _ids(op['pageIds']);
  if (ids.isEmpty) return _unchanged(note);
  final have = {for (final p in note.pages) p['id']};
  if (ids.any((i) => !have.contains(i))) return _err('pageNotFound');
  if (_hasDup(ids)) return _err('duplicateId');
  final pick = ids.toSet();
  final rest = [
    for (final p in note.pages)
      if (!pick.contains(p['id'])) p['id'] as String,
  ];
  final index = op['index'];
  if (!_isInt(index) || (index as num) < 0 || index > rest.length) {
    return _err('indexOutOfRange');
  }
  final at = index.toInt();
  final moved = [
    for (final p in note.pages)
      if (pick.contains(p['id'])) p['id'] as String,
  ];
  return _reorder(note, [
    ...rest.sublist(0, at),
    ...moved,
    ...rest.sublist(at),
  ], ctx);
}

OpResult _setPageOrder(Note note, Map<String, dynamic> op, Ctx ctx) {
  final ids = _ids(op['pageIds']);
  final a = [...ids]..sort();
  final b = [for (final p in note.pages) p['id'] as String]..sort();
  if (!_sameList(a, b)) return _err('pageSetMismatch');
  return _reorder(note, ids, ctx);
}

OpResult _setPageBackground(Note note, Map<String, dynamic> op, Ctx ctx) {
  final items = (op['items'] as List).cast<Map>();
  final have = {for (final p in note.pages) p['id']};
  if (items.any((it) => !have.contains(it['pageId']))) {
    return _err('pageNotFound');
  }
  if (_hasDup([for (final it in items) it['pageId']])) {
    return _err('duplicateId');
  }
  if (items.any((it) => !_backgrounds.contains(it['background']))) {
    return _err('invalidBackground');
  }
  final want = {for (final it in items) it['pageId']: it['background']};
  final json = note.copyJson();
  final back = <Map<String, dynamic>>[];
  var k = 0;
  for (final page in _pagesOf(json)) {
    final w = want[page['id']];
    if (w == null || w == page['background']) continue;
    back.add({'pageId': page['id'], 'background': page['background']});
    page['background'] = w;
    _stamp(page, ctx, ctx.revs[k++]);
  }
  if (back.isEmpty) return _unchanged(note);
  return OpResult.ok(Note.trusted(json), {
    'op': 'setPageBackground',
    'items': back,
  });
}

OpResult _setPageOrientation(Note note, Map<String, dynamic> op, Ctx ctx) {
  final json = note.copyJson();
  final pages = _pagesOf(json);
  final idx = pages.indexWhere((p) => p['id'] == op['pageId']);
  if (idx < 0) return _err('pageNotFound');
  final want = op['orientation'];
  if (want != 'portrait' && want != 'landscape') {
    return _err('invalidOrientation');
  }
  final p = pages[idx];
  final w = p['width'] as num, h = p['height'] as num;
  final cur = w > h ? 'landscape' : 'portrait';
  if (cur == want || w == h) return _unchanged(note);
  p['width'] = h;
  p['height'] = w;
  _stamp(p, ctx, ctx.revs[0]);
  return OpResult.ok(Note.trusted(json), {
    'op': 'setPageOrientation',
    'pageId': op['pageId'],
    'orientation': cur,
  });
}
