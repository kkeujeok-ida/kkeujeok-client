import 'dart:convert';
import 'dart:io';

import 'atomic_file.dart';
import 'note_data.dart';

const syncDeviceFileName = 'sync-device.json';

/// Per-device sync record (spec `sync` "On the device"). No token is ever
/// part of it. Keys this client does not know are kept in [extra].
class SyncDevice {
  const SyncDevice({
    this.sub,
    this.email,
    this.rootFolderId,
    this.conflictsFolderId,
    this.pageToken,
    this.createIntents = const [],
    this.extra = const {},
  });

  final String? sub;
  final String? email;
  final String? rootFolderId;
  final String? conflictsFolderId;
  final String? pageToken;
  final List<Map<String, Object?>> createIntents;
  final Map<String, Object?> extra;

  static const _strings = [
    'sub',
    'email',
    'rootFolderId',
    'conflictsFolderId',
    'pageToken',
  ];

  /// Null unless [json] has the right shape; a missing key is its default.
  static SyncDevice? fromJson(Object? json) {
    if (json is! Map) return null;
    for (final k in _strings) {
      if (json[k] != null && json[k] is! String) return null;
    }
    final ci = json['createIntents'] ?? const [];
    if (ci is! List) return null;
    final intents = <Map<String, Object?>>[];
    for (final e in ci) {
      if (e is! Map ||
          e['kkeujeokId'] is! String ||
          e['kind'] is! String ||
          e['parentId'] is! String) {
        return null;
      }
      intents.add({for (final x in e.entries) '${x.key}': x.value});
    }
    return SyncDevice(
      sub: json['sub'] as String?,
      email: json['email'] as String?,
      rootFolderId: json['rootFolderId'] as String?,
      conflictsFolderId: json['conflictsFolderId'] as String?,
      pageToken: json['pageToken'] as String?,
      createIntents: intents,
      extra: {
        for (final e in json.entries)
          if (!_strings.contains(e.key) && e.key != 'createIntents')
            '${e.key}': e.value,
      },
    );
  }

  Map<String, Object?> toJson() => {
    ...extra,
    'sub': sub,
    'email': email,
    'rootFolderId': rootFolderId,
    'conflictsFolderId': conflictsFolderId,
    'pageToken': pageToken,
    'createIntents': createIntents,
  };

  /// The cached root id and the pending create intents replaced. The
  /// `.conflicts` cache goes with a root that changed.
  SyncDevice withRoot(
    String? id,
    List<Map<String, Object?>> intents, {
    bool forgetConflicts = false,
  }) => SyncDevice(
    sub: sub,
    email: email,
    rootFolderId: id,
    conflictsFolderId: !forgetConflicts && id == rootFolderId
        ? conflictsFolderId
        : null,
    pageToken: pageToken,
    createIntents: intents,
    extra: extra,
  );

  SyncDevice withAccount(String sub, String email) => SyncDevice(
    sub: sub,
    email: email,
    rootFolderId: rootFolderId,
    conflictsFolderId: conflictsFolderId,
    pageToken: pageToken,
    createIntents: createIntents,
    extra: extra,
  );
}

/// `sync-device.json` in the documents root, outside `notes/`. Calls run one
/// after another. A file that exists but cannot be read is never overwritten
/// ([adoptAccount] says false, [write] throws); [clear] removes it.
class SyncDeviceStore {
  SyncDeviceStore(this._data);

  final NoteData _data;
  Future<void> _tail = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<File> _file() async {
    final root = await _data.rootDir();
    return File('${root.path}${Platform.pathSeparator}$syncDeviceFileName');
  }

  /// `device` is empty and `readable` true when there is no file; `readable`
  /// is false when a file is there but not a valid record.
  Future<({SyncDevice device, bool readable})> _load() async {
    final File f;
    try {
      f = await _file();
      if (!await f.exists()) {
        return (device: const SyncDevice(), readable: true);
      }
    } catch (_) {
      return (device: const SyncDevice(), readable: false);
    }
    try {
      final d = SyncDevice.fromJson(jsonDecode(await f.readAsString()));
      return d == null
          ? (device: const SyncDevice(), readable: false)
          : (device: d, readable: true);
    } catch (_) {
      return (device: const SyncDevice(), readable: false);
    }
  }

  /// Never throws; no file or an unreadable one is an empty record.
  Future<SyncDevice> read() => _locked(() async => (await _load()).device);

  Future<void> _write(SyncDevice d) async =>
      writeFileAtomic(await _file(), utf8.encode(jsonEncode(d.toJson())));

  /// Throws when the write fails or the existing file is unreadable.
  Future<void> write(SyncDevice d) => _locked(() async {
    if (!(await _load()).readable) {
      throw const FileSystemException('sync-device.json is unreadable');
    }
    await _write(d);
  });

  /// Tags the device with this account. True when there was no record or it
  /// has the same [sub] (the e-mail is refreshed); false, nothing written,
  /// for another account (what to do is Story 3.7) or an unreadable file.
  /// Throws when the write fails.
  Future<bool> adoptAccount(String sub, String email) => _locked(() async {
    if (sub.isEmpty) return false;
    final cur = await _load();
    if (!cur.readable) return false;
    final d = cur.device;
    if (d.sub != null && d.sub != sub) return false;
    if (d.sub != sub || d.email != email) {
      await _write(d.withAccount(sub, email));
    }
    return true;
  });

  /// Removes the record, whatever state it is in. A file that cannot be
  /// deleted is left (best effort).
  Future<void> clear() => _locked(() async {
    try {
      final f = await _file();
      for (final x in [f, File('${f.path}.tmp')]) {
        try {
          x.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  });
}
