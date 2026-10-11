import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'drive_client.dart';

const _defaultFields = 'id,name,parents,appProperties,createdTime,trashed';

/// Drive v3 REST over `dart:io`. The HTTP client, base URL and token come
/// from the caller, so tests point it at a local server. Throws only
/// [DriveError].
class HttpDriveClient implements DriveClient {
  HttpDriveClient({
    required this.httpClient,
    required this.token,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 30),
  }) : _base = baseUrl ?? Uri.parse('https://www.googleapis.com');

  final HttpClient Function() httpClient;
  final Future<String?> Function() token;
  final Uri _base;
  final Duration timeout;

  Uri _uri(String path, Map<String, String> query) => _base.replace(
    path: '${_base.path == '/' ? '' : _base.path}$path',
    queryParameters: query,
  );

  Future<Map<String, Object?>> _send(
    String method,
    Uri uri, [
    Map<String, Object?>? body,
  ]) async {
    try {
      final t = await token();
      if (t == null || t.isEmpty) {
        throw const DriveError('http', status: 401, reason: 'noToken');
      }
      final client = httpClient();
      try {
        final req = await client.openUrl(method, uri).timeout(timeout);
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.add(utf8.encode(jsonEncode(body)));
        }
        final res = await req.close().timeout(timeout);
        final text = await utf8.decodeStream(res).timeout(timeout);
        if (res.statusCode < 200 || res.statusCode > 299) {
          throw DriveError(
            'http',
            status: res.statusCode,
            reason: _reason(text),
          );
        }
        try {
          final json = jsonDecode(text);
          if (json is Map) {
            return {for (final e in json.entries) '${e.key}': e.value};
          }
        } on FormatException {
          // falls through to parse
        }
        throw const DriveError('parse');
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

  static DriveFile _file(Object? json) {
    try {
      final m = json as Map;
      final props = m['appProperties'];
      final parents = m['parents'];
      return DriveFile(
        id: m['id'] as String,
        name: m['name'] as String?,
        parents: [if (parents is List) ...parents.whereType<String>()],
        appProperties: {
          if (props is Map)
            for (final e in props.entries)
              if (e.value is String) '${e.key}': e.value as String,
        },
        createdTime: m['createdTime'] as String?,
        trashed: m['trashed'] == true,
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
  );

  @override
  Future<DriveFile> update(
    String id, {
    String? addParents,
    String? removeParents,
    bool? trashed,
  }) async => _file(
    await _send(
      'PATCH',
      _uri('/drive/v3/files/${Uri.encodeComponent(id)}', {
        'fields': _defaultFields,
        'addParents': ?addParents,
        'removeParents': ?removeParents,
      }),
      {'trashed': ?trashed},
    ),
  );
}
