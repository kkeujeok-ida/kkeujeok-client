import 'dart:io';

/// Writes [bytes] to `<file>.tmp`, flushes, then renames over [file], so a
/// crash leaves the previous content. Creates the folder; the temp file is
/// removed and the error rethrown on failure.
Future<void> writeFileAtomic(File file, List<int> bytes) async {
  final tmp = File('${file.path}.tmp');
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
