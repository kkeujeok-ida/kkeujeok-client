import 'package:flutter/foundation.dart';
import 'package:kkeujeok/sync/note_receiver.dart';

/// Records the receive triggers; the real work is tested in receive_test.
class RecReceiver implements NoteReceiver {
  @override
  final state = ValueNotifier<ReceiveState>(const ReceiveState());
  int checks = 0;
  final opened = <String>[];

  @override
  Future<void> check() async => checks++;

  @override
  Future<void> noteOpened(String noteId) async => opened.add(noteId);

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
