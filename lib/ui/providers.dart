import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../drive/auth_gateway.dart';
import '../drive/drive_client.dart';
import '../drive/google_auth_gateway.dart';
import '../drive/http_drive_client.dart';
import '../drive/root_folder.dart';
import '../model/ids.dart';
import '../model/note.dart';
import '../model/pen.dart';
import '../ops/history.dart';
import '../ops/ops.dart';
import '../storage/language_store.dart';
import '../storage/new_note_defaults_store.dart';
import '../storage/note_data.dart';
import '../storage/note_store.dart';
import '../storage/pen_slots_store.dart';
import '../storage/session_hint.dart';
import '../storage/sync_device_store.dart';
import '../sync/background_upload.dart';
import '../sync/merge_step.dart';
import '../sync/note_chain.dart';
import '../sync/note_receiver.dart';
import '../sync/note_uploader.dart';
import '../sync/open_note.dart';
import '../sync/sync_log.dart';
import '../sync/unsent.dart';
import '../sync/thumbnail.dart';
import '../sync/upload_coordinator.dart';

/// Overridden in main() with the opened preferences.
final languageStoreProvider = Provider<LanguageStore>(
  (ref) => LanguageStore(null),
);

class LanguageNotifier extends Notifier<LanguageChoice> {
  @override
  LanguageChoice build() => ref.read(languageStoreProvider).read();

  Future<void> select(LanguageChoice choice) async {
    state = choice;
    await ref.read(languageStoreProvider).write(choice);
    await applyAppLocale(choice);
  }
}

final languageProvider = NotifierProvider<LanguageNotifier, LanguageChoice>(
  LanguageNotifier.new,
);

/// Web `/privacy` address from `--dart-define-from-file` (PRIVACY_URL).
final privacyUrlProvider = Provider<String>(
  (ref) => const String.fromEnvironment('PRIVACY_URL'),
);

/// Opens an address in the external browser; false when it could not.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// The sign-in plugin behind its interface; widget tests override it.
/// Whether this device was signed in (a flag, never a token).
final sessionHintProvider = Provider<SessionHint>((ref) => SessionHint(null));

final authGatewayProvider = Provider<AuthGateway>(
  (ref) => GoogleAuthGateway(hint: ref.read(sessionHintProvider)),
);

/// The note data directory remover; tests point it at a temp directory.
final noteDataProvider = Provider<NoteData>((ref) => NoteData());

/// Per-device sync record (account tag, cached ids). Lives beside the notes
/// folder, so the log and this survive clearing the notes.
final syncDeviceStoreProvider = Provider<SyncDeviceStore>(
  (ref) => SyncDeviceStore(ref.read(noteDataProvider)),
);

/// The account (sub and e-mail) already written to the device record in this
/// process, so a save does not read the file again. Reset by disconnect.
class _AdoptedAccount {
  String? key;
}

final _adoptedAccountProvider = Provider<_AdoptedAccount>(
  (ref) => _AdoptedAccount(),
);

/// Every saved note tags the device with the signed-in account; a failure
/// never fails the save (NoteStore swallows it).
final noteStoreProvider = Provider<NoteStore>(
  (ref) => NoteStore(
    ref.read(noteDataProvider),
    onWrite: () async {
      final a = ref.read(authGatewayProvider).account;
      if (a == null) return; // also once disconnect has revoked
      final adopted = ref.read(_adoptedAccountProvider);
      final key = '${a.sub}\u0000${a.email}';
      if (adopted.key == key) return;
      final ok = await ref
          .read(syncDeviceStoreProvider)
          .adoptAccount(a.sub, a.email);
      if (ok) adopted.key = key;
    },
  ),
);

/// The local sync log. Kept when notes are cleared.
final syncLogProvider = Provider<SyncLog>(
  (ref) => SyncLog(ref.read(noteDataProvider).rootDir, DateTime.now),
);

/// Drive over HTTP; the token is asked from the gateway for every call.
final driveClientProvider = Provider<DriveClient>(
  (ref) => HttpDriveClient(
    httpClient: () => HttpClient(),
    token: ref.read(authGatewayProvider).accessToken,
  ),
);

final rootFolderServiceProvider = Provider<RootFolderService>(
  (ref) => RootFolderService(
    client: ref.read(driveClientProvider),
    device: ref.read(syncDeviceStoreProvider),
    notes: ref.read(noteStoreProvider),
    log: ref.read(syncLogProvider),
    account: () => ref.read(authGatewayProvider).account,
  ),
);

