import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../drive/auth_gateway.dart';
import '../drive/google_auth_gateway.dart';
import '../storage/language_store.dart';
import '../storage/session_hint.dart';
import '../storage/note_data.dart';

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
