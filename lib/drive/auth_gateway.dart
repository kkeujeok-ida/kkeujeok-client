/// Result of a sign-in or access request. No token ever crosses this seam.
enum AuthOutcome {
  /// Signed in and Drive access granted.
  granted,

  /// The user closed the account chooser. Not an error.
  cancelled,

  /// The account was chosen but Drive access was refused.
  denied,

  /// Anything else that went wrong, shown as a connection problem.
  networkError,
}

/// The signed-in Google account: its stable `sub` and e-mail. Never a token.
class AuthAccount {
  const AuthAccount({required this.sub, required this.email});
  final String sub;
  final String email;
}

/// The only door to the Google sign-in plugin, so widgets and state can be
/// tested with a fake and plugin changes stay in one place.
abstract interface class AuthGateway {
  /// The account chosen by the last successful [signIn] in this process;
  /// null when none, or after [signOut] and [disconnect]. A relaunch that
  /// only restores the session does not know it.
  AuthAccount? get account;

  /// Lightweight sign-in on relaunch. True only when an account is signed in
  /// and Drive access was granted earlier; never shows UI, never throws.
  Future<bool> restore();

  /// Account choice, then the Drive permission, from the start.
  Future<AuthOutcome> signIn();

  /// Asks for the Drive permission again for the account already chosen.
  Future<AuthOutcome> requestAccess();

  /// Ends the session. Notes on the device are not touched. Throws when the
  /// plugin fails; the caller still treats the session as ended.
  Future<void> signOut();

  /// Revokes the Drive grant for this app. Throws unless it was revoked.
  Future<void> disconnect();
}
