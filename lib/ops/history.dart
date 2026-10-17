import '../model/note.dart';
import 'ops.dart';

/// Undo/redo for one note (spec `ops.undoRedo`). Holds operations only; every
/// undo or redo is applied as a new op, so rev and seq never go back.
class History {
  History(this.note);

  Note note;
  final _undo = <Map<String, dynamic>>[];
  final _redo = <Map<String, dynamic>>[];

  int get undoDepth => _undo.length;
  int get redoDepth => _redo.length;

  final _locked = <String>{};

  /// Makes [pages] read-only (a conflict waits for the person, Story 3.19):
  /// an op on them and an undo or redo of their records answer
  /// `pageReadOnly`. Locks are only added here; a merge keeps them.
  void lockPages(Set<String> pages) => _locked.addAll(pages);

  bool isLocked(String? pageId) => pageId != null && _locked.contains(pageId);

  /// Error code, or null on success. A failure changes nothing.
  String? doOp(Map<String, dynamic> op, Ctx ctx) {
    if (isLocked(op['pageId'] as String?)) return 'pageReadOnly';
    final r = applyOp(note, op, ctx);
    if (r.error != null) return r.error;
    note = r.note!;
    _undo.add(r.inverse!);
    _redo.clear();
    return null;
  }

  /// Takes the note a merge made and forgets the undo and redo records of
  /// [pages] (spec `merge.undoDrop`, AD-16): they would undo another device's
  /// work. Records of other pages stay.
  void adopt(Note merged, Set<String> pages) {
    note = merged;
    _undo.removeWhere((op) => pages.contains(op['pageId']));
    _redo.removeWhere((op) => pages.contains(op['pageId']));
  }

  String? undo(Ctx ctx) => _replay(_undo, _redo, ctx);
  String? redo(Ctx ctx) => _replay(_redo, _undo, ctx);

  String? _replay(
    List<Map<String, dynamic>> from,
    List<Map<String, dynamic>> to,
    Ctx ctx,
  ) {
    if (from.isEmpty) return null;
    if (isLocked(from.last['pageId'] as String?)) return 'pageReadOnly';
    final r = applyOp(note, from.last, ctx);
    if (r.error != null) return r.error;
    note = r.note!;
    from.removeLast();
    to.add(r.inverse!);
    return null;
  }
}
