import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../model/ids.dart' show canonicalNow;
import 'drive_client.dart';

const _defaultFields = 'id,name,parents,appProperties,createdTime,trashed';
const _upFields = 'id,headRevisionId,md5Checksum';

/// Drive v3 REST over `dart:io`. The HTTP client, base URL and token come
/// from the caller, so tests point it at a local server. Throws only
/// [DriveError].
class HttpDriveClient implements DriveClient {
  HttpDriveClient({
    required this.httpClient,
    required this.token,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.transferTimeout = const Duration(minutes: 2),
  }) : _base = baseUrl ?? Uri.parse('https://www.googleapis.com');

  final HttpClient Function() httpClient;
  final Future<String?> Function() token;
  final Uri _base;

  /// Longest a connection or a JSON call may take.
  final Duration timeout;

  /// Longest an upload or download body may take.
  final Duration transferTimeout;

  Uri _uri(String path, Map<String, String> query) => _base.replace(
    path: '${_base.path == '/' ? '' : _base.path}$path',
    queryParameters: query,
  );

  /// One request. A status outside 2xx is a [DriveError] unless it is in
  /// [accept]. Answer headers are keyed in lower case.
  Future<({int status, Map<String, String> headers, List<int> body})> _request(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
    Map<String, String> headers = const {},
    Set<int> accept = const {},
    bool follow = true,
  }) async {
    try {
      final t = await token();
      if (t == null || t.isEmpty) {
        throw const DriveError('http', status: 401, reason: 'noToken');
      }
      final client = httpClient();
      try {
        final req = await client.openUrl(method, uri).timeout(timeout);
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
        req.followRedirects = follow;
        headers.forEach(req.headers.set);
        if (contentType != null) {
          req.headers.set(HttpHeaders.contentTypeHeader, contentType);
        }
        if (body != null) {
          req.contentLength = body.length;
          req.add(body);
        }
        final res = await req.close().timeout(transferTimeout);
        final all = await res
            .fold<BytesBuilder>(BytesBuilder(copy: false), (b, c) => b..add(c))
            .timeout(transferTimeout);
        final bytes = all.takeBytes();
        final status = res.statusCode;
        if ((status < 200 || status > 299) && !accept.contains(status)) {
          throw DriveError(
            'http',
            status: status,
            reason: _reason(utf8.decode(bytes, allowMalformed: true)),
          );
        }
        final h = <String, String>{};
        res.headers.forEach((k, v) => h[k.toLowerCase()] = v.join(','));
        return (status: status, headers: h, body: bytes);
      } finally {
        client.close(force: true);
      }
    } on DriveError {
      rethrow;
    } catch (_) {
      // Socket, TLS, timeout, anything the platform throws: no connection.
      throw const DriveError('network');
    }
  }

  static Map<String, Object?> _json(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      if (json is Map) {
        return {for (final e in json.entries) '${e.key}': e.value};
      }
    } catch (_) {
      // falls through to parse
    }
    throw const DriveError('parse');
  }

  Future<Map<String, Object?>> _send(
    String method,
    Uri uri, [
    Map<String, Object?>? body,
  ]) async => _json(
    (await _request(
      method,
      uri,
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      contentType: body == null ? null : 'application/json',
    )).body,
  );

  /// First `error.errors[].reason`, or the OAuth-style `error` string.
  static String? _reason(String text) {
    try {
      final e = (jsonDecode(text) as Map)['error'];
      final list = e is Map ? e['errors'] : null;
      if (list is List && list.isNotEmpty) {
        final r = (list.first as Map)['reason'];
        if (r is String) return r;
      }
      if (e is String) return e;
    } catch (_) {}
    return null;
  }

  /// [fallbackId] stands in when the answer has no `id` (an update).
  static DriveFile _file(Object? json, [String? fallbackId]) {
    try {
      final m = json as Map;
      final props = m['appProperties'];
      final parents = m['parents'];
      return DriveFile(
        id: (m['id'] ?? fallbackId) as String,
        name: m['name'] as String?,
        parents: [if (parents is List) ...parents.whereType<String>()],
        appProperties: {
          if (props is Map)
            for (final e in props.entries)
              if (e.value is String) '${e.key}': e.value as String,
        },
        createdTime: m['createdTime'] as String?,
        trashed: m['trashed'] == true,
        headRevisionId: m['headRevisionId'] as String?,
        md5Checksum: m['md5Checksum'] as String?,
        modifiedTime: m['modifiedTime'] as String?,
        mimeType: m['mimeType'] as String?,
        thumbnailLink: m['thumbnailLink'] as String?,
      );
    } catch (_) {
      throw const DriveError('parse');
    }
  }

  @override
  Future<DrivePage> list(String q, {String? fields, String? pageToken}) async {
    final m = await _send(
      'GET',
      _uri('/drive/v3/files', {
        'q': q,
        'fields': 'nextPageToken,files(${fields ?? _defaultFields})',
        'pageSize': '1000',
        'spaces': 'drive',
        'pageToken': ?pageToken,
      }),
    );
    final files = m['files'];
    final next = m['nextPageToken'];
    if (files is! List || (next != null && next is! String)) {
      throw const DriveError('parse');
    }
    return DrivePage([for (final f in files) _file(f)], next as String?);
  }

  @override
  Future<DriveFile> create(Map<String, Object?> metadata) async => _file(
    await _send(
      'POST',
      _uri('/drive/v3/files', {'fields': _defaultFields}),
      metadata,
    ),
  );

  @override
  Future<DriveFile> get(String id, {String? fields}) async => _file(
    await _send(
      'GET',
      _uri('/drive/v3/files/${Uri.encodeComponent(id)}', {
        'fields': fields ?? _defaultFields,
      }),
    ),
    id, // a `fields` mask without `id` gets no `id` back
  );

  @override
  Future<DriveFile> update(
    String id, {
    String? addParents,
    String? removeParents,
    bool? trashed,
    Map<String, String>? appProperties,
  }) async => _file(
    await _send(
      'PATCH',
      _uri('/drive/v3/files/${Uri.encodeComponent(id)}', {
        'fields': _defaultFields,
        'addParents': ?addParents,
        'removeParents': ?removeParents,
      }),
      {'trashed': ?trashed, 'appProperties': ?appProperties},
    ),
  );

  Uri _upload(String type, String? fileId) => _uri(
    '/upload/drive/v3/files'
    '${fileId == null ? '' : '/${Uri.encodeComponent(fileId)}'}',
    {'uploadType': type, 'fields': _upFields},
  );

  @override
  Future<DriveFile> uploadSimple({
    String? fileId,
    required Map<String, Object?> metadata,
    required List<int> bytes,
  }) async {
    final boundary = _boundary(bytes, jsonEncode(metadata));
    final b = BytesBuilder(copy: false)
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '${jsonEncode(metadata)}\r\n'
          '--$boundary\r\n'
          'Content-Type: application/octet-stream\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));
    final r = await _request(
      fileId == null ? 'POST' : 'PATCH',
      _upload('multipart', fileId),
      body: b.takeBytes(),
      contentType: 'multipart/related; boundary=$boundary',
    );
    return _file(_json(r.body), fileId);
  }

  /// A random boundary that does not occur in the body.
  static String _boundary(List<int> bytes, String json) {
    final rnd = Random.secure();
    while (true) {
      final b =
          'kkj-${List.generate(24, (_) => rnd.nextInt(16).toRadixString(16)).join()}';
      final needle = utf8.encode(b);
      if (!json.contains(b) && !_contains(bytes, needle)) return b;
    }
  }

  static bool _contains(List<int> hay, List<int> needle) {
    final first = needle.first;
    for (var i = 0; i + needle.length <= hay.length; i++) {
      if (hay[i] != first) continue;
      var j = 1;
      while (j < needle.length && hay[i + j] == needle[j]) {
        j++;
      }
      if (j == needle.length) return true;
    }
    return false;
  }

  @override
  Future<String> startResumable({
    String? fileId,
    required Map<String, Object?> metadata,
    required int size,
  }) async {
    final r = await _request(
      fileId == null ? 'POST' : 'PATCH',
      _upload('resumable', fileId),
      body: utf8.encode(jsonEncode(metadata)),
      contentType: 'application/json; charset=UTF-8',
      headers: {
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '$size',
      },
    );
    final loc = r.headers['location'];
    if (loc == null || loc.isEmpty) throw const DriveError('parse');
    return loc;
  }

  @override
  Future<ResumableResult> putResumable(
    String uri,
    int size,
    int offset,
    List<int>? chunk,
  ) async {
    final range = chunk == null
        ? 'bytes */$size'
        : 'bytes $offset-${offset + chunk.length - 1}/$size';
    final r = await _request(
      'PUT',
      Uri.parse(uri),
      body: chunk ?? const <int>[],
      headers: {HttpHeaders.contentRangeHeader: range},
      accept: const {308},
      follow: false, // 308 here means "resume incomplete"
    );
    if (r.status == 308) {
      final m = RegExp(r'bytes=0-(\d+)').firstMatch(r.headers['range'] ?? '');
      return ResumableResult(
        received: m == null ? 0 : int.parse(m.group(1)!) + 1,
      );
    }
    return ResumableResult(file: _file(_json(r.body)));
  }

  @override
  Future<List<DriveRevision>> listRevisions(String fileId) async {
    final out = <DriveRevision>[];
    String? pageToken;
    do {
      final m = await _send(
        'GET',
        _uri('/drive/v3/files/${Uri.encodeComponent(fileId)}/revisions', {
          'fields': 'nextPageToken,revisions(id,modifiedTime,keepForever)',
          'pageSize': '1000',
          'pageToken': ?pageToken,
        }),
      );
      final list = m['revisions'];
      final next = m['nextPageToken'];
      if (list is! List || (next != null && next is! String)) {
        throw const DriveError('parse');
      }
      for (final r in list) {
        if (r is! Map || r['id'] is! String || r['modifiedTime'] is! String) {
          throw const DriveError('parse');
        }
        // Normalized to `YYYY-MM-DDTHH:mm:ss.sssZ` (Drive may omit the
        // milliseconds); one odd time must not void the whole history.
        final at = DateTime.tryParse(r['modifiedTime'] as String);
        out.add(
          DriveRevision(
            r['id'] as String,
            at == null ? r['modifiedTime'] as String : canonicalNow(at),
            keepForever: r['keepForever'] == true,
          ),
        );
      }
      pageToken = next as String?;
    } while (pageToken != null);
    return out;
  }

  @override
  Future<List<int>> downloadRevision(String fileId, String revisionId) async =>
      (await _request(
        'GET',
        _uri(
          '/drive/v3/files/${Uri.encodeComponent(fileId)}/revisions/'
          '${Uri.encodeComponent(revisionId)}',
          {'alt': 'media'},
        ),
      )).body;

  @override
  Future<void> updateRevision(
    String fileId,
    String revisionId, {
    required bool keepForever,
  }) => _send(
    'PATCH',
    _uri(
      '/drive/v3/files/${Uri.encodeComponent(fileId)}/revisions/'
      '${Uri.encodeComponent(revisionId)}',
      {'fields': 'id,keepForever'},
    ),
    {'keepForever': keepForever},
  );

  @override
  Future<List<int>> downloadFile(String fileId) async => (await _request(
    'GET',
    _uri('/drive/v3/files/${Uri.encodeComponent(fileId)}', {'alt': 'media'}),
  )).body;

  @override
  Future<String> getStartPageToken() async {
    final t = (await _send(
      'GET',
      _uri('/drive/v3/changes/startPageToken', {'spaces': 'drive'}),
    ))['startPageToken'];
    if (t is! String || t.isEmpty) throw const DriveError('parse');
    return t;
  }

  @override
  Future<ChangesPage> listChanges(String pageToken) async {
    final m = await _send(
      'GET',
      _uri('/drive/v3/changes', {
        'pageToken': pageToken,
        'spaces': 'drive',
        'pageSize': '1000',
        'includeRemoved': 'true',
        'restrictToMyDrive': 'true',
        'fields':
            'nextPageToken,newStartPageToken,changes(fileId,removed,file($noteFileFields))',
      }),
    );
    final list = m['changes'];
    final next = m['nextPageToken'], start = m['newStartPageToken'];
    if (list is! List ||
        (next != null && next is! String) ||
        (start != null && start is! String)) {
      throw const DriveError('parse');
    }
    final out = <DriveChange>[];
    for (final c in list) {
      if (c is! Map || c['fileId'] is! String) throw const DriveError('parse');
      final file = c['file'];
      out.add(
        DriveChange(
          c['fileId'] as String,
          removed: c['removed'] == true,
          file: file is Map ? _file(file, c['fileId'] as String) : null,
        ),
      );
    }
    if (next == null && start == null) throw const DriveError('parse');
    return ChangesPage(
      out,
      nextPageToken: next as String?,
      newStartPageToken: start as String?,
    );
  }
}
