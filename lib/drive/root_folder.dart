import '../storage/note_store.dart';
import '../storage/sync_device_store.dart';
import '../sync/error_class.dart';
import '../sync/sync_log.dart';
import 'auth_gateway.dart';
import 'drive_client.dart';
import 'duplicates.dart';

const rootFolderKkeujeokId = 'root';
const rootFolderName = 'Kkeujeok';
const _folderMime = 'application/vnd.google-apps.folder';

enum RootStatus {
  /// Not asked yet, or no Drive call is allowed (no account, other account).
  idle,
  preparing,
  ready,

  /// The root was trashed or deleted: the person decides (Story 3.9).
  missing,

  /// A call failed; [RootResult.errorClass] says which class.
  failed,
}

class RootResult {
  const RootResult(this.status, {this.folderId, this.errorClass});

  final RootStatus status;
  final String? folderId;
  final String? errorClass;
}

/// Finds, creates and repairs the `Kkeujeok` root folder (spec
/// `drive-layout` "Idempotent creation"). Items are found only by
/// `appProperties.kkeujeokId`. Never throws: every failure is a
/// [RootResult] of status `failed`.
class RootFolderService {
  RootFolderService({
    required this.client,
    required this.device,
    required this.notes,
    required this.log,
    required this.account,
    this.maxPages = 10,
  });

  final DriveClient client;
  final SyncDeviceStore device;
  final NoteStore notes;
  final SyncLog log;
  final AuthAccount? Function() account;

  /// Pages followed per listing; a listing that never ends is cut here.
  final int maxPages;

  Future<RootResult>? _flight;

  /// Makes sure the root exists and is cached. Concurrent callers share one
  /// run.
  Future<RootResult> ensureRoot() => _flight ?? _start(recreate: false);

  /// The foreground check: the same run as [ensureRoot] (the listing by id
  /// first, then the cached id), so a root that only moved is found
  /// silently and a trashed one is `missing`.
  Future<RootResult> checkRoot() => ensureRoot();

  /// [새로 만들기]: notes forget their Drive file first (so a half-done run
  /// repeats from the dialog), then a new root is found or created. Waits
  /// for a run in progress; never overlaps another.
  Future<RootResult> recreate() => _start(recreate: true);

  Future<RootResult> _start({required bool recreate}) async {
    // No await before the first check, so a caller that finds no flight
    // registers its own at once.
    while (_flight != null) {
      await _flight;
    }
    late final Future<RootResult> run;
    run = _prepare(recreate: recreate).whenComplete(() {
      if (identical(_flight, run)) _flight = null;
    });
    _flight = run;
    return run;
  }

  Future<RootResult> _prepare({required bool recreate}) async {
    try {
      final a = account();
      if (a == null) return const RootResult(RootStatus.idle);
      // The account may sign out or change during any await below.
      bool gone() => account()?.sub != a.sub;

      var dev = await device.read();
      if (dev.sub != null && dev.sub != a.sub) {
        return const RootResult(RootStatus.idle); // Story 3.7 handles it
      }
      if (dev.sub == null) {
        if (!await device.adoptAccount(a.sub, a.email)) {
          return await _fail('fatal', null, 'deviceUnreadable');
        }
        dev = await device.read();
      }
      final cached = dev.rootFolderId;
      if (gone()) return const RootResult(RootStatus.idle);

      if (recreate) await _resetNotes();
      if (cached == null || recreate) {
        // A recreate drops every other pending creation: they pointed into
        // the root that is gone.
        await device.write(
          dev.withRoot(cached, [
            if (!recreate) ..._otherIntents(dev),
            {
              'kkeujeokId': rootFolderKkeujeokId,
              'kind': 'root',
              'parentId': 'root',
            },
          ]),
        );
      }

      var found = (await _all(kkeujeokIdQuery(rootFolderKkeujeokId))).files;
      String? id;
      if (found.isEmpty) {
        if (cached != null && !recreate) {
          final f = await _getCached(cached);
          if (f == null) return const RootResult(RootStatus.missing);
          id = f.id; // the listing lagged behind
        } else {
          final created = await client.create({
            'name': rootFolderName,
            'mimeType': _folderMime,
            'parents': ['root'],
            'appProperties': {'kkeujeokId': rootFolderKkeujeokId},
          });
          found = (await _all(kkeujeokIdQuery(rootFolderKkeujeokId))).files;
          if (found.isEmpty) id = created.id; // the listing lags
        }
      }
      id ??= await _keepOne(found);

      // Another device made a new root: this device's file ids are stale.
      if (cached != null && id != cached && !recreate) await _resetNotes();

      if (gone()) return const RootResult(RootStatus.idle);
      final latest = await device.read();
      if (latest.sub != a.sub) return const RootResult(RootStatus.idle);
      await device.write(
        latest.withRoot(
          id,
          recreate ? const [] : _otherIntents(latest),
          forgetConflicts: recreate,
        ),
      );
      return RootResult(RootStatus.ready, folderId: id);
    } on DriveError catch (e) {
      return _fail(classifyDriveError(e), e.status, e.reason);
    } catch (_) {
      return _fail('fatal', null, 'localWrite');
    }
  }

