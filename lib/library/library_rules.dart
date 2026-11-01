// Spec `library.*` folder rules and `trash.trashNote` / `trash.trashFolder`.
// Pure; output maps equal the fixtures. Never mutates its input.
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
