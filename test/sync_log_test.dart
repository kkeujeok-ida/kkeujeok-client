import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/sync/sync_log.dart';
import 'package:kkeujeok/sync/sync_log_entry.dart';

const noteId = '01926f3a-0000-7000-8000-000000000900';

void main() {
  late Directory docs;
  late Directory out;
  late SyncLog log;
  late File file;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 10, 10, 4, 20);
    docs = Directory.systemTemp.createTempSync('kkj-log-');
    out = Directory('${docs.path}/out')..createSync();
    file = File('${docs.path}/$syncLogFileName');
    log = SyncLog(() async => docs, () => now);
    addTearDown(() => docs.deleteSync(recursive: true));
  });

  Future<List<String>> lines(File f) async =>
      const LineSplitter().convert(await f.readAsString());

  Future<File> export([SyncLog? l]) => (l ?? log).exportJsonl(
    appVersion: '1.2.3',
    now: DateTime.utc(2026, 10, 10, 23, 59),
    into: out,
  );

  test('error cause and exception round-trip and are coerced', () async {
    expect(
      await log.append('error', {
        'class': 'backoff',
        'cause': 'network',
        'exception': 'DriveError.network',
        'scope': 'note',
        'noteId': noteId,
      }),
      isTrue,
    );
    // Out-of-domain cause becomes unknown; the exception is cut to a 64-char name.
    expect(
      await log.append('error', {
        'class': 'fatal',
        'cause': 'weird',
        'exception': 'Bad Name<T>${'x' * 80}',
      }),
      isTrue,
    );
    final rows = (await lines(file)).map(jsonDecode).toList();
    expect(rows[0]['cause'], 'network');
    expect(rows[0]['exception'], 'DriveError.network');
    expect(rows[1]['cause'], 'unknown');
    expect(rows[1]['exception'], hasLength(64));
    expect(rows[1]['exception'], startsWith('Bad_Name_T_'));
    expect(
      checkLogEntry({
        'at': '2026-10-10T04:20:00.000Z',
        'event': 'error',
        'class': 'fatal',
        'cause': 'x',
      })['field'],
      'cause',
    );
    final why = logWhy('backoff', status: 503, error: const DriveError('http'));
    expect(why, {
      'cause': 'server',
      'exception': 'DriveError.http',
      'scope': 'global',
    });
    expect(logWhy('x', error: const DriveError('network'))['cause'], 'network');
    expect(logWhy('quota', status: 403, noteId: noteId)['cause'], 'quota');
    expect(logWhy('reauth', status: 401)['cause'], 'auth');
    expect(logWhy('fatal', reason: 'x')['cause'], 'unknown');
  });

  test('new diagnostic fields round-trip; old entries still read', () async {
    expect(
      await log.append('stateChange', {
        'noteId': noteId,
        'from': 'error',
        'to': 'pending',
        'reason': 'userRetry',
      }),
      isTrue,
    );
    expect(
      await log.append('stateChange', {
        'noteId': noteId,
        'from': 'error',
        'to': 'pending',
        'reason': 'a b',
      }),
      isTrue,
    );
    expect(
      await log.append('backoff', {
        'class': 'backoff',
        'attempt': 1,
        'delayMs': 0,
        'scope': 'global',
      }),
      isTrue,
    );
    expect(
      await log.append('conflictResolved', {
        'noteId': noteId,
        'choice': 'both',
      }),
      isTrue,
    );
    expect(
      await log.append('conflictResolved', {'noteId': noteId, 'choice': 'x'}),
      isFalse,
    );
    expect(
      await log.append('backoff', {
        'class': 'backoff',
        'attempt': 1,
        'delayMs': 0,
        'scope': 'x',
      }),
      isFalse,
    );
    expect(
      await log.append('backoff', {
        'class': 'backoff',
        'attempt': 1,
        'delayMs': 0,
      }),
      isTrue,
    );
    final e = await log.entries();
    expect(e.length, 5);
    expect(e[1]['reason'], 'other');
  });

  test('logWhy maps socket and timeout errors to network', () {
    expect(logWhy('backoff', error: const SocketException('x'))['cause'], 'network');
    expect(logWhy('backoff', error: TimeoutException('x'))['cause'], 'network');
    expect(logWhy('fatal', error: StateError('x'))['cause'], 'unknown');
  });

  test('an old-shape stored entry and export read without error', () async {
    await file.writeAsString(
      '{"at":"2026-10-10T04:00:00.000Z","event":"error","class":"quota"}\n'
      '{"at":"2026-10-10T04:01:00.000Z","event":"stateChange","noteId":"$noteId","from":"error","to":"pending"}\n',
    );
    expect((await log.entries()).length, 2);
    expect((await lines(await export())).length, 3); // header + 2
  });

  test('append stamps at, keeps the order, one line each', () async {
    expect(await log.append('pageTokenRejected'), isTrue);
    now = now.add(const Duration(seconds: 5));
    expect(
      await log.append('stateChange', {
        'noteId': noteId,
        'from': 'pending',
        'to': 'syncing',
      }),
      isTrue,
    );
    final text = file.readAsStringSync();
    expect(text.endsWith('\n'), isTrue);
    expect(text.codeUnitAt(0), isNot(0xFEFF));
    final e = (await log.entries());
    expect(e.map((x) => x['event']), ['pageTokenRejected', 'stateChange']);
    expect(e.first['at'], '2026-10-10T04:20:00.000Z');
    expect(e.last['at'], '2026-10-10T04:20:05.000Z');
  });

  test('a caller cannot set at or event through fields', () async {
    await log.append('pageTokenRejected', {
      'at': '2000-01-01T00:00:00.000Z',
      'event': 'merged',
    });
    expect((await log.entries()).single['at'], '2026-10-10T04:20:00.000Z');
    expect((await log.entries()).single['event'], 'pageTokenRejected');
  });

  test('an invalid entry is refused and not stored', () async {
    expect(
      await log.append('merged', {'noteId': noteId, 'title': '수학 노트'}),
      isFalse,
    );
    expect(await log.append('merged', {'noteId': 'note-1'}), isFalse);
    expect(await log.append('sync'), isFalse);
    expect(file.existsSync(), isFalse);
    expect(await log.entries(), isEmpty);
  });

  test('a reason outside the domain becomes other', () async {
    expect(
      await log.append('error', {
        'class': 'fatal',
        'status': 403,
        'reason': 'has space and 수학',
      }),
      isTrue,
    );
    expect(
      await log.append('error', {
        'class': 'fatal',
        'reason': 'rateLimitExceeded',
      }),
      isTrue,
    );
    final e = await log.entries();
    expect(e[0]['reason'], 'other');
    expect(e[1]['reason'], 'rateLimitExceeded');
  });

  test(
    'keeps the newest 5,000, oldest first, and the file stays bounded',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      for (var i = 0; i < 6100; i++) {
        expect(
          await log.append('verifyRound', {
            'noteId': noteId,
            'round': 1,
            'count': i,
          }),
          isTrue,
        );
      }
      final e = await log.entries();
      expect(e.length, 5000);
      expect(e.first['count'], 6100 - 5000);
      expect(e.last['count'], 6099);
      // compaction ran: far fewer lines than appended
      expect((await lines(file)).length, lessThan(6000));

      final exported = await lines(await export());
      expect(exported.length, 1 + 5000);
      expect(jsonDecode(exported[1])['count'], 1100);
      expect(jsonDecode(exported.last)['count'], 6099);
    },
  );

  test('a failed compaction still stores the entry', () async {
    String line(int i) =>
        '{"at":"2026-10-10T04:20:00.000Z","event":"verifyRound",'
        '"noteId":"$noteId","round":1,"count":$i}\n';
    file.writeAsStringSync([for (var i = 0; i < 5999; i++) line(i)].join());
    Directory('${file.path}.tmp').createSync(); // the compaction cannot write
    expect(await log.append('pageTokenRejected'), isTrue);
    expect((await log.entries()).last['event'], 'pageTokenRejected');
  });

  test('a cut-short last line is repaired and skipped', () async {
    await log.append('pageTokenRejected');
    file.writeAsStringSync('{"at":"2026-10-10T04:2', mode: FileMode.append);
    final fresh = SyncLog(() async => docs, () => now);
    expect(await fresh.append('pageTokenRejected'), isTrue);
    expect((await fresh.entries()).length, 2);
    final all = await lines(file);
    expect(all.length, 3); // good, broken (alone), good
    expect(all[1], '{"at":"2026-10-10T04:2');
  });

  test('broken and invalid lines in the file are skipped', () async {
    file.writeAsStringSync(
      [
        'garbage',
        '{"at":"2026-10-10T04:20:00.000Z","event":"pageTokenRejected"}',
        '{"at":"2026-10-10T04:20:00.000Z","event":"merged","noteId":"$noteId","title":"x"}',
        '[1]',
        '',
      ].join('\n'),
    );
    final e = await SyncLog(() async => docs, () => now).entries();
    expect(e.length, 1);
  });

  group('export', () {
    test('header then entries, named by the UTC date', () async {
      await log.append('pageTokenRejected');
      // 23:30 at -05:00 on the 10th is already the 11th in UTC
      final f = await log.exportJsonl(
        appVersion: '1.2.3',
        buildId: '42',
        now: DateTime.parse('2026-10-10T23:30:00-05:00'),
        into: out,
      );
      expect(f.uri.pathSegments.last, 'kkeujeok-sync-log-2026-10-11.jsonl');
      final raw = await f.readAsString();
      expect(raw.endsWith('\n'), isTrue);
      expect(raw.codeUnitAt(0), isNot(0xFEFF));
      final l = const LineSplitter().convert(raw);
      expect(l.length, 2);
      final h = jsonDecode(l[0]) as Map;
      expect(h['buildId'], '42');
      expect(h['deviceLabel'], matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(h.remove('deviceLabel'), isNotNull);
      expect(h, {
        'type': 'header',
        'app': 'kkeujeok',
        'appVersion': '1.2.3',
        'buildId': '42',
        'platform': 'android',
        'supportedFormatVersion': 1,
        'exportedAt': '2026-10-11T04:30:00.000Z',
      });
      expect(jsonDecode(l[1])['event'], 'pageTokenRejected');
    });

    test('an empty log is the header line only', () async {
      final f = await export();
      expect(f.uri.pathSegments.last, 'kkeujeok-sync-log-2026-10-10.jsonl');
      final l = await lines(f);
      expect(l.length, 1);
      expect(jsonDecode(l.single)['type'], 'header');
    });

    test(
      'the log lives beside, not inside, the notes and survives clear()',
      () async {
        await log.append('pageTokenRejected');
        final data = NoteData(() async => docs);
        final noteDir = Directory('${docs.path}/$noteDataDirName/$noteId')
          ..createSync(recursive: true);
        File('${noteDir.path}/working.kkj').writeAsStringSync('x');
        await data.clear();
        expect(
          Directory('${docs.path}/$noteDataDirName').existsSync(),
          isFalse,
        );
        expect(file.existsSync(), isTrue);
        final l = await lines(await export());
        expect(l.length, 2);
      },
    );
  });
}