class RootFolderState {
  const RootFolderState(this.status, {this.errorClass, this.folderId});

  final RootStatus status;
  final String? errorClass;
  final String? folderId;
}

/// State of the Drive root folder for the library and the upload gate.
class RootFolderNotifier extends Notifier<RootFolderState> {
  int _gen = 0;
  DateTime? _lastCheck;

  @override
  RootFolderState build() {
    _gen++; // a run that started before a sign-in change is dropped
    ref.watch(authProvider.select((s) => s.phase == AuthPhase.signedIn));
    return const RootFolderState(RootStatus.idle);
  }

  /// First preparation, [다시 시도], and the foreground check. "Preparing"
  /// shows only when nothing usable is known yet, so a check on a ready
  /// root does not flash.
  Future<void> check() async {
    final s = state.status;
    _lastCheck = DateTime.now();
    return _run(
      (v) => v.checkRoot(),
      show: s == RootStatus.idle || s == RootStatus.failed,
    );
  }

  /// The foreground check: skipped when the last one was less than
  /// [rootCheckThrottleProvider] ago and the root is known (ready or
  /// missing); a ready root stays ready while it runs.
  Future<void> checkForeground() async {
    final s = state.status;
    final last = _lastCheck;
    if ((s == RootStatus.ready || s == RootStatus.missing) &&
        last != null &&
        DateTime.now().difference(last) < ref.read(rootCheckThrottleProvider)) {
      return;
    }
    return check();
  }

  /// [다시 로그인]: asks for the Drive permission again for the account
  /// already chosen, then checks the root once more when it was granted.
  Future<void> signInAgain() async {
    var outcome = AuthOutcome.networkError;
    try {
      outcome = await ref.read(authGatewayProvider).requestAccess();
    } catch (_) {}
    if (ref.mounted && outcome == AuthOutcome.granted) await check();
  }

  /// [새로 만들기] of the missing-root dialog.
  Future<void> recreate() => _run((v) => v.recreate(), show: true);

  /// For uploads (Story 3.11) that got 404 or trashed on the root: checks
  /// again before anything is shown.
  Future<void> reportRootGone() => _run((v) => v.checkRoot(), show: false);

  Future<void> _run(
    Future<RootResult> Function(RootFolderService) call, {
    required bool show,
  }) async {
    final gen = _gen;
    if (show) state = const RootFolderState(RootStatus.preparing);
    final r = await call(ref.read(rootFolderServiceProvider));
    if (!ref.mounted || gen != _gen) return;
    state = RootFolderState(
      r.status,
      errorClass: r.errorClass,
      folderId: r.folderId,
    );
  }
}

/// Foreground re-checks closer together than this are skipped.
final rootCheckThrottleProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

final rootFolderProvider =
    NotifierProvider<RootFolderNotifier, RootFolderState>(
      RootFolderNotifier.new,
    );

/// Uploads run only while the root is ready.
final uploadsAllowedProvider = Provider<bool>(
  (ref) => ref.watch(rootFolderProvider).status == RootStatus.ready,
);

/// The open editors, which merge a sync result into their own queue.
final mergeHostsProvider = Provider<MergeHosts>((ref) => MergeHosts());

/// Merges a version that is not ours against the queue state at commit time
/// (Story 3.3). A kept undo history forgets the pages a merge replaced.
final mergeStepProvider = Provider<MergeStep>(
  (ref) => QueueMergeStep(
    store: ref.read(noteStoreProvider),
    hosts: ref.read(mergeHostsProvider),
    onApplied: (noteId, merged, undoDrop) =>
        ref.read(noteHistoriesProvider)[noteId]?.adopt(merged, undoDrop),
  ),
);

/// False only while the device is known to be offline.
final networkProbeProvider = Provider<Future<bool> Function()>(
  (ref) => deviceOnline,
);

/// Asks WorkManager for a task that uploads when a network is there.
final backgroundSchedulerProvider = Provider<Future<void> Function()>(
  (ref) => scheduleBackgroundUpload,
);

/// The note the editor has open.
final openNoteProvider = Provider<OpenNote>(
  (ref) => OpenNote(ref.read(noteDataProvider).rootDir),
);

final uploadLeaseProvider = Provider<UploadLease>(
  (ref) => UploadLease(ref.read(noteDataProvider), DateTime.now),
);

/// One run per note at a time, shared by uploads and receives.
final noteChainProvider = Provider<NoteChain>((ref) => NoteChain());

