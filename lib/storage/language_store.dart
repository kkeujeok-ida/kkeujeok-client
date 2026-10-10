import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LanguageChoice { system, ko, en }

/// Device settings live in SharedPreferences, apart from the note data dir.
class LanguageStore {
  LanguageStore(this._prefs);

  /// Null when preferences could not be opened: the choice then lasts for
  /// this session only.
  final SharedPreferences? _prefs;

  static const _key = 'language';

  LanguageChoice read() {
    String? name;
    try {
      name = _prefs?.getString(_key);
    } catch (_) {
      // A value of the wrong type is treated as no choice.
    }
    return LanguageChoice.values.asNameMap()[name] ?? LanguageChoice.system;
  }

  Future<void> write(LanguageChoice choice) async {
    try {
      await _prefs?.setString(_key, choice.name);
    } catch (_) {
      // Save failed: the choice still applies for this session.
    }
  }
}

/// Korean device -> Korean; anything else -> English.
Locale resolveLocale(LanguageChoice choice, List<Locale>? device) {
  switch (choice) {
    case LanguageChoice.ko:
      return const Locale('ko');
    case LanguageChoice.en:
      return const Locale('en');
    case LanguageChoice.system:
      final first = (device == null || device.isEmpty) ? null : device.first;
      return Locale(first?.languageCode == 'ko' ? 'ko' : 'en');
  }
}

/// Mirrors the choice into the system per-app language (API 33+, handled in
/// MainActivity). `system` clears it. A no-op where the channel is absent.
Future<void> applyAppLocale(LanguageChoice choice) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await const MethodChannel('com.kkeujeok.app/locale').invokeMethod<void>(
      'setApplicationLocales',
      choice == LanguageChoice.system ? null : choice.name,
    );
  } on PlatformException {
    // Best effort.
  } on MissingPluginException {
    // Not running inside MainActivity (tests).
  }
}
