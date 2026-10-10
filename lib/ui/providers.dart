import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../drive/auth_gateway.dart';
import '../drive/google_auth_gateway.dart';
import '../storage/language_store.dart';

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
final authGatewayProvider = Provider<AuthGateway>((ref) => GoogleAuthGateway());

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
      ok = await _gateway.restore().timeout(const Duration(seconds: 10));
    } catch (_) {}
    if (!ref.mounted) return;
    state = AuthState(ok ? AuthPhase.signedIn : AuthPhase.signedOut);
  }

  Future<void> signIn() => _run(() => _gateway.signIn());

  /// Asks for the Drive permission again, nothing else.
  Future<void> requestAccess() => _run(() => _gateway.requestAccess());

  Future<void> _run(Future<AuthOutcome> Function() call) async {
    if (state.phase != AuthPhase.signedOut) return;
    state = const AuthState(AuthPhase.working);
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
