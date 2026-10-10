import 'package:google_sign_in/google_sign_in.dart';

import 'auth_gateway.dart';

const driveFileScope = 'https://www.googleapis.com/auth/drive.file';
const _scopes = [driveFileScope];

/// `google_sign_in` 7.x behind [AuthGateway]. Access tokens are fetched, used
/// as a "granted?" check and dropped: nothing is stored anywhere.
class GoogleAuthGateway implements AuthGateway {
  GoogleAuthGateway({
    this.serverClientId = const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
  });

  /// The web OAuth client ID, which Android's Credential Manager requires.
  final String serverClientId;

  Future<void>? _init;
  GoogleSignInAuthorizationClient? _client; // holds id and email only

  Future<void> _ready() async {
    try {
      await (_init ??= GoogleSignIn.instance.initialize(
        serverClientId: serverClientId.isEmpty ? null : serverClientId,
      ));
    } catch (_) {
      _init = null; // let the next attempt initialise again
      rethrow;
    }
  }

  @override
  Future<bool> restore() async {
    try {
      await _ready();
      final account = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (account == null) return false;
      final client = account.authorizationClient;
      if (await client.authorizationForScopes(_scopes) == null) return false;
      _client = client;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AuthOutcome> signIn() async {
    try {
      await _ready();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: _scopes,
      );
      _client = account.authorizationClient;
    } on GoogleSignInException catch (e) {
      return signInFailure(e.code);
    } catch (_) {
      return AuthOutcome.networkError;
    }
    return requestAccess();
  }

  @override
  Future<AuthOutcome> requestAccess() async {
    try {
      await _ready();
      final client = _client ?? GoogleSignIn.instance.authorizationClient;
      await client.authorizationForScopes(_scopes) ??
          await client.authorizeScopes(_scopes);
      return AuthOutcome.granted;
    } on GoogleSignInException catch (e) {
      return accessFailure(e.code, '${e.description} ${e.details}');
    } catch (_) {
      return AuthOutcome.networkError;
    }
  }

  @override
  Future<void> signOut() async {
    _client = null;
    await _ready();
    await GoogleSignIn.instance.signOut();
  }

  @override
  Future<void> disconnect() async {
    await _ready();
    await GoogleSignIn.instance.disconnect();
    _client = null;
  }
}

/// Account chooser failed: only the user backing out is silent; an
/// interrupted flow or a missing UI shows the retry notice instead of nothing.
AuthOutcome signInFailure(GoogleSignInExceptionCode code) =>
    code == GoogleSignInExceptionCode.canceled
    ? AuthOutcome.cancelled
    : AuthOutcome.networkError;

/// Drive permission request failed.
// ponytail: Android reports a refused consent screen as an API exception text,
// not a code; matched by text, confirm on a device.
AuthOutcome accessFailure(GoogleSignInExceptionCode code, String text) =>
    code == GoogleSignInExceptionCode.canceled ||
        text.toLowerCase().contains('cancel')
    ? AuthOutcome.denied
    : AuthOutcome.networkError;
