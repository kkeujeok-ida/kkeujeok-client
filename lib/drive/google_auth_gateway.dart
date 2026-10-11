import 'package:google_sign_in/google_sign_in.dart';

import '../storage/session_hint.dart';
import 'auth_gateway.dart';

const driveFileScope = 'https://www.googleapis.com/auth/drive.file';
const _scopes = [driveFileScope];

/// `google_sign_in` 7.x behind [AuthGateway]. Access tokens are fetched, used
/// as a "granted?" check and dropped: no token is stored anywhere. Only a
/// "signed in" flag ([SessionHint]) is kept, so launching needs no Google UI.
class GoogleAuthGateway implements AuthGateway {
  GoogleAuthGateway({
    this.serverClientId = const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
    SessionHint? hint,
  }) : _hint = hint ?? SessionHint(null);

  final SessionHint _hint;

  /// The web OAuth client ID, which Android's Credential Manager requires.
  final String serverClientId;

  AuthAccount? _account;

  @override
  AuthAccount? get account => _account;

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

  /// Opens signed in when this device was signed in before. Google is not
  /// asked: the lightweight sign-in would flash its sheet on every launch, and
  /// the Drive token is only needed later, when something calls Drive.
  @override
  Future<bool> restore() async {
    if (!_hint.signedIn) return false;
    final a = _hint.account; // stored by the last granted sign-in
    if (a != null) _account = AuthAccount(sub: a.sub, email: a.email);
    return true;
  }

  @override
  Future<AuthOutcome> signIn() async {
    try {
      await _ready();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: _scopes,
      );
      _client = account.authorizationClient;
      _account = AuthAccount(sub: account.id, email: account.email);
    } on GoogleSignInException catch (e) {
      return signInFailure(e.code);
    } catch (_) {
      return AuthOutcome.networkError;
    }
    final r = await requestAccess();
    if (r != AuthOutcome.granted) {
      _client = null; // no half-signed-in account
      _account = null;
    }
    return r;
  }

  @override
  Future<AuthOutcome> requestAccess() async {
    try {
      await _ready();
      final client = _client ?? GoogleSignIn.instance.authorizationClient;
      await client.authorizationForScopes(_scopes) ??
          await client.authorizeScopes(_scopes);
      await _hint.set(true);
      final a = _account;
      if (a != null) await _hint.setAccount(a.sub, a.email);
      return AuthOutcome.granted;
    } on GoogleSignInException catch (e) {
      return accessFailure(e.code, '${e.description} ${e.details}');
    } catch (_) {
      return AuthOutcome.networkError;
    }
  }

  @override
  Future<String?> accessToken() async {
    await _ready(); // throws on a plugin failure: not "no grant"
    final client = _client ?? GoogleSignIn.instance.authorizationClient;
    return (await client.authorizationForScopes(_scopes))?.accessToken;
  }

  @override
  Future<void> signOut() async {
    _client = null;
    _account = null;
    await _hint.set(false); // the session ends here even if Google errors
    await _ready();
    await GoogleSignIn.instance.signOut();
  }

  @override
  Future<void> disconnect() async {
    await _ready();
    await GoogleSignIn.instance.disconnect();
    _client = null;
    _account = null;
    await _hint.set(false);
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
