import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/new_note_defaults_store.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/ui/library_fab.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_gateway.dart';
import 'shell_test.dart' show pumpApp;

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Note _note(
  int n,
  String title, {
  String at = '2026-10-10T12:00:00.000Z',
  String background = 'plain',
  String orientation = 'portrait',
}) => createNote(
  title: title,
  existingTitles: const [],
  background: background,
  orientation: orientation,
  noteId: _id(n),
  pageId: _id(n + 1000),
  pageRev: _id(n + 2000),
  metaRev: _id(n + 3000),
  orderRev: _id(n + 4000),
  now: at,
  editedBy: 'Pixel 8',
).note!;

void main() {
  late Directory docs;
  late NoteData data;
  late Directory notes;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-lib-');
    data = NoteData(() async => docs);
    notes = Directory('${docs.path}/$noteDataDirName');
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold a handle for a moment; the OS cleans temp.
      }
    });
  });

  File fileOf(int n) => File('${notes.path}/${_id(n)}/working.kkj');

  void seed(Note note) {
    final f = File('${notes.path}/${note.noteId}/working.kkj');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(encodeKkj(note));
  }

  void seedBytes(int n, List<int> bytes) {
    final f = fileOf(n);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
  }

  /// File IO runs outside the fake clock: wait in real time and pump to
  /// deliver the results, until the list is loaded and no frame has been
  /// scheduled for a while.
  Future<void> settle(WidgetTester t) async {
    var idle = 0;
    for (var i = 0; i < 1000 && idle < 30; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
      final scope = find.byType(MaterialApp);
      final loading =
          scope.evaluate().isNotEmpty &&
          ProviderScope.containerOf(t.element(scope))
              .read(libraryProvider)
              .isLoading;
      idle = t.binding.hasScheduledFrame || loading ? 0 : idle + 1;
    }
    await t.pumpAndSettle();
  }

  final fab = find.byType(LibraryFab);
  final fabPlus = find.descendant(of: fab, matching: find.byIcon(Icons.add));
  final fabItem = find.descendant(
    of: fab,
    matching: find.byIcon(Icons.note_add_outlined),
  );

  Future<void> expandFab(WidgetTester t) async {
    await t.tap(fabPlus);
    await t.pumpAndSettle();
  }

  /// Titles in reading order (top to bottom, then left to right).
  List<String> order(WidgetTester t, List<String> titles) {
    final at = {for (final s in titles) s: t.getTopLeft(find.text(s))};
    return titles.toList()..sort((a, b) {
      final c = at[a]!.dy.compareTo(at[b]!.dy);
      return c != 0 ? c : at[a]!.dx.compareTo(at[b]!.dx);
    });
  }

  group('defaults store', () {
    test('first time, invalid values and no preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final s = NewNoteDefaultsStore(sp);
      expect(s.read(), (background: 'plain', orientation: 'portrait'));
      await s.write(background: 'grid', orientation: 'landscape');
      expect(s.read(), (background: 'grid', orientation: 'landscape'));
      SharedPreferences.setMockInitialValues({
        'newNoteBackground': 'neon',
        'newNoteOrientation': 7,
      });
      final bad = NewNoteDefaultsStore(await SharedPreferences.getInstance());
      expect(bad.read(), (background: 'plain', orientation: 'portrait'));
      final none = NewNoteDefaultsStore(null);
      await none.write(background: 'dot', orientation: 'portrait');
      expect(none.read(), (background: 'dot', orientation: 'portrait'));
    });
  });

  group('empty library', () {
    testWidgets('one new-note card, the fab, no header button', (t) async {
      await pumpApp(t, noteData: data);
      await settle(t);
      expect(find.text('New note'), findsOneWidget); // the card
      expect(fab, findsOneWidget);
      expect(fabItem, findsNothing);
      // The header holds the title only.
      expect(find.text('Library'), findsOneWidget);
      expect(find.byType(NoteEditor), findsNothing);
    });

    testWidgets('Korean strings', (t) async {
      await pumpApp(t, noteData: data, device: const [Locale('ko', 'KR')]);
      await settle(t);
      expect(find.text('새 노트'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
    });
  });

  group('fab', () {
    testWidgets('expands to one item, + turns into x, veils behind', (t) async {
      await pumpApp(t, noteData: data);
      await settle(t);
      await expandFab(t);
      expect(fabItem, findsOneWidget);
      expect(
        find.descendant(of: fab, matching: find.text('New note')),
        findsOneWidget,
      );
      expect(
        t
            .widget<AnimatedRotation>(
              find.descendant(of: fab, matching: find.byType(AnimatedRotation)),
            )
            .turns,
        0.125,
      );
      // Veil: a layer over the whole library absorbs taps.
      expect(
        find.descendant(of: fab, matching: find.byType(ColoredBox)),
        findsWidgets,
      );
    });

    testWidgets('x, outside tap, Esc and back each collapse it', (t) async {
      await pumpApp(t, noteData: data);
      await settle(t);

      await expandFab(t);
      await t.tap(fabPlus); // the x
      await t.pumpAndSettle();
      expect(fabItem, findsNothing);

      await expandFab(t);
      await t.tapAt(const Offset(500, 300));
      await t.pumpAndSettle();
      expect(fabItem, findsNothing);

      await expandFab(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(fabItem, findsNothing);

      await expandFab(t);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(fabItem, findsNothing);
      expect(find.byType(NoteEditor), findsNothing);
    });

    testWidgets('the item opens the sheet', (t) async {
      await pumpApp(t, noteData: data);
      await settle(t);
      await expandFab(t);
      await t.tap(fabItem);
      await t.pumpAndSettle();
      expect(fabItem, findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });
  });

  group('new note sheet', () {
    Future<void> openFromCard(WidgetTester t) async {
      await t.tap(find.text('New note'));
      await t.pumpAndSettle();
    }

    testWidgets('first time: plain and portrait are selected', (t) async {
      final h = t.ensureSemantics();
      await pumpApp(t, noteData: data);
      await settle(t);
      await openFromCard(t);
      bool selected(String label) =>
          t
              .getSemantics(find.bySemanticsLabel(label))
              .getSemanticsData()
              .flagsCollection
              .isSelected ==
          Tristate.isTrue;
      expect(selected('Plain'), isTrue);
      expect(selected('Portrait'), isTrue);
      expect(selected('Lined'), isFalse);
      expect(selected('Landscape'), isFalse);
      h.dispose();
    });

    testWidgets('defaults follow the last note made', (t) async {
      await pumpApp(
        t,
        noteData: data,
        prefs: {'newNoteBackground': 'dot', 'newNoteOrientation': 'landscape'},
      );
      await settle(t);
      final h = t.ensureSemantics();
      await openFromCard(t);
      bool selected(String label) =>
          t
              .getSemantics(find.bySemanticsLabel(label))
              .getSemanticsData()
              .flagsCollection
              .isSelected ==
          Tristate.isTrue;
      expect(selected('Dot'), isTrue);
      expect(selected('Landscape'), isTrue);
      expect(selected('Plain'), isFalse);
      h.dispose();
    });

    testWidgets('create saves a one-page note and opens the writing entry', (
      t,
    ) async {
      await pumpApp(t, noteData: data);
      await settle(t);
      await openFromCard(t);
      await t.enterText(find.byType(TextField), '  Algorithms ');
      await t.tap(find.text('Grid'));
      await t.tap(find.text('Landscape'));
      await t.pump();
      await t.tap(find.text('Create'));
      await settle(t);

      expect(find.byType(NoteEditor), findsOneWidget);
      expect(find.text('Algorithms'), findsOneWidget);

      final dirs = notes.listSync().whereType<Directory>().toList();
      expect(dirs, hasLength(1));
      final file = File('${dirs.single.path}/working.kkj');
      final read = decodeKkj(file.readAsBytesSync());
      expect(read.status, ReadStatus.ok);
      final n = read.note!;
      expect(n.title, 'Algorithms');
      expect(n.pages, hasLength(1));
      expect(n.pages.single['background'], 'grid');
      expect(n.pages.single['width'], 842); // landscape A4
      expect(n.pages.single['height'], 595);
      expect(n.pages.single['elements'], isEmpty);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('newNoteBackground'), 'grid');
      expect(sp.getString('newNoteOrientation'), 'landscape');

      // Back to the library: the note is listed.
      await t.tap(find.byTooltip('Back to library'));
      await settle(t);
      expect(find.byType(NoteEditor), findsNothing);
      expect(find.text('Algorithms'), findsOneWidget);
      expect(find.text('New note'), findsNothing); // no empty card any more
    });

    testWidgets('a blank title becomes the smallest unused number', (t) async {
      seed(_note(1, '이름 없는 노트 1'));
      await pumpApp(t, noteData: data);
      await settle(t);
      await t.tap(fabPlus);
      await t.pumpAndSettle();
      await t.tap(fabItem);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '   ');
      await t.tap(find.text('Create'));
      await settle(t);
      expect(find.text('이름 없는 노트 2'), findsOneWidget);
    });

    testWidgets('the same title is allowed', (t) async {
      seed(_note(1, 'Same'));
      await pumpApp(t, noteData: data);
      await settle(t);
      await t.tap(fabPlus);
      await t.pumpAndSettle();
      await t.tap(fabItem);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Same');
      await t.tap(find.text('Create'));
      await settle(t);
      expect(notes.listSync().whereType<Directory>(), hasLength(2));
    });

    testWidgets('the field stops at 100 code points', (t) async {
      await pumpApp(t, noteData: data);
      await settle(t);
      await openFromCard(t);
      await t.enterText(find.byType(TextField), '가' * 150);
      await t.pump();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text.runes,
        hasLength(100),
      );
      // Astral characters count as one code point each.
      await t.enterText(find.byType(TextField), '😀' * 120);
      await t.pump();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text.runes,
        hasLength(100),
      );
    });

    testWidgets('a failed save keeps the sheet and stores nothing', (t) async {
      var fail = true;
      final store = NoteStore(
        data,
        writeFile: (f, b) async {
          if (fail) throw const FileSystemException('disk full');
          await f.writeAsBytes(b);
        },
      );
      await pumpApp(t, noteData: data, noteStore: store);
      await settle(t);
      await openFromCard(t);
      await t.tap(find.text('Lined'));
      await t.tap(find.text('Create'));
      await settle(t);

      expect(find.text("Couldn't save to this device."), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // sheet is still open
      expect(find.byType(NoteEditor), findsNothing);
      expect(notes.existsSync(), isFalse); // no folder, not even the root
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('newNoteBackground'), isNull);

      fail = false;
      await t.tap(find.text('Create'));
      await settle(t);
      expect(find.byType(NoteEditor), findsOneWidget);
      expect(sp.getString('newNoteBackground'), 'lined');
    });

    testWidgets('cancel closes without a note', (t) async {
      await pumpApp(t, noteData: data);
      await settle(t);
      await openFromCard(t);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(notes.existsSync(), isFalse);
    });
  });

  group('note cards', () {
    testWidgets('newest edit first, ties by noteId descending', (t) async {
      seed(_note(1, 'Oldest', at: '2026-10-08T12:00:00.000Z'));
      seed(_note(2, 'TieLow', at: '2026-10-09T12:00:00.000Z'));
      seed(_note(3, 'TieHigh', at: '2026-10-09T12:00:00.000Z'));
      seed(_note(4, 'Newest', at: '2026-10-10T12:00:00.000Z'));
      seedBytes(5, [1, 2, 3]); // unreadable goes last
      await pumpApp(t, noteData: data);
      await settle(t);
      final names = ['Oldest', 'TieLow', 'TieHigh', 'Newest', "Can't open"];
      expect(order(t, names), [
        'Newest',
        'TieHigh',
        'TieLow',
        'Oldest',
        "Can't open",
      ]);
    });

    testWidgets('title, modified date, 3:4 thumbnail', (t) async {
      seed(_note(1, 'Lecture', at: '2026-10-10T12:00:00.000Z'));
      await pumpApp(t, noteData: data);
      await settle(t);
      final date = DateFormat.yMd('en')
          .format(DateTime.parse('2026-10-10T12:00:00.000Z').toLocal());
      expect(find.text(date), findsOneWidget);
      final thumb = find.byType(AspectRatio).first;
      final size = t.getSize(thumb);
      expect(size.width / size.height, closeTo(0.75, 0.001));
    });

    testWidgets('a long title takes two lines then ellipsis', (t) async {
      seed(_note(1, 'Long ' * 15));
      await pumpApp(t, noteData: data);
      await settle(t);
      final text = t.widget<Text>(find.textContaining('Long'));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('a card opens its note', (t) async {
      seed(_note(1, 'Open me'));
      await pumpApp(t, noteData: data);
      await settle(t);
      await t.tap(find.text('Open me'));
      await settle(t);
      expect(find.byType(NoteEditor), findsOneWidget);
    });

    testWidgets('phone width has 2 columns, a tablet more', (t) async {
      for (var i = 1; i <= 6; i++) {
        seed(_note(i, 'N$i', at: '2026-10-1${i}T12:00:00.000Z'));
      }
      Set<double> columns() => {
        for (var i = 1; i <= 6; i++)
          t.getTopLeft(find.text('N$i')).dx.roundToDouble(),
      };
      await pumpApp(t, noteData: data, width: 400);
      await settle(t);
      expect(columns(), hasLength(2));
      await pumpApp(t, noteData: data, width: 700);
      await settle(t);
      expect(columns().length, greaterThanOrEqualTo(3));
    });

    testWidgets('unreadable and newer notes are dimmed and inert', (t) async {
      seedBytes(1, utf8.encode('not gzip'));
      final newer = gzip.encode(
        utf8.encode(jsonEncode({'formatVersion': 2, 'noteId': _id(2)})),
      );
      seedBytes(2, newer);
      seed(_note(3, 'Fine'));
      final before1 = fileOf(1).readAsBytesSync();
      final before2 = fileOf(2).readAsBytesSync();
      await pumpApp(t, noteData: data);
      await settle(t);

      expect(find.text("Can't open"), findsNWidgets(2));
      expect(find.text('Fine'), findsOneWidget);
      final style = t.widget<Text>(find.text("Can't open").first).style!;
      expect(style.color, const Color(0xFFB4B2AC)); // ink-disabled
      await t.tap(find.text("Can't open").first);
      await settle(t);
      expect(find.byType(NoteEditor), findsNothing);
      expect(fileOf(1).readAsBytesSync(), before1);
      expect(fileOf(2).readAsBytesSync(), before2);
    });
  });

  group('accessibility and text size', () {
    testWidgets('card name is the title and its description the date', (
      t,
    ) async {
      final h = t.ensureSemantics();
      seed(_note(1, 'Graphs', at: '2026-10-10T12:00:00.000Z'));
      await pumpApp(t, noteData: data);
      await settle(t);
      final date = DateFormat.yMd('en')
          .format(DateTime.parse('2026-10-10T12:00:00.000Z').toLocal());
      final node = t.getSemantics(find.bySemanticsLabel('Graphs'));
      expect(node.label, 'Graphs');
      // A note that was never uploaded waits to be saved: the state is part
      // of the description (Story 3.15).
      expect(node.value, 'Waiting to save, $date');
      h.dispose();
    });

    testWidgets('the sheet names its route; options report selection', (
      t,
    ) async {
      final h = t.ensureSemantics();
      await pumpApp(t, noteData: data);
      await settle(t);
      await t.tap(find.text('New note'));
      await t.pumpAndSettle();
      final routes = find.semantics.byLabel('New note').evaluate().where((n) {
        final f = n.getSemanticsData().flagsCollection;
        return f.namesRoute && f.scopesRoute;
      });
      expect(routes, isNotEmpty);
      final plain = t
          .getSemantics(find.bySemanticsLabel('Plain'))
          .getSemanticsData()
          .flagsCollection;
      expect(plain.isInMutuallyExclusiveGroup, isTrue);
      expect(plain.isSelected, Tristate.isTrue);
      h.dispose();
    });

    testWidgets('the fab is named, and renamed while open', (t) async {
      final h = t.ensureSemantics();
      await pumpApp(t, noteData: data);
      await settle(t);
      expect(find.bySemanticsLabel('Create new'), findsOneWidget);
      await expandFab(t);
      expect(find.bySemanticsLabel('Close menu'), findsOneWidget);
      h.dispose();
    });

    testWidgets('touch targets are at least 48dp', (t) async {
      seed(_note(1, 'A'));
      await pumpApp(t, noteData: data);
      await settle(t);
      void atLeast48(Finder f) {
        for (final e in f.evaluate()) {
          final s = t.getSize(find.byElementPredicate((x) => x == e));
          expect(s.width, greaterThanOrEqualTo(48));
          expect(s.height, greaterThanOrEqualTo(48));
        }
      }

      atLeast48(find.descendant(of: fab, matching: find.byType(InkWell)));
      await expandFab(t);
      atLeast48(find.descendant(of: fab, matching: find.byType(InkWell)));
      await t.tap(fabPlus);
      await t.pumpAndSettle();
      await t.tap(fabPlus);
      await t.pumpAndSettle();
      await t.tap(fabItem);
      await t.pumpAndSettle();
      for (final label in ['Plain', 'Lined', 'Grid', 'Dot', 'Portrait']) {
        final box = find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        );
        atLeast48(box);
      }
      atLeast48(find.byType(FilledButton));
      atLeast48(find.byType(OutlinedButton));
    });

    testWidgets('large text on a phone does not overflow', (t) async {
      seed(_note(1, 'A fairly long title that wraps ' * 3));
      await pumpApp(t, noteData: data, width: 400, textScale: 2);
      await settle(t);
      expect(t.takeException(), isNull);
      await t.tap(fabPlus);
      await t.pumpAndSettle();
      await t.tap(fabItem);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('shadow token', () {
    test('parses one 8-digit-hex shadow, else no shadow', () {
      final s = kkjShadow('0 2px 12px #22242A29').single;
      expect(s.offset, const Offset(0, 2));
      expect(s.blurRadius, 12);
      expect(s.color, const Color(0x2922242A));
      expect(kkjShadow('0 2px 12px #22242A'), isEmpty);
      expect(kkjShadow('0 2px 12px 1px #22242A29'), isEmpty); // spread
      expect(kkjShadow('0 1px 2px #22242A29, 0 2px 4px #22242A29'), isEmpty);
      expect(kkjShadow(''), isEmpty);
      expect(kkjShadow('none'), isEmpty);
    });
  });

  group('robustness', () {
    Note withEditedAt(Note n, String at) {
      final j = n.copyJson();
      ((j['pages'] as List).first as Map)['editedAt'] = at;
      return Note.parse(j).note!;
    }

    testWidgets('a note without a usable date shows none and sorts after '
        'dated ones', (t) async {
      final h = t.ensureSemantics();
      seed(withEditedAt(_note(1, 'Undated'), 'not a date'));
      seed(_note(2, 'Dated', at: '2000-01-01T12:00:00.000Z'));
      seedBytes(3, [1, 2, 3]);
      await pumpApp(t, noteData: data);
      await settle(t);
      expect(t.takeException(), isNull);
      expect(find.text('1/1/2000'), findsOneWidget);
      // Only the dated card has a date text.
      expect(find.textContaining(RegExp(r'\d+/\d+/\d+')), findsOneWidget);
      expect(
        t.getSemantics(find.bySemanticsLabel('Undated')).value,
        'Waiting to save', // the state only: there is no date
      );
      expect(order(t, ['Dated', 'Undated', "Can't open"]), [
        'Dated',
        'Undated',
        "Can't open",
      ]);
      h.dispose();
    });

    testWidgets('a failed listing shows an error card with retry, not the '
        'new-note card', (t) async {
      var fail = true;
      final store = NoteStore(
        NoteData(() async {
          if (fail) throw const FileSystemException('denied');
          return docs;
        }),
      );
      await pumpApp(t, noteData: data, noteStore: store);
      await settle(t);
      expect(find.text("Couldn't load your notes"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('New note'), findsNothing);

      fail = false;
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text("Couldn't load your notes"), findsNothing);
      expect(find.text('New note'), findsOneWidget);
    });

    testWidgets('a second tap does not open a second editor', (t) async {
      seed(_note(1, 'Once'));
      await pumpApp(t, noteData: data);
      await settle(t);
      final c = t.getCenter(find.text('Once'));
      await t.tapAt(c);
      await t.tapAt(c);
      await settle(t);
      expect(find.byType(NoteEditor, skipOffstage: false), findsOneWidget);
    });

    testWidgets('a second tap does not open a second sheet', (t) async {
      await pumpApp(t, noteData: data);
      await settle(t);
      final c = t.getCenter(find.text('New note'));
      await t.tapAt(c);
      await t.tapAt(c);
      await t.pumpAndSettle();
      expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
    });

    testWidgets('the sheet cannot be dragged away', (t) async {
      await pumpApp(t, noteData: data);
      await settle(t);
      await t.tap(find.text('New note'));
      await t.pumpAndSettle();
      await t.fling(find.text('Create'), const Offset(0, 600), 2000);
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('header and sessions', () {
    testWidgets('phone header clears the menu button; wider is unshifted', (
      t,
    ) async {
      await pumpApp(t, noteData: data, width: 400);
      await settle(t);
      expect(
        t.getTopLeft(find.text('Library')).dx,
        greaterThanOrEqualTo(t.getRect(find.byTooltip('Open menu')).right),
      );
      await pumpApp(t, noteData: data, width: 900);
      await settle(t);
      expect(t.getTopLeft(find.text('Library')).dx, 240 + 24);
      await pumpApp(t, noteData: data, width: 700);
      await settle(t);
      // Rail: 8 padding + 48 button + 8 padding, then the 24 content gutter.
      expect(t.getTopLeft(find.text('Library')).dx, 64 + 24);
    });

    Future<void> signInAgain(WidgetTester t) async {
      await t.tap(find.text('Sign in with Google'));
      await t.pumpAndSettle();
      await settle(t);
    }

    testWidgets('log out then sign in reads the folder again', (t) async {
      seed(_note(1, 'Before'));
      await pumpApp(
        t,
        noteData: data,
        auth: FakeAuthGateway(restored: true),
        prefs: {'language': 'en'},
      );
      await settle(t);
      expect(find.text('Before'), findsOneWidget);
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('Log out'));
      await t.pumpAndSettle();
      // Changed while signed out.
      fileOf(1).parent.deleteSync(recursive: true);
      seed(_note(2, 'After'));
      await signInAgain(t);
      expect(find.text('Before'), findsNothing);
      expect(find.text('After'), findsOneWidget);
    });

    testWidgets('disconnect then sign in shows the empty library', (t) async {
      seed(_note(1, 'Gone'));
      await pumpApp(
        t,
        noteData: data,
        auth: FakeAuthGateway(restored: true),
        prefs: {'language': 'en'},
      );
      await settle(t);
      expect(find.text('Gone'), findsOneWidget);
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('Disconnect'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Disconnect'));
      await settle(t);
      await signInAgain(t);
      expect(find.text('Gone'), findsNothing);
      expect(find.text('New note'), findsOneWidget);
    });
  });
}
