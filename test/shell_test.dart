import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/storage/language_store.dart';
import 'package:kkeujeok/storage/new_note_defaults_store.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/ui/app.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_gateway.dart';

Set<String> arbKeys(String lang) {
  final json = jsonDecode(
    File('lib/l10n/app_$lang.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}

Future<LanguageStore> pumpApp(
  WidgetTester tester, {
  double width = 900,
  Map<String, Object> prefs = const {},
  List<Locale> device = const [Locale('en', 'US')],
  String privacyUrl = '',
  Future<bool> Function(Uri)? openUrl,
  AuthGateway? auth,
  NoteData? noteData,
  NoteStore? noteStore,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.localesTestValue = device;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearLocalesTestValue();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final store = LanguageStore(sp);
  final tmp = Directory.systemTemp.createTempSync('kkj-notes-');
  final data = noteData ?? NoteData(() async => tmp);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        languageStoreProvider.overrideWithValue(store),
        // Shell tests start from a signed-in user.
        authGatewayProvider.overrideWithValue(
          auth ?? FakeAuthGateway(restored: true),
        ),
        // Never touch the real documents directory.
        noteDataProvider.overrideWithValue(data),
        if (noteStore != null) noteStoreProvider.overrideWithValue(noteStore),
        newNoteDefaultsStoreProvider.overrideWithValue(
          NewNoteDefaultsStore(sp),
        ),
        privacyUrlProvider.overrideWithValue(privacyUrl),
        if (openUrl != null) urlOpenerProvider.overrideWithValue(openUrl),
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  group('strings', () {
    test('ko and en ARB keys match', () {
      final ko = arbKeys('ko'), en = arbKeys('en');
      expect(
        en.difference(ko),
        isEmpty,
        reason: 'keys missing from app_ko.arb: ${en.difference(ko)}',
      );
      expect(
        ko.difference(en),
        isEmpty,
        reason: 'keys missing from app_en.arb: ${ko.difference(en)}',
      );
    });
  });

  group('language decision', () {
    test('first run follows the device: ko -> ko, anything else -> en', () {
      expect(
        resolveLocale(LanguageChoice.system, const [Locale('ko', 'KR')]),
        const Locale('ko'),
      );
      expect(
        resolveLocale(LanguageChoice.system, const [Locale('fr')]),
        const Locale('en'),
      );
      expect(
        resolveLocale(LanguageChoice.system, const []),
        const Locale('en'),
      );
    });

    test('an explicit choice wins over the device', () {
      expect(
        resolveLocale(LanguageChoice.en, const [Locale('ko')]),
        const Locale('en'),
      );
      expect(
        resolveLocale(LanguageChoice.ko, const [Locale('fr')]),
        const Locale('ko'),
      );
    });

    test('store round-trips and defaults to system', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LanguageStore(await SharedPreferences.getInstance());
      expect(store.read(), LanguageChoice.system);
      await store.write(LanguageChoice.en);
      expect(store.read(), LanguageChoice.en);
      SharedPreferences.setMockInitialValues({'language': 'bogus'});
      expect(
        LanguageStore(await SharedPreferences.getInstance()).read(),
        LanguageChoice.system,
      );
    });

    test('a store without preferences does not throw', () async {
      final store = LanguageStore(null);
      await store.write(LanguageChoice.ko);
      expect(store.read(), LanguageChoice.system);
    });
  });

  group('shell', () {
    testWidgets('Korean device shows Korean', (t) async {
      await pumpApp(t, device: const [Locale('ko', 'KR')]);
      expect(find.text('Kkeujeok'), findsOneWidget);
      expect(find.text('설정'), findsOneWidget);
    });

    testWidgets('fr device shows English', (t) async {
      await pumpApp(t, device: const [Locale('fr', 'FR')]);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('840 expanded, 839 collapsed', (t) async {
      await pumpApp(t, width: 840);
      expect(find.text('Kkeujeok'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      await pumpApp(t, width: 839);
      expect(find.text('Kkeujeok'), findsNothing);
      expect(find.byTooltip('Open menu'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('600 collapsed, 599 drawer', (t) async {
      await pumpApp(t, width: 600);
      expect(find.byTooltip('Settings'), findsOneWidget);
      await pumpApp(t, width: 599);
      expect(find.byTooltip('Settings'), findsNothing);
      expect(find.byTooltip('Open menu'), findsOneWidget);
      await t.tap(find.byTooltip('Open menu'));
      await t.pumpAndSettle();
      expect(find.text('Kkeujeok'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('touch targets are at least 48dp', (t) async {
      for (final w in [900.0, 700.0, 500.0]) {
        await pumpApp(t, width: w);
        for (final b in t.widgetList<IconButton>(find.byType(IconButton))) {
          final size = t.getSize(find.byWidget(b));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
      }
      await pumpApp(t, width: 900);
      final size = t.getSize(
        find.ancestor(
          of: find.text('Settings'),
          matching: find.byType(InkWell),
        ),
      );
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('settings', () {
    testWidgets('lists language, privacy, log out and disconnect', (t) async {
      await pumpApp(t);
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Follow system settings'), findsOneWidget);
      expect(find.text('한국어'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('choosing Korean switches at once and is remembered', (
      t,
    ) async {
      final store = await pumpApp(t);
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('한국어'));
      await t.pumpAndSettle();
      expect(find.text('언어'), findsOneWidget);
      expect(store.read(), LanguageChoice.ko);
      // Next run reads the stored choice.
      await pumpApp(t, prefs: {'language': 'ko'});
      expect(find.text('설정'), findsOneWidget);
    });

    testWidgets('back to system follows the device again', (t) async {
      final store = await pumpApp(
        t,
        prefs: {'language': 'en'},
        device: const [Locale('ko')],
      );
      expect(find.text('Settings'), findsOneWidget);
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('Follow system settings'));
      await t.pumpAndSettle();
      expect(store.read(), LanguageChoice.system);
      expect(find.text('언어'), findsOneWidget);
    });

    testWidgets('empty PRIVACY_URL disables the item and says why', (t) async {
      var opened = false;
      await pumpApp(
        t,
        openUrl: (_) async {
          opened = true;
          return true;
        },
      );
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      expect(
        find.text('The privacy policy address is not set.'),
        findsOneWidget,
      );
      await t.tap(find.text('Privacy policy'));
      await t.pumpAndSettle();
      expect(opened, isFalse);
    });

    testWidgets('privacy opens the URL; failure is announced', (t) async {
      Uri? opened;
      var ok = true;
      await pumpApp(
        t,
        privacyUrl: 'https://example.com/privacy',
        openUrl: (u) async {
          opened = u;
          return ok;
        },
      );
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('Privacy policy'));
      await t.pumpAndSettle();
      expect(opened, Uri.parse('https://example.com/privacy'));
      ok = false;
      await t.tap(find.text('Privacy policy'));
      await t.pumpAndSettle();
      expect(find.textContaining('open the privacy'), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('items are named and routes set a pane title', (t) async {
      final handle = t.ensureSemantics();
      await pumpApp(t);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      expect(find.bySemanticsLabel('Library'), findsOneWidget);
      expect(
        find.semantics.byFlag(SemanticsFlag.namesRoute),
        findsAtLeastNWidgets(1),
      );
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Privacy policy'), findsOneWidget);
      expect(find.bySemanticsLabel('English'), findsOneWidget);
      expect(
        find.semantics.byFlag(SemanticsFlag.namesRoute),
        findsAtLeastNWidgets(1),
      );
      handle.dispose();
    });
  });

  group('system language mirror', () {
    testWidgets('each choice sends its tag, and system sends null', (t) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.kkeujeok.app/locale'),
            (call) async {
              calls.add(call);
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.kkeujeok.app/locale'),
              null,
            ),
      );
      await pumpApp(t);
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('한국어'));
      await t.pumpAndSettle();
      await t.tap(find.text('English'));
      await t.pumpAndSettle();
      await t.tap(find.text('Follow system settings'));
      await t.pumpAndSettle();
      expect(calls.map((c) => c.method).toSet(), {'setApplicationLocales'});
      expect(calls.map((c) => c.arguments), ['ko', 'en', null]);
    });
  });

  group('compact navigation and selection', () {
    testWidgets('settings opened from the drawer closes the drawer', (t) async {
      await pumpApp(t, width: 500);
      await t.tap(find.byTooltip('Open menu'));
      await t.pumpAndSettle();
      expect(find.text('Kkeujeok'), findsOneWidget);
      final row = t.getSize(find.widgetWithText(InkWell, 'Settings').first);
      expect(row.height, greaterThanOrEqualTo(48));
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Kkeujeok'), findsNothing); // drawer is gone
    });

    testWidgets('the rail opens the drawer at 700dp', (t) async {
      await pumpApp(t, width: 700);
      await t.tap(find.byTooltip('Open menu'));
      await t.pumpAndSettle();
      expect(find.text('Kkeujeok'), findsOneWidget);
    });

    testWidgets('exactly the current language is marked', (t) async {
      await pumpApp(t);
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(InkWell, 'Follow system settings'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      await t.tap(find.text('English'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(InkWell, 'English'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a PRIVACY_URL that is not http(s) disables the item', (
      t,
    ) async {
      for (final bad in ['file:///etc/passwd', 'privacy', '   ']) {
        await pumpApp(t, privacyUrl: bad);
        await t.tap(find.text('Settings'));
        await t.pumpAndSettle();
        expect(
          find.textContaining('address is not set'),
          findsOneWidget,
          reason: bad,
        );
        await t.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
