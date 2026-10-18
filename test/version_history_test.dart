// Story 3.24: the version history screen (states, tags, previews, two-step
// restore, semantics) over a fake Drive, and the flow from the editor menu.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/model/ids.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/note_receiver.dart' show ReceiveState;
import 'package:kkeujeok/sync/version_history.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/version_history.dart';

import 'fake_receiver.dart';
import 'shell_test.dart' show pumpApp;
import 'upload_env.dart';

Map<String, dynamic> _stroke(int n) => {
  'id': '01926f3a-0000-7000-8000-0000000005${n.toString().padLeft(2, '0')}',
  'type': 'stroke',
  'tool': 'pen',
  'color': '#000000',
  'width': 2,
  'usePressure': false,
  'points': [
    [10 + n, 10, 0.5, 0],
    [60 + n, 80, 0.5, 5],
  ],
};

/// A one-page note with [strokes] strokes; [rev] is the page rev.
Note _note(int rev, {int strokes = 1, String by = 'Pixel 8'}) {
  final j = makeNote(rev: rev).copyJson();
  final p = (j['pages'] as List).first as Map<String, dynamic>;
  p['elements'] = [for (var i = 0; i < strokes; i++) _stroke(i)];
  p['editedBy'] = by;
  return Note.trusted(j);
}

String _fmt(String utc) =>
    DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(utc).toLocal());

