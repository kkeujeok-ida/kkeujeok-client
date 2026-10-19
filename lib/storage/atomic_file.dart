import 'dart:io';

var _writes = 0;

/// Writes [bytes] to a temp file next to [file], flushes, then renames over
/// [file], so a crash leaves the previous content. The temp name is unique
/// per call: two writers of one file (editor, receive, upload) never share a
/// temp file, which made the second rename fail with `localWrite`. Creates
/// the folder; the temp file is removed and the error rethrown on failure.
Future<void> writeFileAtomic(File file, List<int> bytes) async {
  final tmp = File('${file.path}.${pid}_${_writes++}.tmp');
  try {
    await file.parent.create(recursive: true);
    final out = await tmp.open(mode: FileMode.write);
    try {
      await out.writeFrom(bytes);
      await out.flush();
    } finally {
      await out.close();
    }
    await tmp.rename(file.path);
  } catch (_) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}
