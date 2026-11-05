import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/ui/help_screen.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/settings.dart';
import 'package:kkeujeok/ui/sign_in.dart';

import 'fake_auth_gateway.dart';

// Story 10.8: UI text at 2.0x on a 320dp phone must not overflow and every
// button must carry a name for TalkBack.
void main() {
  for (final (name, home) in [
    ('settings', const SettingsScreen()),
    ('help', const HelpScreen()),
    ('sign-in', const SignInScreen()),
  ]) {
    for (final lang in ['en', 'ko']) {
      testWidgets('$name at 2.0x text, 320dp, $lang', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(320, 1600);
        t.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final sem = t.ensureSemantics();
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              authGatewayProvider.overrideWithValue(FakeAuthGateway()),
            ],
            child: MaterialApp(
              locale: Locale(lang),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: home,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        void walk(SemanticsNode n) {
          final d = n.getSemanticsData();
          if (d.hasFlag(SemanticsFlag.isButton)) {
            expect(
              d.label.isNotEmpty || d.tooltip.isNotEmpty,
              isTrue,
              reason: 'unnamed button in $name',
            );
          }
          n.visitChildren((c) {
            walk(c);
            return true;
          });
        }

        walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
        sem.dispose();
      });
    }
  }
}
