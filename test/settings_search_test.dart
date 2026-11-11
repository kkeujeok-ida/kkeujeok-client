import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/settings.dart';

import 'fake_auth_gateway.dart';

// Story 27.4: settings search (filter, counts, no results, clear restores).
void main() {
  Future<void> pump(WidgetTester t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(900, 700);
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> type(WidgetTester t, String q) async {
    if (find.byType(TextField).evaluate().isEmpty) {
      await t.tap(find.byTooltip('Search settings')); // one icon until opened
      await t.pumpAndSettle();
    }
    await t.enterText(find.byType(TextField), q);
    await t.pumpAndSettle();
  }

  testWidgets('filters items, shows counts, hides empty sections', (t) async {
    await pump(t);
    await type(t, 'pressure');
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Input and writing (1)'), findsOneWidget);
    expect(find.text('General (0)'), findsNothing);
    expect(find.text('Language'), findsNothing); // hidden, mounted offstage
    expect(find.text('Language', skipOffstage: false), findsOneWidget);
    expect(find.text('Pressure curve'), findsWidgets);
  });

  testWidgets('no match shows no results', (t) async {
    await pump(t);
    await type(t, 'zzz');
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('clear restores everything and the scroll position', (t) async {
    await pump(t);
    final scroll = find.byType(SingleChildScrollView).at(1);
    await t.drag(scroll, const Offset(0, -300));
    await t.pumpAndSettle();
    final before = t.widget<SingleChildScrollView>(scroll).controller!.offset;
    expect(before, greaterThan(0));
    await type(t, 'zzz');
    await t.tap(find.byTooltip('Clear search'));
    await t.pumpAndSettle();
    expect(find.text('No results'), findsNothing);
    expect(find.text('General'), findsWidgets);
    expect(t.widget<SingleChildScrollView>(scroll).controller!.offset, before);
  });

  testWidgets('blank query shows all, no counts', (t) async {
    await pump(t);
    await type(t, '  ');
    expect(find.text('No results'), findsNothing);
    expect(find.textContaining('result'), findsNothing);
  });

  testWidgets('no Divider under a heading when the first item is hidden', (
    t,
  ) async {
    await pump(t);
    await type(t, 'theme'); // general: language hidden, theme shown
    final dividers = find.byType(Divider);
    expect(dividers, findsNothing);
  });
}