void main() {
  late UploadEnv env;
  late List<Map<String, Object?>> restored;
  late RestoreFailure? answer;
  var online = true;

  setUp(() {
    _result = null;
    restored = [];
    answer = null;
    online = true;
  });

  Future<void> settle(WidgetTester t) async {
    var idle = 0;
    for (var i = 0; i < 1000 && idle < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
      idle = t.binding.hasScheduledFrame ? 0 : idle + 1;
    }
    await t.pumpAndSettle();
  }

  /// R1 (one stroke, Pixel 8), R2 (two strokes, Galaxy Tab) = head.
  Future<void> history(WidgetTester t, {bool second = true}) async {
    await t.runAsync(() async {
      env = await UploadEnv.create();
      final up = env.uploader();
      await env.save(_note(1));
      await up.upload(noteId);
      if (second) {
        await env.save(_note(2, strokes: 2, by: 'Galaxy Tab'));
        await up.upload(noteId);
      }
    });
  }

  Future<void> show(
    WidgetTester t, {
    Locale locale = const Locale('en'),
    double width = 400,
    bool route = false,
    bool? pushed,
  }) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Future<RestoreFailure?> onRestore(Map<String, Object?> e, String f) async {
      restored.add(e);
      return answer;
    }

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          noteStoreProvider.overrideWithValue(env.store),
          driveClientProvider.overrideWithValue(env.drive),
          networkProbeProvider.overrideWithValue(() async => online),
          uploadsAllowedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: route
              ? Builder(
                  builder: (context) => TextButton(
                    onPressed: () async => _result = await showVersionHistory(
                      context,
                      noteId: noteId,
                      onRestore: onRestore,
                    ),
                    child: const Text('open'),
                  ),
                )
              : VersionHistoryScreen(noteId: noteId, onRestore: onRestore),
        ),
      ),
    );
    if (route) {
      await t.tap(find.text('open'));
    }
  }

  Finder restoreButton(String text) =>
      find.widgetWithText(OutlinedButton, text);

  group('states', () {
    testWidgets('placeholders while loading, then the older versions', (
      t,
    ) async {
      final h = t.ensureSemantics();
      await history(t);
      await show(t);
      expect(find.bySemanticsLabel('Loading version history'), findsOneWidget);
      expect(find.text('Restore this version'), findsNothing);
      await settle(t);
      expect(find.bySemanticsLabel('Loading version history'), findsNothing);
      // R2 is the head (current), so one older version is listed.
      expect(find.text('Restore this version'), findsOneWidget);
      h.dispose();
    });

    testWidgets('no older version: the empty text, in ko too', (t) async {
      await history(t, second: false);
      await show(t);
      await settle(t);
      expect(find.text('No earlier versions yet'), findsOneWidget);
      expect(find.text('Restore this version'), findsNothing);
      await show(t, locale: const Locale('ko'));
      await settle(t);
      expect(find.text('아직 이전 버전이 없어요'), findsOneWidget);
    });

    testWidgets('a note never uploaded has no history and no call', (t) async {
      await t.runAsync(() async {
        env = await UploadEnv.create();
        await env.save(_note(1));
      });
      await show(t);
      await settle(t);
      expect(find.text('No earlier versions yet'), findsOneWidget);
      expect(env.drive.calls, isEmpty);
    });

    testWidgets('offline: the message, and Drive is not asked', (t) async {
      await history(t);
      env.drive.calls.clear();
      online = false;
      await show(t);
      await settle(t);
      expect(
        find.text('Version history is available once you are connected.'),
        findsOneWidget,
      );
      expect(env.drive.calls, isEmpty);
      await show(t, locale: const Locale('ko'));
      await settle(t);
      expect(find.text('연결되면 버전 기록을 볼 수 있어요.'), findsOneWidget);
    });

    testWidgets('a list that cannot be read: message and try again', (t) async {
      await history(t);
      env.drive.failures['revisions'] = [const DriveError('network')];
      await show(t);
      await settle(t);
      expect(find.text('Could not load the version history.'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('Restore this version'), findsOneWidget);
    });
  });

  group('items', () {
    testWidgets('time, device, preview, and the TalkBack name', (t) async {
      final h = t.ensureSemantics();
      await history(t);
      final r1 = env.note.revisions.first;
      await show(t);
      await settle(t);
      final label = '${_fmt(r1.modifiedTime)}, Pixel 8';
      expect(find.text(_fmt(r1.modifiedTime)), findsOneWidget);
      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);
      // The preview is the page, drawn.
      final painters = [
        for (final c in find.byType(CustomPaint).evaluate())
          if ((c.widget as CustomPaint).painter is PagePainter)
            (c.widget as CustomPaint).painter as PagePainter,
      ];
      expect(painters.single.page['elements'], hasLength(1));
      h.dispose();
    });

    testWidgets('"before restore" for a pinned revision, conflict tag for a '
        'sidecar, newest first; the semantic name has them', (t) async {
      final h = t.ensureSemantics();
      await history(t);
      env.note.revisions.first.keepForever = true;
      final folder = env.drive.seed(name: noteId, kkeujeokId: 'cf:$noteId');
      final page = _note(5, by: 'Galaxy Tab').pages.first;
      final sc = env.drive.seed(
        name: 'x.json',
        kkeujeokId: 'sc:$noteId:${page['id']}:${page['rev']}',
        parents: [folder.id],
      );
      final nowTs = canonicalNow(DateTime.now());
      sc.appProperties.addAll({
        'kkjEdited': '${page['editedAt']}',
        'kkjIndex': '0',
        'kkjResolved': nowTs,
      });
      env.drive.foreignRevision(
        sc,
        utf8.encode(
          jsonEncode({
            'noteId': noteId,
            'pageId': page['id'],
            'rev': page['rev'],
            'seq': 1,
            'editedAt': page['editedAt'],
            'editedBy': 'Galaxy Tab',
            'kind': 'bothEdited',
            'page': page,
          }),
        ),
      );
      await show(t);
      await settle(t);
      expect(find.text('Before restore'), findsOneWidget);
      expect(find.text('Version kept from a conflict'), findsOneWidget);
      final r1 = env.note.revisions.first;
      expect(
        find.bySemanticsLabel(
          '${_fmt(r1.modifiedTime)}, Pixel 8, Before restore',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '${_fmt('${page['editedAt']}')}, Galaxy Tab, Version kept from a conflict',
        ),
        findsOneWidget,
      );
      // The sidecar (edited 2000, a real clock) comes after the revision.
      final tops = [
        t.getTopLeft(find.text('Before restore')).dy,
        t.getTopLeft(find.text('Version kept from a conflict')).dy,
      ];
      expect(tops[0], lessThan(tops[1]));
      h.dispose();
    });

    testWidgets('a purged revision: placeholder, restore disabled', (t) async {
      await history(t);
      env.drive.failures['media'] = [
        const DriveError('http', status: 404, reason: 'notFound'),
      ];
      await show(t);
      await settle(t);
      expect(find.text('Preview unavailable'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(restoreButton('Restore this version'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('an unreadable revision: the same, nothing thrown', (t) async {
      await history(t);
      env.note.revisions.first.bytes
        ..clear()
        ..addAll([1, 2, 3]);
      await show(t);
      await settle(t);
      expect(find.text('Preview unavailable'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(restoreButton('Restore this version'))
            .onPressed,
        isNull,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('a download that fails keeps the restore possible', (t) async {
      await history(t);
      env.drive.failures['media'] = [const DriveError('network')];
      await show(t);
      await settle(t);
      expect(find.text('Preview unavailable'), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(restoreButton('Restore this version'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('48 dp targets and the route is named', (t) async {
      final h = t.ensureSemantics();
      await history(t);
      await show(t);
      await settle(t);
      expect(
        t.getSize(restoreButton('Restore this version')).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        t
            .getSize(find.widgetWithIcon(IconButton, Icons.arrow_back))
            .shortestSide,
        greaterThanOrEqualTo(48),
      );
      final route = t.widget<Semantics>(
        find
            .byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.scopesRoute == true &&
                  w.properties.label == 'Version history',
            )
            .first,
      );
      expect(route.properties.namesRoute, isTrue);
      h.dispose();
    });

    testWidgets('ko strings', (t) async {
      await history(t);
      await show(t, locale: const Locale('ko'));
      await settle(t);
      expect(find.text('버전 기록'), findsOneWidget);
      expect(find.text('이 버전으로 복원'), findsOneWidget);
    });
  });

  group('restore', () {
    testWidgets('two taps in place; the second restores and closes', (t) async {
      await history(t);
      await show(t, route: true);
      await settle(t);
      await t.tap(restoreButton('Restore this version'));
      await t.pump();
      expect(restored, isEmpty);
      expect(find.text('Tap again to switch to this version'), findsOneWidget);
      await t.tap(restoreButton('Tap again to switch to this version'));
      await settle(t);
      expect(restored, hasLength(1));
      expect(restored.single['revisionId'], env.note.revisions.first.id);
      expect(find.byType(VersionHistoryScreen), findsNothing);
      expect(_result, isTrue);
    });

    testWidgets('a tap elsewhere takes the question back', (t) async {
      await history(t);
      await show(t);
      await settle(t);
      await t.tap(restoreButton('Restore this version'));
      await t.pump();
      expect(find.text('Tap again to switch to this version'), findsOneWidget);
      await t.tapAt(const Offset(200, 600));
      await t.pump();
      expect(find.text('Restore this version'), findsOneWidget);
      expect(restored, isEmpty);
    });

    testWidgets('a failed restore: message, screen stays, button back', (
      t,
    ) async {
      await history(t);
      answer = RestoreFailure.notSaved;
      await show(t, route: true);
      await settle(t);
      await t.tap(restoreButton('Restore this version'));
      await t.pump();
      await t.tap(restoreButton('Tap again to switch to this version'));
      await settle(t);
      expect(restored, hasLength(1));
      expect(
        find.text(
          'Could not save the current state to Drive, so nothing was restored.',
        ),
        findsOneWidget,
      );
      expect(find.byType(VersionHistoryScreen), findsOneWidget);
      expect(find.text('Restore this version'), findsOneWidget);
      expect(_result, isNull);
    });
  });

  group('failure messages', () {
    for (final (f, text) in <(RestoreFailure, String)>[
      (RestoreFailure.unreadable, 'This version cannot be read.'),
      (
        RestoreFailure.notPinned,
        'Could not mark the version before restore, so nothing was restored.',
      ),
      (RestoreFailure.notApplied, 'Could not restore. Try again in a moment.'),
    ]) {
      testWidgets('$f', (t) async {
        await history(t);
        answer = f;
        await show(t);
        await settle(t);
        await t.tap(restoreButton('Restore this version'));
        await t.pump();
        await t.tap(restoreButton('Tap again to switch to this version'));
        await settle(t);
        expect(find.text(text), findsOneWidget);
      });
    }

    testWidgets('not saved while offline says so', (t) async {
      await history(t);
      answer = RestoreFailure.notSaved;
      await show(t);
      await settle(t);
      await t.tap(restoreButton('Restore this version'));
      await t.pump();
      online = false;
      await t.tap(restoreButton('Tap again to switch to this version'));
      await settle(t);
      expect(
        find.text('You can restore once you are connected.'),
        findsOneWidget,
      );
    });
  });

  group('from the editor', () {
    Future<RecReceiver> openEditor(WidgetTester t, {RecReceiver? rec}) async {
      final r = rec ?? RecReceiver();
      await pumpApp(
        t,
        noteData: env.data,
        noteStore: env.store,
        overrides: [
          driveClientProvider.overrideWithValue(env.drive),
          networkProbeProvider.overrideWithValue(() async => true),
          uploadsAllowedProvider.overrideWithValue(true),
          noteReceiverProvider.overrideWithValue(r),
          backgroundSchedulerProvider.overrideWithValue(() async {}),
        ],
      );
      await settle(t);
      await t.tap(find.text('a'));
      await settle(t);
      return r;
    }

    testWidgets('a whole-note restore frees a conflicted page at once', (
      t,
    ) async {
      await history(t);
      await t.runAsync(
        () => env.store.updateSync(
          noteId,
          (c) => c.copyWith(
            state: SyncState.conflict,
            conflicts: [
              {
                'pageId': pageId,
                'kind': 'bothEdited',
                'rev': 'x1',
                'theirsRev': 'x2',
                'detectedAt': '2026-10-17T00:00:00.000Z',
                'originalIndex': 0,
                'resolvedAt': null,
              },
            ],
          ),
        ),
      );
      await openEditor(t);
      expect(find.text('Resolve'), findsOneWidget); // the banner
      await t.tap(find.byTooltip('More'));
      await settle(t);
      await t.tap(find.text('Version history'));
      await settle(t);
      await t.tap(restoreButton('Restore this version'));
      await t.pump();
      await t.tap(restoreButton('Tap again to switch to this version'));
      await settle(t);
      expect(find.byType(NoteEditor), findsOneWidget);
      expect(find.text('Resolve'), findsNothing);
      final i = (await t.runAsync(() => env.store.readSync(noteId)))!.info;
      expect(i.unresolvedConflicts, isEmpty);
    });

    testWidgets('no [버전 기록] while the note is being received', (t) async {
      await history(t);
      final rec = await openEditor(t);
      await t.tap(find.byTooltip('More'));
      await settle(t);
      Finder item() => find.widgetWithText(MenuItemButton, 'Version history');
      expect(t.widget<MenuItemButton>(item()).onPressed, isNotNull);
      env.drive.calls.clear();
      rec.state.value = ReceiveState(receiving: {noteId});
      await t.pump();
      expect(t.widget<MenuItemButton>(item()).onPressed, isNull);
      expect(env.drive.calls, isEmpty);
    });

    testWidgets('[버전 기록] restores a revision: the note shows it, the '
        'screen is gone, polite notice, uploaded', (t) async {
      final sent = <Map>[];
      t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        (m) async {
          sent.add(m as Map);
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              null,
            ),
      );
      await history(t);
      // The note on the device is the head (two strokes) and in sync.
      expect(env.info.state, SyncState.synced);
      final uploadsBefore = env.drive.uploads.length;
      await pumpApp(
        t,
        noteData: env.data,
        noteStore: env.store,
        overrides: [
          driveClientProvider.overrideWithValue(env.drive),
          networkProbeProvider.overrideWithValue(() async => true),
          uploadsAllowedProvider.overrideWithValue(true),
          noteReceiverProvider.overrideWithValue(RecReceiver()),
          backgroundSchedulerProvider.overrideWithValue(() async {}),
        ],
      );
      await settle(t);
      await t.tap(find.text('a'));
      await settle(t);
      expect(find.byType(NoteEditor), findsOneWidget);

      await t.tap(find.byTooltip('More'));
      await settle(t);
      await t.tap(find.text('Version history'));
      await settle(t);
      expect(find.byType(VersionHistoryScreen), findsOneWidget);
      expect(find.text('Restore this version'), findsOneWidget);

      await t.tap(restoreButton('Restore this version'));
      await t.pump();
      await t.tap(restoreButton('Tap again to switch to this version'));
      await settle(t);

      expect(find.byType(VersionHistoryScreen), findsNothing);
      expect(find.byType(NoteEditor), findsOneWidget);
      final onDisk = (await t.runAsync(() => env.store.read(noteId)))!.note!;
      expect(onDisk.pages.first['elements'], hasLength(1)); // R1's strokes
      final painted = [
        for (final c
            in find
                .descendant(
                  of: find.byType(NoteEditor),
                  matching: find.byType(CustomPaint),
                )
                .evaluate())
          if ((c.widget as CustomPaint).painter is PagePainter)
            ((c.widget as CustomPaint).painter as PagePainter).page,
      ];
      expect(painted.single['elements'], hasLength(1));
      expect(
        sent.where(
          (m) =>
              m['type'] == 'announce' &&
              (m['data'] as Map)['message'] == 'Restored this version' &&
              (m['data'] as Map)['assertiveness'] == null,
        ),
        hasLength(1),
      );
      // "복원 전" is pinned and the restored note went up.
      expect(env.note.revisions.where((r) => r.keepForever), hasLength(1));
      expect(env.drive.uploads.length, greaterThan(uploadsBefore));
      expect(noteOf(env.note.bytes)!.pages.first['elements'], hasLength(1));
    });
  });
}

bool? _result;
