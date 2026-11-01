// Spec `library.*` folder rules and `trash.trashNote` / `trash.trashFolder`.
// Pure; output maps equal the fixtures. Never mutates its input.
import 'dart:convert' show utf8;

import '../drive/note_summary.dart' show driveFileNameRule;
import '../model/note_title.dart';

typedef RuleJson = Map<String, Object?>;

List<RuleJson> _folders(Object? v) => [
  for (final f in v as List) {...(f as Map).cast<String, Object?>()},
];

bool _hasParent(List<RuleJson> folders, Object? id) =>
    id == 'root' || folders.any((f) => f['id'] == id);

/// `library.folderName`.
RuleJson libraryFolderName(RuleJson input) {
  final r = (input['name'] as String).runes.toList();
  var a = 0, b = r.length;
  while (a < b && isTitleTrim(r[a])) {
    a++;
  }
  while (b > a && isTitleTrim(r[b - 1])) {
    b--;
  }
  if (a == b) return {'ok': false, 'reason': 'emptyName'};
  if (b - a > 100) return {'ok': false, 'reason': 'nameTooLong'};
  return {'ok': true, 'name': String.fromCharCodes(r.sublist(a, b))};
}

/// `library.createFolder`.
RuleJson libraryCreateFolder(RuleJson i) {
  final folders = _folders(i['folders']);
  final n = libraryFolderName({'name': i['name']});
  if (n['ok'] != true) return {'error': n['reason']};
  if (!_hasParent(folders, i['parentId'])) return {'error': 'parentNotFound'};
  final id = i['id'], parentId = i['parentId'];
  return {
    'folders': [
      ...folders,
      {'id': id, 'name': n['name'], 'parentId': parentId},
    ],
    'drive': {
      'kind': 'createFolder',
      'id': id,
      'name': n['name'],
      'parentId': parentId,
    },
    'inverse': {'op': 'trashFolder', 'id': id},
  };
}

/// `library.renameFolder`.
RuleJson libraryRenameFolder(RuleJson i) {
  final folders = _folders(i['folders']);
  final id = i['id'];
  final f = folders.where((x) => x['id'] == id).firstOrNull;
  if (f == null) return {'error': 'folderNotFound'};
  final n = libraryFolderName({'name': i['name']});
  if (n['ok'] != true) return {'error': n['reason']};
  if (n['name'] == f['name']) {
    return {'folders': folders, 'drive': null, 'inverse': null};
  }
  return {
    'folders': [
      for (final x in folders) x['id'] == id ? {...x, 'name': n['name']} : x,
    ],
    'drive': {'kind': 'renameFolder', 'id': id, 'name': n['name']},
    'inverse': {'op': 'renameFolder', 'id': id, 'name': f['name']},
  };
}

/// `library.moveFolder`.
RuleJson libraryMoveFolder(RuleJson i) {
  final folders = _folders(i['folders']);
  final id = i['id'], target = i['targetParentId'];
  final f = folders.where((x) => x['id'] == id).firstOrNull;
  if (f == null) return {'error': 'folderNotFound'};
  if (!_hasParent(folders, target)) return {'error': 'parentNotFound'};
  if (target == id) return {'error': 'moveIntoSelf'};
  Object? p = target;
  for (var guard = 0; p != 'root' && guard <= folders.length; guard++) {
    if (p == id) return {'error': 'moveIntoDescendant'};
    final pf = folders.where((x) => x['id'] == p).firstOrNull;
    if (pf == null) break;
    p = pf['parentId'];
  }
  if (target == f['parentId']) {
    return {'folders': folders, 'drive': null, 'inverse': null};
  }
  return {
    'folders': [
      for (final x in folders) x['id'] == id ? {...x, 'parentId': target} : x,
    ],
    'drive': {
      'kind': 'moveFolder',
      'id': id,
      'addParent': target,
      'removeParent': f['parentId'],
    },
    'inverse': {'op': 'moveFolder', 'id': id, 'targetParentId': f['parentId']},
  };
}