final noteUploaderProvider = Provider<NoteUploader>(
  (ref) => NoteUploader(
    chain: ref.read(noteChainProvider),
    store: ref.read(noteStoreProvider),
    drive: ref.read(driveClientProvider),
    device: ref.read(syncDeviceStoreProvider),
    log: ref.read(syncLogProvider),
    merge: ref.read(mergeStepProvider),
    allowed: () async => ref.read(uploadsAllowedProvider),
    online: ref.read(networkProbeProvider),
    sleep: Future<void>.delayed,
    jitter: Random().nextDouble,
    thumbnail: renderThumbnail,
    heartbeat: ref.read(uploadLeaseProvider).renew,
  ),
);

/// Receives remote changes (Story 3.13): app start, foreground, 20 s poll.
final noteReceiverProvider = Provider<NoteReceiver>((ref) {
  final r = NoteReceiver(
    store: ref.read(noteStoreProvider),
    drive: ref.read(driveClientProvider),
    device: ref.read(syncDeviceStoreProvider),
    log: ref.read(syncLogProvider),
    merge: ref.read(mergeStepProvider),
    hosts: ref.read(mergeHostsProvider),
    allowed: () async => ref.read(uploadsAllowedProvider),
    online: ref.read(networkProbeProvider),
    account: () => ref.read(authGatewayProvider).account,
    sleep: Future<void>.delayed,
    jitter: Random().nextDouble,
    chain: ref.read(noteChainProvider),
  );
  ref.onDispose(r.dispose);
  return r;
});

/// The receiver's state for the library and the editor.
class ReceiveStateNotifier extends Notifier<ReceiveState> {
  @override
  ReceiveState build() {
    final r = ref.watch(noteReceiverProvider);
    void follow() {
      if (ref.mounted) state = r.state.value;
    }

    r.state.addListener(follow);
    ref.onDispose(() => r.state.removeListener(follow));
    return r.state.value;
  }
}

final receiveStateProvider =
    NotifierProvider<ReceiveStateNotifier, ReceiveState>(
      ReceiveStateNotifier.new,
    );

/// Upload triggers: note closed, background, app start, foreground.
final uploadCoordinatorProvider = Provider<UploadCoordinator>(
  (ref) => UploadCoordinator(
    store: ref.read(noteStoreProvider),
    uploader: ref.read(noteUploaderProvider),
    openNote: ref.read(openNoteProvider),
    lease: ref.read(uploadLeaseProvider),
    log: ref.read(syncLogProvider),
    allowed: () async => ref.read(uploadsAllowedProvider),
    online: ref.read(networkProbeProvider),
    schedule: ref.read(backgroundSchedulerProvider),
  ),
);

/// Hands an exported log file to the system share sheet.
final logSharerProvider = Provider<Future<void> Function(File)>(
  (ref) =>
      (file) => SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/x-ndjson')],
        ),
      ),
);

final appVersionProvider = Provider<Future<String> Function()>(
  (ref) =>
      () async => (await PackageInfo.fromPlatform()).version,
);

/// Hands exported note files to the system share sheet (its targets include
/// saving to a chosen place).
final noteFilesSharerProvider = Provider<Future<void> Function(List<File>)>(
  (ref) =>
      (files) => SharePlus.instance.share(
        ShareParams(
          files: [
            for (final f in files)
              XFile(f.path, mimeType: 'application/octet-stream'),
          ],
        ),
      ),
);

/// The notes with changes Drive does not have; null = could not check.
final unsentIdsProvider = Provider<Future<List<String>?> Function()>(
  (ref) =>
      () => unsentNoteIds(ref.read(noteStoreProvider)),
);

/// Erases every local copy of the notes and the device record (account tag,
/// cached ids). False, with the device record kept, when the notes cannot be
/// deleted. The sync log stays.
final discardLocalDataProvider = Provider<Future<bool> Function()>(
  (ref) => () async {
    try {
      await ref.read(noteDataProvider).clear();
    } catch (_) {
      return false;
    }
    ref.read(noteHistoriesProvider).clear();
    ref.read(_adoptedAccountProvider).key = null;
    await ref.read(syncDeviceStoreProvider).clear();
    return true;
  },
);

/// Where the exported log is written before sharing.
final exportDirProvider = Provider<Future<Directory> Function()>(
  (ref) => getTemporaryDirectory,
);

