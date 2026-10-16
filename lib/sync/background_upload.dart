import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

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

Future<void> initBackgroundUpload() =>
    Workmanager().initialize(backgroundUploadDispatcher);

/// One unique task that waits for a network; asking again while one is
/// pending changes nothing.
Future<void> scheduleBackgroundUpload() => Workmanager().registerOneOffTask(
  _uniqueName,
  _taskName,
  constraints: Constraints(networkType: NetworkType.connected),
  existingWorkPolicy: ExistingWorkPolicy.keep,
);

/// Uploads every unsent note except the one the editor has open. Builds its
/// own object graph: no Riverpod, no UI.
Future<void> runBackgroundUpload() async {
  final prefs = await SharedPreferences.getInstance();
  final hint = SessionHint(prefs);
  final saved = hint.account;
  if (!hint.signedIn || saved == null) return;

  final auth = GoogleAuthGateway(hint: hint);
  final data = NoteData();
  final device = SyncDeviceStore(data);
  final d = await device.read();
  // The gate: the root folder is known and the local data is this account's.
  if (d.rootFolderId == null || d.sub != saved.sub) return;

  final store = NoteStore(data);
  final log = SyncLog(data.rootDir, DateTime.now);
  final random = Random();
  final uploader = NoteUploader(
    store: store,
    drive: HttpDriveClient(httpClient: HttpClient.new, token: auth.accessToken),
    device: device,
    log: log,
    merge: const UnavailableMergeStep(),
    allowed: () async => true,
    online: deviceOnline,
    sleep: Future<void>.delayed,
    jitter: random.nextDouble,
    thumbnail: renderThumbnail,
  );
  final coordinator = UploadCoordinator(
    store: store,
    uploader: uploader,
    openNote: OpenNote(data.rootDir),
    lease: UploadLease(data, DateTime.now),
    log: log,
    allowed: () async => true,
    online: deviceOnline,
    schedule: () async {}, // already running
  );
  await coordinator.uploadUnsent();
}
