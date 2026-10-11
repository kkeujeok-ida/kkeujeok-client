import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/drive/root_folder.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_device_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/error_class.dart';
import 'package:kkeujeok/sync/sync_log.dart';

import 'fake_drive.dart';

const _me = AuthAccount(sub: 'sub-1', email: 'a@example.com');
const _noteId = '01926f3a-0000-7000-8000-000000000900';

Note _note() => createNote(
  title: 'a',
  existingTitles: const [],
  background: 'plain',
  orientation: 'portrait',
  noteId: _noteId,
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
  late FakeDrive drive;
  late SyncDeviceStore device;
  late NoteStore notes;
  late SyncLog log;
  AuthAccount? account;

  RootFolderService service({int maxPages = 10, DriveClient? client}) =>
      RootFolderService(
        client: client ?? drive,
        device: device,
        notes: notes,
        log: log,
        account: () => account,
        maxPages: maxPages,
      );

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-root-');
    data = NoteData(() async => docs);
    device = SyncDeviceStore(data);
    notes = NoteStore(data);
    log = SyncLog(() async => docs, () => DateTime.utc(2026, 10, 10, 5));
    drive = FakeDrive();
    account = _me;
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may hold a handle for a moment.
      }
    });
  });

  Future<List<Map<String, Object?>>> logged(String event) async => [
    for (final e in await log.entries())
      if (e['event'] == event) e,
  ];

  group('first preparation', () {
    test('creates one root at the top level and caches its id', () async {
      final r = await service().ensureRoot();
      expect(r.status, RootStatus.ready);
      final root = drive.roots().single;
      expect(r.folderId, root.id);
      expect(root.parents, ['root']);
      expect(root.name, 'Kkeujeok');
      expect(drive.calls, ['list', 'create', 'list']);
      final d = await device.read();
      expect(d.rootFolderId, root.id);
      expect(d.createIntents, isEmpty);
      expect(d.sub, 'sub-1');
    });

    test('the intent is saved before the first query', () async {
      Object? seen;
      drive.before = (c) {
        if (c == 'list' && seen == null) {
          final f = File('${docs.path}/$syncDeviceFileName');
          seen = f.existsSync() ? f.readAsStringSync() : '';
        }
      };
      await service().ensureRoot();
      expect(seen, contains('"kkeujeokId":"root"'));
      expect(seen, contains('"kind":"root"'));
    });

    test('a root another device made is used, nothing is created', () async {
      final other = drive.seed(kkeujeokId: 'root');
      final r = await service().ensureRoot();
      expect(r.folderId, other.id);
      expect(drive.calls, ['list']);
    });

    test('a user folder with the same name is invisible', () async {
      drive.seed(name: 'Kkeujeok', visible: false);
      drive.seed(name: 'Kkeujeok'); // no kkeujeokId
      final r = await service().ensureRoot();
      expect(r.status, RootStatus.ready);
      expect(drive.roots().length, 1);
      expect(drive.calls, contains('create'));
    });

    test('a lagging listing: the create response id is used', () async {
      drive.lagLists = 1;
      final r = await service().ensureRoot();
      final root = drive.roots().single;
      expect(r.folderId, root.id);
      expect((await device.read()).rootFolderId, root.id);
      expect(drive.calls, ['list', 'create', 'list']);
    });

    test('a crash after create: the next run lists first and no second '
        'root appears', () async {
      drive.after = (c) {
        if (c == 'create') throw StateError('killed');
      };
      final r1 = await service().ensureRoot();
      expect(r1.status, RootStatus.failed);
      expect(drive.roots().length, 1);
      expect((await device.read()).createIntents, isNotEmpty);

      drive.after = null;
      drive.calls.clear();
      final r2 = await service().ensureRoot();
      expect(r2.status, RootStatus.ready);
      expect(drive.roots().length, 1);
      expect(drive.calls, ['list']);
      expect((await device.read()).createIntents, isEmpty);
    });

    test('concurrent callers share one run', () async {
      final s = service();
      final a = s.ensureRoot();
      final b = s.checkRoot();
      final r = await Future.wait([a, b]);
      expect(r[0], same(r[1]));
      expect(drive.calls.where((c) => c == 'create').length, 1);
    });
  });

  group('duplicates', () {
    test('earliest stays, children move first, the other is trashed last, '
        'logged', () async {
      final keep = drive.seed(
        kkeujeokId: 'root',
        createdTime: '2026-10-10T04:20:00.000Z',
      );
      final dup = drive.seed(
        kkeujeokId: 'root',
        createdTime: '2026-10-10T04:30:00.000Z',
      );
      final child = drive.seed(name: 'a', kkeujeokId: 'x', parents: [dup.id]);
      final r = await service().ensureRoot();
      expect(r.folderId, keep.id);
      expect(child.parents, [keep.id]);
      expect(dup.trashed, isTrue);
      final move = drive.calls.indexOf('update:${child.id}:move');
      final trash = drive.calls.indexOf('update:${dup.id}:trash');
      expect(move, greaterThanOrEqualTo(0));
      expect(trash, greaterThan(move));
      expect((await logged('duplicatesCleaned')).single['count'], 1);
      expect((await device.read()).rootFolderId, keep.id);
    });

    test('a failed move leaves the duplicate, the next run repeats', () async {
      final keep = drive.seed(
        kkeujeokId: 'root',
        createdTime: '2026-10-10T04:20:00.000Z',
      );
      final dup = drive.seed(
        kkeujeokId: 'root',
        createdTime: '2026-10-10T04:30:00.000Z',
      );
      final child = drive.seed(name: 'a', kkeujeokId: 'x', parents: [dup.id]);
      drive.failures['update'] = [const DriveError('network')];
      final r1 = await service().ensureRoot();
      expect(r1.status, RootStatus.ready);
      expect(r1.folderId, keep.id);
      expect(dup.trashed, isFalse);
      expect(await logged('duplicatesCleaned'), isEmpty);
      expect((await logged('error')).single['class'], 'backoff');

      final r2 = await service().ensureRoot();
      expect(r2.folderId, keep.id);
      expect(child.parents, [keep.id]);
      expect(dup.trashed, isTrue);
    });

    test('listings are followed across pages', () async {
      drive.pageSize = 1;
      final a = drive.seed(
        kkeujeokId: 'root',
        createdTime: '2026-10-10T04:30:00.000Z',
      );
      final b = drive.seed(
        kkeujeokId: 'root',
        createdTime: '2026-10-10T04:20:00.000Z',
      );
      final r = await service().ensureRoot();
      expect(r.folderId, b.id); // the earliest is on page 2
      expect(a.trashed, isTrue);
    });

    test('a listing that never ends is cut at the page cap', () async {
      drive.pageSize = 1;
      for (var i = 0; i < 10; i++) {
        drive.seed(kkeujeokId: 'root');
      }
      await service(maxPages: 3).ensureRoot();
      // Only the 3 roots of the first 3 pages were seen: 2 are trashed.
      expect(
        drive.roots(includeTrashed: true).where((i) => i.trashed).length,
        2,
      );
    });
  });

  group('missing and moved', () {
    Future<void> hadRoot() async {
      final r = await service().ensureRoot();
      expect(r.status, RootStatus.ready);
      drive.calls.clear();
    }

    test('trashed root is missing, nothing is created', () async {
      await hadRoot();
      drive.roots().single.trashed = true;
      final r = await service().checkRoot();
      expect(r.status, RootStatus.missing);
      expect(drive.calls.where((c) => c == 'create'), isEmpty);
    });

    test('deleted root is missing', () async {
      await hadRoot();
      drive.roots().single.deleted = true;
      expect((await service().checkRoot()).status, RootStatus.missing);
    });

    test('a root that only moved is used silently', () async {
      await hadRoot();
      final root = drive.roots().single;
      final elsewhere = drive.seed(name: 'x', kkeujeokId: 'f');
      root.parents = [elsewhere.id];
      final r = await service().checkRoot();
      expect(r.status, RootStatus.ready);
      expect(r.folderId, root.id);
    });

    test('a failed call is never missing', () async {
      await hadRoot();
      drive.roots().single.trashed = true;
      drive.failures['list'] = [const DriveError('network')];
      final r = await service().checkRoot();
      expect(r.status, RootStatus.failed);
      expect(r.errorClass, 'backoff');
    });

    test('a failed get of the cached id is never missing', () async {
      await hadRoot();
      drive.roots().single.trashed = true;
      drive.failures['get'] = [const DriveError('http', status: 503)];
      expect((await service().checkRoot()).status, RootStatus.failed);
    });

    test('recreate: new root, notes reset, noteId kept', () async {
      await notes.write(_note());
      await notes.commitSync(
        _note(),
        _note(),
        const SyncInfo(
          fileId: 'old-file',
          baseHeadRevisionId: 'R1',
          state: SyncState.synced,
          pendingVerify: {
            'parentRevisionId': 'R1',
            'oursRevisionId': null,
            'round': 1,
          },
        ),
      );
      await hadRoot();
      final oldRoot = drive.roots().single;
      oldRoot.trashed = true;

      final r = await service().recreate();
      expect(r.status, RootStatus.ready);
      expect(r.folderId, isNot(oldRoot.id));
      expect(drive.roots().single.id, r.folderId);

      final s = await notes.readSync(_noteId);
      expect(s.info.fileId, isNull);
      expect(s.info.baseHeadRevisionId, isNull);
      expect(s.info.pendingVerify, isNull);
      expect(s.info.createIntent, isNull);
      expect(s.state, SyncState.pending);
      expect(s.base, isNull);
      expect((await notes.read(_noteId))!.note!.noteId, _noteId);
      expect((await device.read()).rootFolderId, r.folderId);
    });
  });

  group('failures', () {
    for (final (name, err, cls) in [
      ('network', const DriveError('network'), 'backoff'),
      (
        '503',
        const DriveError('http', status: 503, reason: 'backendError'),
        'backoff',
      ),
      ('401', const DriveError('http', status: 401), 'reauth'),
      (
        '403 rate',
        const DriveError('http', status: 403, reason: 'rateLimitExceeded'),
        'backoff',
      ),
      ('400', const DriveError('http', status: 400), 'fatal'),
    ]) {
      test('$name is failed($cls), logged without names', () async {
        drive.failures['list'] = [err];
        final r = await service().ensureRoot();
        expect(r.status, RootStatus.failed);
        expect(r.errorClass, cls);
        final e = (await logged('error')).single;
        expect(e['class'], cls);
        expect(
          e.keys.toSet().difference({
            'at',
            'event',
            'class',
            'status',
            'reason',
          }),
          isEmpty,
        );
        // One retry run works.
        final again = await service().ensureRoot();
        expect(again.status, RootStatus.ready);
      });
    }

    test('an unexpected exception is failed(fatal), never thrown', () async {
      drive.before = (c) => throw StateError('boom');
      expect((await service().ensureRoot()).status, RootStatus.failed);
    });
  });

  group('account', () {
    test('another account: no Drive call, idle', () async {
      await device.adoptAccount('sub-other', 'o@example.com');
      final r = await service().ensureRoot();
      expect(r.status, RootStatus.idle);
      expect(drive.calls, isEmpty);
    });

    test('no account known: no Drive call, idle', () async {
      account = null;
      expect((await service().ensureRoot()).status, RootStatus.idle);
      expect(drive.calls, isEmpty);
    });
  });

  group('reset and races', () {
    Future<void> seedNote({required SyncInfo info, Note? working}) async {
      await notes.write(working ?? _note());
      await notes.commitSync(working ?? _note(), null, info);
    }

    Future<void> hadRoot() async {
      expect((await service().ensureRoot()).status, RootStatus.ready);
    }

    test('withRoot drops conflictsFolderId on a new root, keeps it on the '
        'same one', () {
      const d = SyncDevice(rootFolderId: 'r1', conflictsFolderId: 'c1');
      expect(d.withRoot('r1', const []).conflictsFolderId, 'c1');
      expect(d.withRoot('r2', const []).conflictsFolderId, isNull);
      expect(
        d.withRoot('r1', const [], forgetConflicts: true).conflictsFolderId,
        isNull,
      );
    });

    test('reset keeps conflicts and unsent sidecars and leaves the working '
        'copy alone', () async {
      await seedNote(
        info: const SyncInfo(
          fileId: 'old',
          state: SyncState.conflict,
          conflicts: [
            {'pageId': 'p', 'rev': 'r', 'resolvedAt': null},
          ],
          unsentSidecars: [
            {'pageId': 'p', 'rev': 'r'},
          ],
        ),
      );
      final file = File(
        '${docs.path}/$noteDataDirName/$_noteId/$workingFileName',
      );
      final before = file.readAsBytesSync();
      final stamp = file.lastModifiedSync();
      await hadRoot();
      drive.roots().single.trashed = true;
      expect((await service().recreate()).status, RootStatus.ready);

      final s = (await notes.readSync(_noteId)).info;
      expect(s.fileId, isNull);
      expect(s.state, SyncState.pending);
      expect(s.conflicts.single['pageId'], 'p');
      expect(s.unsentSidecars.single['rev'], 'r');
      expect(file.readAsBytesSync(), before);
      expect(file.lastModifiedSync(), stamp);
    });

    test('an unreadable note loses its fileId too', () async {
      await seedNote(
        info: const SyncInfo(fileId: 'old', state: SyncState.synced),
      );
      File('${docs.path}/$noteDataDirName/$_noteId/$workingFileName')
          .writeAsBytesSync([1, 2, 3]);
      await hadRoot();
      drive.roots().single.trashed = true;
      expect((await service().recreate()).status, RootStatus.ready);
      final raw = File('${docs.path}/$noteDataDirName/$_noteId/$syncFileName')
          .readAsStringSync();
      expect(raw, contains('"fileId":null'));
    });

    test('another device made a new root: notes forget their file', () async {
      await seedNote(
        info: const SyncInfo(fileId: 'old', state: SyncState.synced),
      );
      await hadRoot();
      drive.roots().single.trashed = true;
      final other = drive.seed(kkeujeokId: 'root');
      final r = await service().ensureRoot();
      expect(r.folderId, other.id);
      expect((await notes.readSync(_noteId)).info.fileId, isNull);
    });

    test('recreate drops other intents and the conflicts cache', () async {
      await hadRoot();
      final d = await device.read();
      await device.write(
        SyncDevice(
          sub: d.sub,
          email: d.email,
          rootFolderId: d.rootFolderId,
          conflictsFolderId: 'c1',
          createIntents: const [
            {'kkeujeokId': 'f', 'kind': 'folder', 'parentId': 'old'},
          ],
        ),
      );
      drive.roots().single.trashed = true;
      expect((await service().recreate()).status, RootStatus.ready);
      final n = await device.read();
      expect(n.createIntents, isEmpty);
      expect(n.conflictsFolderId, isNull);
    });

    test('an account that signs out mid-run gets no write', () async {
      drive.before = (c) {
        if (c == 'create') account = null;
      };
      final r = await service().ensureRoot();
      expect(r.status, RootStatus.idle);
      expect((await device.read()).rootFolderId, isNull);
    });

    test('an unreadable device record is failed(fatal) and logged', () async {
      File('${docs.path}/$syncDeviceFileName').writeAsStringSync('{ nope');
      final r = await service().ensureRoot();
      expect(r.status, RootStatus.failed);
      expect(r.errorClass, 'fatal');
      expect((await logged('error')).single['reason'], 'deviceUnreadable');
      expect(drive.calls, isEmpty);
    });

    test('two recreates in a row run one after the other', () async {
      await hadRoot();
      drive.roots().single.trashed = true;
      drive.calls.clear();
      final s = service();
      final r = await Future.wait([s.recreate(), s.recreate(), s.ensureRoot()]);
      expect(r.every((x) => x.status == RootStatus.ready), isTrue);
      expect(drive.roots().length, 1);
      expect(drive.calls.where((c) => c == 'create').length, 1);
    });

    test('a truncated children listing keeps the duplicate', () async {
      drive.pageSize = 1;
      drive.seed(kkeujeokId: 'root', createdTime: '2026-10-10T04:20:00.000Z');
      final dup = drive.seed(
        kkeujeokId: 'root',
        createdTime: '2026-10-10T04:30:00.000Z',
      );
      for (var i = 0; i < 4; i++) {
        drive.seed(name: 'k$i', kkeujeokId: 'k$i', parents: [dup.id]);
      }
      final r = await service(maxPages: 2).ensureRoot();
      expect(r.status, RootStatus.ready);
      expect(dup.trashed, isFalse);
      expect(await logged('duplicatesCleaned'), isEmpty);
      expect((await logged('error')).single['reason'], 'listTruncated');
    });

    test('a transient token failure is backoff, a missing grant reauth', () {
      expect(classifyDriveError(const DriveError('network')), 'backoff');
      expect(
        classifyDriveError(
          const DriveError('http', status: 401, reason: 'noToken'),
        ),
        'reauth',
      );
    });
  });

  group('q strings', () {
    test('escape backslash first, then the quote', () {
      expect(escapeQ(r"a'b\c"), r"a\'b\\c");
      expect(
        kkeujeokIdQuery("x'y"),
        "appProperties has { key='kkeujeokId' and value='x\\'y' } "
        'and trashed=false',
      );
      expect(childrenQuery('ab'), "'ab' in parents and trashed=false");
    });
  });
}
