import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/note_store.dart' show SyncRead;
import '../storage/sync_info.dart';
import '../sync/sync_rules.dart';
import 'providers.dart';

/// The one label a note's state is shown as (spec `sync` "What is shown").
enum SyncLabel {
  saved,
  pending,
  offline,
  saving,
  receiving,
  twoVersions,
  notSaved,
}

/// What the indicator, the popover and the card badge show for one note.
class NoteSyncView {
  const NoteSyncView(
    this.label, {
    this.state = SyncState.pending,
    this.errorClass,
    this.errorReason,
    this.loaded = true,
  });

  /// False for the placeholder shown until the first read ends.
  final bool loaded;

  final SyncLabel label;
  final SyncState state;

  /// `lastError.class`, only while [state] is `error`.
  final String? errorClass;

  /// `lastError.reason`, only while [state] is `error`.
  final String? errorReason;

  /// The Drive file was deleted elsewhere (Story 3.17).
  bool get deleted => errorClass == 'deleted';

  /// The remote file cannot be read here: the card is "열 수 없음".
  bool get unreadable => errorClass == 'unreadable' && errorReason == 'parse';

  /// The remote note is of a newer format: it opens read-only.
  bool get newVersion =>
      errorClass == 'unreadable' && errorReason == 'unsupportedVersion';

  bool get isError => label == SyncLabel.notSaved;
  bool get quota => isError && errorClass == 'quota';
  bool get reauth => isError && errorClass == 'reauth';

  @override
  bool operator ==(Object other) =>
      other is NoteSyncView &&
      other.label == label &&
      other.state == state &&
      other.errorClass == errorClass &&
      other.errorReason == errorReason &&
      other.loaded == loaded;

  @override
  int get hashCode =>
      Object.hash(label, state, errorClass, errorReason, loaded);
}

/// `saving` and `receiving` are drawn only after this long...
const syncSlowDelay = Duration(milliseconds: 1000);

/// ...and `saving`, once drawn, stays at least this long.
const syncSavingHold = Duration(milliseconds: 600);

/// False only while the device is known to be offline. Follows connectivity;
/// a return of the connection uploads what waited (Story 3.15).
class OnlineNotifier extends Notifier<bool> {
  @override
  bool build() {
    var disposed = false;
    var current = true;
    _changed = false;
    final sub = ref.read(connectivityChangesProvider).listen((on) {
      if (disposed) return;
      _changed = true;
      final back = on && !current;
      current = on;
      state = on;
      if (back) {
        unawaited(ref.read(uploadCoordinatorProvider).reconnected());
      }
    }, onError: (Object _) {});
    ref.onDispose(() {
      disposed = true;
      sub.cancel();
    });
    ref.read(networkProbeProvider)().then((on) {
      // A change that arrived while the probe ran is newer.
      if (!disposed && !_changed) state = current = on;
    }, onError: (Object _) {});
    return true;
  }

  bool _changed = false;
}

/// Connectivity changes as online (true) / offline (false). Android only, as
/// the plugin is not there elsewhere; tests override it.
final connectivityChangesProvider = Provider<Stream<bool>>(
  (ref) => !Platform.isAndroid
      ? const Stream<bool>.empty()
      : Connectivity().onConnectivityChanged.map(
          (r) => r.isEmpty || r.any((x) => x != ConnectivityResult.none),
        ),
);

final onlineProvider = NotifierProvider<OnlineNotifier, bool>(
  OnlineNotifier.new,
);

/// The display state of one note: `sync.json` and the unsent check
/// (`readSync`), the receive set, and the connection, through the spec's
/// `display` rule, with the 1,000 ms / 600 ms timing of `saving`.
class NoteSyncNotifier extends Notifier<NoteSyncView> {
  NoteSyncNotifier(this.noteId);

  final String noteId;
  SyncRead? _read;
  SyncLabel? _shown; // the slow label (saving / receiving) now drawn
  SyncLabel? _armed; // the slow label whose 1,000 ms delay is running
  Timer? _showTimer, _holdTimer;

  @override
  NoteSyncView build() {
    final store = ref.read(noteStoreProvider);
    final online = ref.watch(onlineProvider);
    final receiving = ref.watch(
      receiveStateProvider.select((r) => r.receiving.contains(noteId)),
    );
    final sub = store.changes.listen((e) {
      if (e.noteId != noteId) return;
      // A plain edit changes the display only from `synced` (to `pending`):
      // no reread, and no decode of the note, per stroke.
      if (!e.sync && _read != null && _read!.state != SyncState.synced) return;
      unawaited(_reload());
    });
    ref.onDispose(() {
      sub.cancel();
      _showTimer?.cancel();
      _holdTimer?.cancel();
      _holdTimer = null;
    });
    if (_read == null) unawaited(_reload());
    return _view(online, receiving);
  }

