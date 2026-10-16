import 'dart:async';

/// When the app asks for remote changes (spec `sync` "Triggers and
/// polling"): at once on a kick, and every [interval] while in the
/// foreground. A kick closer than [minGap] to the previous one is skipped.
class ReceiveScheduler {
  ReceiveScheduler({
    required this.check,
    this.interval = const Duration(milliseconds: 20000),
    this.minGap = const Duration(milliseconds: 5000),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<void> Function() check;
  final Duration interval;
  final Duration minGap;
  final DateTime Function() _clock;

  Timer? _timer;
  DateTime? _last;
  bool _disposed = false;

  /// The app is in the foreground: the timer runs.
  void resume() {
    if (_disposed) return;
    _timer ??= Timer.periodic(interval, (_) => _run());
  }

  /// The app left the foreground: no timer, no request.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  /// Check now, unless the last kick was less than [minGap] ago ([force]
  /// ignores that, for the root turning ready).
  void kick({bool force = false}) {
    if (_disposed) return;
    final last = _last;
    if (!force && last != null && _clock().difference(last) < minGap) return;
    _run();
  }

  void _run() {
    if (_disposed) return;
    _last = _clock();
    unawaited(check().catchError((Object _) {}));
  }

  void dispose() {
    _disposed = true;
    pause();
  }
}
