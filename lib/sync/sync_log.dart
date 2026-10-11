import 'dart:convert';
import 'dart:io';

import '../model/ids.dart';
import '../model/note.dart';
import '../storage/atomic_file.dart';
import 'sync_log_entry.dart';

const syncLogFileName = 'sync-log.jsonl';

/// Entries kept; the file is compacted back to this when it reaches
/// [_compactAt] lines, so most appends are one small write.
const syncLogKeep = 5000;
const _compactAt = 6000;

/// The local sync log (spec `sync-log`): JSON Lines in the documents root,
/// outside `notes/`. Holds no note content; every entry passes
/// [checkLogEntry] before it is stored.
///
/// One instance per file: the line count and the calls' order are kept in
/// memory, so two instances over one file may compact against stale counts
/// (the providers keep a single instance).
class SyncLog {
  SyncLog(this._dir, this._clock);

  final Future<Directory> Function() _dir;
  final DateTime Function() _clock;

  Future<void> _tail = Future<void>.value();
  int? _lines; // physical lines in the file, known after the first append
  bool _cutShort = false; // the file does not end with a line end

  Future<T> _locked<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<File> _file() async {
    final root = await _dir();
    return File('${root.path}${Platform.pathSeparator}$syncLogFileName');
  }

  Future<List<int>> _bytes() async {
    final f = await _file();
    return await f.exists() ? await f.readAsBytes() : const [];
  }

  /// Valid entries as stored lines, oldest first; broken lines are skipped.
  List<String> _valid(List<int> bytes) {
    final out = <String>[];
    final text = utf8.decode(bytes, allowMalformed: true);
    for (final line in const LineSplitter().convert(text)) {
      try {
        if (checkLogEntry(jsonDecode(line))['ok'] == true) out.add(line);
      } catch (_) {}
    }
    return out;
  }

  static List<T> _newest<T>(List<T> all) =>
      all.length > syncLogKeep ? all.sublist(all.length - syncLogKeep) : all;

  /// Adds one entry stamped with the clock's time. A `reason` outside its
  /// domain becomes `other`. False, nothing stored, when the entry is
  /// invalid or the write fails. Never throws.
  Future<bool> append(String event, [Map<String, Object?> fields = const {}]) =>
      _locked(() async {
        try {
          final entry = <String, Object?>{
            ...fields,
            'at': canonicalNow(_clock()),
            'event': event,
          };
          if (entry.containsKey('reason') && !validLogReason(entry['reason'])) {
            entry['reason'] = 'other';
          }
          if (checkLogEntry(entry)['ok'] != true) return false;

          final file = await _file();
          if (_lines == null) {
            final bytes = await _bytes();
            _cutShort = bytes.isNotEmpty && bytes.last != 10;
            _lines = bytes.where((b) => b == 10).length + (_cutShort ? 1 : 0);
          }
          // No fsync per entry: the log is diagnostic and a cut-short line
          // is repaired above.
          await file.parent.create(recursive: true);
          await file.writeAsString(
            '${_cutShort ? '\n' : ''}${jsonEncode(entry)}\n',
            mode: FileMode.append,
          );
          _cutShort = false;
          _lines = _lines! + 1;
          if (_lines! >= _compactAt) {
            try {
              final kept = _newest(_valid(await _bytes()));
              await writeFileAtomic(
                file,
                utf8.encode(kept.map((l) => '$l\n').join()),
              );
              _lines = kept.length;
            } catch (_) {
              // The entry is stored; the next append tries compacting again.
            }
          }
          return true;
        } catch (_) {
          _lines = null; // look at the file again next time
          return false;
        }
      });

  /// The newest [syncLogKeep] valid entries, oldest first.
  Future<List<Map<String, Object?>>> entries() => _locked(() async {
    return [
      for (final l in _newest(_valid(await _bytes())))
        (jsonDecode(l) as Map).cast<String, Object?>(),
    ];
  });

  /// Writes `kkeujeok-sync-log-YYYY-MM-DD.jsonl` (UTC date of [now]) into
  /// [into]: the header line, then the entries. Throws on a write failure.
  Future<File> exportJsonl({
    required String appVersion,
    required DateTime now,
    required Directory into,
  }) async {
    final e = await entries();
    final at = canonicalNow(now);
    final header = jsonEncode({
      'type': 'header',
      'app': 'kkeujeok',
      'appVersion': appVersion,
      'platform': 'android',
      'supportedFormatVersion': supportedFormatVersion,
      'exportedAt': at,
    });
    final file = File(
      '${into.path}${Platform.pathSeparator}'
      'kkeujeok-sync-log-${at.substring(0, 10)}.jsonl',
    );
    await writeFileAtomic(
      file,
      utf8.encode('$header\n${e.map((x) => '${jsonEncode(x)}\n').join()}'),
    );
    return file;
  }
}
