import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/l10n/app_localizations.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/sync/sync_log.dart';
import 'package:kkeujeok/ui/providers.dart';
import 'package:kkeujeok/ui/settings.dart';

import 'fake_auth_gateway.dart';

const label = 'Export sync log';

void main() {
  late Directory docs;
  late Directory tmp;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-export-');
    tmp = Directory('${docs.path}/tmp')..createSync();
    addTearDown(() => docs.deleteSync(recursive: true));
  });

  Future<void> pump(
    WidgetTester t,
    Future<void> Function(File) sharer, {
    String locale = 'en',
  }) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          authGatewayProvider.overrideWithValue(FakeAuthGateway()),
          noteDataProvider.overrideWithValue(NoteData(() async => docs)),
          logSharerProvider.overrideWithValue(sharer),
          appVersionProvider.overrideWithValue(() async => '9.9.9'),
          exportDirProvider.overrideWithValue(() async => tmp),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await t.pump();
  }

  // Real file IO does not advance under the fake clock.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump();
    }
  }

  testWidgets('shown while signed out; 48dp row; button semantics', (t) async {
    final h = t.ensureSemantics();
    await pump(t, (_) async {});
    expect(find.text(label), findsOneWidget);
    final row = find.ancestor(
      of: find.text(label),
      matching: find.byType(InkWell),
    );
    expect(t.getSize(row.first).height, greaterThanOrEqualTo(48));
    expect(
      t.getSemantics(find.bySemanticsLabel(label)),
      isSemantics(isButton: true, label: label, hasTapAction: true),
    );
    h.dispose();
  });

  testWidgets('shown in Korean', (t) async {
    await pump(t, (_) async {}, locale: 'ko');
    expect(find.text('동기화 로그 내보내기'), findsOneWidget);
  });

  testWidgets('tap shares a .jsonl file: header, then the entries', (t) async {
    final log = SyncLog(() async => docs, DateTime.now);
    await t.runAsync(() async {
      await log.append('pageTokenRejected');
      await log.append('error', {'class': 'fatal', 'status': 500});
    });
    File? shared;
    String? text;
    await pump(t, (f) async {
      shared = f;
      text = f.readAsStringSync();
    });
    await t.tap(find.text(label));
    await settle(t);
    expect(shared, isNotNull);
    expect(
      shared!.uri.pathSegments.last,
      matches(RegExp(r'^kkeujeok-sync-log-\d{4}-\d{2}-\d{2}\.jsonl$')),
    );
    final lines = const LineSplitter().convert(text!);
    expect(lines.length, 3);
    expect(jsonDecode(lines[0])['appVersion'], '9.9.9');
    expect(jsonDecode(lines[2])['class'], 'fatal');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a tap while an export runs is ignored', (t) async {
    final gate = Completer<void>();
    var calls = 0;
    await pump(t, (_) {
      calls++;
      return gate.future;
    });
    await t.tap(find.text(label));
    await settle(t);
    await t.tap(find.text(label));
    await settle(t);
    expect(calls, 1);
    gate.complete();
    await settle(t);
    await t.tap(find.text(label)); // free again
    await settle(t);
    expect(calls, 2);
  });

  testWidgets('the exported temp copy is deleted after sharing', (t) async {
    File? shared;
    await pump(t, (f) async => shared = f);
    await t.tap(find.text(label));
    await settle(t);
    expect(shared, isNotNull);
    expect(shared!.existsSync(), isFalse);
  });

  testWidgets('the row is disabled while an export runs', (t) async {
    final gate = Completer<void>();
    await pump(t, (_) => gate.future);
    await t.tap(find.text(label));
    await settle(t);
    final disabled = Theme.of(t.element(find.text(label))).disabledColor;
    expect(t.widget<Text>(find.text(label)).style?.color, disabled);
    gate.complete();
    await settle(t);
    expect(t.widget<Text>(find.text(label)).style?.color, isNot(disabled));
  });

  testWidgets('a failed export shows a snackbar and stays usable', (t) async {
    var calls = 0;
    await pump(t, (_) async {
      calls++;
      throw StateError('no share target');
    });
    await t.tap(find.text(label));
    await settle(t);
    expect(find.text("Couldn't export the log"), findsOneWidget);
    await t.tap(find.text(label));
    await settle(t);
    expect(calls, 2);
  });
}
