// Story 3.19: the library's wiring of the conflict notification (permission
// on the first foreground conflict, a tap or a launch opens the note).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/conflict_notifier.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

class _Notifier implements ConflictNotifier {
  final tapsController = StreamController<String>.broadcast();
  String? launch;
  int requests = 0;

  @override
  Future<bool> isGranted() async => true;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return true;
  }

  @override
  Future<void> show(String noteId) async {}

  @override
  Stream<String> get taps => tapsController.stream;

  @override
  Future<String?> launchNoteId() async => launch;
}

void main() {
  late Directory docs;
  late NoteData data;
  late NoteStore store;
  late _Notifier notifier;

  setUp(() {
    notifier = _Notifier();
    docs = Directory.systemTemp.createTempSync('kkj-conflict-lib-');
    data = NoteData(() async => docs);
    store = NoteStore(data);
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // The OS cleans temp up later.
      }
    });
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 40; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  Future<void> seed(WidgetTester t, {bool conflict = false}) async {
    final note = createNote(
      title: 'Lecture',
      existingTitles: const [],
      background: 'plain',
      orientation: 'portrait',
      noteId: _id(1),
      pageId: _id(1001),
      pageRev: _id(2001),
      metaRev: _id(3001),
      orderRev: _id(4001),
      now: '2000-01-01T12:00:00.000Z',
      editedBy: 'Pixel 8',
    ).note!;
    final f = File('${docs.path}/$noteDataDirName/${_id(1)}/working.kkj');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(encodeKkj(note));
    await t.runAsync(() => store.updateSync(_id(1), (s) => s));
    if (conflict) {
      await t.runAsync(
        () => store.updateSync(
          _id(1),
          (s) => s.copyWith(
            state: SyncState.conflict,
            conflicts: [
              {
                'pageId': _id(1001),
                'kind': 'bothEdited',
                'rev': _id(1),
                'theirsRev': _id(2),
                'detectedAt': '2026-10-17T00:00:00.000Z',
                'originalIndex': 0,
                'resolvedAt': null,
              },
            ],
          ),
        ),
      );
    }
  }

  Future<void> pump(WidgetTester t) async {
    await pumpApp(
      t,
      noteData: data,
      noteStore: store,
      overrides: [conflictNotifierProvider.overrideWithValue(notifier)],
    );
    await settle(t);
  }

  testWidgets('a conflict on library entry asks for the permission once', (
    t,
  ) async {
    await seed(t, conflict: true);
    await pump(t);
    expect(notifier.requests, 1);
  });

  testWidgets('no conflict: the permission is not asked', (t) async {
    await seed(t);
    await pump(t);
    expect(notifier.requests, 0);
  });

  testWidgets('a tapped notification opens that note', (t) async {
    await seed(t);
    await pump(t);
    expect(find.byType(NoteEditor), findsNothing);
    notifier.tapsController.add(_id(1));
    await settle(t);
    expect(find.byType(NoteEditor), findsOneWidget);
  });

  testWidgets('a notification that launched the app opens that note', (
    t,
  ) async {
    await seed(t);
    notifier.launch = _id(1);
    await pump(t);
    expect(find.byType(NoteEditor), findsOneWidget);
  });
}
