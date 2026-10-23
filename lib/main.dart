import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage/language_store.dart';
import 'storage/new_note_defaults_store.dart';
import 'storage/pen_slots_store.dart';
import 'storage/session_hint.dart';
import 'sync/background_upload.dart';
import 'ui/app.dart';
import 'ui/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Full screen by default: no status bar or navigation bar over the page. A
  // swipe from an edge shows them for a moment and they hide again.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    // Falls back to "follow system" for this session.
  }
  try {
    // The task that uploads when a network returns (Android WorkManager).
    await initBackgroundUpload();
  } catch (_) {
    // Uploads still run from the app's own triggers.
  }
  final container = ProviderContainer(
    overrides: [
      languageStoreProvider.overrideWithValue(LanguageStore(prefs)),
      newNoteDefaultsStoreProvider.overrideWithValue(
        NewNoteDefaultsStore(prefs),
      ),
      penSlotsStoreProvider.overrideWithValue(PenSlotsStore(prefs)),
      sessionHintProvider.overrideWithValue(SessionHint(prefs)),
    ],
  );
  // Nothing is open when the process starts: the mark of a dead process goes
  // here, once, never at a later upload trigger.
  try {
    await container.read(openNoteProvider).clear();
  } catch (_) {
    // Not fatal: a stale mark only keeps one note from the background task.
  }
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
