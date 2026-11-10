import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/settings.dart';

import 'fake_auth_gateway.dart';

// Story 27.2: category sidebar (wide) / chip row (narrow), tap-to-scroll, spy.
void main() {
  Future<void> pump(WidgetTester t, double w, {double h = 700}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(w, h);
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

  Finder entry(String name) => find.bySemanticsLabel(name);
  bool selected(WidgetTester t, String name) => t
      .getSemantics(entry(name).first)
      .getSemanticsData()
      .hasFlag(SemanticsFlag.isSelected);

  testWidgets('wide, signed out: sidebar of 4; tap scrolls and highlights', (
    t,
  ) async {
    final h = t.ensureSemantics();
    await pump(t, 900);
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.text('Account'), findsNothing);
    expect(selected(t, 'General'), isTrue);
    final heading = find.text('Tools').last; // main-area heading
    await t.tap(find.text('Tools').first);
    await t.pumpAndSettle();
    expect(selected(t, 'Tools'), isTrue);
    expect(selected(t, 'General'), isFalse);
    final top = t.getTopLeft(heading).dy;
    expect(top, lessThan(56 + 72 + 40)); // under the app bar and search field
    h.dispose();
  });

  testWidgets('scrolling moves the highlight; end = last section', (t) async {
    final h = t.ensureSemantics();
    await pump(t, 900);
    await t.drag(
      find.byType(SingleChildScrollView).at(1),
      const Offset(0, -5000),
    );
    await t.pumpAndSettle();
    expect(selected(t, 'Help and diagnostics'), isTrue);
    h.dispose();
  });

  testWidgets('narrow: chip row, no sidebar', (t) async {
    final h = t.ensureSemantics();
    await pump(t, 400);
    expect(find.byType(VerticalDivider), findsNothing);
    await t.tap(find.text('Input and writing').first);
    await t.pumpAndSettle();
    expect(selected(t, 'Input and writing'), isTrue);
    h.dispose();
  });

  testWidgets('200% text at 900dp uses the chip row', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(t, 900);
    expect(find.byType(VerticalDivider), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('narrow: last chip brings its heading to the viewport top', (
    t,
  ) async {
    await pump(t, 400);
    final chip = find.text('Help and diagnostics').first;
    await t.ensureVisible(chip); // off-screen in the horizontal row
    await t.tap(chip);
    await t.pumpAndSettle();
    final scroll = find.byType(SingleChildScrollView).at(1);
    final top = t.getTopLeft(scroll).dy;
    final head = t.getTopLeft(find.text('Help and diagnostics').last).dy;
    expect(head - top, lessThan(24 + 8));
  });
}
