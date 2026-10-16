// Spec `drive.fileName` and `drive.listSummary`. Pure; never throw.
import 'dart:convert';

const _bad = <String, Object?>{'error': 'invalidInput'};

bool _isTrim(int c) =>
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x20 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

bool _validTitle(String t) {
  final r = t.runes;
  return r.isNotEmpty &&
      r.length <= 100 &&
      !_isTrim(r.first) &&
      !_isTrim(r.last);
}

/// `drive.fileName`.
Map<String, Object?> driveFileNameRule(Map<String, Object?> input) {
  final t = input['title'];
  if (t is! String || !_validTitle(t)) return const {'error': 'invalidTitle'};
  return {'name': '$t.kkj'};
}

final _md5 = RegExp(r'^[0-9a-f]{32}$');
final _timestamp = RegExp(
  r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d\.\d{3}Z$',
);

/// Longest `kkjCover` value: key `kkjCover` (8) + value must stay <= 124.
const maxCoverBytes = 116;

/// `drive.listSummary` (`write` and `read`).
Map<String, Object?> listSummaryRule(Map<String, Object?> input) {
  try {
    return switch (input['op']) {
      'write' => _write(input),
      'read' => _read(input),
      _ => _bad,
    };
  } catch (_) {
    return _bad; // a note or a file of the wrong shape: never an exception
  }
}

Map<String, Object?> _write(Map<String, Object?> input) {
  final note = input['note'] as Map;
  final meta = note['meta'] as Map;
  final name = driveFileNameRule({'title': meta['title']});
  if (name.containsKey('error')) return name;
  final md5 = input['md5'];
  if (md5 is! String || !_md5.hasMatch(md5)) {
    return const {'error': 'invalidMd5'};
  }
  final id = note['noteId'] as String;
  final pages = (note['pages'] as List).cast<Map>();
  bool size(Object? v) => v is num && v.isFinite && v > 0;
  for (final p in pages) {
    if (!size(p['width']) || !size(p['height'])) return _bad;
  }
  final cover = meta['coverId'];
  final order = input['order'];
  Map? first = pages.isEmpty ? null : pages.first;
  if (order is List && order.isNotEmpty) {
    final m = pages.where((p) => p['id'] == order.first);
    if (m.isNotEmpty) first = m.first;
  }
  String? edited;
  for (final p in pages) {
    final e = p['editedAt'] as String;
    if (edited == null || e.compareTo(edited) > 0) edited = e;
  }
  final coverValue = cover is String && cover.isNotEmpty ? cover : null;
  if (coverValue != null && utf8.encode(coverValue).length > maxCoverBytes) {
    return {
      'name': name['name'],
      'appProperties': {
        'kkeujeokId': id,
        'kkjV': null,
        'kkjMd5': null,
        'kkjCover': null,
        'kkjEdited': null,
      },
      'thumbnail': null,
    };
  }
  Map<String, Object?>? thumb;
  if (first != null) {
    final w = (first['width'] as num).toDouble();
    final h = (first['height'] as num).toDouble();
    final v = ((300 * h) / w + 0.5).floor();
    thumb = {
      'mimeType': 'image/png',
      'width': 300,
      'height': v < 1 ? 1 : (v > 900 ? 900 : v),
    };
  }
  return {
    'name': name['name'],
    'appProperties': {
      'kkeujeokId': id,
      'kkjV': '1',
      'kkjMd5': md5,
      'kkjCover': coverValue,
      'kkjEdited': edited,
    },
    'thumbnail': thumb,
  };
}

Map<String, Object?> _read(Map<String, Object?> input) {
  const download = {'source': 'download'};
  final f = input['file'];
  if (f is! Map) return _bad;
  final props = f['appProperties'];
  final name = f['name'];
  if (props is! Map || name is! String) return download;
  final id = props['kkeujeokId'];
  final md5 = props['kkjMd5'], sum = f['md5Checksum'];
  final edited = props['kkjEdited'];
  final title = name.endsWith('.kkj')
      ? name.substring(0, name.length - 4)
      : name;
  if (props['kkjV'] != '1' ||
      id is! String ||
      id.isEmpty ||
      md5 is! String ||
      !_md5.hasMatch(md5) ||
      sum is! String ||
      sum != md5 ||
      !_validTitle(title) ||
      (props.containsKey('kkjEdited') &&
          edited != null &&
          (edited is! String || !_timestamp.hasMatch(edited)))) {
    return download;
  }
  final parents = f['parents'];
  final root = input['rootFolderId'];
  String? folder = parents is List && parents.isNotEmpty
      ? parents.first as String?
      : null;
  if (folder != null && root != null && folder == root) folder = null;
  final cover = props['kkjCover'];
  final link = f['thumbnailLink'];
  return {
    'source': 'summary',
    'card': {
      'noteId': id,
      'title': title,
      'folderId': folder,
      'coverId': cover is String && cover.isNotEmpty ? cover : null,
      'modifiedAt': edited is String ? edited : f['modifiedTime'],
      'thumbnail': link is String && link.isNotEmpty ? 'drive' : 'none',
    },
  };
}
