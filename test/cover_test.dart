import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/sync/upload_coordinator.dart';
import 'package:kkeujeok/ui/cover_art.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'shell_test.dart' show pumpApp;

/// Records the notes handed to the upload flow; the upload is tested elsewhere.
class _Rec implements UploadCoordinator {
  final closed = <String>[];

  @override
  Future<void> noteClosed(String id) async => closed.add(id);

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

String _id(int n) =>
    '01926f3a-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

Note _note(int n, {String? coverId}) => createNote(
  title: 'Note $n',
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
  coverId: coverId,
).note!;

void main() {
  testWidgets('index lists the three covers in order', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final list = await t.runAsync(() => c.read(coverIndexProvider.future));
    expect(list!.map((e) => e.id), ['linen', 'midnight', 'sage']);
  });

  testWidgets('selected tile reads "Cover, Sage, selected"', (t) async {
    final h = t.ensureSemantics();
    String? picked = 'unset';
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CoverChoice(selected: 'sage', onChanged: (v) => picked = v),
          ),
        ),
      ),
    );
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Cover, Sage, selected'), findsOneWidget);
    expect(find.bySemanticsLabel('Cover, Linen'), findsOneWidget);
    expect(find.bySemanticsLabel('Cover, No cover'), findsOneWidget);
    await t.tap(find.text('Midnight'));
    expect(picked, 'midnight');
    h.dispose();
  });

  testWidgets('setCover sets, removes, ignores same; unknown id is kept', (
    t,
  ) async {
    final docs = Directory.systemTemp.createTempSync('kkj-cover-');
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // temp is cleaned later
      }
    });
    for (final n in [
      for (final n in [1, 2]) _note(n, coverId: n == 2 ? 'future' : null),
    ].indexed) {
      final note = n.$2;
      final f = File(
        '${docs.path}/$noteDataDirName/${note.noteId}/working.kkj',
      );
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(encodeKkj(note));
    }
    final rec = _Rec();
    await pumpApp(
      t,
      noteData: NoteData(() async => docs),
      overrides: [uploadCoordinatorProvider.overrideWithValue(rec)],
      settle: false,
    );
    final scope = ProviderScope.containerOf(
      t.element(find.byType(MaterialApp)),
    );
    for (var i = 0; i < 200 && scope.read(libraryProvider).isLoading; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
    }
    final c = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
    final n = c.read(libraryProvider.notifier);
    Future<T> go<T>(Future<T> f) async {
      T? r;
      var done = false;
      f.then((v) {
        r = v;
        done = true;
      });
      for (var i = 0; i < 300 && !done; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
      }
      expect(done, isTrue, reason: 'did not finish');
      return r as T;
    }

    Future<Note> read(int i) async =>
        (await t.runAsync(() => c.read(noteStoreProvider).read(_id(i))))!.note!;

    final before = (await read(1)).metaRev;
    expect(await go(n.setCover(_id(1), 'sage')), isTrue);
    var a = await read(1);
    expect(a.coverId, 'sage');
    expect(a.metaRev, isNot(before));
    expect(await go(n.setCover(_id(1), 'sage')), isFalse);
    expect((await read(1)).metaRev, a.metaRev);
    await go(n.setCover(_id(1), null));
    a = await read(1);
    expect((a.copyJson()['meta'] as Map).containsKey('coverId'), isFalse);
    // A cover this app does not know is not drawn as a cover, not erased.
    expect((await read(2)).coverId, 'future');
    expect(
      (await t.runAsync(() => c.read(coverIndexProvider.future)))!
          .any((e) => e.id == 'future'),
      isFalse,
    );
    expect(rec.closed, [_id(1), _id(1)]); // set and remove each upload
    // An invalid id is refused and changes nothing.
    final r = await go(
      n.setCover(_id(1), '').then((_) => 'ok', onError: (_) => 'refused'),
    );
    expect(r, 'refused');
  });
}
