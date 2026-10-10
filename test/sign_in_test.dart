import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_gateway.dart';
import 'shell_test.dart' show pumpApp;

const deniedBody =
    'To save notes in the Kkeujeok folder of your Google Drive, you need to '
    'allow access. Kkeujeok can only see files it created.';

void main() {
  void expectSignIn() {
    expect(find.text('Kkeujeok'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(
      find.text(
        'Your notes are saved in the Kkeujeok folder of your Google Drive',
      ),
      findsOneWidget,
    );
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.byTooltip('Open menu'), findsNothing);
  }

  testWidgets('first run shows only the sign-in screen', (t) async {
    final g = FakeAuthGateway();
    await pumpApp(t, auth: g);
    expectSignIn();
    expect(g.restoreCalls, 1);
    expect(g.signInCalls, 0);
  });

  testWidgets('copy is Korean on a Korean device', (t) async {
    await pumpApp(t, auth: FakeAuthGateway(), device: const [Locale('ko')]);
    expect(find.text('Google로 로그인'), findsOneWidget);
    expect(find.text('노트는 내 Google Drive의 Kkeujeok 폴더에 저장돼요'), findsOneWidget);
  });

  testWidgets('sign-in then granted opens the shell, storing nothing', (
    t,
  ) async {
    await pumpApp(t, auth: FakeAuthGateway());
    await t.tap(find.text('Sign in with Google'));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  testWidgets('relaunch with earlier consent skips sign-in', (t) async {
    final g = FakeAuthGateway(restored: true);
    await pumpApp(t, auth: g);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);
    expect(g.signInCalls, 0);
  });

  testWidgets('denied blocks entry; request again asks only for access', (
    t,
  ) async {
    final g = FakeAuthGateway(signIns: [AuthOutcome.denied]);
    await pumpApp(t, auth: g);
    await t.tap(find.text('Sign in with Google'));
    await t.pumpAndSettle();
    expect(find.text('Google Drive access was denied.'), findsOneWidget);
    expect(find.text(deniedBody), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    await t.tap(find.text('Request again'));
    await t.pumpAndSettle();
    expect(g.signInCalls, 1);
    expect(g.requestCalls, 1);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('denied again stays blocked', (t) async {
    final g = FakeAuthGateway(
      signIns: [AuthOutcome.denied],
      requests: [AuthOutcome.denied],
    );
    await pumpApp(t, auth: g);
    await t.tap(find.text('Sign in with Google'));
    await t.pumpAndSettle();
    await t.tap(find.text('Request again'));
    await t.pumpAndSettle();
    expect(find.text('Google Drive access was denied.'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('cancelling the account chooser shows no error', (t) async {
    await pumpApp(t, auth: FakeAuthGateway(signIns: [AuthOutcome.cancelled]));
    await t.tap(find.text('Sign in with Google'));
    await t.pumpAndSettle();
    expectSignIn();
    expect(find.text('Google Drive access was denied.'), findsNothing);
    expect(find.text('Check your connection and try again'), findsNothing);
  });

  testWidgets('network error shows retry, which starts over', (t) async {
    final g = FakeAuthGateway(
      signIns: [AuthOutcome.networkError, AuthOutcome.granted],
    );
    await pumpApp(t, auth: g);
    await t.tap(find.text('Sign in with Google'));
    await t.pumpAndSettle();
    expect(find.text('Check your connection and try again'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(g.signInCalls, 2);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('privacy link opens externally; empty URL is disabled', (
    t,
  ) async {
    Uri? opened;
    await pumpApp(
      t,
      auth: FakeAuthGateway(),
      privacyUrl: 'https://example.com/privacy',
      openUrl: (u) async {
        opened = u;
        return true;
      },
    );
    await t.tap(find.text('Privacy policy'));
    await t.pumpAndSettle();
    expect(opened, Uri.parse('https://example.com/privacy'));

    await pumpApp(t, auth: FakeAuthGateway(), openUrl: (_) async => true);
    final button = t.widget<TextButton>(
      find.widgetWithText(TextButton, 'Privacy policy'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('errors are polite live regions; buttons are 48dp', (t) async {
    final handle = t.ensureSemantics();
    await pumpApp(t, auth: FakeAuthGateway(signIns: [AuthOutcome.denied]));
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsNothing);
    await t.tap(find.text('Sign in with Google'));
    await t.pumpAndSettle();
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsOneWidget);
    for (final label in [
      'Sign in with Google',
      'Request again',
      'Privacy policy',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
      final size = t.getSize(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
    }
    handle.dispose();
  });
}
