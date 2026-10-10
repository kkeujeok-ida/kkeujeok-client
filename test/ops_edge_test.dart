import 'package:flutter_test/flutter_test.dart';
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

  test('Ctx.fromJson defaults lastSeenRemoteSeq', () {
    expect(
      Ctx.fromJson({'rev': 'a', 'now': 'n', 'editedBy': 'e'}).lastSeenRemoteSeq,
      0,
    );
  });
}
