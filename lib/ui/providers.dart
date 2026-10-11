import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../drive/auth_gateway.dart';
import '../drive/google_auth_gateway.dart';
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

final noteStoreProvider = Provider<NoteStore>(
  (ref) => NoteStore(ref.read(noteDataProvider)),
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

// ponytail: the Android model name needs a device-info plugin; one constant
// until a story adds it.
const deviceEditedBy = 'Android';

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
    try {
      await ref.read(noteDataProvider).clear();
      ref.read(noteHistoriesProvider).clear(); // the notes are gone
    } catch (_) {
      return DisconnectResult.deleteFailed;
    }
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
