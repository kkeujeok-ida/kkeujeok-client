/// Runs work for one note id after the earlier work of the same id, so an
/// upload and a receive of one note never interleave. A failure of one run
/// does not stop the next.
class NoteChain {
  final _chains = <String, Future<void>>{};

  Future<T> run<T>(String noteId, Future<T> Function() body) {
    final run = (_chains[noteId] ?? Future<void>.value()).then((_) => body());
    final done = run.then<void>((_) {}, onError: (Object _) {});
    _chains[noteId] = done;
    done.whenComplete(() {
      if (identical(_chains[noteId], done)) _chains.remove(noteId);
    });
    return run;
  }
}
