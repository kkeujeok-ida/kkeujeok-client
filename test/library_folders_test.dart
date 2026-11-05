import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/library/folder_service.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'shell_test.dart' show pumpApp;

// Stories 18.3, 18.4, 18.8 in the library screen.
const _view = FolderView(
  folders: [
    LibraryFolder('a', 'Class', 'root'),
    LibraryFolder('b', 'Math', 'a'),
    LibraryFolder('c', 'Diary', 'root'),
  ],
);

class _Tree extends FolderTreeNotifier {
  @override
  Future<FolderView> build() async => _view;
}

class _MoveTree extends _Tree {
  static final moved = <String>[];

  @override
  Future<FolderResult> moveNote(String noteId, String parentId) async {
    moved.add('$noteId>$parentId');
    return const FolderResult();
  }
}

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Note _note(int n, String title) => createNote(
  title: title,
  existingTitles: const [],
  background: 'plain',
  orientation: 'portrait',
  noteId: _id(n),
  pageId: _id(n + 1000),
  pageRev: _id(n + 2000),
  metaRev: _id(n + 3000),
  orderRev: _id(n + 4000),
  now: '2026-10-10T12:00:00.000Z',
  editedBy: 'Pixel 8',
).note!;

void main() {
  late Directory docs;
  late NoteData data;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-libf-');
    data = NoteData(() async => docs);
    final n = _note(1, 'Lecture');
    final f = File('${docs.path}/$noteDataDirName/${n.noteId}/working.kkj');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(encodeKkj(n));
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // The OS cleans temp.
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

  Future<void> start(WidgetTester t) async {
    await pumpApp(
      t,
      noteData: data,
      prefs: {'language': 'en'},
      overrides: [folderTreeProvider.overrideWith(_Tree.new)],
    );
    await settle(t);
  }

  testWidgets('root shows folder cards before notes; enter and go up', (
    t,
  ) async {
    await start(t);
    expect(find.text('Lecture'), findsOneWidget);
    expect(find.text('Diary'), findsWidgets);
    expect(find.text('../'), findsNothing);
    await t.tap(find.byKey(const ValueKey('folder-card-a')));
    await settle(t);
    expect(find.text('../'), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-card-b')), findsOneWidget);
    expect(find.text('Lecture'), findsNothing); // it is at the top level
    await t.tap(find.text('../'));
    await settle(t);
    expect(find.text('../'), findsNothing);
    expect(find.text('Lecture'), findsOneWidget);
  });

  testWidgets('the + has New folder; no sidebar new-folder row', (t) async {
    await start(t);
    await t.tap(find.byIcon(Icons.add).last);
    await t.pumpAndSettle();
    expect(find.text('New folder'), findsOneWidget);
    expect(find.text('New note'), findsWidgets);
  });

  testWidgets('long press selects; the bar counts; cancel ends', (t) async {
    await start(t);
    await t.longPress(find.text('Lecture'));
    await t.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byKey(const Key('selectMove')), findsOneWidget);
    expect(find.byKey(const Key('selectDelete')), findsOneWidget);
    await t.tap(find.byKey(const Key('selectDelete')));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('selectCancel')));
    await t.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('search is an icon; opens with focus; folds when empty', (
    t,
  ) async {
    await start(t);
    expect(find.byKey(const Key('searchField')), findsNothing);
    await t.tap(find.byKey(const Key('searchOpen')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('searchField')), findsOneWidget);
    await t.enterText(find.byKey(const Key('searchField')), 'lec');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('searchClear')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('searchField')), findsNothing);
    expect(find.byKey(const Key('searchOpen')), findsOneWidget);
  });

  testWidgets('a note dragged onto a folder card moves', (
    t,
  ) async {
    _MoveTree.moved.clear();
    await pumpApp(
      t,
      noteData: data,
      prefs: {'language': 'en'},
      overrides: [folderTreeProvider.overrideWith(_MoveTree.new)],
    );
    await settle(t);
    final g = await t.startGesture(t.getCenter(find.text('Lecture')));
    await t.pump(const Duration(milliseconds: 700)); // long press: drag starts
    await g.moveTo(t.getCenter(find.byKey(const ValueKey('folder-card-c'))));
    await t.pump();
    await g.up();
    await settle(t);
    expect(_MoveTree.moved, ['${_id(1)}>c']);
    expect(find.text('1 selected'), findsNothing); // the drop ends selection
  });
}
