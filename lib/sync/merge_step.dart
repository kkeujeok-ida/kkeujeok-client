import '../model/note.dart';

/// What a [MergeStep] answers.
sealed class MergeOutcome {
  const MergeOutcome();
}

/// The three versions were merged; [note] is what is uploaded next.
class Merged extends MergeOutcome {
  const Merged(this.note);

  final Note note;
}

/// No merge engine is installed (Story 3.3 supplies one).
class MergeNotImplemented extends MergeOutcome {
  const MergeNotImplemented();
}

/// The seam the uploader calls when Drive holds a version that is not ours
/// (spec `sync` steps 1 and 3). [base] is null for a note never uploaded.
///
/// Story 3.3 supplies the real step through `mergeStepProvider`; on `merged`
/// it rewrites the working copy through the editor queue (never through
/// `NoteStore.updateSync`).
abstract interface class MergeStep {
  Future<MergeOutcome> merge({
    required Note working,
    required Note? base,
    required Note remote,
  });
}

/// Default: answers [MergeNotImplemented], so nothing is overwritten.
class UnavailableMergeStep implements MergeStep {
  const UnavailableMergeStep();

  @override
  Future<MergeOutcome> merge({
    required Note working,
    required Note? base,
    required Note remote,
  }) async => const MergeNotImplemented();
}