/// Undo/redo history per note id, for this app process only (never written
/// to disk), so it survives moving between notes.
final noteHistoriesProvider = Provider<Map<String, History>>((ref) => {});

/// Overridden in main() with the opened preferences.
final newNoteDefaultsStoreProvider = Provider<NewNoteDefaultsStore>(
  (ref) => NewNoteDefaultsStore(null),
);

/// Overridden in main() with the opened preferences.
final penSlotsStoreProvider = Provider<PenSlotsStore>(
  (ref) => PenSlotsStore(null),
);

/// The pen slots the toolbar and the editor share.
class PenSlotsNotifier extends Notifier<List<Pen>> {
  @override
  List<Pen> build() => ref.read(penSlotsStoreProvider).read();

  /// Applies at once; the next stroke uses it. A failed save keeps the value
  /// for this session.
  Future<void> setUsePressure(int index, bool value) async {
    if (index < 0 || index >= state.length) return;
    final next = [...state]..[index] = state[index].withUsePressure(value);
    state = next;
    await ref.read(penSlotsStoreProvider).write(next);
  }
}

final penSlotsProvider = NotifierProvider<PenSlotsNotifier, List<Pen>>(
  PenSlotsNotifier.new,
);

/// One row of the library: a readable note, or one that cannot be opened
/// ([note] null).
class LibraryEntry {
  const LibraryEntry(this.noteId, this.note, this.editedAt);

  final String noteId;
  final Note? note;

  /// Latest page `editedAt`; null when no page has a readable date.
  final DateTime? editedAt;

  bool get readable => note != null;
}

/// Never throws: a missing, non-string or unparseable `editedAt` is skipped.
DateTime? _lastEdited(Note n) {
  DateTime? latest;
  for (final p in n.pages) {
    final v = p['editedAt'];
    final t = v is String ? DateTime.tryParse(v) : null;
    if (t != null && (latest == null || t.isAfter(latest))) latest = t;
  }
  return latest;
}

int _rank(LibraryEntry e) => !e.readable ? 2 : (e.editedAt == null ? 1 : 0);

/// Newest edit first, equal dates by noteId descending; readable notes
/// without a date after those with one; unreadable last.
int _compare(LibraryEntry a, LibraryEntry b) {
  final r = _rank(a).compareTo(_rank(b));
  if (r != 0) return r;
  final c = a.editedAt == null ? 0 : b.editedAt!.compareTo(a.editedAt!);
  return c != 0 ? c : b.noteId.compareTo(a.noteId);
}

class LibraryNotifier extends AsyncNotifier<List<LibraryEntry>> {
  @override
  Future<List<LibraryEntry>> build() => _load();

  Future<List<LibraryEntry>> _load() async {
    final rows = await ref.read(noteStoreProvider).list();
    return [
      for (final r in rows)
        LibraryEntry(
          r.noteId,
          r.result.note,
          r.result.note == null ? null : _lastEdited(r.result.note!),
        ),
    ]..sort(_compare);
  }

  /// Reads the folder again; keeps the old list when that fails, and stays
  /// in the error state when there never was one.
  Future<void> reload() async {
    if (!state.hasValue) state = const AsyncLoading();
    try {
      final list = await _load();
      if (ref.mounted) state = AsyncData(list);
    } catch (e, st) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, st);
    }
  }

  /// Creates, saves and lists a one-page note. Throws [NoteSaveException];
  /// nothing is stored and the defaults stay as they were in that case.
  Future<Note> create({
    required String title,
    required String background,
    required String orientation,
  }) async {
    final current = state.value ?? await _load();
    final r = createNote(
      title: title,
      existingTitles: [
        for (final e in current)
          if (e.note != null) e.note!.title,
      ],
      background: background,
      orientation: orientation,
      noteId: newId(),
      pageId: newId(),
      pageRev: newId(),
      metaRev: newId(),
      orderRev: newId(),
      now: canonicalNow(DateTime.now()),
      editedBy: deviceEditedBy,
    );
    final note = r.note;
    if (note == null) throw NoteSaveException(r.error ?? 'could not create');
    await ref.read(noteStoreProvider).write(note);
    await ref
        .read(newNoteDefaultsStoreProvider)
        .write(background: background, orientation: orientation);
    if (ref.mounted) {
      // The list may have changed while the save ran: add to what is there.
      final latest = state.value ?? current;
      state = AsyncData(
        [LibraryEntry(note.noteId, note, _lastEdited(note)), ...latest]
          ..sort(_compare),
      );
    }
    return note;
  }
}

