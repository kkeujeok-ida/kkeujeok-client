import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../drive/drive_client.dart';
import '../drive/google_auth_gateway.dart';
import '../drive/http_drive_client.dart';
import '../storage/note_data.dart';
import '../storage/note_store.dart';
import '../storage/session_hint.dart';
import '../storage/sync_device_store.dart';
import 'merge_step.dart';
import 'note_uploader.dart';
import 'open_note.dart';
import 'sync_log.dart';
import 'thumbnail.dart';
import 'upload_coordinator.dart';

const _uniqueName = 'kkeujeok-upload';
const _taskName = 'kkeujeok.upload';

/// False only when the device says it has no network. A probe that fails is
/// "online": the request itself then decides (and backs off).
Future<bool> deviceOnline() async {
  try {
    final r = await Connectivity().checkConnectivity();
    return r.isEmpty || r.any((x) => x != ConnectivityResult.none);
  } catch (_) {
    return true;
  }
}

/// Entry point of the WorkManager task. It may run in a second isolate, or
/// (the plugin's choice) on the running engine.
@pragma('vm:entry-point')
void backgroundUploadDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await runBackgroundUpload();
    } catch (_) {
      // Notes keep their state on disk; the next trigger repeats.
    }
    return true;
  });
}

/// WorkManager is Android only; elsewhere nothing is set up.
Future<void> initBackgroundUpload() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(backgroundUploadDispatcher);
}

/// One unique task that waits for a network; asking again while one is
/// pending changes nothing.
Future<void> scheduleBackgroundUpload() async {
  if (!Platform.isAndroid) return;
  await Workmanager().registerOneOffTask(
    _uniqueName,
    _taskName,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

/// Uploads every unsent note except the one the editor has open. Builds its
/// own object graph: no Riverpod, no UI. The arguments exist for tests.
///
/// The gate: this device is signed in, the local data is that account's, the
/// root folder is known and still alive on Drive (a trashed or deleted root
/// is left to the app, which asks the person).
Future<void> runBackgroundUpload({
  SharedPreferences? prefs,
  NoteData? data,
  DriveClient? drive,
  Future<bool> Function()? online,
}) async {
  final hint = SessionHint(prefs ?? await SharedPreferences.getInstance());
  final saved = hint.account;
  if (!hint.signedIn || saved == null) return;

  final noteData = data ?? NoteData();
  final device = SyncDeviceStore(noteData);
  final d = await device.read();
  final rootId = d.rootFolderId;
  if (rootId == null || d.sub != saved.sub) return;

  final store = NoteStore(noteData);
  final log = SyncLog(noteData.rootDir, DateTime.now);
  final client =
      drive ??
      HttpDriveClient(
        httpClient: HttpClient.new,
        token: GoogleAuthGateway(hint: hint).accessToken,
      );

  bool? alive;
  Future<bool> rootAlive() async {
    if (alive != null) return alive!;
    try {
      alive = !(await client.get(rootId, fields: 'id,trashed')).trashed;
    } on DriveError catch (e) {
      alive = false;
      if (e.kind == 'http' && e.status == 404) {
        await log.append('error', {
          'class': 'deleted',
          'status': 404,
          'reason': 'rootGone',
        });
      }
    } catch (_) {
      alive = false;
    }
    return alive!;
  }

  final probe = online ?? deviceOnline;
  final lease = UploadLease(noteData, DateTime.now);
  final uploader = NoteUploader(
    store: store,
    drive: client,
    device: device,
    log: log,
    // No editor lives in this isolate: the note is merged under its lock.
    merge: QueueMergeStep(store: store, hosts: MergeHosts()),
    allowed: rootAlive,
    online: probe,
    sleep: Future<void>.delayed,
    jitter: Random().nextDouble,
    thumbnail: renderThumbnail,
    heartbeat: lease.renew,
  );
  final coordinator = UploadCoordinator(
    store: store,
    uploader: uploader,
    openNote: OpenNote(noteData.rootDir),
    lease: lease,
    log: log,
    allowed: rootAlive,
    online: probe,
    schedule: () async {}, // already running
  );
  await coordinator.uploadUnsent();
}
