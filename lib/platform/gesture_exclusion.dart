import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.kkeujeok.app/gesture');

List<Rect>? _last;

@visibleForTesting
void resetGestureExclusion() => _last = null;

/// Keeps the system back gesture off [px] (screen pixels); an empty list
/// lifts it. Android only; a missing channel or an error is ignored.
Future<void> setGestureExclusion(List<Rect> px) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  if (listEquals(_last, px)) return;
  _last = List.of(px);
  try {
    await _channel.invokeMethod<void>('setExclusionRects', [
      for (final r in px) [r.left, r.top, r.right, r.bottom],
    ]);
  } on MissingPluginException {
    // No native side (tests, other builds).
  } on PlatformException {
    // The system refused: the back gesture just stays as it is.
  }
}
