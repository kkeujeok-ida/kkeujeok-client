import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/auth_gateway.dart';
import 'package:kkeujeok/drive/root_folder.dart' show RootStatus;
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/sync/open_note.dart';
import 'package:kkeujeok/sync/upload_coordinator.dart';
import 'package:kkeujeok/ui/note_editor.dart';
import 'package:kkeujeok/ui/providers.dart';

import 'fake_auth_gateway.dart';
import 'fake_drive.dart';
import 'shell_test.dart' show pumpApp;
import 'upload_env.dart' show makeNote, noteId;

/// Records which trigger fired; the real work is tested elsewhere.
class _Rec implements UploadCoordinator {
  final calls = <String>[];

  @override
  Future<void> Function()? flushOpen;

  @override
  Future<void> noteClosed(String id) async => calls.add('closed:$id');
  @override
  Future<void> appBackgrounded() async => calls.add('background');
  @override
  Future<void> appStarted() async => calls.add('started');
  @override
  Future<void> uploadUnsent() async => calls.add('unsent');
  @override
  Future<void> rootReady() async => calls.add('rootReady');
  @override
  Future<void> foreground() async => calls.add('foreground');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _ReadyRoot extends RootFolderNotifier {
  @override
  RootFolderState build() => const RootFolderState(RootStatus.ready);
}

void main() {
  late Directory docs;
  late NoteData data;
  late _Rec rec;
  late FakeDrive drive;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('kkj-wiring-');
    data = NoteData(() async => docs);
    rec = _Rec();
    drive = FakeDrive();
    final f = File('${docs.path}/$noteDataDirName/$noteId/working.kkj');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(encodeKkj(makeNote(title: 'Wired')));
    addTearDown(() {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        // The OS cleans temp up later.
      }
    });
  });

  Future<void> open(WidgetTester t, {List<Override> more = const []}) async {
    await pumpApp(
      t,
      auth: FakeAuthGateway(restored: true)
        ..account = const AuthAccount(sub: 's', email: 'e'),
      noteData: data,
      overrides: [
        uploadCoordinatorProvider.overrideWithValue(rec),
        driveClientProvider.overrideWithValue(drive),
        rootCheckThrottleProvider.overrideWithValue(Duration.zero),
        ...more,
      ],
      settle: false,
    );
  }

  /// File IO runs outside the fake clock: wait in real time, pump.
  Future<void> until(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 600 && !done(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump();
    }
    expect(done(), isTrue);
    await t.pump();
  }

  Future<String?> marker(WidgetTester t) =>
      t.runAsync(() => OpenNote(data.rootDir).read()).then((v) => v);

  testWidgets('rootReady runs when the root turns ready, once', (t) async {
    await open(t);
    await until(t, () => rec.calls.contains('rootReady'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump();
    expect(rec.calls.where((c) => c == 'rootReady'), hasLength(1));
  });

  testWidgets('rootReady also runs when the root is ready at the first build', (
    t,
  ) async {
    await open(t, more: [rootFolderProvider.overrideWith(_ReadyRoot.new)]);
    await t.pump();
    await t.pump();
    expect(rec.calls, contains('rootReady')); // no transition ever came
  });

  testWidgets('paused is appBackgrounded, resumed is foreground', (t) async {
    await open(t);
    await until(t, () => rec.calls.contains('rootReady'));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await until(t, () => rec.calls.contains('background'));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(t, () => rec.calls.contains('foreground'));
  });

  testWidgets('the editor marks the note open, registers the flush, and the '
      'library uploads the note after the pop', (t) async {
    await open(t);
    await until(t, () => find.text('Wired').evaluate().isNotEmpty);
    await t.tap(find.text('Wired'));
    await until(t, () => find.byType(NoteEditor).evaluate().isNotEmpty);

    expect(rec.flushOpen, isNotNull);
    String? m;
    for (var i = 0; i < 200 && m != noteId; i++) {
      m = await marker(t);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(m, noteId);
    expect(rec.calls.where((c) => c.startsWith('closed:')), isEmpty);

    await t.tap(find.byTooltip('Back to library'));
    await until(t, () => rec.calls.contains('closed:$noteId'));
    expect(find.byType(NoteEditor), findsNothing);
    expect(rec.flushOpen, isNull);
    for (var i = 0; i < 200 && m != null; i++) {
      m = await marker(t);
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(m, isNull);
  });
}
