// Runs every fixture in the root repo's test/ folder (read unchanged from the
// sibling path) against this client's implementation of the rule.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/model/note_title.dart';
import 'package:kkeujeok/model/number.dart';
import 'package:kkeujeok/ops/history.dart';
import 'package:kkeujeok/ops/ops.dart';

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

Map<String, dynamic> _opOutput(OpResult r) => r.error != null
    ? {'error': r.error}
    : {'note': r.note!.copyJson(), 'inverse': r.inverse};

void _same(Object? actual, Object? expected) =>
    expect(actual, equals(expected)); // == on numbers: 1 equals 1.0

// Rules whose fixtures exist but whose code lands in a later story. The file
// must still be there; a rule not named here and without a runner fails.
const pendingRules = <String, String>{
  'stroke.outline.pen': 'Story 2.5',
  'page.background': 'Story 2.5',
};

// Rule id -> how to judge one case. A new spec rule adds one line here.
final runners = <String, void Function(Case)>{
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
  'note.roundTrip': (c) => _same(_roundTrip(c['input']), c['expected']),
  'note.unknownFields': (c) => _same(_roundTrip(c['input']), c['expected']),
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
  'ops.removeStroke': _runOp,
  'ops.undoRedo': (c) {
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
  },
};

void _runOp(Case c) {
  final i = c['input'] as Map<String, dynamic>;
  final r = applyOp(
    _note(i['note']),
    i['op'] as Map<String, dynamic>,
    Ctx.fromJson(i['ctx'] as Map<String, dynamic>),
  );
  _same(_opOutput(r), c['expected']);
}

final _sep = Platform.pathSeparator;

// `flutter test` runs with the package root as the working directory.
final sharedDir = '${Directory.current.parent.path}${_sep}test';

final _ruleId = RegExp(r'^[a-z][a-z0-9]*\.[a-z][A-Za-z0-9]*$');

Map<String, List<Case>> loadFixtures(String dir) {
  if (!Directory(dir).existsSync()) {
    throw StateError(
      'Fixture folder not found: $dir\n'
      '루트 kkeujeok 레포 안에 클론했는지 확인하세요 '
      '(kkeujeok-client must be cloned inside the root kkeujeok repo, next to test/).',
    );
  }
  final fixtures = <String, List<Case>>{};
  final seenPending = <String>{};
  final files = [
    for (final e in Directory(dir).listSync())
      e.path.split(RegExp(r'[/\\]')).last,
  ];
  // test/tools holds the committed generator scripts, not fixtures.
  if (Directory('$dir${_sep}tools').existsSync()) files.remove('tools');
  files.sort();
  for (final file in files) {
    if (file == 'README.md') continue;
    StateError bad(String why) => StateError('Bad fixture $file: $why');
    // Anything else in the folder (a subfolder, "x.JSON", "x.json.bak") would
    // otherwise be skipped without a word.
    if (!file.endsWith('.json')) throw bad('not a "<rule id>.json" file');
    final id = file.substring(0, file.length - '.json'.length);
    // spec/README allows one dot, but the 2.2 fixture stroke.outline.pen has
    // two; the pending rules are named exactly, so they are let through.
    if (!pendingRules.containsKey(id) && !_ruleId.hasMatch(id)) {
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
    if (pendingRules.containsKey(id)) {
      seenPending.add(id);
      continue;
    }
    if (!runners.containsKey(id)) {
      throw StateError(
        'Fixture $file has no test: rule "$id" is not implemented in the Android client. '
        'Add it to `runners` in test/fixtures_test.dart.',
      );
    }
    fixtures[id] = cases.cast<Case>();
  }
  for (final id in [...runners.keys, ...pendingRules.keys]) {
    if (seenPending.contains(id)) continue;
    if (!fixtures.containsKey(id)) {
      throw StateError('Fixture file missing: $dir$_sep$id.json');
    }
  }
  return fixtures;
}

Matcher throwsMessage(Pattern p) =>
    throwsA(predicate((e) => e.toString().contains(p), 'message contains $p'));

void main() {
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

    test('number.round2 never returns negative zero', () {
      for (final x in [-0.004, -0.0]) {
        final out = round2(x);
        expect(out, 0.0);
        expect(out.isNegative, isFalse);
      }
    });
  });
}
