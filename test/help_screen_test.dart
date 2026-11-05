import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/settings.dart';

import 'fake_auth_gateway.dart';

void main() {
  for (final (locale, entry, gesture) in [
    ('en', 'Help and gestures', 'Three fingers'),
    ('ko', '도움말·제스처', '손가락 세 개'),
  ]) {
    testWidgets('settings opens the help page in $locale', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(800, 2400);
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [authGatewayProvider.overrideWithValue(FakeAuthGateway())],
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      );
      expect(find.text(gesture), findsNothing); // never opens by itself
      await t.tap(find.text(entry));
      await t.pumpAndSettle();
      expect(find.text(gesture), findsOneWidget);
    });
  }
}
