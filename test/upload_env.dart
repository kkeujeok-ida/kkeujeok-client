import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/model/kkj_codec.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/note_data.dart';
import 'package:kkeujeok/storage/note_store.dart';
import 'package:kkeujeok/storage/sync_device_store.dart';
import 'package:kkeujeok/storage/sync_info.dart';
import 'package:kkeujeok/sync/merge_step.dart';
import 'package:kkeujeok/sync/note_uploader.dart';
import 'package:kkeujeok/sync/sync_log.dart';

import 'fake_drive.dart';

const noteId = '01926f3a-0000-7000-8000-000000000900';
const pageId = '01926f3a-0000-7000-8000-000000000001';

/// A one-page note; [rev] is the page rev, so a different [rev] is an edit.
Note makeNote({int rev = 1, String title = 'a', String? noteIdOverride}) {
  final r = createNote(
    title: title,
    existingTitles: [],
    background: 'plain',
    orientation: 'portrait',
    noteId: noteIdOverride ?? noteId,
    pageId: pageId,
    pageRev: '01926f3a-0000-7000-8000-0000000000${(50 + rev)}',
    metaRev: '01926f3a-0000-7000-8000-000000000901',
    orderRev: '01926f3a-0000-7000-8000-000000000902',
    now: '2026-10-10T04:20:00.000Z',
    editedBy: 'Pixel 8',
  );
  return r.note!;
}

/// [makeNote] with an element of random bytes, so its gzip is about
/// [megabytes] MiB (random data does not compress).
Note bigNote({required double megabytes, int rev = 1}) {
  final json = makeNote(rev: rev).copyJson();
  final raw = (megabytes * 1024 * 1024).round();
  final rnd = Random(7);
  final bytes = List<int>.generate(raw, (_) => rnd.nextInt(256));
  (json['pages'] as List).first['elements'].add({
    'id': '01926f3a-0000-7000-8000-000000000777',
    'type': 'blob',
    'data': base64Encode(bytes),
  });
  return Note.trusted(json);
}

class Crash implements Exception {
  @override
  String toString() => 'Crash';
}

class StubMerge implements MergeStep {
  StubMerge(this.answer);

  final MergeOutcome Function(int call) answer;
  int calls = 0;

  @override
  Future<MergeOutcome> merge({
    required Note working,
    required Note? base,
    required Note remote,
  }) async => answer(++calls);
}

/// Everything one uploader test needs, over a temp folder and a [FakeDrive].
class UploadEnv {
  UploadEnv._(
    this.docs,
    this.data,
    this.store,
    this.device,
    this.log,
    this.drive,
  );

  final Directory docs;
  final NoteData data;
  final NoteStore store;
  final SyncDeviceStore device;
  final SyncLog log;
  final FakeDrive drive;
  late final FakeItem root;

  bool allowed = true;
  bool online = true;
  MergeStep merge = const UnavailableMergeStep();
  final sleeps = <Duration>[];
  double jitter = 0.5;
  Future<List<int>?> Function(Map<String, dynamic>, int, int)? thumbnail;

  static Future<UploadEnv> create({FakeDrive? drive}) async {
    final docs = Directory.systemTemp.createTempSync('kkj-upload-');
    addTearDown(() => docs.deleteSync(recursive: true));
    final data = NoteData(() async => docs);
    var t = DateTime.utc(2026, 10, 11);
    final env = UploadEnv._(
      docs,
      data,
      NoteStore(data),
      SyncDeviceStore(data),
      SyncLog(data.rootDir, () => t = t.add(const Duration(seconds: 1))),
      drive ?? FakeDrive(),
    );
    env.root = env.drive.seed(kkeujeokId: 'root');
    await env.device.write(
      SyncDevice(sub: 's', email: 'e', rootFolderId: env.root.id),
    );
    return env;
  }

  /// A new uploader over the same files and Drive (as after a restart).
  NoteUploader uploader() => NoteUploader(
    store: store,
    drive: drive,
    device: device,
    log: log,
    merge: merge,
    allowed: () async => allowed,
    online: () async => online,
    sleep: (d) async => sleeps.add(d),
    jitter: () => jitter,
    thumbnail: thumbnail,
  );

  Directory get noteDir => Directory('${docs.path}/$noteDataDirName/$noteId');
  File get working => File('${noteDir.path}/working.kkj');
  File get syncFile => File('${noteDir.path}/sync.json');

  /// `sync.json` as stored (null when there is none).
  Map<String, Object?>? get sync => syncFile.existsSync()
      ? jsonDecode(syncFile.readAsStringSync()) as Map<String, Object?>
      : null;

  Future<void> save(Note n) => store.write(n);

  Future<List<Map<String, Object?>>> events() => log.entries();

  Future<List<String>> eventNames() async => [
    for (final e in await events()) e['event'] as String,
  ];

  /// The `stateChange` entries as `from>to`.
  Future<List<String>> stateChanges() async => [
    for (final e in await events())
      if (e['event'] == 'stateChange') '${e['from']}>${e['to']}',
  ];

  FakeItem get note => drive.byKkeujeokId(noteId)!;

  String md5Of(List<int> bytes) => crypto.md5.convert(bytes).toString();

  SyncInfo get info => SyncInfo.fromJson(sync)!;
}

/// The note a Drive revision holds.
Note? noteOf(List<int> bytes) => decodeKkj(bytes).note;
