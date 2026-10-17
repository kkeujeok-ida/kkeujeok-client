// Story 3.21: the resolve sheet itself (layout by width, texts, defaults,
// two-step "rest", later), without an editor behind it.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/design_tokens/build/tokens.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/render/page_painter.dart';
import 'package:kkeujeok/ui/conflict_sheet.dart';

Map<String, dynamic> _stroke(String id, double x) => {
  'id': id,
  'type': 'stroke',
  'tool': 'pen',
  'color': '#000000',
  'width': 2,
  'usePressure': false,
  'points': [
    [x, 10, 0.5, 0],
    [x + 30, 40, 0.5, 5],
  ],
};

Map<String, dynamic> _page(
  String rev,
  List<Map<String, dynamic>> els, {
  String at = '2026-10-17T01:00:00.000Z',
  String by = 'Pixel 8',
}) => {
  'id': 'p',
  'rev': rev,
  'seq': 1,
  'width': 200,
  'height': 280,
  'background': 'plain',
  'elements': els,
  'editedAt': at,
  'editedBy': by,
};

ConflictItem _both(
  int index, {
  String id = 'p1',
  DateTime? otherTime,
  List<Map<String, dynamic>>? mine,
  List<Map<String, dynamic>>? theirs,
  String mineAt = '2026-10-17T01:00:00.000Z',
  String theirsAt = '2026-10-17T02:00:00.000Z',
}) => ConflictItem(
  entry: {
    'pageId': id,
    'kind': 'bothEdited',
    'rev': 'a$index',
    'theirsRev': 'b$index',
    'originalIndex': index,
    'resolvedAt': null,
  },
  sidecar: {
    'pageId': id,
    'rev': 'a$index',
    'editedAt': mineAt,
    'editedBy': 'Pixel 8',
    'page': _page('a$index', mine ?? [_stroke('s1', 10)], at: mineAt),
  },
  current: _page(
    'b$index',
    theirs ?? [_stroke('s1', 10), _stroke('s2', 60)],
    at: theirsAt,
    by: 'Galaxy Tab',
  ),
  otherTime: otherTime,
);

ConflictItem _deleted(int index, String kind, {String id = 'd1'}) =>
    ConflictItem(
      entry: {
        'pageId': id,
        'kind': kind,
        'rev': 'a$index',
        'theirsRev': kind == 'remoteDeleted' ? null : 'b$index',
        'originalIndex': index,
        'resolvedAt': null,
      },
      sidecar: {
        'pageId': id,
        'rev': 'a$index',
        'editedAt': '2026-10-17T01:00:00.000Z',
        'editedBy': 'Pixel 8',
        'page': _page('a$index', [_stroke('s1', 10)]),
      },
      current: kind == 'remoteDeleted' ? null : _page('b$index', const []),
    );