/// `library.moveNote`.
RuleJson libraryMoveNote(RuleJson i) {
  final folders = _folders(i['folders']);
  final note = (i['note'] as Map).cast<String, Object?>();
  final target = i['targetParentId'];
  if (!_hasParent(folders, target)) return {'error': 'folderNotFound'};
  if (target == note['parentId']) {
    return {'parentId': note['parentId'], 'drive': null, 'inverse': null};
  }
  return {
    'parentId': target,
    'drive': {
      'kind': 'moveNote',
      'noteId': note['noteId'],
      'addParent': target,
      'removeParent': note['parentId'],
    },
    'inverse': {
      'op': 'moveNote',
      'noteId': note['noteId'],
      'targetParentId': note['parentId'],
    },
  };
}

/// `library.tree`.
RuleJson libraryTree(RuleJson input) {
  final folders = _folders(input['folders']);
  final notes = [
    for (final n in input['notes'] as List) (n as Map).cast<String, Object?>(),
  ];
  final byId = {for (final f in folders) f['id'] as String: f};
  final done = <String>{};
  final repair = <String>{};
  for (final f in folders) {
    if (done.contains(f['id'])) continue;
    final path = <String>[];
    final at = <String, int>{};
    RuleJson? cur = f;
    while (cur != null &&
        !done.contains(cur['id']) &&
        !at.containsKey(cur['id'])) {
      at[cur['id'] as String] = path.length;
      path.add(cur['id'] as String);
      cur = byId[cur['parentId']];
    }
    if (cur != null && at.containsKey(cur['id'])) {
      final members = path.sublist(at[cur['id']]!)..sort();
      repair.add(members.first); // smallest id by code unit
    }
    done.addAll(path);
  }
  bool orphan(RuleJson f) =>
      f['parentId'] != 'root' &&
      f['parentId'] != 'trashbin' &&
      !byId.containsKey(f['parentId']);
  String effParent(RuleJson f) =>
      repair.contains(f['id']) || orphan(f) ? 'root' : f['parentId'] as String;
  final memo = <String, bool>{};
  bool hidden(RuleJson f) => memo[f['id'] as String] ??= switch (effParent(f)) {
    'trashbin' => true,
    'root' => false,
    final p => hidden(byId[p]!),
  };
  final outFolders = <RuleJson>[], hiddenFolders = <String>[];
  for (final f in folders) {
    if (hidden(f)) {
      hiddenFolders.add(f['id'] as String);
    } else {
      outFolders.add({'id': f['id'], 'parentId': effParent(f)});
    }
  }
  final outNotes = <RuleJson>[], hiddenNotes = <String>[];
  for (final n in notes) {
    final p = n['parentId'];
    final id = n['noteId'];
    if (p == 'root' || (p != 'trashbin' && !byId.containsKey(p))) {
      outNotes.add({'noteId': id, 'folderId': null});
    } else if (p == 'trashbin' || hidden(byId[p]!)) {
      hiddenNotes.add(id as String);
    } else {
      outNotes.add({'noteId': id, 'folderId': p});
    }
  }
  return {
    'folders': outFolders,
    'notes': outNotes,
    'hidden': {'folders': hiddenFolders, 'notes': hiddenNotes},
    'repairs': [
      for (final id in (repair.toList()..sort()))
        {'id': id, 'parentId': 'root'},
    ],
  };
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

RuleJson _trash(RuleJson i, {required bool folder}) {
  if (folder && !_uuid.hasMatch(i['id'] as String)) {
    return {'error': 'notUserFolder'};
  }
  if (i['parentId'] == 'trashbin') {
    return {
      'already': true,
      'pending': null,
      'steps': <String>[],
      'request': null,
    };
  }
  final pending = (i['pending'] as Map?)?.cast<String, Object?>();
  final trashedAt = pending != null ? pending['trashedAt'] : i['now'];
  final from = pending != null && pending['from'] != null
      ? pending['from']
      : i['parentId'];
  final out = {'trashedAt': trashedAt, 'from': from};
  if (i['online'] != true) {
    return {
      'already': false,
      'pending': out,
      'steps': <String>[],
      'request': null,
    };
  }
  return {
    'already': false,
    'pending': out,
    'steps': [if (i['unsent'] == true) 'upload', 'move', 'removeLocal'],
    'request': {
      'fileId': i['fileId'],
      'addParents': i['trashbinFileId'],
      'removeParents': i['parentFileId'],
      'appProperties': {'trashedFrom': from, 'trashedAt': trashedAt},
    },
  };
}

/// `trash.trashNote`.
RuleJson trashNoteRule(RuleJson i) => _trash(i, folder: false);

/// `trash.trashFolder`.
RuleJson trashFolderRule(RuleJson i) => _trash(i, folder: true);

/// `library.renameNote`.
RuleJson libraryRenameNote(RuleJson i) {
  final note = (i['note'] as Map).cast<String, Object?>();
  final title = normalizeTitle(((i['op'] as Map)['title']) as String, [
    for (final t in i['existingTitles'] as List) t as String,
  ]);
  if (title == null) return {'error': 'titleTooLong'};
  final name = driveFileNameRule({'title': title})['name'];
  final meta = (note['meta'] as Map).cast<String, Object?>();
  if (title == meta['title']) {
    return {'note': note, 'inverse': null, 'name': name};
  }
  final ctx = (i['ctx'] as Map).cast<String, Object?>();
  final seq = (note['metaSeq'] as num),
      seen = (ctx['lastSeenRemoteSeq'] as num);
  return {
    'note': {
      ...note,
      'meta': {...meta, 'title': title},
      'metaRev': ctx['rev'],
      'metaSeq': (seq > seen ? seq : seen) + 1,
    },
    'inverse': {'op': 'renameNote', 'title': meta['title']},
    'name': name,
  };
}

/// `library.setCover`.
RuleJson librarySetCover(RuleJson i) {
  final note = (i['note'] as Map).cast<String, Object?>();
  final cover = (i['op'] as Map)['coverId'];
  if (cover != null &&
      (cover is! String || cover.isEmpty || utf8.encode(cover).length > 116)) {
    return {'error': 'invalidCoverId'};
  }
  final meta = (note['meta'] as Map).cast<String, Object?>();
  final old = meta['coverId'] is String ? meta['coverId'] : null;
  if (cover == old) return {'note': note, 'inverse': null};
  final ctx = (i['ctx'] as Map).cast<String, Object?>();
  final seq = (note['metaSeq'] as num),
      seen = (ctx['lastSeenRemoteSeq'] as num);
  final newMeta = {...meta};
  if (cover == null) {
    newMeta.remove('coverId');
  } else {
    newMeta['coverId'] = cover;
  }
  return {
    'note': {
      ...note,
      'meta': newMeta,
      'metaRev': ctx['rev'],
      'metaSeq': (seq > seen ? seq : seen) + 1,
    },
    'inverse': {'op': 'setCover', 'coverId': old},
  };
}

final _coverIdRe = RegExp(r'^[a-z][a-z0-9-]{0,31}$');
final _coverFileRe = RegExp(r'^[a-z0-9][a-z0-9-]*\.svg$');

bool _nonEmptyStr(Object? v) => v is String && v.isNotEmpty;

/// The valid entries of a covers index (`id`, `ko`, `en`, `file`), in order;
/// empty when the index itself is not valid.
List<({String id, String ko, String en, String file})> libraryCoverEntries(
  Object? index,
) {
  if (index is! Map || index['version'] != 1 || index['covers'] is! List) {
    return const [];
  }
  final out = <({String id, String ko, String en, String file})>[];
  for (final e in index['covers'] as List) {
    if (e is! Map) continue;
    final id = e['id'], name = e['name'], file = e['file'];
    if (id is! String || !_coverIdRe.hasMatch(id)) continue;
    if (name is! Map ||
        !_nonEmptyStr(name['ko']) ||
        !_nonEmptyStr(name['en'])) {
      continue;
    }
    if (file is! String || !_coverFileRe.hasMatch(file)) continue;
    if (out.any((o) => o.id == id)) continue; // first valid entry wins
    out.add((
      id: id,
      ko: name['ko'] as String,
      en: name['en'] as String,
      file: file,
    ));
  }
  return out;
}

/// `library.coverResolve`.
RuleJson libraryCoverResolve(RuleJson i) {
  final id = i['coverId'];
  if (id is String) {
    for (final e in libraryCoverEntries(i['index'])) {
      if (e.id == id) return {'kind': 'cover', 'id': e.id, 'file': e.file};
    }
  }
  return {'kind': 'none'};
}

// NFC for what titles contain: Hangul jamo and Latin letters + one accent.
// shortcut: no other scripts' combining marks, upgrade with a pinned unorm package.
const _latinPairs =
    '\u0041\u0300\u00c0\u0041\u0301\u00c1\u0041\u0302\u00c2\u0041\u0303\u00c3\u0041\u0308\u00c4\u0041\u030a\u00c5\u0043\u0327\u00c7\u0045\u0300\u00c8\u0045\u0301\u00c9\u0045\u0302\u00ca\u0045\u0308\u00cb\u0049\u0300\u00cc\u0049\u0301\u00cd\u0049\u0302\u00ce\u0049\u0308\u00cf\u004e\u0303\u00d1\u004f\u0300\u00d2\u004f\u0301\u00d3\u004f\u0302\u00d4\u004f\u0303\u00d5\u004f\u0308\u00d6\u0055\u0300\u00d9\u0055\u0301\u00da\u0055\u0302\u00db\u0055\u0308\u00dc\u0059\u0301\u00dd\u0061\u0300\u00e0\u0061\u0301\u00e1\u0061\u0302\u00e2\u0061\u0303\u00e3\u0061\u0308\u00e4\u0061\u030a\u00e5\u0063\u0327\u00e7\u0065\u0300\u00e8\u0065\u0301\u00e9\u0065\u0302\u00ea\u0065\u0308\u00eb\u0069\u0300\u00ec\u0069\u0301\u00ed\u0069\u0302\u00ee\u0069\u0308\u00ef\u006e\u0303\u00f1\u006f\u0300\u00f2\u006f\u0301\u00f3\u006f\u0302\u00f4\u006f\u0303\u00f5\u006f\u0308\u00f6\u0075\u0300\u00f9\u0075\u0301\u00fa\u0075\u0302\u00fb\u0075\u0308\u00fc\u0079\u0301\u00fd\u0079\u0308\u00ff\u0041\u0304\u0100\u0061\u0304\u0101\u0041\u0306\u0102\u0061\u0306\u0103\u0041\u0328\u0104\u0061\u0328\u0105\u0043\u0301\u0106\u0063\u0301\u0107\u0043\u0302\u0108\u0063\u0302\u0109\u0043\u0307\u010a\u0063\u0307\u010b\u0043\u030c\u010c\u0063\u030c\u010d\u0044\u030c\u010e\u0064\u030c\u010f\u0045\u0304\u0112\u0065\u0304\u0113\u0045\u0306\u0114\u0065\u0306\u0115\u0045\u0307\u0116\u0065\u0307\u0117\u0045\u0328\u0118\u0065\u0328\u0119\u0045\u030c\u011a\u0065\u030c\u011b\u0047\u0302\u011c\u0067\u0302\u011d\u0047\u0306\u011e\u0067\u0306\u011f\u0047\u0307\u0120\u0067\u0307\u0121\u0047\u0327\u0122\u0067\u0327\u0123\u0048\u0302\u0124\u0068\u0302\u0125\u0049\u0303\u0128\u0069\u0303\u0129\u0049\u0304\u012a\u0069\u0304\u012b\u0049\u0306\u012c\u0069\u0306\u012d\u0049\u0328\u012e\u0069\u0328\u012f\u0049\u0307\u0130\u004a\u0302\u0134\u006a\u0302\u0135\u004b\u0327\u0136\u006b\u0327\u0137\u004c\u0301\u0139\u006c\u0301\u013a\u004c\u0327\u013b\u006c\u0327\u013c\u004c\u030c\u013d\u006c\u030c\u013e\u004e\u0301\u0143\u006e\u0301\u0144\u004e\u0327\u0145\u006e\u0327\u0146\u004e\u030c\u0147\u006e\u030c\u0148\u004f\u0304\u014c\u006f\u0304\u014d\u004f\u0306\u014e\u006f\u0306\u014f\u004f\u030b\u0150\u006f\u030b\u0151\u0052\u0301\u0154\u0072\u0301\u0155\u0052\u0327\u0156\u0072\u0327\u0157\u0052\u030c\u0158\u0072\u030c\u0159\u0053\u0301\u015a\u0073\u0301\u015b\u0053\u0302\u015c\u0073\u0302\u015d\u0053\u0327\u015e\u0073\u0327\u015f\u0053\u030c\u0160\u0073\u030c\u0161\u0054\u0327\u0162\u0074\u0327\u0163\u0054\u030c\u0164\u0074\u030c\u0165\u0055\u0303\u0168\u0075\u0303\u0169\u0055\u0304\u016a\u0075\u0304\u016b\u0055\u0306\u016c\u0075\u0306\u016d\u0055\u030a\u016e\u0075\u030a\u016f\u0055\u030b\u0170\u0075\u030b\u0171\u0055\u0328\u0172\u0075\u0328\u0173\u0057\u0302\u0174\u0077\u0302\u0175\u0059\u0302\u0176\u0079\u0302\u0177\u0059\u0308\u0178\u005a\u0301\u0179\u007a\u0301\u017a\u005a\u0307\u017b\u007a\u0307\u017c\u005a\u030c\u017d\u007a\u030c\u017e';

final Map<int, int> _compose = () {
  final m = <int, int>{};
  for (var i = 0; i + 2 < _latinPairs.length; i += 3) {
    final u = _latinPairs.codeUnits;
    m[(u[i] << 16) | u[i + 1]] = u[i + 2];
  }
  return m;
}();

List<int> _nfc(List<int> r) {
  final out = <int>[];
  for (final c in r) {
    if (out.isNotEmpty) {
      final p = out.last;
      if (p >= 0x1100 && p <= 0x1112 && c >= 0x1161 && c <= 0x1175) {
        out[out.length - 1] = 0xAC00 + ((p - 0x1100) * 21 + (c - 0x1161)) * 28;
        continue;
      }
      if (p >= 0xAC00 &&
          p <= 0xD7A3 &&
          (p - 0xAC00) % 28 == 0 &&
          c > 0x11A7 &&
          c <= 0x11C2) {
        out[out.length - 1] = p + (c - 0x11A7);
        continue;
      }
      final z = _compose[(p << 16) | c];
      if (z != null) {
        out[out.length - 1] = z;
        continue;
      }
    }
    out.add(c);
  }
  return out;
}

/// `library.normalize`: NFC, then each code point lower-cased on its own.
String libraryKey(String text) => [
  for (final c in _nfc(text.runes.toList()))
    String.fromCharCode(c).toLowerCase(),
].join();

RuleJson libraryNormalize(RuleJson i) => {
  'key': libraryKey(i['text'] as String),
};

bool _in(int c, List<int> r) {
  for (var i = 0; i < r.length; i += 2) {
    if (c >= r[i] && c <= r[i + 1]) return true;
  }
  return false;
}

int _class(int c) {
  if (c >= 0x30 && c <= 0x39) return 1;
  if (_in(c, const [
    0,
    0x2F,
    0x3A,
    0x40,
    0x5B,
    0x60,
    0x7B,
    0xBF,
    0x2000,
    0x206F,
    0x3000,
    0x303F, //
  ])) {
    return 0;
  }
  if (_in(c, const [0x61, 0x7A, 0xC0, 0x24F])) return 2;
  if (_in(c, const [
    0x1100,
    0x11FF,
    0x3130,
    0x318F,
    0xA960,
    0xA97F,
    0xAC00,
    0xD7FF,
  ])) {
    return 3;
  }
  return 4;
}

/// Compares two keys token by token (spec `library.sort`, name).
int libraryKeyCompare(String a, String b) {
  final x = a.runes.toList(), y = b.runes.toList();
  var i = 0, j = 0;
  while (i < x.length && j < y.length) {
    final ca = _class(x[i]), cb = _class(y[j]);
    if (ca != cb) return ca.compareTo(cb);
    if (ca == 1) {
      var ie = i, je = j;
      while (ie < x.length && _class(x[ie]) == 1) {
        ie++;
      }
      while (je < y.length && _class(y[je]) == 1) {
        je++;
      }
      var da = String.fromCharCodes(x.sublist(i, ie))
          .replaceFirst(RegExp('^0+'), '');
      var db = String.fromCharCodes(y.sublist(j, je))
          .replaceFirst(RegExp('^0+'), '');
      if (da.length != db.length) return da.length.compareTo(db.length);
      final c = da.compareTo(db);
      if (c != 0) return c;
      i = ie;
      j = je;
    } else {
      if (x[i] != y[j]) return x[i].compareTo(y[j]);
      i++;
      j++;
    }
  }
  return (x.length - i).compareTo(y.length - j); // a prefix comes first
}

/// Name order of two notes from their keys; `desc` reverses only the key part.
int libraryNameCompare(
  String keyA,
  String titleA,
  String idA,
  String keyB,
  String titleB,
  String idB, {
  bool desc = false,
}) {
  final k = libraryKeyCompare(keyA, keyB);
  if (k != 0) return desc ? -k : k;
  final t = titleA.compareTo(titleB);
  return t != 0 ? t : idA.compareTo(idB);
}

/// `library.sort`.
RuleJson librarySort(RuleJson input) {
  final by = input['by'] as String;
  final items = [
    for (final i in input['items'] as List) (i as Map).cast<String, Object?>(),
  ];
  int? created(String id) => int.tryParse(
    id.replaceAll('-', '').padRight(12, 'x').substring(0, 12),
    radix: 16,
  );
  final time = switch (by) {
    'createdAsc' || 'createdDesc' => (m) => created(m['noteId'] as String),
    _ => (m) => null,
  };
  final keys = {
    for (final m in items) m['noteId']: libraryKey(m['title'] as String),
  };
  int cmp(Map<String, Object?> a, Map<String, Object?> b) {
    final ia = a['noteId'] as String, ib = b['noteId'] as String;
    if (by.startsWith('name')) {
      return libraryNameCompare(
        keys[ia]!,
        a['title'] as String,
        ia,
        keys[ib]!,
        b['title'] as String,
        ib,
        desc: by == 'nameDesc',
      );
    }
    final desc = by.endsWith('Desc');
    int c;
    if (by.startsWith('edited')) {
      final ea = a['editedAt'] as String?, eb = b['editedAt'] as String?;
      c = ea == null || eb == null
          ? (ea == eb ? 0 : (ea == null ? 1 : -1))
          : (desc ? eb.compareTo(ea) : ea.compareTo(eb));
    } else {
      final ta = time(a), tb = time(b);
      c = ta == null || tb == null
          ? (ta == tb ? 0 : (ta == null ? 1 : -1))
          : (desc ? tb.compareTo(ta) : ta.compareTo(tb));
    }
    return c != 0 ? c : ia.compareTo(ib);
  }

  return {
    'noteIds': [
      for (final m in ([...items]..sort(cmp))) m['noteId'],
    ],
  };
}

/// `library.search`: titles whose key contains the key of the trimmed query.
RuleJson librarySearch(RuleJson input) {
  final q = libraryKey(libraryTrim(input['query'] as String));
  return {
    'noteIds': [
      for (final t in input['titles'] as List)
        if (libraryKey((t as Map)['title'] as String).contains(q)) t['noteId'],
    ],
  };
}

/// Trim with the title trim set (spec `library.search`).
String libraryTrim(String s) {
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
