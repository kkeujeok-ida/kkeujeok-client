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
    this.headRevisionId,
    this.md5Checksum,
    this.modifiedTime,
    this.mimeType,
    this.thumbnailLink,
  });

  final String id;
  final String? name;
  final List<String> parents;
  final Map<String, String> appProperties;

  /// Canonical timestamp (`YYYY-MM-DDTHH:mm:ss.sssZ`) or null.
  final String? createdTime;
  final bool trashed;

  /// Id of the newest revision, when asked for.
  final String? headRevisionId;
  final String? md5Checksum;

  /// Canonical timestamp or null.
  final String? modifiedTime;
  final String? mimeType;
  final String? thumbnailLink;
}

/// One entry of `changes.list`: [file] is null for a removed file.
class DriveChange {
  const DriveChange(this.fileId, {this.removed = false, this.file});

  final String fileId;
  final bool removed;
  final DriveFile? file;
}

/// One page of `changes.list`: [nextPageToken] while more follow, else
/// [newStartPageToken] is the token to save.
class ChangesPage {
  const ChangesPage(this.changes, {this.nextPageToken, this.newStartPageToken});

  final List<DriveChange> changes;
  final String? nextPageToken;
  final String? newStartPageToken;
}

/// One entry of `revisions.list` (`id`, `modifiedTime`).
class DriveRevision {
  const DriveRevision(this.id, this.modifiedTime);

  final String id;
  final String modifiedTime;
}

/// Answer of one resumable `PUT`: [file] is set when the upload finished
/// (200 or 201); otherwise [received] is the number of bytes Drive holds
/// (308).
class ResumableResult {
  const ResumableResult({this.received = 0, this.file});

  final int received;
  final DriveFile? file;
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

  /// One `multipart` upload (`fields=id,headRevisionId`). Creates when
  /// [fileId] is null, else replaces the content of [fileId]. [metadata] is
  /// the JSON part; an update never carries `parents`.
  Future<DriveFile> uploadSimple({
    String? fileId,
    required Map<String, Object?> metadata,
    required List<int> bytes,
  });

  /// Starts a resumable session with the same metadata; returns its URI.
  Future<String> startResumable({
    String? fileId,
    required Map<String, Object?> metadata,
    required int size,
  });

  /// One `PUT` of a session. A null [chunk] asks how far it got
  /// (`Content-Range: bytes */size`). HTTP 404 or 410 is a [DriveError].
  Future<ResumableResult> putResumable(
    String uri,
    int size,
    int offset,
    List<int>? chunk,
  );

  /// Every revision of [fileId] (all pages, `pageSize=1000`).
  Future<List<DriveRevision>> listRevisions(String fileId);

  /// `revisions.get` with `alt=media`.
  Future<List<int>> downloadRevision(String fileId, String revisionId);

  /// `changes.getStartPageToken`.
  Future<String> getStartPageToken();

  /// One page of `changes.list`. HTTP 400, 404 or 410 is a rejected token.
  Future<ChangesPage> listChanges(String pageToken);
}

/// `mimeType` of a note file.
const noteMimeType = 'application/vnd.kkeujeok.kkj';

/// The file fields a receive reads (listing and changes).
const noteFileFields =
    'id,name,parents,appProperties,createdTime,trashed,headRevisionId,'
    'md5Checksum,modifiedTime,mimeType,thumbnailLink';

/// `q` for every live note file (the tree scan of spec `sync`).
const noteTreeQuery = "trashed=false and mimeType='$noteMimeType'";

/// `q` for one `kkeujeokId` (spec `drive-layout` "Finding").
String kkeujeokIdQuery(String id) =>
    "appProperties has { key='kkeujeokId' and value='${escapeQ(id)}' } "
    'and trashed=false';

/// `q` for the live children of a folder.
String childrenQuery(String folderId) =>
    "'${escapeQ(folderId)}' in parents and trashed=false";

/// Escapes `\` first and then `'` for a quoted `q` string.
String escapeQ(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
