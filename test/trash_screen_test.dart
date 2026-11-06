import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/library/trash_service.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/trash_screen.dart';

class _Trash implements TrashService {
  _Trash(this.entries);

  List<TrashEntry> entries;
  final purged = <String>[];

  @override
  Future<List<TrashEntry>> list() async => [...entries];

  @override
  Future<TrashOutcome> purge(TrashEntry e) async {
    purged.add(e.id);
    entries = [
      for (final x in entries)
        if (x.id != e.id) x,
    ];
    return TrashOutcome.done;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester t, _Trash svc) => t.pumpWidget(
  ProviderScope(
    overrides: [trashServiceProvider.overrideWithValue(svc)],
    child: const MaterialApp(
      locale: Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TrashScreen(),
    ),
  ),
);

void main() {
  testWidgets('empty trash says so', (t) async {
    await _pump(t, _Trash([]));
    await t.pumpAndSettle();
    expect(find.text('휴지통이 비어 있어요.'), findsOneWidget);
  });

  testWidgets('rows are labelled; purge needs a second tap', (t) async {
    final svc = _Trash([
      const TrashEntry(
        isFolder: false,
        id: 'n1',
        fileId: 'f1',
        title: '필기',
        trashedAt: '2026-10-30T00:00:00.000Z',
      ),
      const TrashEntry(
        isFolder: true,
        id: 'd1',
        fileId: 'f2',
        title: '수업',
        trashedAt: '2026-10-29T00:00:00.000Z',
        noteCount: 3,
      ),
    ]);
    await _pump(t, svc);
    await t.pumpAndSettle();
    expect(find.text('노트 3개 · 2026. 10. 29.'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^필기, 노트, ')), findsOneWidget);

    await t.tap(find.byTooltip('필기 메뉴'));
    await t.pumpAndSettle();
    await t.tap(find.text('영구 삭제'));
    await t.pumpAndSettle();
    expect(svc.purged, isEmpty); // first step only asks
    await t.tap(find.text('한 번 더 누르면 영구 삭제돼요'));
    await t.pumpAndSettle();
    expect(svc.purged, ['n1']);
    expect(find.text('필기'), findsNothing);
  });
}
