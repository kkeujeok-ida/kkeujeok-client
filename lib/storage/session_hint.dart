import 'package:shared_preferences/shared_preferences.dart';

/// Remembers only that this device was signed in, so the app can open straight
/// into the shell without asking Google anything at launch (which would show
/// the Google sheet). It is a flag plus the account's `sub` and e-mail (so a
/// relaunch still knows whom the local data belongs to), never a token:
/// access tokens are fetched on demand and never stored.
class SessionHint {
  SessionHint(this._prefs);

  /// Null when preferences could not be opened: nothing is remembered.
  final SharedPreferences? _prefs;

  static const _key = 'signedIn';
  static const _subKey = 'accountSub';
  static const _emailKey = 'accountEmail';

  /// The account remembered with the flag; null when not both are stored.
  ({String sub, String email})? get account {
    try {
      final sub = _prefs?.getString(_subKey),
          email = _prefs?.getString(_emailKey);
      return sub == null || email == null ? null : (sub: sub, email: email);
    } catch (_) {
      return null;
    }
  }

  Future<void> setAccount(String sub, String email) async {
    try {
      await _prefs?.setString(_subKey, sub);
      await _prefs?.setString(_emailKey, email);
    } catch (_) {
      // Not remembered: the tag is unknown until the next sign-in.
    }
  }

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
        await _prefs?.remove(_subKey);
        await _prefs?.remove(_emailKey);
      }
    } catch (_) {
      // Not remembered: the next launch shows the sign-in screen.
    }
  }
}
