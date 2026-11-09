// Runs every fixture in the root repo's test/ folder (read unchanged from the
// sibling path) against this client's implementation of the rule.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart'
    show AxisDirection, EdgeInsets, Offset, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/duplicates.dart';
import 'package:kkeujeok/drive/note_summary.dart';
import 'package:kkeujeok/export/export_rules.dart';
import 'package:kkeujeok/model/shape.dart';
import 'package:kkeujeok/model/straighten.dart';
import 'package:kkeujeok/library/library_rules.dart';
import 'package:kkeujeok/library/trash_rules.dart';
import 'package:kkeujeok/model/image_rules.dart';
import 'package:kkeujeok/model/invert.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/note_title.dart';
import 'package:kkeujeok/model/number.dart';
import 'package:kkeujeok/l10n/app_localizations_en.dart';
import 'package:kkeujeok/l10n/app_localizations_ko.dart';
import 'package:kkeujeok/model/page_bounds.dart';
import 'package:kkeujeok/model/pdf_rules.dart';
import 'package:kkeujeok/model/pen.dart';
import 'package:kkeujeok/model/pen_palette.dart';
import 'package:kkeujeok/model/brush.dart';
import 'package:kkeujeok/model/curve.dart';
import 'package:kkeujeok/model/pressure_curve.dart';
import 'package:kkeujeok/ui/pen_toolbar.dart'
    show PenBubbleAnchor, penColorName, placePenBubble;
import 'package:kkeujeok/model/select.dart';
import 'package:kkeujeok/model/smooth.dart';
import 'package:kkeujeok/model/text_layout.dart';
import 'package:kkeujeok/model/text_metrics.dart';
import 'package:kkeujeok/ops/history.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/ops/resolve_conflict.dart';
import 'package:kkeujeok/ops/restore.dart';
import 'package:kkeujeok/render/page_background.dart';
import 'package:kkeujeok/render/pencil_texture.dart';
import 'package:kkeujeok/render/stroke_outline.dart';
import 'package:kkeujeok/render/zoom_snap.dart';
import 'package:kkeujeok/sync/error_class.dart';
import 'package:kkeujeok/sync/has_unsent.dart';
import 'package:kkeujeok/sync/merge.dart';
import 'package:kkeujeok/sync/sync_log_entry.dart';
import 'package:kkeujeok/ui/toolbar_dock.dart';
import 'package:kkeujeok/model/toolbar_pos.dart';
import 'package:kkeujeok/sync/sync_rules.dart';
import 'package:kkeujeok/sync/version_list.dart';

typedef Case = Map<String, dynamic>;

Note _note(Object? json) {
  final r = Note.parse(json);
  if (r.note == null) throw FormatException('note is ${r.status.name}');
  return r.note!;
}

// write then read, through the real file bytes.
Map<String, dynamic> _roundTrip(Object? input) {
  final r = decodeKkj(encodeKkj(_note((input as Map)['note'])));
  return {'note': r.note!.copyJson()};
}

// A client always writes the supported formatVersion (note-format.md), so a
// version 1 fixture reads back as 2.
Map<String, dynamic> _written(Object? expected) {
  final m = jsonDecode(jsonEncode(expected)) as Map<String, dynamic>;
  (m['note'] as Map<String, dynamic>)['formatVersion'] = supportedFormatVersion;
  return m;
}

Map<String, dynamic> _opOutput(OpResult r) => r.error != null
    ? {'error': r.error}
    : {'note': r.note!.copyJson(), 'inverse': r.inverse};

void _same(Object? actual, Object? expected) =>
    expect(actual, equals(expected)); // == on numbers: 1 equals 1.0

/// [actual] equals [expected]; numbers within [tol].
void _near(Object? actual, Object? expected, double tol) {
  if (expected is num) {
    expect(actual, isA<num>());
    expect((actual as num) - expected, closeTo(0, tol + 1e-9));
  } else if (expected is List) {
    expect(actual, isA<List>());
    expect((actual as List).length, expected.length);
    for (var k = 0; k < expected.length; k++) {
      _near(actual[k], expected[k], tol);
    }
  } else if (expected is Map) {
    expect(actual, isA<Map>());
    for (final k in expected.keys) {
      _near((actual as Map)[k], expected[k], tol);
    }
  } else {
    expect(actual, equals(expected));
  }
}

List<Map<String, dynamic>> _els(Map<String, dynamic> i) => [
  for (final e in i['elements'] as List) e as Map<String, dynamic>,
];

List<(double, double)> _poly(Object? v) => [
  for (final p in v as List)
    ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
];

// Rule id -> how to judge one case. A new spec rule adds one line here.
void _exportPlanCase(Case c) {
  final i = c['input'] as Map<String, dynamic>;
  _same(
    exportPlan(
      // trusted: the plan reads an unknown page background as plain.
      Note.trusted(copyJsonValue(i['note']) as Map<String, dynamic>),
      (i['range'] as Map).cast<String, dynamic>(),
      (i['localAssets'] as List).cast<String>(),
    ),
    c['expected'],
  );
}

void _rgb(List<int> got, Case c) {
  final want = (_json(c['expected'])['rgb'] as List).cast<num>();
  final tol = (c['tolerance'] as num?) ?? 0;
  for (var i = 0; i < 3; i++) {
    expect((got[i] - want[i]).abs() <= tol, isTrue, reason: '$got vs $want');
  }
}

void _outlineCase(Case c, String rule) {
  final i = c['input'] as Map<String, dynamic>;
  final t = c['tolerance'];
  if (t is! num) {
    throw FormatException(
      'stroke.outline.$rule needs a top-level "tolerance" number',
    );
  }
  final tol = t.toDouble();
  final got = strokeOutlineFor(
    rule,
    (i['width'] as num).toDouble(),
    i['usePressure'] as bool,
    i['points'] as List,
  );
  final want = (c['expected'] as Map)['polygon'] as List;
  expect(got.length, want.length, reason: 'polygon point count');
  for (var k = 0; k < got.length; k++) {
    for (var d = 0; d < 2; d++) {
      final e = ((want[k] as List)[d] as num).toDouble();
      expect(
        (got[k][d] - e).abs() <= tol + 1e-9,
        isTrue,
        reason: 'point $k[$d]: got ${got[k][d]}, expected $e',
      );
    }
  }
}