  int _reloads = 0;

  Future<void> _reload() async {
    final mine = ++_reloads;
    final SyncRead r;
    try {
      r = await ref.read(noteStoreProvider).readSync(noteId);
    } catch (_) {
      return;
    }
    if (!ref.mounted || mine != _reloads) return; // a newer read is coming
    _read = r;
    state = _view(ref.read(onlineProvider), _receiving);
  }

  bool get _receiving =>
      ref.read(receiveStateProvider).receiving.contains(noteId);

  NoteSyncView _view(bool online, bool receiving) {
    final r = _read;
    if (r == null) {
      return const NoteSyncView(SyncLabel.pending, loaded: false);
    }
    final SyncLabel raw;
    if (receiving) {
      raw = SyncLabel.receiving;
    } else {
      final out = stateMachineRule({
        'op': 'display',
        'state': r.state.name,
        'cause': 'upload',
        'platform': 'android',
        'online': online,
      });
      raw = SyncLabel.values.byName(out['label'] as String);
    }
    NoteSyncView view(SyncLabel l) => NoteSyncView(
      l,
      state: r.state,
      errorClass: r.state == SyncState.error
          ? (r.info.lastError?['class'] as String?)
          : null,
      errorReason: r.state == SyncState.error
          ? (r.info.lastError?['reason'] as String?)
          : null,
    );

    final slow = raw == SyncLabel.saving || raw == SyncLabel.receiving;
    // The armed delay keeps running while the same slow label is pending.
    if (!slow || _armed != raw) {
      _showTimer?.cancel();
      _showTimer = null;
      _armed = null;
    }
    if (slow) {
      if (_shown == raw) return view(raw);
      _shown = null;
      if (_armed == raw) return view(SyncLabel.pending);
      _armed = raw;
      // Not drawn yet: it still reads as waiting.
      _showTimer = Timer(syncSlowDelay, () {
        _armed = null;
        _shown = raw;
        if (raw == SyncLabel.saving) {
          _holdTimer?.cancel();
          _holdTimer = Timer(syncSavingHold, () {
            _holdTimer = null;
            if (ref.mounted) {
              state = _view(ref.read(onlineProvider), _receiving);
            }
          });
        }
        if (ref.mounted) state = _view(ref.read(onlineProvider), _receiving);
      });
      return view(SyncLabel.pending);
    }
    if (_shown == SyncLabel.saving && _holdTimer != null) {
      return view(SyncLabel.saving); // held; the hold timer redraws
    }
    _shown = null;
    return view(raw);
  }
}

final noteSyncProvider =
    NotifierProvider.family<NoteSyncNotifier, NoteSyncView, String>(
      NoteSyncNotifier.new,
    );

/// What blocks sync for the whole device: a sign-in that needs the person
/// (banner) and a full Drive (one notice).
class SyncProblems {
  const SyncProblems({this.reauth = false, this.quota = false});

  final bool reauth, quota;

  @override
  bool operator ==(Object other) =>
      other is SyncProblems && other.reauth == reauth && other.quota == quota;

  @override
  int get hashCode => Object.hash(reauth, quota);
}

class SyncProblemsNotifier extends Notifier<SyncProblems> {
  @override
  SyncProblems build() {
    final store = ref.read(noteStoreProvider);
    // ponytail: reads every note on a sync commit; keep a per-note cache if
    // libraries get large.
    final sub = store.changes.listen((e) {
      if (e.sync) unawaited(_scan());
    });
    ref.onDispose(sub.cancel);
    unawaited(_scan());
    return const SyncProblems();
  }

  int _gen = 0;

  Future<void> _scan() async {
    final gen = ++_gen;
    final store = ref.read(noteStoreProvider);
    var reauth = false, quota = false;
    try {
      for (final id in await store.ids()) {
        final s = await store.readSync(id);
        if (s.state != SyncState.error) continue;
        final c = s.info.lastError?['class'];
        reauth |= c == 'reauth';
        quota |= c == 'quota';
      }
    } catch (_) {
      return;
    }
    if (ref.mounted && gen == _gen) {
      state = SyncProblems(reauth: reauth, quota: quota);
    }
  }
}

final syncProblemsProvider =
    NotifierProvider<SyncProblemsNotifier, SyncProblems>(
      SyncProblemsNotifier.new,
    );

/// The quota notice is given once per app run.
class QuotaNoticeFlag {
  bool shown = false;
}

final quotaNoticeProvider = Provider<QuotaNoticeFlag>(
  (ref) => QuotaNoticeFlag(),
);