/// Dropped with the shell, so a new session reads the folder again.
final libraryProvider =
    AsyncNotifierProvider.autoDispose<LibraryNotifier, List<LibraryEntry>>(
      LibraryNotifier.new,
    );

/// How long the plugin may take to sign out or revoke before it counts as
/// failed, so a dialog is never busy forever.
const authCallTimeout = Duration(seconds: 10);

enum DisconnectResult { done, revokeFailed, deleteFailed }

enum AuthPhase { checking, signedOut, working, signedIn }

enum AuthProblem { none, denied, network }

class AuthState {
  const AuthState(this.phase, [this.problem = AuthProblem.none]);

  final AuthPhase phase;
  final AuthProblem problem;
}

/// Signed-in state lives in memory only; relaunch asks the gateway again.
class AuthNotifier extends Notifier<AuthState> {
  AuthGateway get _gateway => ref.read(authGatewayProvider);

  @override
  AuthState build() {
    _restore();
    return const AuthState(AuthPhase.checking);
  }

  Future<void> _restore() async {
    var ok = false;
    try {
      // A stalled lightweight sign-in must not leave a blank screen forever.
      ok = await _gateway.restore().timeout(authCallTimeout);
    } catch (_) {}
    if (!ref.mounted) return;
    state = AuthState(ok ? AuthPhase.signedIn : AuthPhase.signedOut);
  }

  Future<void> signIn() => _run(() => _gateway.signIn());

  /// Asks for the Drive permission again, nothing else.
  Future<void> requestAccess() => _run(() => _gateway.requestAccess());

  /// Ends the session without asking; a plugin error still ends it locally.
  /// Notes on the device stay.
  Future<void> signOut() async {
    if (state.phase != AuthPhase.signedIn) return;
    _revoked = false; // a later session, maybe another account, starts clean
    try {
      await _gateway.signOut().timeout(authCallTimeout);
    } catch (_) {}
    if (!ref.mounted) return;
    state = const AuthState(AuthPhase.signedOut);
  }

  // True once the grant is revoked but the local delete has not finished, so a
  // retry does not revoke again.
  bool _revoked = false;

  /// Revokes the grant, then removes the note data directory. A failed
  /// revocation leaves local data alone; a failed delete is retried without
  /// revoking again.
  Future<DisconnectResult> disconnect() async {
    if (state.phase != AuthPhase.signedIn) return DisconnectResult.revokeFailed;
    if (!_revoked) {
      try {
        await _gateway.disconnect().timeout(authCallTimeout);
      } catch (_) {
        return DisconnectResult.revokeFailed;
      }
      _revoked = true;
    }
    // Both deletes are tried, then reported. The gateway has no account any
    // more (revoked above), so a save in flight cannot tag the device again.
    // The log stays.
    var failed = false;
    try {
      await ref.read(noteDataProvider).clear();
    } catch (_) {
      failed = true;
    }
    ref.read(noteHistoriesProvider).clear();
    ref.read(_adoptedAccountProvider).key = null;
    try {
      await ref.read(syncDeviceStoreProvider).clear();
    } catch (_) {
      failed = true;
    }
    if (failed) return DisconnectResult.deleteFailed;
    _revoked = false;
    if (ref.mounted) state = const AuthState(AuthPhase.signedOut);
    return DisconnectResult.done;
  }

  Future<void> _run(Future<AuthOutcome> Function() call) async {
    if (state.phase != AuthPhase.signedOut) return;
    state = const AuthState(AuthPhase.working);
    _revoked = false;
    var outcome = AuthOutcome.networkError;
    try {
      outcome = await call();
    } catch (_) {}
    if (!ref.mounted) return;
    state = switch (outcome) {
      AuthOutcome.granted => const AuthState(AuthPhase.signedIn),
      AuthOutcome.cancelled => const AuthState(AuthPhase.signedOut),
      AuthOutcome.denied => const AuthState(
        AuthPhase.signedOut,
        AuthProblem.denied,
      ),
      AuthOutcome.networkError => const AuthState(
        AuthPhase.signedOut,
        AuthProblem.network,
      ),
    };
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// An http(s) address with a host, or null (treated as not configured).
Uri? privacyUri(String url) {
  final u = Uri.tryParse(url.trim());
  return u != null &&
          (u.scheme == 'https' || u.scheme == 'http') &&
          u.host.isNotEmpty
      ? u
      : null;
}
