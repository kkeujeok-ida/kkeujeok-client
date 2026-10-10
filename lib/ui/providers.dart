import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
