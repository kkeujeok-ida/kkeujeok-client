// The local notification of a conflict found by a background upload
// (Story 3.19, UX-DR66): through the `ConflictNotifier` seam, never asked from
// the background.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/background_upload.dart';
import 'package:kkeujeok/sync/conflict_notifier.dart';
import 'package:kkeujeok/sync/note_uploader.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'upload_env.dart';

class FakeNotifier implements ConflictNotifier {
  FakeNotifier({this.granted = true, this.failShow = false});

  bool granted, failShow;
  int requests = 0;
  final shown = <String>[];

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<void> show(String noteId) async {
    if (failShow) throw StateError('no');
    shown.add(noteId);
  }

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<String?> launchNoteId() async => null;
}

void main() {
  late UploadEnv env;

  setUp(() async {
    env = await UploadEnv.create();
    await env.save(makeNote());
    expect(await env.uploader().upload(noteId), UploadOutcome.uploaded);
    // Edited here while the other device edited the same page.
    await env.save(makeNote(rev: 2));
    env.drive.foreignRevision(env.note, encodeKkj(makeNote(rev: 9)));
  });

  Future<void> run(FakeNotifier n) async {
    SharedPreferences.setMockInitialValues({
      'signedIn': true,
      'accountSub': 's',
      'accountEmail': 'e',
    });
    await runBackgroundUpload(
      prefs: await SharedPreferences.getInstance(),
      data: env.data,
      drive: env.drive,
      online: () async => true,
      notifier: n,
    );
  }

  test('a conflict found in the background: one notification, note id', () async {
    final n = FakeNotifier();
    await run(n);
    expect(env.info.state, SyncState.conflict);
    expect(n.shown, [noteId]);
    expect(n.requests, 0);
  });

  test('permission not granted: nothing shown, nothing asked', () async {
    final n = FakeNotifier(granted: false);
    await run(n);
    expect(env.info.state, SyncState.conflict);
    expect(n.shown, isEmpty);
    expect(n.requests, 0);
  });

  test('unresolved count unchanged: no second notification', () async {
    await run(FakeNotifier());
    final n = FakeNotifier();
    await run(n);
    expect(n.shown, isEmpty);
  });

  test('a notifier error is swallowed', () async {
    final n = FakeNotifier(failShow: true);
    await run(n);
    expect(env.info.state, SyncState.conflict);
  });

  test('the permission is asked once, and the texts are kept', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final n = FakeNotifier(granted: false);
    for (var i = 0; i < 3; i++) {
      await askConflictPermissionOnce(
        n,
        title: 't',
        channel: 'c',
        prefs: prefs,
      );
    }
    expect(n.requests, 1); // a refusal is not asked again
    expect(prefs.getString('conflictNotifyTitle'), 't');
  });
}