void main() {
  late List<List<(ConflictItem, String)>> calls;
  late bool? result;
  Set<String>? Function(List<(ConflictItem, String)>) answer = (c) => {
    for (final x in c) x.$1.pageId,
  };

  Future<void> show(
    WidgetTester t,
    List<ConflictItem> items, {
    double width = 900,
    Locale locale = const Locale('en'),
  }) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    calls = [];
    result = null;
    await t.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showConflictSheet(
                c,
                items: items,
                onResolve: (choices) async {
                  calls.add(choices);
                  return answer(choices) ?? {};
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  setUp(() => answer = (c) => {for (final x in c) x.$1.pageId});

  group('layout by width', () {
    testWidgets('>= 840: centered dialog with the sheet scrim', (t) async {
      await show(t, [_both(2)]);
      expect(find.byType(Dialog), findsOneWidget);
      final barrier = t.widget<ModalBarrier>(find.byType(ModalBarrier).last);
      expect(barrier.color, KkjLight.componentsConflictSheetScrim);
      // Side by side: the two tags are on one row.
      final a = t.getTopLeft(find.text('This device').first);
      final b = t.getTopLeft(find.text('Other device').first);
      expect(a.dy, b.dy);
      expect(a.dx, lessThan(b.dx));
    });

    testWidgets('600-839: bottom sheet, side by side', (t) async {
      await show(t, [_both(2)], width: 700);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      final a = t.getTopLeft(find.text('This device').first);
      final b = t.getTopLeft(find.text('Other device').first);
      expect(a.dy, b.dy);
    });

    testWidgets('< 600: bottom sheet, previews stacked, this device first', (
      t,
    ) async {
      await show(t, [_both(2)], width: 400);
      expect(find.byType(BottomSheet), findsOneWidget);
      final a = t.getTopLeft(find.text('This device').first);
      final b = t.getTopLeft(find.text('Other device').first);
      expect(a.dx, b.dx);
      expect(a.dy, lessThan(b.dy));
    });
  });

  group('a page edited on both devices', () {
    testWidgets('en: texts, tags, buttons, default focus on keep both', (
      t,
    ) async {
      final h = t.ensureSemantics();
      await show(t, [_both(2), _both(4, id: 'p2')]);
      expect(find.text('Pages edited on both devices'), findsOneWidget);
      expect(find.text('Page 3 · 1/2'), findsOneWidget);
      expect(find.text('Which one do you want to keep?'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Other device'), findsOneWidget);
      expect(find.textContaining('Pixel 8 · '), findsOneWidget);
      expect(find.textContaining('Galaxy Tab · '), findsOneWidget);
      expect(find.text('This device version'), findsOneWidget);
      expect(find.text('Other device version'), findsOneWidget);
      expect(find.text('Keep both'), findsOneWidget);
      expect(
        find.text(
          'The version you do not keep can be restored from version '
          'history for 30 days.',
        ),
        findsOneWidget,
      );
      expect(find.text('Decide later'), findsOneWidget);
      // The primary button holds the focus.
      final both = find.widgetWithText(FilledButton, 'Keep both');
      expect(t.widget<FilledButton>(both).focusNode!.hasFocus, isTrue);
      expect(
        t.widget<FilledButton>(both).style!.backgroundColor!.resolve({}),
        KkjLight.componentsConflictSheetPrimaryBackground,
      );
      // Touch targets and the pane title.
      for (final f in [
        both,
        find.widgetWithText(OutlinedButton, 'This device version'),
        find.widgetWithText(OutlinedButton, 'Other device version'),
        find.widgetWithText(TextButton, 'Decide later'),
      ]) {
        expect(t.getSize(f).height, greaterThanOrEqualTo(48));
      }
      expect(
        find.bySemanticsLabel('Pages edited on both devices'),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(RegExp('This device version of page 3')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Other device version of page 3')),
        findsOneWidget,
      );
      h.dispose();
    });

    testWidgets('ko texts', (t) async {
      await show(t, [_both(2), _both(4, id: 'p2')], locale: const Locale('ko'));
      expect(find.text('두 기기에서 고친 페이지가 있어요'), findsOneWidget);
      expect(find.text('3페이지 · 1/2'), findsOneWidget);
      expect(find.text('어느 쪽을 남길까요?'), findsOneWidget);
      expect(find.text('이 기기'), findsOneWidget);
      expect(find.text('다른 기기'), findsOneWidget);
      expect(find.text('이 기기 버전'), findsOneWidget);
      expect(find.text('다른 기기 버전'), findsOneWidget);
      expect(find.text('둘 다 남기기'), findsOneWidget);
      expect(find.text('고르지 않은 버전은 30일 동안 버전 기록에서 되살릴 수 있어요.'), findsOneWidget);
      expect(find.text('나중에 결정'), findsOneWidget);
      expect(find.text('나머지 모두 이 기기 버전'), findsOneWidget);
    });

    testWidgets('"more recent" is on the later side, by the Drive time', (
      t,
    ) async {
      // Page times say the other device is later; the Drive time says this
      // device is.
      await show(t, [_both(2, otherTime: DateTime.utc(2026, 10, 17, 0, 30))]);
      expect(find.text('Newer'), findsOneWidget);
      final newer = t.getTopLeft(find.text('Newer'));
      final thisTag = t.getTopLeft(find.text('This device').first);
      final otherTag = t.getTopLeft(find.text('Other device').first);
      expect(
        (newer.dx - thisTag.dx).abs(),
        lessThan((newer.dx - otherTag.dx).abs()),
      );
    });

    testWidgets('offline: the page time is used', (t) async {
      await show(t, [_both(2)]);
      final newer = t.getTopLeft(find.text('Newer'));
      final thisTag = t.getTopLeft(find.text('This device').first);
      final otherTag = t.getTopLeft(find.text('Other device').first);
      expect(
        (newer.dx - otherTag.dx).abs(),
        lessThan((newer.dx - thisTag.dx).abs()),
      );
    });

    testWidgets('each choice maps to its resolve choice', (t) async {
      for (final (label, choice) in [
        ('This device version', 'mine'),
        ('Other device version', 'theirs'),
        ('Keep both', 'both'),
      ]) {
        await show(t, [_both(2)]);
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        expect(calls.single.single.$2, choice);
        expect(result, isTrue); // the only conflict: the sheet closed
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(Dialog), findsNothing);
      }
    });

    testWidgets('the next conflict comes up, the last closes the sheet', (
      t,
    ) async {
      await show(t, [_both(2), _both(4, id: 'p2')]);
      await t.tap(find.text('Keep both'));
      await t.pumpAndSettle();
      expect(find.text('Page 5 · 1/1'), findsOneWidget);
      expect(result, isNull);
      expect(find.text('Rest: all this device version'), findsNothing);
      await t.tap(find.text('Keep both'));
      await t.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('a failed choice keeps the sheet and says so', (t) async {
      answer = (_) => <String>{};
      await show(t, [_both(2)]);
      await t.tap(find.text('Keep both'));
      await t.pumpAndSettle();
      expect(find.text('Could not resolve. Try again.'), findsOneWidget);
      expect(find.text('Keep both'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('arrows move between conflicts', (t) async {
      await show(t, [_both(2), _both(4, id: 'p2')]);
      expect(
        t
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.byTooltip('Next page'));
      await t.pumpAndSettle();
      expect(find.text('Page 5 · 2/2'), findsOneWidget);
      await t.tap(find.byTooltip('Previous page'));
      await t.pumpAndSettle();
      expect(find.text('Page 3 · 1/2'), findsOneWidget);
    });

    testWidgets('the changed range is outlined on the side that has it', (
      t,
    ) async {
      await show(t, [_both(2)]);
      // Only the other device's page has s2.
      final outlines = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_OutlinePainter',
      );
      expect(outlines, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet).evaluate().isEmpty
              ? find.byType(Dialog)
              : find.byType(BottomSheet),
          matching: outlines,
        ),
        findsOneWidget,
      );
    });

    test('changedRange: ids absent from the other version, by id', () {
      final a = _page('x', [_stroke('s1', 10), _stroke('s2', 60)]);
      final b = _page('y', [_stroke('s1', 10)]);
      expect(changedRange(b, a), isNull);
      final r = changedRange(a, b)!;
      expect(r.left, closeTo(59, 0.01));
      expect(r.right, closeTo(91, 0.01));
      expect(changedRange(a, null), isNotNull);
    });
  });

  group('a page one side deleted', () {
    testWidgets('remoteDeleted: placeholder on the other side, keep is '
        'primary and focused', (t) async {
      await show(t, [_deleted(0, 'remoteDeleted')]);
      expect(find.text('Page deleted on another device'), findsOneWidget);
      expect(find.text('Delete page'), findsOneWidget);
      expect(find.text('Keep this version'), findsOneWidget);
      expect(find.text('Keep both'), findsNothing);
      expect(find.text('Newer'), findsNothing);
      final keep = find.widgetWithText(FilledButton, 'Keep this version');
      expect(t.widget<FilledButton>(keep).focusNode!.hasFocus, isTrue);
      // The kept version is under this device's preview, the delete button
      // under the placeholder.
      expect(
        t.getTopLeft(find.text('Keep this version')).dx,
        lessThan(t.getTopLeft(find.text('Delete page')).dx),
      );
      await t.tap(find.text('Delete page'));
      await t.pumpAndSettle();
      expect(calls.single.single.$2, 'remove');
    });

    testWidgets('localDeleted: placeholder on this side', (t) async {
      await show(t, [_deleted(0, 'localDeleted')]);
      expect(find.text('Page deleted on this device'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Delete page')).dx,
        lessThan(t.getTopLeft(find.text('Keep this version')).dx),
      );
      await t.tap(find.text('Keep this version'));
      await t.pumpAndSettle();
      expect(calls.single.single.$2, 'keep');
    });

    testWidgets('ko placeholders and buttons', (t) async {
      await show(t, [_deleted(0, 'remoteDeleted')], locale: const Locale('ko'));
      expect(find.text('다른 기기에서 지운 페이지'), findsOneWidget);
      expect(find.text('페이지 지우기'), findsOneWidget);
      expect(find.text('이 버전 남기기'), findsOneWidget);
    });
  });

  group('the rest, in two steps', () {
    testWidgets('first tap asks, second applies to all that are left; deleted '
        'pages follow the side', (t) async {
      final items = [
        _both(0),
        _deleted(1, 'remoteDeleted', id: 'd1'),
        _deleted(2, 'localDeleted', id: 'd2'),
      ];
      await show(t, items);
      await t.tap(find.text('Rest: all this device version'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('Tap again to apply to 3 pages'), findsOneWidget);
      expect(find.text('Rest: all this device version'), findsNothing);
      await t.tap(find.text('Tap again to apply to 3 pages'));
      await t.pumpAndSettle();
      expect([for (final c in calls.single) c.$2], ['mine', 'keep', 'remove']);
      expect(result, isTrue);
    });

    testWidgets('the other device version: deleted on the other side removes', (
      t,
    ) async {
      await show(t, [_both(0), _deleted(1, 'remoteDeleted', id: 'd1')]);
      await t.tap(find.text('Rest: all other device version'));
      await t.pump();
      await t.tap(find.text('Tap again to apply to 2 pages'));
      await t.pumpAndSettle();
      expect([for (final c in calls.single) c.$2], ['theirs', 'remove']);
    });

    testWidgets('a tap elsewhere takes the question back', (t) async {
      await show(t, [_both(0), _both(1, id: 'p2')]);
      await t.tap(find.text('Rest: all this device version'));
      await t.pump();
      expect(find.text('Tap again to apply to 2 pages'), findsOneWidget);
      await t.tap(find.text('Which one do you want to keep?'));
      await t.pump();
      expect(find.text('Tap again to apply to 2 pages'), findsNothing);
      expect(find.text('Rest: all this device version'), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('switching to the other rest button asks again', (t) async {
      await show(t, [_both(0), _both(1, id: 'p2')]);
      await t.tap(find.text('Rest: all this device version'));
      await t.pump();
      await t.tap(find.text('Rest: all other device version'));
      await t.pump();
      expect(calls, isEmpty);
      expect(find.text('Tap again to apply to 2 pages'), findsOneWidget);
    });

    testWidgets('one conflict: no rest buttons', (t) async {
      await show(t, [_both(0)]);
      expect(find.textContaining('Rest:'), findsNothing);
    });

    testWidgets('ko: rest and confirm', (t) async {
      await show(t, [_both(0), _both(1, id: 'p2')], locale: const Locale('ko'));
      await t.tap(find.text('나머지 모두 다른 기기 버전'));
      await t.pump();
      expect(find.text('한 번 더 누르면 2페이지에 적용돼요'), findsOneWidget);
    });
  });

  group('later', () {
    testWidgets('closes without choosing', (t) async {
      await show(t, [_both(0)]);
      await t.tap(find.text('Decide later'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      expect(result, isFalse);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('back closes without choosing', (t) async {
      await show(t, [_both(0)]);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      expect(result, isFalse);
      expect(find.byType(Dialog), findsNothing);
    });
  });

  testWidgets('previews have their own outline cache and follow the page', (
    t,
  ) async {
    await show(t, [_both(0)]);
    final painters = [
      for (final w in t.widgetList<CustomPaint>(find.byType(CustomPaint)))
        if (w.painter is PagePainter) w.painter as PagePainter,
    ];
    expect(painters, hasLength(2));
    expect(identical(painters[0].cache, painters[1].cache), isFalse);
    expect(painters[0].viewport, isNull); // fitted to the preview
  });
}
