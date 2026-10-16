import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/drive/http_drive_client.dart';

import 'fake_drive.dart';
import 'upload_env.dart' show makeNote;

void main() {
  group('HttpDriveClient changes', () {
    late HttpServer server;
    late List<Uri> seen;
    late int status;
    late String reply;

    HttpDriveClient client() => HttpDriveClient(
      httpClient: () => HttpClient(),
      token: () async => 'tok',
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      timeout: const Duration(seconds: 5),
    );

    setUp(() async {
      seen = [];
      status = 200;
      reply = '{}';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        seen.add(r.uri);
        await utf8.decodeStream(r);
        r.response.statusCode = status;
        r.response.write(reply);
        await r.response.close();
      });
      addTearDown(() => server.close(force: true));
    });

    test('getStartPageToken reads startPageToken', () async {
      reply = '{"startPageToken":"77"}';
      expect(await client().getStartPageToken(), '77');
      expect(seen.single.path, '/drive/v3/changes/startPageToken');
    });

    test('a start token that is missing is a parse error', () async {
      reply = '{}';
      await expectLater(
        client().getStartPageToken(),
        throwsA(isA<DriveError>().having((e) => e.kind, 'kind', 'parse')),
      );
    });

    test('listChanges sends the documented query and reads a page', () async {
      reply = jsonEncode({
        'newStartPageToken': '9',
        'changes': [
          {
            'fileId': 'a',
            'removed': false,
            'file': {
              'id': 'a',
              'name': 'x.kkj',
              'mimeType': noteMimeType,
              'headRevisionId': 'R1',
              'thumbnailLink': 'https://t',
              'appProperties': {'kkeujeokId': 'n'},
            },
          },
          {'fileId': 'b', 'removed': true},
        ],
      });
      final p = await client().listChanges('5');
      final q = seen.single.queryParameters;
      expect(seen.single.path, '/drive/v3/changes');
      expect(q['pageToken'], '5');
      expect(q['pageSize'], '1000');
      expect(q['includeRemoved'], 'true');
      expect(q['restrictToMyDrive'], 'true');
      expect(q['spaces'], 'drive');
      expect(q['fields'], contains('newStartPageToken'));
      expect(q['fields'], contains('headRevisionId'));
      expect(p.newStartPageToken, '9');
      expect(p.nextPageToken, isNull);
      expect(p.changes, hasLength(2));
      final f = p.changes.first.file!;
      expect(f.mimeType, noteMimeType);
      expect(f.headRevisionId, 'R1');
      expect(f.thumbnailLink, 'https://t');
      expect(p.changes.last.removed, isTrue);
      expect(p.changes.last.file, isNull);
    });

    test('a page with a next token keeps it', () async {
      reply = '{"nextPageToken":"6","changes":[]}';
      final p = await client().listChanges('5');
      expect(p.nextPageToken, '6');
      expect(p.newStartPageToken, isNull);
    });

    test('a page with neither token is a parse error', () async {
      reply = '{"changes":[]}';
      await expectLater(
        client().listChanges('5'),
        throwsA(isA<DriveError>().having((e) => e.kind, 'kind', 'parse')),
      );
    });

    test('a rejected token is an http error with its status', () async {
      status = 410;
      reply = '{"error":{"errors":[{"reason":"gone"}]}}';
      await expectLater(
        client().listChanges('5'),
        throwsA(isA<DriveError>().having((e) => e.status, 'status', 410)),
      );
    });
  });

  group('FakeDrive changes', () {
    test('every write is a change; the start token is the log length', () async {
      final d = FakeDrive();
      final root = d.seed(kkeujeokId: 'root');
      expect(await d.getStartPageToken(), '0');
      final n = d.foreignNote(makeNote(), parent: root.id);
      expect(await d.getStartPageToken(), '1');
      final p = await d.listChanges('0');
      expect(p.newStartPageToken, '1');
      expect(p.changes.single.fileId, n.id);
      expect(p.changes.single.file!.mimeType, noteMimeType);
      expect((await d.listChanges('1')).changes, isEmpty);
    });

    test('pages follow the page size and an unknown token is 410', () async {
      final d = FakeDrive()..changesPageSize = 1;
      final root = d.seed(kkeujeokId: 'root');
      d.foreignNote(makeNote(), parent: root.id);
      d.foreignNote(makeNote(noteIdOverride: '01926f3a-0000-7000-8000-000000000901'), parent: root.id);
      final a = await d.listChanges('0');
      expect(a.nextPageToken, '1');
      final b = await d.listChanges('1');
      expect(b.nextPageToken, isNull);
      expect(b.newStartPageToken, '2');
      await expectLater(
        d.listChanges('99'),
        throwsA(isA<DriveError>().having((e) => e.status, 'status', 410)),
      );
    });

    test('the tree query lists only note files', () async {
      final d = FakeDrive();
      final root = d.seed(kkeujeokId: 'root');
      d.foreignNote(makeNote(), parent: root.id);
      final p = await d.list(noteTreeQuery, fields: noteFileFields);
      expect(p.files, hasLength(1));
      expect(p.files.single.mimeType, noteMimeType);
    });
  });
}
