// Story 4.12: the image intake check, the insert and its undo, assets going
// to Drive before the note, and an image whose asset is fetched.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kkeujeok/drive/drive_client.dart';
import 'package:kkeujeok/model/image_rules.dart';
import 'package:kkeujeok/model/note.dart';
import 'package:kkeujeok/ops/history.dart';
import 'package:kkeujeok/ops/ops.dart';
import 'package:kkeujeok/storage/asset_store.dart';
import 'package:kkeujeok/storage/image_intake.dart';
import 'package:kkeujeok/sync/asset_sync.dart';
import 'package:kkeujeok/sync/note_uploader.dart';

import 'upload_env.dart';

// 12 bytes of a PNG / HEIC / GIF header, padded to [n] bytes.
List<int> _bytes(List<int> head, int n) => [
  ...head,
  ...List<int>.filled(n - head.length, 1),
];
const _png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0];
const _jpg = [0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1];
const _heic = [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63];
const _gif = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 0, 1, 0, 0, 0];

Future<(int, int)?> _dims(List<int> b) async => (800, 600);

Ctx _ctx(String id) => Ctx(
  rev: '01926f3a-0000-7000-8000-0000000000a1',
  now: '2026-10-24T09:00:00.000Z',
  editedBy: 'Pixel 8',
  ids: [id],
);

