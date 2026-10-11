import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/sync_device_store.dart';
import 'package:kkeujeok/sync/sync_log.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'fake_auth_gateway.dart';

const noteId = '01926f3a-0000-7000-8000-000000000900';

Note _note() => createNote(
  title: 'a',
  existingTitles: [],
  background: 'plain',
  orientation: 'portrait',
  noteId: noteId,
  pageId: '01926f3a-0000-7000-8000-000000000001',
  pageRev: '01926f3a-0000-7000-8000-000000000051',
  metaRev: '01926f3a-0000-7000-8000-000000000901',
  orderRev: '01926f3a-0000-7000-8000-000000000902',
  now: '2026-10-10T04:20:00.000Z',
  editedBy: 'Pixel 8',
).note!;

void main() {
  late Directory docs;
  late NoteData data;
  late SyncDeviceStore store;
  late File file;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-device-');
    data = NoteData(() async => docs);
    store = SyncDeviceStore(data);
    file = File('${docs.path}/$syncDeviceFileName');
    addTearDown(() => docs.deleteSync(recursive: true));
  });

  Map<String, dynamic> stored() =>
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  test('nothing stored and a broken file both read as empty', () async {
    expect((await store.read()).sub, isNull);
    file.writeAsStringSync('{ not json');
    expect((await store.read()).sub, isNull);
    file.writeAsStringSync('{"sub": 5}');
    expect((await store.read()).sub, isNull);
  });

  test('an unreadable existing file is never overwritten', () async {
    for (final text in [
      '{ not json',
      '[1]',
      '{"sub": 5}',
      '{"createIntents":[{"kkeujeokId":"k"}]}', // incomplete intent
    ]) {
      file.writeAsStringSync(text);
      expect(await store.adoptAccount('sub-1', 'a@example.com'), isFalse);
      await expectLater(store.write(const SyncDevice()), throwsA(anything));
      expect(file.readAsStringSync(), text);
    }
    await store.clear(); // clear is the way out
    expect(file.existsSync(), isFalse);
    expect(await store.adoptAccount('sub-1', 'a@example.com'), isTrue);
  });

  test('unknown keys survive adoption', () async {
    file.writeAsStringSync('{"future":{"a":1},"sub":null}');
    await store.adoptAccount('sub-1', 'a@example.com');
    expect(stored()['future'], {'a': 1});
    expect(stored()['sub'], 'sub-1');
  });

  test('clear tolerates a delete that fails', () async {
    Directory('${file.path}/inner').createSync(recursive: true); // a folder
    await store.clear(); // does not throw
    expect(Directory(file.path).existsSync(), isTrue);
  });

  test('first account is adopted; the file has no token', () async {
    expect(await store.adoptAccount('sub-1', 'a@example.com'), isTrue);
    expect(stored(), {
      'sub': 'sub-1',
      'email': 'a@example.com',
      'rootFolderId': null,
      'conflictsFolderId': null,
      'pageToken': null,
      'createIntents': [],
    });
    expect(Directory(docs.path).listSync().length, 1); // no temp file
  });

  test('same sub refreshes the e-mail and keeps the cache', () async {
    await store.write(
      const SyncDevice(
        sub: 'sub-1',
        email: 'old@example.com',
        rootFolderId: 'R',
        pageToken: 'P',
        createIntents: [
          {'kkeujeokId': 'k', 'kind': 'folder', 'parentId': 'R'},
        ],
      ),
    );
    expect(await store.adoptAccount('sub-1', 'new@example.com'), isTrue);
    final j = stored();
    expect(j['email'], 'new@example.com');
    expect(j['rootFolderId'], 'R');
    expect(j['pageToken'], 'P');
    expect((j['createIntents'] as List).length, 1);
  });

  test('another sub is refused and nothing is overwritten', () async {
    await store.adoptAccount('sub-1', 'a@example.com');
    final before = file.readAsStringSync();
    expect(await store.adoptAccount('sub-2', 'b@example.com'), isFalse);
    expect(file.readAsStringSync(), before);
    expect(await store.adoptAccount('', 'b@example.com'), isFalse);
  });

  test('concurrent calls are serialised: the first sub wins', () async {
    final r = await Future.wait([
      store.adoptAccount('sub-1', 'a@example.com'),
      store.adoptAccount('sub-2', 'b@example.com'),
    ]);
    expect(r, [true, false]);
    expect(stored()['sub'], 'sub-1');
  });

  test('clear removes the file and is fine when there is none', () async {
    await store.adoptAccount('sub-1', 'a@example.com');
    await store.clear();
    expect(file.existsSync(), isFalse);
    await store.clear();
  });

  group('wiring', () {
    late FakeAuthGateway gateway;
    late ProviderContainer c;

    setUp(() {
      gateway = FakeAuthGateway(
        signInAccount: const AuthAccount(sub: 'sub-9', email: 'z@example.com'),
      );
      c = ProviderContainer(
        overrides: [
          authGatewayProvider.overrideWithValue(gateway),
          noteDataProvider.overrideWithValue(data),
        ],
      );
      addTearDown(c.dispose);
    });

    test('saving a note while signed in tags the device', () async {
      await gateway.signIn();
      await c.read(noteStoreProvider).write(_note());
      expect(stored()['sub'], 'sub-9');
      expect(stored()['email'], 'z@example.com');
    });

    test('saving without a known account writes no device file', () async {
      await c.read(noteStoreProvider).write(_note());
      expect(file.existsSync(), isFalse);
      expect(
        Directory('${docs.path}/$noteDataDirName/$noteId/working.kkj').parent
            .existsSync(),
        isTrue,
      );
    });

    test(
      'a device tagged with another sub is kept; the save still works',
      () async {
        await store.adoptAccount('sub-1', 'a@example.com');
        await gateway.signIn();
        await c.read(noteStoreProvider).write(_note());
        expect(stored()['sub'], 'sub-1');
        expect(await c.read(noteStoreProvider).read(noteId), isNotNull);
      },
    );

    test(
      'a save does not read the device file again for the same account',
      () async {
        await gateway.signIn();
        final notes = c.read(noteStoreProvider);
        await notes.write(_note());
        file.deleteSync(); // only a re-adoption would bring it back
        await notes.write(_note());
        expect(file.existsSync(), isFalse);
      },
    );

    test('disconnect clears notes and device state, keeps the log', () async {
      await gateway.signIn();
      final auth = c.read(authProvider.notifier);
      await c.read(noteStoreProvider).write(_note());
      await c.read(syncLogProvider).append('pageTokenRejected');
      expect(file.existsSync(), isTrue);

      c.read(authProvider); // build
      // The fake restores as signed out: sign in through the notifier.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await auth.signIn();
      expect(c.read(authProvider).phase, AuthPhase.signedIn);

      expect(await auth.disconnect(), DisconnectResult.done);
      expect(file.existsSync(), isFalse);
      expect(Directory('${docs.path}/$noteDataDirName').existsSync(), isFalse);
      expect(File('${docs.path}/$syncLogFileName').existsSync(), isTrue);
      expect(gateway.account, isNull);
    });
  });
}
