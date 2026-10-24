import 'dart:async';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../drive/drive_client.dart';
import '../model/image_rules.dart';
import '../storage/asset_store.dart';
import 'error_class.dart';
import 'sync_rules.dart';

/// What the device knows about the image assets of the open note (spec
/// `image`): which have verified bytes here, which could not be fetched, and
/// which Drive is known to hold. Fetches the missing ones in the background
/// with `sync.backoff`. Listeners are told of every change.
class AssetSync extends ChangeNotifier {
  AssetSync({
    required this.store,
    required this.drive,
    required this.online,
    required this.allowed,
    required this.sleep,
    required this.jitter,
  });

  final AssetStore store;
  final DriveClient drive;
  final Future<bool> Function() online;
  final Future<bool> Function() allowed;
  final Future<void> Function(Duration) sleep;
  final double Function() jitter;

  final _local = <String>{};
  final _failed = <String>{};
  final _confirmed = <String>{};
  final _busy = <String>{};
  final _unconfirmed = <String>{}; // Drive said no; asked again on an event
  bool _disposed = false;

  /// Hashes whose bytes are on this device and verified.
  Set<String> get local => _local;

  /// Hashes whose last fetch failed.
  Set<String> get failed => _failed;

  /// Hashes Drive is known to hold.
  Set<String> get confirmed => _confirmed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Bytes were just stored here (an insert); Drive has not seen them.
  void markLocal(String hash) {
    _unconfirmed.remove(hash);
    if (_local.add(hash)) _changed();
  }

  /// The uploader found [hash] on Drive.
  void markConfirmed(String hash) {
    _unconfirmed.remove(hash);
    if (_confirmed.add(hash)) _changed();
  }

  /// [assets] maps a hash to its `ext` for every image of the open note.
  /// Reads the disk for the ones not yet known, fetches the ones that are
  /// not here (once at a time), and asks Drive about the ones it may not
  /// have. Never throws.
  Future<void> ensure(Map<String, String> assets) async {
    for (final e in assets.entries) {
      final h = e.key;
      if (!isAssetHash(h) || _busy.contains(h)) continue;
      if (!_local.contains(h)) {
        _busy.add(h); // before the await: an overlapping call skips it
        final here = await store.read(h) != null;
        _busy.remove(h);
        if (here) {
          _local.add(h);
          _changed();
        } else if (!_failed.contains(h)) {
          unawaited(_fetch(h, e.value));
          continue;
        }
      }
      if (_local.contains(h) &&
          !_confirmed.contains(h) &&
          !_unconfirmed.contains(h)) {
        unawaited(_confirm(h));
      }
    }
  }

  /// [다시 시도]: forgets the failure and fetches again.
  void retry(String hash, String ext) {
    if (_busy.contains(hash) || _local.contains(hash)) return;
    _failed.remove(hash);
    _unconfirmed.remove(hash);
    unawaited(_fetch(hash, ext));
  }

  Future<List<DriveFile>> _find(String hash) async => (await drive.list(
    kkeujeokIdQuery('asset:$hash'),
    fields: 'id,size,md5Checksum',
  )).files;

  // Has Drive this asset? Best effort: any failure leaves it unconfirmed.
  Future<void> _confirm(String hash) async {
    _busy.add(hash);
    try {
      if (!await online() || !await allowed()) return;
      final bytes = await store.read(hash);
      final found = await _find(hash);
      final md5 = bytes == null ? null : crypto.md5.convert(bytes).toString();
      if (bytes != null &&
          found.any((f) => f.size == bytes.length && f.md5Checksum == md5)) {
        _confirmed.add(hash);
      } else {
        _unconfirmed.add(hash);
      }
    } catch (_) {
      // unknown stays unconfirmed
    } finally {
      _busy.remove(hash);
      _changed();
    }
  }

  Future<void> _fetch(String hash, String ext) async {
    _busy.add(hash);
    _changed();
    try {
      var attempt = 0;
      while (!_disposed) {
        try {
          if (!await online() || !await allowed()) {
            throw const DriveError('network');
          }
          final found = await _find(hash);
          if (found.isEmpty) throw const DriveError('network'); // not up yet
          final f = found.first;
          final bytes = await drive.downloadFile(f.id);
          if ((f.size != null && f.size != bytes.length) ||
              !await store.writeVerified(hash, ext, bytes)) {
            throw const DriveError('network'); // dropped, fetched again
          }
          _local.add(hash);
          _confirmed.add(hash);
          _failed.remove(hash);
          return;
        } on DriveError catch (e) {
          if (classifyDriveError(e) != 'backoff') break;
          final plan = backoffRule({'attempt': ++attempt, 'jitter': jitter()});
          if (plan['retry'] != true) break;
          await sleep(Duration(milliseconds: plan['delayMs'] as int));
        }
      }
      _failed.add(hash);
    } catch (_) {
      _failed.add(hash); // a local write error: the same way out
    } finally {
      _busy.remove(hash);
      _changed();
    }
  }
}
