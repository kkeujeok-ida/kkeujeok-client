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
  /// `pageReadOnly`. This adds to the locked set; [setLocks] replaces it. A
  /// merge keeps the locks.
  void lockPages(Set<String> pages) => _locked.addAll(pages);

  /// Replaces the locked set (Story 3.21): a resolved page is editable again.
  void setLocks(Set<String> pages) {
    _locked
      ..clear()
      ..addAll(pages);
  }

  bool sameLocks(Set<String> pages) =>
      pages.length == _locked.length && _locked.containsAll(pages);

  bool isLocked(String? pageId) => pageId != null && _locked.contains(pageId);

  /// Every page id a record names: `pageId`, `pageIds`, `items[].pageId` and
  /// the pages an `insertPages` brings back.
  static Set<String> _touched(Map<String, dynamic> op) => {
    if (op['pageId'] is String) op['pageId'] as String,
    for (final id in (op['pageIds'] as List? ?? const [])) id as String,
    for (final it in (op['items'] as List? ?? const []))
      if (it is Map && it['pageId'] is String)
        it['pageId'] as String
      else if (it is Map &&
          it['page'] is Map &&
          (it['page'] as Map)['id'] is String)
        (it['page'] as Map)['id'] as String,
  };

  bool _lockedOp(Map<String, dynamic> op) => _touched(op).any(_locked.contains);

  /// The inverse of the last [doOp] made with `record: false`, else null.
  Map<String, dynamic>? lastInverse;

  /// Error code, or null on success. A failure changes nothing. With
  /// `record: false` the op leaves no undo record and the redo records stay;
  /// the caller keeps its own undo in [lastInverse] (the page overview's
  /// delete history).
  String? doOp(Map<String, dynamic> op, Ctx ctx, {bool record = true}) {
    if (isLocked(op['pageId'] as String?)) return 'pageReadOnly';
    final r = applyOp(note, op, ctx);
    if (r.error != null) return r.error;
    note = r.note!;
    final inv = r.inverse;
    lastInverse = record ? null : inv;
    if (inv != null && record) {
      _undo.add(inv);
      _redo.clear();
    }
    return null;
  }

  /// Takes the note a merge made and forgets the undo and redo records of
  /// [pages] (spec `merge.undoDrop`, AD-16): they would undo another device's
  /// work. Records of other pages stay.
  void adopt(Note merged, Set<String> pages) {
    note = merged;
    bool hit(Map<String, dynamic> op) => _touched(op).any(pages.contains);
    _undo.removeWhere(hit);
    _redo.removeWhere(hit);
  }

  String? undo(Ctx ctx) => _replay(_undo, _redo, ctx);
  String? redo(Ctx ctx) => _replay(_redo, _undo, ctx);

  String? _replay(
    List<Map<String, dynamic>> from,
    List<Map<String, dynamic>> to,
    Ctx ctx,
  ) {
    if (from.isEmpty) return null;
    if (_lockedOp(from.last)) return 'pageReadOnly';
    final r = applyOp(note, from.last, ctx);
    if (r.error != null) return r.error;
    note = r.note!;
    from.removeLast();
    to.add(r.inverse!);
    return null;
  }
}