  List<Map<String, Object?>> _otherIntents(SyncDevice d) => [
    for (final i in d.createIntents)
      if (i['kkeujeokId'] != rootFolderKkeujeokId) i,
  ];

  /// The cached root when it is alive; null when it is gone or trashed.
  Future<DriveFile?> _getCached(String id) async {
    try {
      final f = await client.get(id, fields: 'id,trashed');
      return f.trashed ? null : f;
    } on DriveError catch (e) {
      if (e.kind == 'http' && e.status == 404) return null;
      rethrow;
    }
  }

  /// Every page up to [maxPages]; `truncated` when more was left.
  Future<({List<DriveFile> files, bool truncated})> _all(String q) async {
    final out = <DriveFile>[];
    String? token;
    for (var page = 0; page < maxPages; page++) {
      final p = await client.list(q, pageToken: token);
      out.addAll(p.files);
      token = p.nextPageToken;
      if (token == null) return (files: out, truncated: false);
    }
    return (files: out, truncated: true);
  }

  /// The folder `drive.duplicates` keeps; the others get their children
  /// moved and are trashed last. A failure, or a children listing that was
  /// cut, leaves the duplicate for the next run.
  Future<String> _keepOne(List<DriveFile> found) async {
    final r = driveDuplicatesRule({
      'kkeujeokId': rootFolderKkeujeokId,
      'items': [
        for (final f in found)
          {
            'id': f.id,
            'createdTime': f.createdTime ?? '9999-12-31T23:59:59.999Z',
          },
      ],
    });
    final keep = r['keep'] as String;
    var cleaned = 0;
    for (final dup in (r['merge'] as List).cast<String>()) {
      try {
        final kids = await _all(childrenQuery(dup));
        for (final c in kids.files) {
          await client.update(c.id, addParents: keep, removeParents: dup);
        }
        if (kids.truncated) {
          await _fail('fatal', null, 'listTruncated');
          break; // children may be left in it: never trash it
        }
        await client.update(dup, trashed: true); // last
        cleaned++;
      } on DriveError catch (e) {
        await _fail(classifyDriveError(e), e.status, e.reason);
        break;
      }
    }
    if (cleaned > 0) await log.append('duplicatesCleaned', {'count': cleaned});
    return keep;
  }

  /// Every note forgets its Drive file and base and is pending again, with
  /// the same `noteId`. Only `sync.json` is written, so edits made while
  /// this runs stay; unreadable notes are reset too.
  Future<void> _resetNotes() async {
    for (final row in await notes.list()) {
      await notes.resetSync(row.noteId);
    }
  }

  Future<RootResult> _fail(String cls, int? status, String? reason) async {
    await log.append('error', {
      'class': cls,
      if (status != null && status >= 100 && status <= 599) 'status': status,
      'reason': ?reason,
    });
    return RootResult(RootStatus.failed, errorClass: cls);
  }
}
