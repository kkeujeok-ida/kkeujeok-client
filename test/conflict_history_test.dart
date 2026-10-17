// Page locks of `History` (Story 3.19): a conflicted page is read-only for
// ops, undo and redo; other pages are not; a merge keeps the locks.
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/history.dart';
import 'package:kkeujeok/ops/ops.dart';

const _a = 'page-a';
const _b = 'page-b';

Note _twoPages() {
  final j = createNote(
    title: 'a',
    existingTitles: [],
    background: 'plain',
    orientation: 'portrait',
    noteId: '01926f3a-0000-7000-8000-000000000900',
    pageId: _a,
    pageRev: 'r1',
    metaRev: 'm',
    orderRev: 'o',
    now: '2026-10-10T04:20:00.000Z',
    editedBy: 'x',
  ).note!.copyJson();
  final pages = j['pages'] as List;
  pages.add({...(pages.first as Map<String, dynamic>), 'id': _b, 'rev': 'r2'});
  return Note.trusted(j);
}

Map<String, dynamic> _stroke(String id) => {
  'id': id,
  'type': 'stroke',
  'tool': 'pen',
  'color': '#000000',
  'width': 2,
  'usePressure': true,
  'points': [
    [1, 1, 0.5, 0],
    [2, 2, 0.5, 5],
  ],
};

var _n = 0;
Ctx _ctx() => Ctx(
  rev: 'rev${++_n}',
  now: '2026-10-10T04:20:01.000Z',
  editedBy: 'x',
);

Map<String, dynamic> _add(String page, String id) => {
  'op': 'addStroke',
  'pageId': page,
  'stroke': _stroke(id),
};

int _strokes(History h, String page) =>
    (h.note.pages.firstWhere((p) => p['id'] == page)['elements'] as List)
        .length;

void main() {
  test('an op on a locked page is pageReadOnly and changes nothing', () {
    final h = History(_twoPages())..lockPages({_a});
    expect(h.doOp(_add(_a, 's1'), _ctx()), 'pageReadOnly');
    expect(_strokes(h, _a), 0);
    expect(h.undoDepth, 0);
  });

  test('another page stays editable', () {
    final h = History(_twoPages())..lockPages({_a});
    expect(h.doOp(_add(_b, 's1'), _ctx()), isNull);
    expect(_strokes(h, _b), 1);
    expect(h.undoDepth, 1);
  });

  test('undo and redo of a locked page pop nothing', () {
    final h = History(_twoPages());
    expect(h.doOp(_add(_a, 's1'), _ctx()), isNull);
    expect(h.undo(_ctx()), isNull);
    expect(h.redoDepth, 1);
    h.lockPages({_a});
    expect(h.redo(_ctx()), 'pageReadOnly');
    expect(h.redoDepth, 1);
    expect(_strokes(h, _a), 0);

    final g = History(_twoPages());
    expect(g.doOp(_add(_a, 's1'), _ctx()), isNull);
    g.lockPages({_a});
    expect(g.undo(_ctx()), 'pageReadOnly');
    expect(g.undoDepth, 1);
    expect(_strokes(g, _a), 1);
  });

  test('undo of an unlocked page is not blocked by a lock elsewhere', () {
    final h = History(_twoPages());
    expect(h.doOp(_add(_b, 's1'), _ctx()), isNull);
    h.lockPages({_a});
    expect(h.undo(_ctx()), isNull);
    expect(_strokes(h, _b), 0);
  });

  test('adopt keeps the locks and drops the records of the merged pages', () {
    final h = History(_twoPages());
    expect(h.doOp(_add(_a, 's1'), _ctx()), isNull);
    expect(h.doOp(_add(_b, 's2'), _ctx()), isNull);
    h.lockPages({_a});
    h.adopt(_twoPages(), {_a});
    expect(h.undoDepth, 1); // page B's record stays
    expect(h.isLocked(_a), isTrue);
    expect(h.doOp(_add(_a, 's3'), _ctx()), 'pageReadOnly');
  });

  test('locks only add', () {
    final h = History(_twoPages())
      ..lockPages({_a})
      ..lockPages({_b})
      ..lockPages({});
    expect(h.isLocked(_a), isTrue);
    expect(h.isLocked(_b), isTrue);
    expect(h.isLocked(null), isFalse);
  });
}