void main() {
  group('acceptImage', () {
    test('png is kept as it is', () async {
      final r = await acceptImage(
        _bytes(_png, 100),
        toJpeg: (_) async => null,
        dimensions: _dims,
      );
      expect(r.image!.ext, 'png');
      expect(r.image!.converted, isFalse);
    });

    test(
      'heic is converted once and the converted bytes are checked',
      () async {
        final jpeg = _bytes(_jpg, 50);
        final r = await acceptImage(
          _bytes(_heic, 20000000), // over the limit before conversion: fine
          toJpeg: (_) async => jpeg,
          dimensions: _dims,
        );
        expect(r.image!.ext, 'jpg');
        expect(r.image!.converted, isTrue);
        expect(r.image!.bytes, jpeg);
      },
    );

    test('a converted image over 10 MB is refused', () async {
      final r = await acceptImage(
        _bytes(_heic, 100),
        toJpeg: (_) async => _bytes(_jpg, imageMaxBytes + 1),
        dimensions: _dims,
      );
      expect(r.failure, IntakeFailure.tooLarge);
    });

    test('a failed conversion, a gif and 10 MB + 1 are refused', () async {
      Future<IntakeFailure?> f(List<int> b, [List<int>? jpeg]) async =>
          (await acceptImage(
            b,
            toJpeg: (_) async => jpeg,
            dimensions: _dims,
          )).failure;
      expect(await f(_bytes(_heic, 100)), IntakeFailure.convertFailed);
      expect(await f(_bytes(_gif, 100)), IntakeFailure.unsupported);
      expect(await f(_bytes(_jpg, imageMaxBytes)), isNull);
      expect(await f(_bytes(_jpg, imageMaxBytes + 1)), IntakeFailure.tooLarge);
    });
  });

  test('insertImage is one undo step; a second insert shares the asset', () {
    final h = History(makeNote());
    final asset = AssetStore.sha256Hex([1, 2, 3]);
    Map<String, dynamic> op(double x) => {
      'op': 'insertImage',
      'pageId': pageId,
      'asset': asset,
      'ext': 'png',
      'pxWidth': 800,
      'pxHeight': 600,
      'x': x,
      'y': 100,
      'width': 400,
      'height': 300,
    };
    expect(h.doOp(op(10), _ctx('01926f3a-0000-7000-8000-0000000000b1')), null);
    expect(h.doOp(op(50), _ctx('01926f3a-0000-7000-8000-0000000000b2')), null);
    List els() => h.note.pages.first['elements'] as List;
    expect(els().map((e) => e['asset']), [asset, asset]);
    expect(referencedAssets(h.note), [asset]);
    expect(h.undo(_ctx('01926f3a-0000-7000-8000-0000000000b3')), null);
    expect(els().length, 1);
    expect(h.undoDepth, 1);
  });

  group('assets go to Drive before the note', () {
    late UploadEnv env;
    late AssetStore assets;
    final bytes = _bytes(_png, 3000);
    late String hash;

    setUp(() async {
      env = await UploadEnv.create();
      assets = AssetStore(env.data);
    });

    NoteUploader uploader() => NoteUploader(
      store: env.store,
      drive: env.drive,
      device: env.device,
      log: env.log,
      merge: env.merge,
      allowed: () async => true,
      online: () async => true,
      sleep: (d) async => env.sleeps.add(d),
      jitter: () => 0.5,
      assets: assets,
    );

    Future<void> saveWithImage([String? asset]) async {
      final json = makeNote().copyJson();
      ((json['pages'] as List).first['elements'] as List).add({
        'id': '01926f3a-0000-7000-8000-000000000002',
        'type': 'image',
        'x': 10,
        'y': 10,
        'width': 100,
        'height': 75,
        'rotation': 0,
        'asset': asset ?? hash,
        'ext': 'png',
        'pxWidth': 800,
        'pxHeight': 600,
      });
      await env.save(Note.trusted(json));
    }

    test(
      'asset first (in .assets), then the note; nothing is re-sent',
      () async {
        hash = await assets.write(bytes, 'png');
        await saveWithImage();
        expect(await uploader().upload(noteId), UploadOutcome.uploaded);

        expect(env.drive.uploads.map((u) => u.metadata['name']), [
          '$hash.png',
          'a.kkj',
        ]);
        final folder = env.drive.byKkeujeokId('assets')!;
        expect(folder.parents, [env.root.id]);
        final file = env.drive.byKkeujeokId('asset:$hash')!;
        expect(file.parents, [folder.id]);
        expect(file.bytes, bytes);

        // An edit and a second upload: the asset is found, not sent again.
        final json = env.store.read(noteId);
        final n = (await json)!.note;
        final edited = n!.copyJson();
        (edited['pages'] as List).first['rev'] =
            '01926f3a-0000-7000-8000-0000000000c9';
        (edited['pages'] as List).first['seq'] = 9;
        await env.save(Note.trusted(edited));
        env.drive.uploads.clear();
        expect(await uploader().upload(noteId), UploadOutcome.uploaded);
        expect(
          env.drive.uploads.map((u) => u.metadata['name']),
          isNot(contains('$hash.png')),
        );
      },
    );

    test('an asset already on Drive is not uploaded', () async {
      hash = await assets.write(bytes, 'png');
      final item = env.drive.seed(
        kkeujeokId: 'asset:$hash',
        parents: [env.root.id],
      );
      env.drive.foreignRevision(item, bytes);
      await saveWithImage();
      expect(await uploader().upload(noteId), UploadOutcome.uploaded);
      expect(env.drive.uploads.map((u) => u.metadata['name']), ['a.kkj']);
    });

    test('a failed asset keeps the note back', () async {
      hash = await assets.write(bytes, 'png');
      await saveWithImage();
      env.drive.failures['upload'] = [
        const DriveError('http', status: 403, reason: 'forbidden'),
      ];
      expect(await uploader().upload(noteId), UploadOutcome.failed);
      expect(env.drive.byKkeujeokId(noteId), isNull);
      expect(env.drive.uploads, isEmpty);
    });

    test('bytes neither on Drive nor here block the note', () async {
      hash = AssetStore.sha256Hex([9, 9, 9]);
      await saveWithImage();
      expect(await uploader().upload(noteId), UploadOutcome.failed);
      expect(env.drive.byKkeujeokId(noteId), isNull);
    });
  });

  group('an image whose asset is not here', () {
    test('placeholder, then the image once fetched and verified', () async {
      final env = await UploadEnv.create();
      final bytes = _bytes(_png, 2000);
      final hash = AssetStore.sha256Hex(bytes);
      final item = env.drive.seed(
        kkeujeokId: 'asset:$hash',
        parents: [env.root.id],
      );
      env.drive.foreignRevision(item, bytes);

      final store = AssetStore(env.data);
      final sync = AssetSync(
        store: store,
        drive: env.drive,
        online: () async => true,
        allowed: () async => true,
        sleep: (_) async {},
        jitter: () => 0,
      );
      expect(assetState(hash, sync.local, sync.failed), AssetState.downloading);
      await sync.ensure({hash: 'png'});
      while (!sync.local.contains(hash) && !sync.failed.contains(hash)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(assetState(hash, sync.local, sync.failed), AssetState.ready);
      expect(await store.read(hash), bytes);
      expect(sync.confirmed, contains(hash));
      sync.dispose();
    });

    test('bytes that do not match the hash are dropped: failed', () async {
      final env = await UploadEnv.create();
      final hash = AssetStore.sha256Hex(_bytes(_png, 2000));
      final item = env.drive.seed(
        kkeujeokId: 'asset:$hash',
        parents: [env.root.id],
      );
      env.drive.foreignRevision(item, _bytes(_png, 1999));

      final store = AssetStore(env.data);
      final sync = AssetSync(
        store: store,
        drive: env.drive,
        online: () async => true,
        allowed: () async => true,
        sleep: (_) async {},
        jitter: () => 0,
      );
      await sync.ensure({hash: 'png'});
      while (!sync.local.contains(hash) && !sync.failed.contains(hash)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(assetState(hash, sync.local, sync.failed), AssetState.failed);
      expect(await store.read(hash), isNull);
      expect(
        Directory('${env.docs.path}/assets').existsSync()
            ? Directory('${env.docs.path}/assets').listSync()
            : const [],
        isEmpty,
      );
      sync.dispose();
    });
  });
}
