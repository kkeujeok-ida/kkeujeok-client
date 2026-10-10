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

/// The only door to the Google sign-in plugin, so widgets and state can be
/// tested with a fake and plugin changes stay in one place.
abstract interface class AuthGateway {
  /// Lightweight sign-in on relaunch. True only when an account is signed in
  /// and Drive access was granted earlier; never shows UI, never throws.
  Future<bool> restore();

  /// Account choice, then the Drive permission, from the start.
  Future<AuthOutcome> signIn();

  /// Asks for the Drive permission again for the account already chosen.
  Future<AuthOutcome> requestAccess();
}
