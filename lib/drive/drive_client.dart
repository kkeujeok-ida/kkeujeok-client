/// A failed Drive call, in the terms of spec `sync.errorClass`: [kind] is
/// `http`, `network`, `trashed` or `parse`; [status] only for `http`;
/// [reason] the first `errors[].reason` of the Drive error.
class DriveError implements Exception {
  const DriveError(this.kind, {this.status, this.reason});

  final String kind;
  final int? status;
  final String? reason;

  @override
  String toString() => 'DriveError($kind, $status, $reason)';
}

/// The fields of a Drive file this client reads. A field not asked for is
/// empty.
class DriveFile {
  const DriveFile({
    required this.id,
    this.name,
    this.parents = const [],
    this.appProperties = const {},
    this.createdTime,
    this.trashed = false,
  });

  final String id;
  final String? name;
  final List<String> parents;
  final Map<String, String> appProperties;

  /// Canonical timestamp (`YYYY-MM-DDTHH:mm:ss.sssZ`) or null.
  final String? createdTime;
  final bool trashed;
}

/// One page of a listing; [nextPageToken] is null on the last one.
class DrivePage {
  const DrivePage(this.files, [this.nextPageToken]);

  final List<DriveFile> files;
  final String? nextPageToken;
}

/// The Drive v3 calls this client makes, behind one seam so tests use an
/// in-memory Drive and later stories (uploads) add methods here. Every
/// method throws only [DriveError].
abstract interface class DriveClient {
  Future<DrivePage> list(String q, {String? fields, String? pageToken});

  /// `files.create` with metadata only (`name`, `mimeType`, `parents`,
  /// `appProperties`).
  Future<DriveFile> create(Map<String, Object?> metadata);

  Future<DriveFile> get(String id, {String? fields});

  /// `files.update` of metadata: parents moved and/or the file trashed.
  Future<DriveFile> update(
    String id, {
    String? addParents,
    String? removeParents,
    bool? trashed,
  });
}

/// `q` for one `kkeujeokId` (spec `drive-layout` "Finding").
String kkeujeokIdQuery(String id) =>
    "appProperties has { key='kkeujeokId' and value='${escapeQ(id)}' } "
    'and trashed=false';

/// `q` for the live children of a folder.
String childrenQuery(String folderId) =>
    "'${escapeQ(folderId)}' in parents and trashed=false";

/// Escapes `\` first and then `'` for a quoted `q` string.
String escapeQ(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
