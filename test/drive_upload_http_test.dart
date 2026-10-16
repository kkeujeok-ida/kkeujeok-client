import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/drive/http_drive_client.dart';

class _Req {
  _Req(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final HttpHeaders headers;
  final List<int> body;

  String get text => utf8.decode(body, allowMalformed: true);
}

void main() {
  late HttpServer server;
  late List<_Req> seen;
  late int status;
  late String reply;
  late Map<String, String> replyHeaders;
  late List<String> replies; // answers in turn, before [reply]

  HttpDriveClient client() => HttpDriveClient(
    httpClient: HttpClient.new,
    token: () async => 'tok',
    baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    timeout: const Duration(seconds: 5),
    transferTimeout: const Duration(seconds: 5),
  );

  setUp(() async {
    seen = [];
    status = 200;
    reply = '{}';
    replyHeaders = {};
    replies = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final b = BytesBuilder();
      await for (final c in r) {
        b.add(c);
      }
      seen.add(_Req(r.method, r.uri, r.headers, b.takeBytes()));
      r.response.statusCode = status;
      replyHeaders.forEach((k, v) => r.response.headers.set(k, v));
      r.response.write(replies.isEmpty ? reply : replies.removeAt(0));
      await r.response.close();
    });
    addTearDown(() => server.close(force: true));
  });

  test('uploadSimple creates: multipart, fields, both parts, id from the '
      'answer', () async {
    reply = jsonEncode({'id': 'N1', 'headRevisionId': 'R1'});
    final f = await client().uploadSimple(
      metadata: {
        'name': 'a.kkj',
        'parents': ['P'],
        'appProperties': {'kkeujeokId': 'x', 'kkjCover': null},
      },
      bytes: [0, 1, 2, 255],
    );
    final r = seen.single;
    expect(f.id, 'N1');
    expect(f.headRevisionId, 'R1');
    expect(r.method, 'POST');
    expect(r.uri.path, '/upload/drive/v3/files');
    expect(r.uri.queryParameters['uploadType'], 'multipart');
    expect(r.uri.queryParameters['fields'], 'id,headRevisionId,md5Checksum');
    expect(r.headers.value('authorization'), 'Bearer tok');
    expect(r.headers.contentType?.mimeType, 'multipart/related');
    expect(r.text, contains('"name":"a.kkj"'));
    expect(r.text, contains('"kkjCover":null'));
    expect(r.body.contains(255), isTrue);
  });

  test('uploadSimple updates: PATCH on the file, the id is the request id '
      'when the answer has none', () async {
    reply = jsonEncode({'headRevisionId': 'R2'});
    final f = await client().uploadSimple(
      fileId: 'F 1',
      metadata: {'name': 'a.kkj'},
      bytes: [1],
    );
    expect(f.id, 'F 1');
    expect(f.headRevisionId, 'R2');
    expect(seen.single.method, 'PATCH');
    expect(seen.single.uri.path, '/upload/drive/v3/files/F%201');
    expect(seen.single.text, isNot(contains('addParents')));
  });

  test('a failed upload is a DriveError with the Drive reason', () async {
    status = 403;
    reply = jsonEncode({
      'error': {
        'errors': [
          {'reason': 'storageQuotaExceeded'},
        ],
      },
    });
    await expectLater(
      client().uploadSimple(metadata: {'name': 'a'}, bytes: [1]),
      throwsA(
        isA<DriveError>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.reason, 'reason', 'storageQuotaExceeded'),
      ),
    );
  });

  test('startResumable sends the size and returns the session URI', () async {
    replyHeaders = {'Location': 'http://127.0.0.1:${server.port}/session/1'};
    final uri = await client().startResumable(
      metadata: {'name': 'a.kkj'},
      size: 6000000,
    );
    final r = seen.single;
    expect(uri, endsWith('/session/1'));
    expect(r.uri.queryParameters['uploadType'], 'resumable');
    expect(r.headers.value('x-upload-content-length'), '6000000');
    expect(r.text, contains('"name":"a.kkj"'));
  });

  test('startResumable without a Location is a parse error', () async {
    await expectLater(
      client().startResumable(metadata: {}, size: 1),
      throwsA(isA<DriveError>().having((e) => e.kind, 'kind', 'parse')),
    );
  });

  test('putResumable: chunk range, 308 progress, 200 finished', () async {
    final uri = 'http://127.0.0.1:${server.port}/session/1';
    status = 308;
    replyHeaders = {'Range': 'bytes=0-262143'};
    reply = '';
    var r = await client().putResumable(uri, 600000, 0, List.filled(300000, 1));
    expect(r.file, isNull);
    expect(r.received, 262144);
    expect(seen.last.headers.value('content-range'), 'bytes 0-299999/600000');
    expect(seen.last.body.length, 300000);

    status = 308;
    replyHeaders = {};
    r = await client().putResumable(uri, 600000, 0, null);
    expect(r.received, 0);
    expect(seen.last.headers.value('content-range'), 'bytes */600000');
    expect(seen.last.body, isEmpty);

    status = 201;
    reply = jsonEncode({'id': 'N1', 'headRevisionId': 'R1'});
    r = await client().putResumable(uri, 600000, 300000, [1, 2]);
    expect(r.file?.id, 'N1');
    expect(r.file?.headRevisionId, 'R1');
    expect(
      seen.last.headers.value('content-range'),
      'bytes 300000-300001/600000',
    );
  });

  test('putResumable 404 and 410 are DriveErrors', () async {
    final uri = 'http://127.0.0.1:${server.port}/session/1';
    for (final s in [404, 410]) {
      status = s;
      reply = '{}';
      await expectLater(
        client().putResumable(uri, 10, 0, null),
        throwsA(isA<DriveError>().having((e) => e.status, 'status', s)),
      );
    }
  });

  test('listRevisions follows every page', () async {
    replies = [
      for (var n = 1; n <= 3; n++)
        jsonEncode({
          'revisions': [
            {'id': 'R$n', 'modifiedTime': '2026-10-10T04:20:0$n.000Z'},
          ],
          if (n < 3) 'nextPageToken': 'p$n',
        }),
    ];
    final revs = await client().listRevisions('F1');
    expect([for (final r in revs) r.id], ['R1', 'R2', 'R3']);
    expect(seen[0].uri.path, '/drive/v3/files/F1/revisions');
    expect(seen[0].uri.queryParameters['pageSize'], '1000');
    expect(
      seen[0].uri.queryParameters['fields'],
      'nextPageToken,revisions(id,modifiedTime)',
    );
    expect(seen[1].uri.queryParameters['pageToken'], 'p1');
    expect(seen[2].uri.queryParameters['pageToken'], 'p2');
  });

  test('downloadRevision asks alt=media and returns the bytes', () async {
    reply = 'abc';
    final b = await client().downloadRevision('F1', 'R1');
    expect(utf8.decode(b), 'abc');
    expect(seen.single.uri.path, '/drive/v3/files/F1/revisions/R1');
    expect(seen.single.uri.queryParameters['alt'], 'media');
  });

  test(
    'get reads headRevisionId; modifiedTime and md5Checksum when asked',
    () async {
      reply = jsonEncode({
        'id': 'F1',
        'headRevisionId': 'R5',
        'md5Checksum': 'ab',
        'modifiedTime': '2026-10-10T04:20:00.000Z',
      });
      final f = await client().get('F1', fields: 'headRevisionId,trashed');
      expect(f.headRevisionId, 'R5');
      expect(f.md5Checksum, 'ab');
      expect(f.modifiedTime, '2026-10-10T04:20:00.000Z');
      expect(
        seen.single.uri.queryParameters['fields'],
        'headRevisionId,trashed',
      );
    },
  );

  test('the multipart boundary is random and not in the body', () async {
    reply = jsonEncode({'id': 'N1', 'headRevisionId': 'R1'});
    // Content that looks like the old fixed boundary changes nothing.
    final tricky = utf8.encode('--kkeujeok-multipart-boundary--');
    await client().uploadSimple(metadata: {'name': 'a'}, bytes: tricky);
    await client().uploadSimple(metadata: {'name': 'a'}, bytes: tricky);
    String b(_Req r) =>
        RegExp(r'boundary=(\S+)')
            .firstMatch(r.headers.contentType.toString())!
            .group(1)!;
    expect(b(seen[0]), isNot(b(seen[1])));
    for (final r in seen) {
      final boundary = b(r);
      expect(boundary, startsWith('kkj-'));
      expect('--$boundary'.allMatches(r.text).length, 3); // 2 parts and the end
      expect('--$boundary--'.allMatches(r.text).length, 1);
    }
  });
}
