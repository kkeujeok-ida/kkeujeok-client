import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/shape.dart';
import 'package:kkeujeok/ops/history.dart';
import 'package:kkeujeok/ops/ops.dart';

void main() {
  final r = createNote(
    title: 'a',
    existingTitles: [],
    background: 'plain',
    orientation: 'portrait',
    noteId: '01926f3a-0000-7000-8000-000000000900',
    pageId: 'p',
    pageRev: 'r',
    metaRev: 'm',
    orderRev: 'o',
    now: '2026-10-10T04:20:00.000Z',
    editedBy: 'x',
  );
  const ctx = Ctx(rev: 'r2', now: '2026-10-10T04:20:01.000Z', editedBy: 'x');

  test('bad stroke and unknown op are errors, never exceptions', () {
    final h = History(r.note!);
    for (final s in <Object?>[
      null,
      'x',
      <String, dynamic>{'id': 'a'},
    ]) {
      expect(
        h.doOp({'op': 'addStroke', 'pageId': 'p', 'stroke': s}, ctx),
        'invalidStroke',
      );
    }
    expect(h.doOp(r.inverse!, ctx), 'unknownOp');
    expect(h.undoDepth, 0);
  });

  test('restore ops are not history operations: unknownOp, no record', () {
    final h = History(r.note!);
    for (final op in ['restoreNote', 'restorePage']) {
      expect(h.doOp({'op': op, 'pageId': 'p'}, ctx), 'unknownOp');
    }
    expect(h.undoDepth, 0);
  });

  test('Ctx.fromJson defaults lastSeenRemoteSeq', () {
    expect(
      Ctx.fromJson({'rev': 'a', 'now': 'n', 'editedBy': 'e'}).lastSeenRemoteSeq,
      0,
    );
  });

  test('reshapeStroke: one undo step, redo, and the errors', () {
    final h = History(r.note!);
    final rect = {
      'kind': 'rect',
      'x': 10,
      'y': 10,
      'width': 40,
      'height': 20,
      'rotation': 0,
    };
    final stroke = {
      'id': 's',
      'type': 'stroke',
      'tool': 'pen',
      'color': '#000000',
      'width': 2,
      'usePressure': false,
      'points': shapePoints(rect),
      'shape': rect,
    };
    expect(
      h.doOp({'op': 'addStroke', 'pageId': 'p', 'stroke': stroke}, ctx),
      isNull,
    );
    final big = {...rect, 'width': 80, 'rotation': 15};
    Map el() =>
        (h.note.copyJson()['pages'] as List).first['elements'][0] as Map;
    final op = {
      'op': 'reshapeStroke',
      'pageId': 'p',
      'id': 's',
      'shape': big,
      'points': shapePoints(big),
    };
    expect(h.doOp(op, ctx), isNull);
    expect(el()['shape'], big);
    expect(el()['width'], 2);
    expect(h.undoDepth, 2);
    expect(h.undo(ctx), isNull);
    expect(el()['shape'], rect);
    expect(el()['points'], stroke['points']);
    expect(h.redo(ctx), isNull);
    expect(el()['shape'], big);
    expect(h.doOp({...op, 'id': 'x'}, ctx), 'strokeNotFound');
    expect(h.doOp({...op, 'pageId': 'q'}, ctx), 'pageNotFound');
    expect(h.doOp({...op, 'points': []}, ctx), 'invalidStroke');
    expect(
      h.doOp({
        'op': 'reshapeStroke',
        'pageId': 'p',
        'id': 's',
        'shape': null,
        'points': [
          [1, 2, 0.5, 0],
        ],
      }, ctx),
      isNull,
    );
    expect(el().containsKey('shape'), isFalse);
  });
}
