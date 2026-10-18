import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/drive/http_drive_client.dart';

class _Req {
  _Req(this.method, this.uri, this.auth, this.body);
  final String method;
  final Uri uri;
  final String? auth;
  final String body;
}

void main() {
  late HttpServer server;
  late List<_Req> seen;
  late int status;
  late String reply;
  String? token;

  HttpDriveClient client() => HttpDriveClient(
    httpClient: () => HttpClient(),
    token: () async => token,
    baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    timeout: const Duration(seconds: 5),
  );

  setUp(() async {
    seen = [];
    status = 200;
    reply = '{}';
    token = 'tok';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      seen.add(
        _Req(
          r.method,
          r.uri,
          r.headers.value(HttpHeaders.authorizationHeader),
          await utf8.decodeStream(r),
        ),
      );
      r.response.statusCode = status;
      r.response.write(reply);
      await r.response.close();
    });
    addTearDown(() => server.close(force: true));
  });

  Future<DriveError> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } on DriveError catch (e) {
      return e;
    }
    throw StateError('did not fail');
  }

  test('list sends q, fields and the bearer token; reads a page', () async {
    reply = jsonEncode({
      'nextPageToken': 'p2',
      'files': [
        {
          'id': 'a',
          'name': 'Kkeujeok',
          'parents': ['root'],
          'appProperties': {'kkeujeokId': 'root'},
          'createdTime': '2026-10-10T04:20:00.000Z',
        },
      ],
    });
    final p = await client().list("x='y'", pageToken: 'p1');
    final r = seen.single;
    expect(r.method, 'GET');
    expect(r.auth, 'Bearer tok');
    expect(r.uri.path, '/drive/v3/files');
    expect(r.uri.queryParameters['q'], "x='y'");
    expect(r.uri.queryParameters['pageToken'], 'p1');
    expect(r.uri.queryParameters['fields'], contains('appProperties'));
    expect(p.nextPageToken, 'p2');
    expect(p.files.single.id, 'a');
    expect(p.files.single.parents, ['root']);
    expect(p.files.single.appProperties['kkeujeokId'], 'root');
  });

  test('create posts JSON metadata', () async {
    reply = '{"id":"n1"}';
    final f = await client().create({
      'name': 'Kkeujeok',
      'parents': ['root'],
    });
    expect(f.id, 'n1');
    expect(seen.single.method, 'POST');
    expect(jsonDecode(seen.single.body), {
      'name': 'Kkeujeok',
      'parents': ['root'],
    });
  });

  test('get and update address the file id', () async {
    reply = '{"id":"a/b","trashed":true}';
    final g = await client().get('a/b', fields: 'id,trashed');
    expect(g.trashed, isTrue);
    expect(seen.single.uri.path, '/drive/v3/files/a%2Fb');
    await client().update(
      'c',
      addParents: 'k',
      removeParents: 'd',
      trashed: true,
    );
    final u = seen.last;
    expect(u.method, 'PATCH');
    expect(u.uri.queryParameters['addParents'], 'k');
    expect(u.uri.queryParameters['removeParents'], 'd');
    expect(jsonDecode(u.body), {'trashed': true});
  });

  test('update can set appProperties alone (the sidecar mark)', () async {
    reply = '{"id":"c"}';
    await client().update('c', appProperties: {'kkjResolved': 'T'});
    expect(seen.last.method, 'PATCH');
    expect(jsonDecode(seen.last.body), {
      'appProperties': {'kkjResolved': 'T'},
    });
  });

  test('a Drive error carries status and the first reason', () async {
    status = 403;
    reply = jsonEncode({
      'error': {
        'errors': [
          {'reason': 'rateLimitExceeded'},
          {'reason': 'other'},
        ],
      },
    });
    final e = await failure(() => client().get('a'));
    expect((e.kind, e.status, e.reason), ('http', 403, 'rateLimitExceeded'));
  });

  test(
    'an error body that is not JSON is an http error without reason',
    () async {
      status = 502;
      reply = '<html>bad gateway</html>';
      final e = await failure(() => client().get('a'));
      expect((e.kind, e.status, e.reason), ('http', 502, null));
    },
  );

  test('a 2xx body that is not JSON is parse', () async {
    reply = 'not json';
    expect((await failure(() => client().get('a'))).kind, 'parse');
  });

  test('a file without an id is parse', () async {
    reply = '{"name":"x"}';
    expect((await failure(() => client().create({}))).kind, 'parse');
  });

  test('get with a fields mask that leaves out id still parses', () async {
    // Drive answers only the fields asked for (Story 11.1).
    reply = '{"headRevisionId":"r9"}';
    final g = await client().get('a', fields: 'headRevisionId');
    expect((g.id, g.headRevisionId), ('a', 'r9'));
  });

  test('no token is 401 without a call', () async {
    token = null;
    final e = await failure(() => client().get('a'));
    expect((e.kind, e.status), ('http', 401));
    expect(seen, isEmpty);
  });

  test('no connection is network', () async {
    final c = client();
    await server.close(force: true);
    expect((await failure(() => c.get('a'))).kind, 'network');
  });

  test('a token function that throws is network, not an exception', () async {
    final c = HttpDriveClient(
      httpClient: () => HttpClient(),
      token: () async => throw StateError('plugin'),
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    expect((await failure(() => c.get('a'))).kind, 'network');
  });
}
