import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../model/image_rules.dart';
import 'atomic_file.dart';
import 'note_data.dart';

/// Bytes of image assets on this device, `assets/<sha256>.<ext>` in the app
/// documents directory. A file is written once (atomic) and kept after its
/// upload as a cache. Every read checks the SHA-256 (spec `image.md`).
class AssetStore {
  AssetStore(this._data);

  final NoteData _data;

  Future<Directory> _dir() async {
    final root = await _data.rootDir();
    return Directory('${root.path}${Platform.pathSeparator}assets');
  }

  static String sha256Hex(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();

  Future<File> _file(String hash, String ext) async =>
      File('${(await _dir()).path}${Platform.pathSeparator}$hash.$ext');

  /// Stores [bytes] under their hash and returns it. The same hash is not
  /// written again. Throws [FileSystemException] when the write fails.
  Future<String> write(List<int> bytes, String ext) async {
    // The extension comes from a note file: never a path.
    if (!const {'jpg', 'png', 'webp'}.contains(ext)) {
      throw ArgumentError.value(ext, 'ext');
    }
    final hash = sha256Hex(bytes);
    final f = await _file(hash, ext);
    if (!await f.exists() || await f.length() != bytes.length) {
      await writeFileAtomic(f, bytes);
    }
    return hash;
  }

  /// Stores [bytes] only when their SHA-256 is [hash]; false otherwise.
  Future<bool> writeVerified(String hash, String ext, List<int> bytes) async {
    if (sha256Hex(bytes) != hash) return false;
    await write(bytes, ext);
    return true;
  }

  /// The verified bytes of [hash], or null (missing, or corrupt: then the
  /// file is removed so it is fetched again).
  Future<List<int>?> read(String hash) async {
    if (!isAssetHash(hash)) return null;
    for (final ext in const ['jpg', 'png', 'webp']) {
      final f = await _file(hash, ext);
      try {
        if (!await f.exists()) continue;
        final b = await f.readAsBytes();
        if (sha256Hex(b) == hash) return b;
        await f.delete();
      } on FileSystemException {
        // unreadable: as missing
      }
    }
    return null;
  }

  /// Which of [hashes] have verified bytes here.
  Future<Set<String>> local(Iterable<String> hashes) async => {
    for (final h in hashes)
      if (await read(h) != null) h,
  };
}
