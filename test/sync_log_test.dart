import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/sync/sync_log.dart';

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
        now: DateTime.parse('2026-10-10T23:30:00-05:00'),
        into: out,
      );
      expect(f.uri.pathSegments.last, 'kkeujeok-sync-log-2026-10-11.jsonl');
      final raw = await f.readAsString();
      expect(raw.endsWith('\n'), isTrue);
      expect(raw.codeUnitAt(0), isNot(0xFEFF));
      final l = const LineSplitter().convert(raw);
      expect(l.length, 2);
      expect(jsonDecode(l[0]), {
        'type': 'header',
        'app': 'kkeujeok',
        'appVersion': '1.2.3',
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
