// Story 14.2: the app trash on Android. Everything here is Drive-only: a
// trashed note has no device copy (spec `trash`), so nothing touches the
// note store.
import '../drive/drive_client.dart';
import '../model/kkj_codec.dart';
import '../model/note.dart';
import '../storage/sync_device_store.dart';
import 'folder_service.dart';
import 'library_rules.dart' show RuleJson;
import 'trash_rules.dart';

const _folderMime = 'application/vnd.google-apps.folder';

/// One row of the trash (`trash.list`).
class TrashEntry {
  const TrashEntry({
    required this.isFolder,
    required this.id,
    required this.fileId,
    required this.title,
    required this.trashedAt,
    this.trashedFrom,
    this.noteCount = 0,
  });

  final bool isFolder;
  final String id;
  final String fileId;
  final String title;

  /// Canonical timestamp.
  final String trashedAt;
  final String? trashedFrom;
  final int noteCount;
}

enum TrashOutcome { done, gone, rootFallback, failed }

class TrashService {
  TrashService({
    required this.drive,
    required this.device,
    required this.folders,
  });

  final DriveClient drive;
  final SyncDeviceStore device;
  final FolderService folders;

  /// The direct children of `.trashbin`, newest delete first. Throws
  /// [DriveError].
  Future<List<TrashEntry>> list() async {
    final bin = await folders.trashbinFileId();
    if (bin == null) return const [];
    final files = await _all(childrenQuery(bin));
    final counts = <String, int>{
      for (final f in files)
        if (f.mimeType == _folderMime && f.appProperties['kkeujeokId'] != null)
          f.appProperties['kkeujeokId']!: await _notesBelow(f.id),
    };
    final r = trashListRule({
      'items': [
        for (final f in files)
          {
            'id': f.id,
            'name': f.name,
            'mimeType': f.mimeType,
            'modifiedTime': f.modifiedTime,
            'appProperties': f.appProperties,
          },
      ],
      'noteCounts': counts,
    });
    final byFile = {for (final f in files) f.id: f};
    return [
      for (final e in r['entries'] as List)
        TrashEntry(
          isFolder: (e as Map)['kind'] == 'folder',
          id: e['id'] as String,
          fileId: e['fileId'] as String,
          title: _title(byFile[e['fileId']]!),
          trashedAt: e['trashedAt'] as String,
          trashedFrom: e['trashedFrom'] as String?,
          noteCount: (e['noteCount'] as int?) ?? 0,
        ),
    ];
  }

  static String _title(DriveFile f) {
    final n = f.name ?? '';
    return n.endsWith('.kkj') ? n.substring(0, n.length - 4) : n;
  }

  Future<int> _notesBelow(String folderFile) async {
    var n = 0;
    for (final c in await _all(childrenQuery(folderFile))) {
      if (c.mimeType == _folderMime) {
        n += await _notesBelow(c.id);
      } else if (c.mimeType == noteMimeType) {
        n++;
      }
    }
    return n;
  }

  Future<List<DriveFile>> _all(String q) async {
    final out = <DriveFile>[];
    String? token;
    do {
      final p = await drive.list(
        q,
        fields: 'id,name,mimeType,modifiedTime,appProperties',
        pageToken: token,
      );
      out.addAll(p.files);
      token = p.nextPageToken;
    } while (token != null);
    return out;
  }

  /// Downloads a trashed note by file id for the read-only view; nothing is
  /// stored.
  Future<NoteReadResult> open(TrashEntry e) async =>
      decodeKkj(await drive.downloadFile(e.fileId));

  /// `files.get` just before a restore or purge; null = 404 (gone).
  Future<DriveFile?> _reread(String fileId) async {
    try {
      return await drive.get(
        fileId,
        fields: 'id,parents,trashed,appProperties',
      );
    } on DriveError catch (e) {
      if (e.kind == 'http' && e.status == 404) return null;
      rethrow;
    }
  }

  /// Whether the folder file [fileId] lies in `.trashbin` (or cannot be
  /// followed: then it is no destination).
  Future<bool> _inTrash(String fileId, String bin, String root) async {
    var cur = fileId;
    for (var i = 0; i < 64; i++) {
      final f = await _reread(cur);
      final p = f?.parents.firstOrNull;
      if (f == null || f.trashed || p == null || p == bin) return true;
      if (p == root) return false;
      cur = p;
    }
    return true;
  }

  /// `trash.restoreNote` / `trash.restoreFolder`.
  Future<TrashOutcome> restore(TrashEntry e) async {
    final bin = await folders.trashbinFileId();
    final root = (await device.read()).rootFolderId;
    if (bin == null || root == null) return TrashOutcome.failed;
    final cur = await _reread(e.fileId);
    if (cur == null) return TrashOutcome.gone;
    final from = cur.appProperties['trashedFrom'];
    Map<String, Object?>? origin;
    if (from != null && from != '' && from != 'root' && from != 'trashbin') {
      final found = await _all(kkeujeokIdQuery(from));
      if (found.isNotEmpty) {
        final f = found.first;
        final inTrash =
            await folders.trashPending(from) || await _inTrash(f.id, bin, root);
        origin = {'fileId': f.id, 'inTrash': inTrash};
      }
    }
    final RuleJson r = trashRestoreRule({
      'item': {
        'id': e.id,
        'fileId': e.fileId,
        'parentFileId': cur.parents.where((p) => p == bin).join(','),
        'parentId': cur.parents.contains(bin) ? 'trashbin' : 'other',
        'trashed': cur.trashed,
        'appProperties': cur.appProperties,
      },
      'trashbinFileId': bin,
      'rootFileId': root,
      'origin': origin,
    });
    if (r['gone'] == true) return TrashOutcome.gone;
    // Another device restored it: nothing to do here.
    if (r['already'] == true) return TrashOutcome.gone;
    final q = (r['request'] as Map).cast<String, Object?>();
    await drive.update(
      e.fileId,
      addParents: q['addParents'] as String,
      removeParents: q['removeParents'] as String,
      appProperties: {
        for (final p in (q['appProperties'] as Map).entries)
          '${p.key}': p.value as String?,
      },
    );
    return r['rootFallback'] == true
        ? TrashOutcome.rootFallback
        : TrashOutcome.done;
  }

  /// `trash.purgeItem`: `trashed=true`, never `files.delete`.
  Future<TrashOutcome> purge(TrashEntry e) async {
    final bin = await folders.trashbinFileId();
    if (bin == null) return TrashOutcome.failed;
    final cur = await _reread(e.fileId);
    if (cur == null) return TrashOutcome.gone;
    final r = trashPurgeRule({
      'item': {
        'fileId': e.fileId,
        'parentId': cur.parents.contains(bin) ? 'trashbin' : 'other',
        'trashed': cur.trashed,
      },
    });
    if (r['request'] == null) {
      return r['already'] == true ? TrashOutcome.gone : TrashOutcome.failed;
    }
    await drive.update(e.fileId, trashed: true);
    return TrashOutcome.done;
  }

  /// `trash.emptyTrash`: one by one; a failure does not stop the others.
  /// Returns the entries that are still in the trash.
  Future<List<TrashEntry>> empty(List<TrashEntry> entries) async {
    final left = <TrashEntry>[];
    for (final e in entries) {
      try {
        if (await purge(e) == TrashOutcome.failed) left.add(e);
      } on DriveError {
        left.add(e);
      }
    }
    return left;
  }
}
