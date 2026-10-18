import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one local notification of a conflict found while the app was in the
/// background (UX-DR66). A seam, so tests post to a fake. The content never
/// carries note content: a fixed title, and the note id as the payload.
abstract interface class ConflictNotifier {
  /// Whether a notification would be shown now. Never asks the person.
  Future<bool> isGranted();

  /// Asks the person (Android 13+); only called from the foreground.
  Future<bool> requestPermission();

  /// Posts the notification of [noteId], in the language the foreground last
  /// saved ([askConflictPermissionOnce]).
  Future<void> show(String noteId);

  /// Note ids of notifications the person tapped while the app runs.
  Stream<String> get taps;

  /// The note whose notification started the app, if any (read once).
  Future<String?> launchNoteId();
}

const _askedKey = 'conflictNotifyAsked';
const _titleKey = 'conflictNotifyTitle';
const _channelKey = 'conflictNotifyChannel';

/// Asks for the permission once: the first time a conflict is shown in the
/// foreground. The answer is not kept; a refusal is final (the person can
/// change it in the system settings). Also keeps the texts the background
/// notification uses, as it has no UI language of its own. Never throws.
Future<void> askConflictPermissionOnce(
  ConflictNotifier notifier, {
  required String title,
  required String channel,
  SharedPreferences? prefs,
}) async {
  try {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(_titleKey, title);
    await p.setString(_channelKey, channel);
    if (p.getBool(_askedKey) ?? false) return;
    await p.setBool(_askedKey, true);
    await notifier.requestPermission();
  } catch (_) {}
}

/// `flutter_local_notifications` on Android; nothing elsewhere.
class LocalConflictNotifier implements ConflictNotifier {
  // The launch payload is handed out once per process.
  static bool _launchConsumed = false;

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  Future<void>? _ready;

  Future<void> _init() => _ready ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) {
          final id = r.payload;
          if (id != null && id.isNotEmpty) _taps.add(id);
        },
      )
      .then((_) {});

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<bool> isGranted() async {
    if (!Platform.isAndroid) return false;
    await _init();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    await _init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> show(String noteId) async {
    if (!Platform.isAndroid) return;
    await _init();
    final p = await SharedPreferences.getInstance();
    final title = p.getString(_titleKey) ?? 'Kkeujeok';
    final channel = p.getString(_channelKey) ?? 'Conflicts';
    await _plugin.show(
      // One notification per note: a second conflict replaces it.
      id: noteId.hashCode & 0x7fffffff,
      title: title,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'conflicts',
          channel,
          importance: Importance.defaultImportance,
        ),
      ),
      payload: noteId,
    );
  }

  @override
  Future<String?> launchNoteId() async {
    if (!Platform.isAndroid || _launchConsumed) return null;
    _launchConsumed = true;
    await _init();
    final d = await _plugin.getNotificationAppLaunchDetails();
    final id = d?.notificationResponse?.payload;
    return d != null &&
            d.didNotificationLaunchApp &&
            id != null &&
            id.isNotEmpty
        ? id
        : null;
  }
}
