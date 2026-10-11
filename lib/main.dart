import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage/language_store.dart';
import 'storage/new_note_defaults_store.dart';
import 'storage/pen_slots_store.dart';
import 'storage/session_hint.dart';
import 'ui/app.dart';
import 'ui/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    // Falls back to "follow system" for this session.
  }
  runApp(
    ProviderScope(
      overrides: [
        languageStoreProvider.overrideWithValue(LanguageStore(prefs)),
        newNoteDefaultsStoreProvider.overrideWithValue(
          NewNoteDefaultsStore(prefs),
        ),
        penSlotsStoreProvider.overrideWithValue(PenSlotsStore(prefs)),
        sessionHintProvider.overrideWithValue(SessionHint(prefs)),
      ],
      child: const App(),
    ),
  );
}
