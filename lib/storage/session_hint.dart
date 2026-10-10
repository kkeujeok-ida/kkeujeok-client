import 'package:shared_preferences/shared_preferences.dart';

/// Remembers only that this device was signed in, so the app can open straight
/// into the shell without asking Google anything at launch (which would show
/// the Google sheet). It is a flag, not a token or an account: access tokens
/// are still fetched on demand and never stored.
class SessionHint {
  SessionHint(this._prefs);

  /// Null when preferences could not be opened: nothing is remembered.
  final SharedPreferences? _prefs;

  static const _key = 'signedIn';

  bool get signedIn {
    try {
      return _prefs?.getBool(_key) ?? false;
    } catch (_) {
      return false; // a value of the wrong type counts as signed out
    }
  }

  Future<void> set(bool signedIn) async {
    try {
      if (signedIn) {
        await _prefs?.setBool(_key, true);
      } else {
        await _prefs?.remove(_key);
      }
    } catch (_) {
      // Not remembered: the next launch shows the sign-in screen.
    }
  }
}