void _penKinds(Case c) {
  final tool = (c['input'] as Map)['tool'] as String;
  final colors = paletteFor(tool);
  final ko = AppLocalizationsKo(), en = AppLocalizationsEn();
  final (lo, hi) = penWidthRange(tool);
  final d = defaultPenOf(tool);
  _same({
    'columns': 6,
    'rows': colors.length ~/ 6,
    'colors': [
      for (final p in colors)
        {
          'color': p.hex,
          'ko': penColorName(ko, p.nameKey),
          'en': penColorName(en, p.nameKey),
        },
    ],
    'width': {'min': lo, 'max': hi, 'default': d.width, 'step': 0.1},
    'usePressureDefault': d.usePressure,
  }, c['expected']);
}

final Map<String, void Function(Case)> runners = {
  'number.round2': (c) {
    final input = c['input'], expected = c['expected'];
    if (input is! num || expected is! num) {
      throw const FormatException(
        '"input" and "expected" must be JSON numbers',
      );
    }
    // JSON numbers without a fraction decode as int.
    final out = round2(input.toDouble());
    expect(
      out == 0 && out.isNegative,
      isFalse,
      reason: 'output is negative zero',
    );
    expect(
      out == expected.toDouble(),
      isTrue,
      reason: 'got $out, expected $expected',
    );
  },
  'invert.color': (c) =>
      _rgb(invertColor(_json(c['input'])['color'] as String), c),
  'invert.ink': (c) {
    final r = invertInk(_json(c['input'])['color'] as String);
    _rgb(r.rgb, c);
    expect(r.corrected, _json(c['expected'])['corrected']);
  },
  'invert.paper': (c) => _rgb(paperRgb, c),
  'invert.highlighter': (c) => _rgb(
    invertHighlighter([
      ...(_json(c['input'])['colors'] as List).cast<String>(),
    ]),
    c,
  ),
  'invert.background': (c) {
    final out = invertBackground(_json(c['input'])['background']);
    final e = _json(c['expected']);
    expect(out.keys.toSet(), e.keys.toSet());
    for (final k in e.keys) {
      _rgb(out[k] as List<int>, {
        'expected': {'rgb': e[k]},
        'tolerance': c['tolerance'],
      });
    }
  },
  'invert.layers': (c) => _same(invertLayers(_json(c['input'])), c['expected']),
  'pdf.pageBox': (c) => _same(pdfPageBox(_json(c['input'])), c['expected']),
  'pdf.import': (c) => _same(pdfImport(_json(c['input'])), c['expected']),
  'pdf.pageDisplay': (c) =>
      _same(pdfPageDisplay(_json(c['input'])), c['expected']),
  'pdf.pageOps': _runOp,
  'pdf.pageMatrix': (c) {
    final i = _json(c['input']);
    List p(Json m) => m['point'] as List;
    _same({
      'point': pdfPageMatrix(i['box'], i['rotate'], i['userUnit'], p(i)),
    }, c['expected']);
    // and back: the expected point gives the input point again
    _same(
      pdfPagePoint(
        i['box'],
        i['rotate'],
        i['userUnit'],
        p(c['expected'] as Json),
      ),
      p(i),
    );
  },
  'note.roundTrip': (c) =>
      _same(_roundTrip(c['input']), _written(c['expected'])),
  'note.unknownFields': (c) =>
      _same(_roundTrip(c['input']), _written(c['expected'])),
  'note.formatVersion': (c) {
    final input = c['input'] as Map<String, dynamic>;
    final List<int> bytes;
    if (input.containsKey('json')) {
      bytes = gzip.encode(utf8.encode(jsonEncode(input['json'])));
    } else if (input.containsKey('text')) {
      bytes = gzip.encode(utf8.encode(input['text'] as String));
    } else {
      bytes = base64Decode(input['gzipBase64'] as String);
    }
    final r = decodeKkj(bytes);
    _same({
      'result': r.status.name,
      'writable': r.writable,
      if (r.note != null) 'note': r.note!.copyJson(),
    }, c['expected']);
  },
  'library.folderName': (c) =>
      _same(libraryFolderName(_json(c['input'])), c['expected']),
  'library.createFolder': (c) =>
      _same(libraryCreateFolder(_json(c['input'])), c['expected']),
  'library.renameFolder': (c) =>
      _same(libraryRenameFolder(_json(c['input'])), c['expected']),
  'library.moveFolder': (c) =>
      _same(libraryMoveFolder(_json(c['input'])), c['expected']),
  'library.moveNote': (c) =>
      _same(libraryMoveNote(_json(c['input'])), c['expected']),
  'library.renameNote': (c) =>
      _same(libraryRenameNote(_json(c['input'])), c['expected']),
  'library.setCover': (c) =>
      _same(librarySetCover(_json(c['input'])), c['expected']),
  'library.coverResolve': (c) =>
      _same(libraryCoverResolve(_json(c['input'])), c['expected']),
  'library.tree': (c) => _same(libraryTree(_json(c['input'])), c['expected']),
  'library.normalize': (c) =>
      _same(libraryNormalize(_json(c['input'])), c['expected']),
  'library.sort': (c) => _same(librarySort(_json(c['input'])), c['expected']),
  'library.search': (c) =>
      _same(librarySearch(_json(c['input'])), c['expected']),
  'trash.trashNote': (c) =>
      _same(trashNoteRule(_json(c['input'])), c['expected']),
  'trash.trashFolder': (c) =>
      _same(trashFolderRule(_json(c['input'])), c['expected']),
  'trash.restoreNote': (c) =>
      _same(trashRestoreRule(_json(c['input'])), c['expected']),
  'trash.restoreFolder': (c) =>
      _same(trashRestoreRule(_json(c['input'])), c['expected']),
  'trash.purgeItem': (c) =>
      _same(trashPurgeRule(_json(c['input'])), c['expected']),
  'trash.emptyTrash': (c) =>
      _same(trashEmptyRule(_json(c['input'])), c['expected']),
  'trash.list': (c) => _same(trashListRule(_json(c['input'])), c['expected']),
  'trash.access': (c) =>
      _same(trashAccessRule(_json(c['input'])), c['expected']),
  'trash.remoteTrashed': (c) =>
      _same(trashRemoteTrashedRule(_json(c['input'])), c['expected']),
  'drive.trashbinFolder': (c) =>
      _same(driveTrashbinFolderRule(_json(c['input'])), c['expected']),
  'note.title': (c) {
    final input = c['input'] as Map<String, dynamic>;
    final t = normalizeTitle(
      input['title'] as String,
      (input['existingTitles'] as List).cast<String>(),
    );
    _same(
      t == null ? {'ok': false, 'reason': 'tooLong'} : {'ok': true, 'title': t},
      c['expected'],
    );
  },
  'ops.createNote': (c) {
    final i = c['input'] as Map<String, dynamic>;
    _same(
      _opOutput(
        createNote(
          title: i['title'] as String,
          existingTitles: (i['existingTitles'] as List).cast<String>(),
          background: i['background'] as String,
          orientation: i['orientation'] as String,
          noteId: i['noteId'] as String,
          pageId: i['pageId'] as String,
          pageRev: i['pageRev'] as String,
          metaRev: i['metaRev'] as String,
          orderRev: i['orderRev'] as String,
          now: i['now'] as String,
          editedBy: i['editedBy'] as String,
        ),
      ),
      c['expected'],
    );
  },
  'ops.addStroke': _runOp,
  'ops.reshapeStroke': _runOp,
  'ops.addPage': _runOp,
  'ops.deletePage': _runOp,
  'ops.insertPages': _runOp,
  'ops.duplicatePage': _runOp,
  'ops.movePages': _runOp,
  'ops.setPageOrder': _runOp,
  'ops.setPageBackground': _runOp,
  'ops.setPageOrientation': _runOp,
  'ops.move': _runOp,
  'ops.scale': _runOp,
  'ops.rotate': _runOp,
  'ops.setStrokeColor': _runOp,
  'ops.setStrokeWidth': _runOp,
  'ops.delete': _runOp,
  'ops.paste': _runOp,
  'ops.removeStroke': _runOp,
  'ops.createTextBox': _runOp,
  'ops.eraseStrokes': _runOp,
  'ops.erasePartial': _runOp,
  'ops.insertImage': _runOp,
  'ops.image': _runOp,
  'ops.editText': _runOp,
  'ops.setTextBoxWidth': _runOp,
  'ops.textBox': _runOp,
  'image.unknownFields': _unknownFields,
  'text.unknownFields': _unknownFields,
  'text.layout': (c) {
    final l = layoutText(
      (c['input'] as Map<String, dynamic>)['element'] as Map<String, dynamic>,
    );
    final e = c['expected'] as Map<String, dynamic>;
    final tol = (c['tolerance'] as num).toDouble();
    void near(Object? a, Object? b, String what) => expect(
      (a as num) - (b as num),
      inInclusiveRange(-tol, tol),
      reason: what,
    );
    near(l.height, e['height'], 'height');
    final lines = e['lines'] as List;
    expect(l.lines.length, lines.length, reason: 'line count');
    for (var k = 0; k < lines.length; k++) {
      final x = lines[k] as Map<String, dynamic>, y = l.lines[k];
      expect([y.start, y.end], [x['start'], x['end']], reason: 'line $k range');
      near(y.width, x['width'], 'line $k width');
      near(y.top, x['top'], 'line $k top');
      near(y.baseline, x['baseline'], 'line $k baseline');
      near(y.height, x['height'], 'line $k height');
    }
  },
  'image.accept': (c) {
    final i = c['input'] as Map<String, dynamic>;
    _same(imageAccept(i['head'] as String, i['size'] as int), c['expected']);
  },
  'image.initialSize': (c) {
    final i = c['input'] as Map<String, dynamic>;
    _same(
      imageInitialSize(
        i['pxWidth'] as num,
        i['pxHeight'] as num,
        i['pageWidth'] as num,
        i['pageHeight'] as num,
      ),
      c['expected'],
    );
  },
  'image.referencedAssets': (c) => _same(
    referencedAssets(_note((c['input'] as Map)['note'])),
    c['expected'],
  ),
  'image.uploadPlan': (c) {
    final i = c['input'] as Map<String, dynamic>;
    List<String> l(String k) => [for (final h in i[k] as List) h as String];
    _same(
      imageUploadPlan(l('referenced'), l('confirmed'), l('onDevice')),
      c['expected'],
    );
  },
  'image.assetState': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final st = assetState(
      i['asset'] as String,
      {for (final h in i['local'] as List) h as String},
      {for (final h in i['failed'] as List) h as String},
    );
    _same({'state': st.name}, c['expected']);
  },
  'select.image': (c) => _selectRunners[(c['input'] as Map)['fn']]!(c),
  'select.textBox': (c) => _selectRunners[(c['input'] as Map)['fn']]!(c),
  'stroke.outline.pen': (c) => _outlineCase(c, 'pen'),
  'stroke.outline.fountain': (c) => _outlineCase(c, 'fountain'),
  'stroke.outline.pencil': (c) => _outlineCase(c, 'pencil'),
  'stroke.outline.tape': (c) => _outlineCase(c, 'tape'),
  'stroke.texture.pencil': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final tol = (c['tolerance'] as num).toDouble();
    final want = c['expected'] as Map<String, dynamic>;
    switch (i['fn']) {
      case 'density':
        final d = pencilDensity((i['q'] as num).toDouble());
        expect((d.density - (want['density'] as num)).abs() <= tol, isTrue);
        expect(d.threshold, want['threshold']);
      default:
        fail('unknown fn ${i['fn']}');
    }
  },
  'stroke.texture.pencilStamps': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final tol = (c['tolerance'] as num).toDouble();
    final got = pencilStamps(
      id: i['id'] as String,
      width: (i['width'] as num).toDouble(),
      usePressure: i['usePressure'] as bool,
      points: i['points'] as List,
      opacity: ((i['opacity'] as num?) ?? 1).toDouble(),
    );
    final want = (c['expected'] as Map)['stamps'] as List;
    expect(got.length, want.length);
    for (var k = 0; k < want.length; k++) {
      final w = want[k] as Map;
      final g = got[k];
      for (final e in {
        'x': g.x,
        'y': g.y,
        'size': g.size,
        'angle': g.angle,
      }.entries) {
        expect(
          (e.value - (w[e.key] as num)).abs() <= tol,
          isTrue,
          reason: '$k ${e.key}',
        );
      }
      expect(
        (g.alpha - (w['alpha'] as num)).abs() <= 0.01,
        isTrue,
        reason: '$k alpha',
      );
    }
  },
  'stroke.outline.highlighter': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final tol = (c['tolerance'] as num).toDouble();
    final got = highlighterPolygons(
      (i['width'] as num).toDouble(),
      i['points'] as List,
    );
    final want = (c['expected'] as Map)['polygons'] as List;
    expect(got.length, want.length, reason: 'polygon count');
    for (var k = 0; k < got.length; k++) {
      final w = want[k] as List;
      expect(got[k].length, w.length, reason: 'polygon $k point count');
      for (var j = 0; j < w.length; j++) {
        for (var d = 0; d < 2; d++) {
          final e = ((w[j] as List)[d] as num).toDouble();
          expect(
            (got[k][j][d] - e).abs() <= tol + 1e-9,
            isTrue,
            reason: 'polygon $k point $j[$d]: got ${got[k][j][d]}, want $e',
          );
        }
      }
    }
  },
  'stroke.smooth': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final got = smoothPoints(i['points'] as List, i['level'] as int);
    final want = c['expected'] as List;
    expect(got.length, want.length);
    for (var k = 0; k < want.length; k++) {
      for (var j = 0; j < 4; j++) {
        expect(
          ((got[k][j] as num) - (want[k][j] as num)).abs() <=
              (c['tolerance'] as num) + 1e-12,
          isTrue,
          reason: 'point $k[$j]: got ${got[k][j]}, want ${want[k][j]}',
        );
      }
    }
  },
  'pen.straighten': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final on = straightenActive(
      enabled: i['enabled'] as bool,
      tool: i['tool'] as String,
      palm: i['palm'] as bool,
      secondPointer: i['secondPointer'] as bool,
      at: i['at'] as num,
      samples: [
        for (final s in i['samples'] as List) List<num>.from(s as List),
      ],
    );
    expect({'active': on}, c['expected']);
  },
  'shape.lineSnap': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final (x, y) = lineSnapEnd(
      List<num>.from(i['start'] as List),
      List<num>.from(i['end'] as List),
    );
    final want = (c['expected'] as Map)['end'] as List;
    final tol = (c['tolerance'] as num).toDouble();
    expect((x - (want[0] as num)).abs() <= tol, isTrue, reason: 'x: $x');
    expect((y - (want[1] as num)).abs() <= tol, isTrue, reason: 'y: $y');
  },
  'shape.points': (c) {
    final pts = shapePoints((c['input'] as Map)['shape'])!;
    final want = ((c['expected'] as Map)['points'] as List).cast<List>();
    final tol = (c['tolerance'] as num).toDouble();
    expect(pts.length, want.length);
    for (var i = 0; i < want.length; i++) {
      expect((pts[i][0] - want[i][0]).abs() <= tol, isTrue, reason: 'x[$i]');
      expect((pts[i][1] - want[i][1]).abs() <= tol, isTrue, reason: 'y[$i]');
      expect(pts[i][2], want[i][2]);
      expect(pts[i][3], want[i][3]);
    }
  },
  'shape.recognize': (c) {
    final pts = [
      for (final p in (c['input'] as Map)['points'] as List) List<num>.from(p),
    ];
    final s = recognizeShape(pts);
    final want = (c['expected'] as Map)['shape'] as Map?;
    if (want == null) return expect(s, isNull);
    final tol = (c['tolerance'] as num).toDouble();
    expect(s, isNotNull);
    expect(s!['kind'], want['kind']);
    List flat(Map m) => m['vertices'] != null
        ? [for (final v in m['vertices'] as List) ...v as List]
        : [
            for (final k in ['x', 'y', 'width', 'height']) m[k],
          ];
    final a = flat(s), b = flat(want);
    expect(a.length, b.length);
    for (var k = 0; k < a.length; k++) {
      expect(
        ((a[k] as num) - (b[k] as num)).abs() <= tol,
        isTrue,
        reason: '$k',
      );
    }
  },
  'shape.resize': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final s = shapeResize(
      i['shape'] as Map,
      i['handle'] as String,
      List<num>.from(i['to'] as List),
      i['keepRatio'] as bool,
    )!;
    final want = (c['expected'] as Map)['shape'] as Map;
    final tol = (c['tolerance'] as num).toDouble();
    expect(s['kind'], want['kind']);
    final a = s['vertices'] != null
        ? [for (final v in s['vertices'] as List) ...v as List]
        : [
            for (final k in ['x', 'y', 'width', 'height', 'rotation']) s[k],
          ];
    final b = want['vertices'] != null
        ? [for (final v in want['vertices'] as List) ...v as List]
        : [
            for (final k in ['x', 'y', 'width', 'height', 'rotation']) want[k],
          ];
    for (var k = 0; k < a.length; k++) {
      expect(
        ((a[k] as num) - (b[k] as num)).abs() <= tol,
        isTrue,
        reason: '$k',
      );
    }
  },
  'shape.rotate': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final r = shapeRotate(i['shape'] as Map, List<num>.from(i['to'] as List));
    final want = ((c['expected'] as Map)['rotation'] as num).toDouble();
    expect((r - want).abs() <= (c['tolerance'] as num).toDouble(), isTrue);
  },
  'shape.fromDrag': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final s = shapeFromDrag(
      i['kind'] as String,
      List<num>.from(i['from'] as List),
      List<num>.from(i['to'] as List),
      i['lockRatio'] as bool,
    );
    final want = (c['expected'] as Map)['shape'] as Map?;
    if (want == null) return expect(s, isNull);
    final tol = (c['tolerance'] as num).toDouble();
    expect(s!['kind'], want['kind']);
    final a = s['vertices'] != null
        ? [for (final v in s['vertices'] as List) ...v as List]
        : [
            for (final k in ['x', 'y', 'width', 'height']) s[k],
          ];
    final b = want['vertices'] != null
        ? [for (final v in want['vertices'] as List) ...v as List]
        : [
            for (final k in ['x', 'y', 'width', 'height']) want[k],
          ];
    expect(a.length, b.length);
    for (var k = 0; k < a.length; k++) {
      expect(((a[k] as num) - (b[k] as num)).abs() <= tol, isTrue);
    }
  },
  'pen.pressureCurve': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final tol = (c['tolerance'] as num).toDouble();
    final q = drawPressure(
      PressureCurve.fromJson(i['curve']),
      i['usePressure'] as bool,
      i['pressure'] as num?,
    );
    final want = c['expected'] as Map;
    expect((q - (want['q'] as num)).abs() <= tol, isTrue, reason: 'q: $q');
    expect(
      (radiusFactor(q) - (want['factor'] as num)).abs() <= tol,
      isTrue,
      reason: 'factor of $q',
    );
  },
  'pen.palette': _penKinds,
  'pen.kinds': _penKinds,
  'pen.switchKind': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final s = i['slot'] as Map<String, dynamic>;
    final out = Pen(
      tool: s['tool'] as String,
      color: s['color'] as String,
      width: (s['width'] as num).toDouble(),
      usePressure: s['usePressure'] as bool,
    ).withTool(i['to'] as String);
    _same({'slot': out.toJson()}, c['expected']);
  },
  'note.penKinds': (c) => runners['note.formatVersion']!(c),
  'note.brush': (c) => runners['note.formatVersion']!(c),
  'brush.curve': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final fn = i['fn'];
    _near(
      fn == 'eval'
          ? {'y': curveEval(i['curve'], (i['x'] as num).toDouble())}
          : fn == 'convert'
          ? {'points': curveToPoints(i['curve'])}
          : {'opacityPressureCurve': opacityPressureCurve(i['brush'])},
      c['expected'],
      (c['tolerance'] as num?)?.toDouble() ?? 0,
    );
  },
  'brush.resolve': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final p = brushResolve(i['tool'], i['brush']);
    _same({
      'params': {
        'pressureCurve': p.pressureCurve,
        'tiltCurve': p.tiltCurve,
        'tiltTarget': p.tiltTarget,
        'opacity': p.opacity,
        'texture': p.texture,
      },
    }, c['expected']);
  },
  'pen.defaultSlots': (c) => _same({
    'slots': [for (final p in defaultPenSlots) p.toJson()],
  }, c['expected']),
  'page.outOfBounds': (c) {
    final i = c['input'] as Map<String, dynamic>;
    _same({
      'ids': pageOutOfBounds(i['width'] as num, i['height'] as num, [
        for (final e in i['elements'] as List)
          (e as Map).cast<String, dynamic>(),
      ]),
    }, c['expected']);
  },
  'export.range': (c) => _same(exportRange(_json(c['input'])), c['expected']),
  'pdf.exportStructure': _exportPlanCase,
  'export.fileName': (c) =>
      _same(exportFileName(_json(c['input'])), c['expected']),
  'export.plan': _exportPlanCase,
  'page.background': (c) {
    final i = c['input'] as Map<String, dynamic>;
    _same(
      pageBackground(
        i['background'] as String,
        i['width'] as num,
        i['height'] as num,
      ),
      c['expected'],
    );
  },
  'sync.hasUnsent': (c) => _same(
    hasUnsentRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'drive.duplicates': (c) => _same(
    driveDuplicatesRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'sync.errorClass': (c) => _same(
    errorClassRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'synclog.entry': (c) =>
      _same(checkLogEntry((c['input'] as Map)['entry']), c['expected']),
  'sync.uploadKind': (c) => _same(
    uploadKindRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'sync.staleHead': (c) => _same(
    staleHeadRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'sync.verifyPlan': (c) => _same(
    verifyPlanRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'sync.backoff': (c) => _same(
    backoffRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'sync.stateMachine': (c) => _same(
    stateMachineRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'drive.assetsFolder': (c) {
    final items = (c['input'] as Map)['items'] as List;
    _same(driveAssetsFolderRule({'items': items}), c['expected']);
  },
  'drive.fileName': (c) => _same(
    driveFileNameRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'toolbar.snap': (c) {
    final i = c['input'] as Map<String, dynamic>;
    Size sz(String k) => Size(
      ((i[k] as Map)['w'] as num).toDouble(),
      ((i[k] as Map)['h'] as num).toDouble(),
    );
    final p = i['pointer'] as Map;
    final d = dockAtPointer(
      Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
      sz('bar'),
      sz('win'),
      EdgeInsets.zero,
    );
    expect(d?.name, c['expected']);
  },
  'bubble.tail': (c) {
    final i = c['input'] as Map<String, dynamic>;
    Rect r(Map m) => Rect.fromLTWH(
      (m['left'] as num).toDouble(),
      (m['top'] as num).toDouble(),
      (m['w'] as num).toDouble(),
      (m['h'] as num).toDouble(),
    );
    Size sz(Map m) =>
        Size((m['w'] as num).toDouble(), (m['h'] as num).toDouble());
    final p = placePenBubble(
      PenBubbleAnchor(
        r(i['tool'] as Map),
        r(i['bar'] as Map),
        vertical: i['vertical'] as bool,
      ),
      sz(i['bubble'] as Map),
      sz(i['win'] as Map),
    );
    final got = {
      'side': switch (p.side) {
        AxisDirection.down => 'down',
        AxisDirection.up => 'up',
        AxisDirection.right => 'right',
        AxisDirection.left => 'left',
      },
      'left': p.topLeft.dx,
      'top': p.topLeft.dy,
      'tail': p.tail,
    };
    // `left`/`top` are only in cases where the 8 dp and web 12 px margins agree.
    (c['expected'] as Map).forEach(
      (k, v) => expect(got[k], v is num ? closeTo(v, 1e-9) : v, reason: '$k'),
    );
  },
  'zoom.snap': (c) {
    final i = c['input'] as Map<String, dynamic>;
    final out = zoomSnap(
      (i['scale'] as num).toDouble(),
      (i['fitScale'] as num).toDouble(),
    );
    expect(out, closeTo((c['expected'] as num).toDouble(), 1e-12));
  },
  'drive.remoteTitle': (c) => _same(
    driveRemoteTitleRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'drive.listSummary': (c) => _same(
    listSummaryRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  for (final id in const [
    'merge.page3way',
    'merge.staleSeq',
    'merge.seqAfterMerge',
    'merge.conflictSidecar',
    'merge.order',
    'merge.meta',
    'merge.unknownFields',
    'merge.formatVersion',
    'merge.undoDrop',
    'merge.pageOps',
  ])
    id: _runMerge,
  'merge.requeue': (c) {
    final i = _json(c['input']);
    _same(
      mergeRequeueNotes(
        base: i['base'] as Json?,
        localAtStart: i['localAtStart'] as Json,
        localAtCommit: i['localAtCommit'] as Json,
        remote: i['remote'] as Json,
        ctx: i['ctx'] as Json,
      ),
      c['expected'],
    );
  },
  'merge.resolve': (c) => _same(_resolve(_json(c['input'])), c['expected']),
  'merge.keepBothConverge': (c) {
    final i = _json(c['input']);
    final a = _resolve({...i['a'] as Json, 'choice': 'both'});
    final b = _resolve({...i['b'] as Json, 'choice': 'both'});
    Map<String, Object?> m(Object? x, Object? y) => mergeNotes(
      i['base'] as Json?,
      (x as Map<String, Object?>)['note'] as Json,
      (y as Map<String, Object?>)['note'] as Json,
      i['ctx'] as Json,
    );
    _same({'a': a, 'b': b, 'ab': m(a, b), 'ba': m(b, a)}, c['expected']);
  },
  'version.list': (c) => _same(
    versionListRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'version.keepForever': (c) => _same(
    keepForeverRule((c['input'] as Map).cast<String, Object?>()),
    c['expected'],
  ),
  'ops.restoreNote': (c) => _same(_restore(c, restoreNote), c['expected']),
  'ops.restorePage': (c) => _same(_restore(c, restorePage), c['expected']),
  'ops.undoRedo': _runHistory,
  'ops.eraseHistory': _runHistory,
  'select.lasso': _selectLasso,
  'select.tap': _selectTap,
  'select.rect': _selectRect,
};

void _runHistory(Case c) {
  final i = c['input'] as Map<String, dynamic>;
  final h = History(_note(i['note']));
  final errors = <String?>[];
  for (final s in (i['steps'] as List).cast<Map<String, dynamic>>()) {
    final ctx = Ctx.fromJson(s['ctx'] as Map<String, dynamic>);
    errors.add(switch (s['kind']) {
      'do' => h.doOp(s['op'] as Map<String, dynamic>, ctx),
      'undo' => h.undo(ctx),
      'redo' => h.redo(ctx),
      final k => throw FormatException('unknown step kind $k'),
    });
  }
  _same({
    'note': h.note.copyJson(),
    'undoDepth': h.undoDepth,
    'redoDepth': h.redoDepth,
    'errors': errors,
  }, c['expected']);
}

void _unknownFields(Case c) {
  final i = c['input'] as Map<String, dynamic>;
  if (i['op'] == null) return _same(_roundTrip(i), _written(c['expected']));
  final r = applyOp(
    _note(i['note']),
    i['op'] as Map<String, dynamic>,
    Ctx.fromJson(i['ctx'] as Map<String, dynamic>),
  );
  _same({'note': r.note?.copyJson()}, c['expected']);
}

final _selectRunners = <Object?, void Function(Case)>{
  'lasso': _selectLasso,
  'tap': _selectTap,
  'rect': _selectRect,
};

void _selectLasso(Case c) {
  {
    final i = c['input'] as Map<String, dynamic>;
    _same(selectLasso(_els(i), _poly(i['polygon'])), c['expected']);
  }
}

void _selectTap(Case c) {
  {
    final i = c['input'] as Map<String, dynamic>;
    final p = i['point'] as List;
    _same(
      selectTap(_els(i), (
        (p[0] as num).toDouble(),
        (p[1] as num).toDouble(),
      ), (i['tolerance'] as num?)?.toDouble() ?? 6),
      c['expected'],
    );
  }
}

void _selectRect(Case c) {
  {
    final i = c['input'] as Map<String, dynamic>;
    _same(
      selectRect(_els(i), [
        for (final v in i['rect'] as List) (v as num).toDouble(),
      ]),
      c['expected'],
    );
  }
}

Json _json(Object? v) => v as Json;

void _runMerge(Case c) {
  final i = _json(c['input']);
  _same(
    mergeNotes(
      i['base'] as Json?,
      i['local'] as Json,
      i['remote'] as Json,
      i['ctx'] as Json,
    ),
    c['expected'],
  );
}

Map<String, Object?> _resolve(Json i) => resolveConflict(
  i['note'] as Json,
  i['conflict'] as Json,
  i['sidecar'] as Json,
  i['choice'],
  i['ctx'] as Json,
);

Map<String, Object?> _restore(
  Case c,
  Map<String, Object?> Function(Json, Json, Json, List<Json>) run,
) {
  final i = _json(c['input']);
  return run(i['note'] as Json, i['op'] as Json, i['ctx'] as Json, [
    for (final x in i['conflicts'] as List) x as Json,
  ]);
}

void _runOp(Case c) {
  final i = c['input'] as Map<String, dynamic>;
  final r = applyOp(
    _note(i['note']),
    i['op'] as Map<String, dynamic>,
    Ctx.fromJson(i['ctx'] as Map<String, dynamic>),
  );
  if (i['undoCtx'] != null && r.error == null && r.inverse != null) {
    final u = applyOp(
      r.note!,
      r.inverse!,
      Ctx.fromJson(i['undoCtx'] as Map<String, dynamic>),
    );
    _same({'note': u.note?.copyJson()}, c['expected']);
    return;
  }
  _same(_opOutput(r), c['expected']);
}

// Rules whose fixture exists but whose client code is a later story's. Each
// needs a valid fixture file and must not have a runner yet: when its story
// adds the runner, the entry has to go (a stale entry fails the run).
// The select.* rules have runners (Story 4.2); the ops.* edit rules (Story 4.1) arrive with the Android stories 4.4, 4.6. The erase rules have runners (Story 5.6): none pending.
const pendingRules = <String>{
  // Epic 25/26 (Stories 25.1, 26.1): runners arrive with 25.x and 26.x Android stories.
  'note.shape',
  // Story 26.11: runners arrive with the 26.x stories.
  'shape.corners',
  'shape.outline',
  'shape.recognizeTilted',
  'shape.holdResize',
};

final _sep = Platform.pathSeparator;

// `flutter test` runs with the package root as the working directory.
final sharedDir = '${Directory.current.parent.path}${_sep}test';

final _ruleId = RegExp(
  r'^[a-z][a-z0-9]*\.[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)?$',
);

Map<String, List<Case>> loadFixtures(
  String dir, {
  Set<String> pending = pendingRules,
}) {
  if (!Directory(dir).existsSync()) {
    throw StateError(
      'Fixture folder not found: $dir\n'
      '루트 kkeujeok 레포 안에 클론했는지 확인하세요 '
      '(kkeujeok-client must be cloned inside the root kkeujeok repo, next to test/).',
    );
  }
  final fixtures = <String, List<Case>>{};
  final seen = <String>{}; // rule ids of every valid fixture file
  final files = [
    for (final e in Directory(dir).listSync())
      e.path.split(RegExp(r'[/\\]')).last,
  ];
  // test/tools holds the committed generator scripts, not fixtures.
  if (Directory('$dir${_sep}tools').existsSync()) files.remove('tools');
  // test/pdf holds the sample PDF files and their manifest.
  if (Directory('$dir${_sep}pdf').existsSync()) files.remove('pdf');
  files.sort();
  for (final file in files) {
    if (file == 'README.md') continue;
    StateError bad(String why) => StateError('Bad fixture $file: $why');
    // Anything else in the folder (a subfolder, "x.JSON", "x.json.bak") would
    // otherwise be skipped without a word.
    if (!file.endsWith('.json')) throw bad('not a "<rule id>.json" file');
    final id = file.substring(0, file.length - '.json'.length);
    if (!_ruleId.hasMatch(id)) {
      throw bad('file name is not a rule id');
    }
    final Object? data;
    try {
      data = jsonDecode(File('$dir$_sep$file').readAsStringSync());
    } on FormatException catch (e) {
      throw bad('not valid JSON (${e.message})');
    } on FileSystemException catch (e) {
      throw bad('cannot be read (${e.message})');
    }
    if (data is! Map<String, dynamic>) throw bad('top level is not an object');
    if (data['rule'] != id) {
      throw bad(
        '"rule" is ${jsonEncode(data['rule'])}, expected "$id" (the file name)',
      );
    }
    final cases = data['cases'];
    if (cases is! List || cases.isEmpty) {
      throw bad('"cases" is missing or empty');
    }
    final names = <String>{};
    for (final (i, c) in cases.indexed) {
      if (c is! Map<String, dynamic>) throw bad('case $i is not an object');
      final name = c['name'];
      if (name is! String || name.isEmpty) throw bad('case $i has no "name"');
      if (!names.add(name)) throw bad('duplicate case name "$name"');
      if (!c.containsKey('input') || !c.containsKey('expected')) {
        throw bad('case "$name" needs both "input" and "expected"');
      }
    }
    if (!runners.containsKey(id) && !pending.contains(id)) {
      throw StateError(
        'Fixture $file has no test: rule "$id" is not implemented in the Android client. '
        'Add it to `runners` in test/fixtures_test.dart.',
      );
    }
    seen.add(id);
    if (!runners.containsKey(id)) continue; // pending: valid, not run yet
    // A top-level `tolerance` rides along with each case.
    fixtures[id] = [
      for (final c in cases.cast<Case>())
        if (data.containsKey('tolerance'))
          {...c, 'tolerance': data['tolerance']}
        else
          c,
    ];
  }
  for (final id in runners.keys) {
    if (!fixtures.containsKey(id)) {
      throw StateError('Fixture file missing: $dir$_sep$id.json');
    }
  }
  for (final id in pending) {
    if (runners.containsKey(id)) {
      throw StateError(
        'Rule "$id" has a runner: remove it from pendingRules in '
        'test/fixtures_test.dart.',
      );
    }
    if (!seen.contains(id)) {
      throw StateError('Pending fixture missing: $dir$_sep$id.json');
    }
  }
  return fixtures;
}

Matcher throwsMessage(Pattern p) =>
    throwsA(predicate((e) => e.toString().contains(p), 'message contains $p'));

void main() {
  // A font file that is not the one of spec/decisions/text-font.md fails here.
  TextMetrics.install(
    File('assets/fonts/Pretendard-Regular.otf').readAsBytesSync(),
    File('assets/fonts/Pretendard-SemiBold.otf').readAsBytesSync(),
  );
  // Thrown at load time on purpose: a broken setup fails the run, never skips.
  loadFixtures(sharedDir).forEach((id, cases) {
    group(id, () {
      for (final c in cases) {
        test(c['name'] as String, () {
          try {
            runners[id]!(c);
          } on FormatException catch (e) {
            // Name the file, as the loader's own errors do.
            throw FormatException(
              '$id.json, case "${c['name']}": ${e.message}',
            );
          }
        });
      }
    });
  });

  group('harness refuses a broken setup', () {
    final good = File('$sharedDir${_sep}number.round2.json').readAsStringSync();
    // Loads a temp folder holding exactly the given files.
    Map<String, List<Case>> loadOnly(Map<String, String> files) {
      final dir = Directory.systemTemp.createTempSync('kkj-fixtures-');
      try {
        files.forEach(
          (name, text) => File('${dir.path}$_sep$name').writeAsStringSync(text),
        );
        return loadFixtures(dir.path);
      } finally {
        dir.deleteSync(recursive: true);
      }
    }

    // The real fixture plus the given extra files.
    Map<String, List<Case>> loadWith(Map<String, String> files) =>
        loadOnly({'number.round2.json': good, ...files});

    String fixture(String rule, List<Object?> cases) =>
        jsonEncode({'rule': rule, 'cases': cases});
    const one = {'name': 'a', 'input': 1, 'expected': 1};

    test('real fixture is loaded with its cases', () {
      expect(loadFixtures(sharedDir)['number.round2'], isNotEmpty);
    });

    test('fixture folder missing', () {
      final missing =
          '${Directory.systemTemp.path}${_sep}kkj-fixtures-does-not-exist';
      expect(
        () => loadFixtures(missing),
        throwsMessage('루트 kkeujeok 레포 안에 클론했는지 확인'),
      );
      expect(() => loadFixtures(missing), throwsMessage(missing));
    });

    test('fixture with no test', () {
      expect(
        () => loadWith({
          'stroke.hitTest.json': fixture('stroke.hitTest', [one]),
        }),
        throwsMessage('"stroke.hitTest"'),
      );
    });

    test('rule differs from file name', () {
      expect(
        () => loadWith({
          'number.round2.json': fixture('number.round3', [one]),
        }),
        throwsMessage(RegExp(r'number\.round2\.json.*"rule"')),
      );
    });

    test('empty cases', () {
      expect(
        () => loadWith({'number.round2.json': fixture('number.round2', [])}),
        throwsMessage(RegExp(r'number\.round2\.json.*"cases"')),
      );
    });

    test('case without input or expected', () {
      expect(
        () => loadWith({
          'number.round2.json': fixture('number.round2', [
            {'name': 'a'},
          ]),
        }),
        throwsMessage(RegExp(r'number\.round2\.json.*needs both')),
      );
    });

    test('runner whose fixture file is gone', () {
      expect(
        () => loadOnly({}),
        throwsMessage(RegExp(r'Fixture file missing.*number\.round2\.json')),
      );
    });

    test('entry that is not a rule id .json file', () {
      expect(
        () => loadWith({'stroke.hitTest.JSON': good}),
        throwsMessage('stroke.hitTest.JSON'),
      );
      expect(
        () => loadWith({'constructor.json': good}),
        throwsMessage('not a rule id'),
      );
    });

    group('pendingRules', () {
      const later = 'x.later';
      final laterFile = fixture(later, [one]);

      // A copy of the real fixture folder, changed by [edit].
      Map<String, List<Case>> loadCopy(
        void Function(Directory) edit, {
        required Set<String> pending,
      }) {
        final dir = Directory.systemTemp.createTempSync('kkj-fixtures-');
        try {
          for (final e in Directory(sharedDir).listSync()) {
            if (e is File) {
              e.copySync('${dir.path}$_sep${e.uri.pathSegments.last}');
            }
          }
          edit(dir);
          // The ids of later stories stay pending in every copy.
          return loadFixtures(dir.path, pending: {...pendingRules, ...pending});
        } finally {
          dir.deleteSync(recursive: true);
        }
      }

      void put(Directory d, String text) =>
          File('${d.path}${_sep}x.later.json').writeAsStringSync(text);

      test('the real folder passes with the pending ids of later stories', () {
        expect(pendingRules.where((id) => id.startsWith('merge.')), isEmpty);
        expect(loadCopy((_) {}, pending: pendingRules), isNotEmpty);
      });

      test('a pending rule with a valid file and no runner passes', () {
        final f = loadCopy((d) => put(d, laterFile), pending: {later});
        expect(f, isNot(contains(later)));
      });

      test('a pending rule whose file is gone fails', () {
        expect(
          () => loadCopy((_) {}, pending: {later}),
          throwsMessage('Pending fixture missing'),
        );
      });

      test('a pending rule that has a runner fails', () {
        expect(
          () => loadCopy((_) {}, pending: {'sync.hasUnsent'}),
          throwsMessage('remove it from pendingRules'),
        );
      });

      test('a pending rule with an invalid file fails', () {
        expect(
          () => loadCopy((d) => put(d, '{ not json'), pending: {later}),
          throwsMessage('not valid JSON'),
        );
      });

      test('a rule that is neither run nor pending still fails', () {
        expect(
          () => loadCopy((d) => put(d, laterFile), pending: <String>{}),
          throwsMessage('has no test'),
        );
      });
    });

    test('number.round2 case with non-number values', () {
      final run = runners['number.round2']!;
      expect(
        () => run({'name': 'a', 'input': 'abc', 'expected': 'abc'}),
        throwsMessage('JSON numbers'),
      );
      expect(
        () => run({'name': 'a', 'input': null, 'expected': 0}),
        throwsMessage('JSON numbers'),
      );
    });

    test('stroke.outline.pen case without a tolerance', () {
      expect(
        () => runners['stroke.outline.pen']!({
          'name': 'a',
          'input': {'width': 2, 'usePressure': true, 'points': []},
          'expected': {'polygon': []},
        }),
        throwsMessage('tolerance'),
      );
    });

    test('number.round2 never returns negative zero', () {
      for (final x in [-0.004, -0.0]) {
        final out = round2(x);
        expect(out, 0.0);
        expect(out.isNegative, isFalse);
      }
    });
  });
}
