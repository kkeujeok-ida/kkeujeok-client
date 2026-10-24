import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'note.dart';

/// The app's element clipboard (Story 4.6): deep-copied element JSON in page
/// order. Memory only, app wide, so it outlives the editor and its note.
class ElementClipboard extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() => const [];

  void set(Iterable<Map<String, dynamic>> elements) => state = [
    for (final e in elements) copyJsonValue(e) as Map<String, dynamic>,
  ];
}

final elementClipboardProvider =
    NotifierProvider<ElementClipboard, List<Map<String, dynamic>>>(
      ElementClipboard.new,
    );
