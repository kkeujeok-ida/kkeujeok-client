enum SyncState { synced, pending, syncing, conflict, error }

/// A Drive revision id doubles as part of a file name, so its form is fixed.
/// The one definition: the sync log checks revision ids with it too.
final revisionIdPattern = RegExp(r'^[A-Za-z0-9_.~-]{1,200}$');

typedef JsonMap = Map<String, Object?>;

/// `sync.json` of one note (spec `sync` "On the device"). Fields this client
/// does not know are kept in [extra] and written back.
class SyncInfo {
  const SyncInfo({
    this.fileId,
    this.baseHeadRevisionId,
    this.state = SyncState.pending,
    this.pendingVerify,
    this.resumableSession,
    this.createIntent,
    this.conflicts = const [],
    this.unsentSidecars = const [],
    this.lastError,
    this.extra = const {},
  });

  final String? fileId;
  final String? baseHeadRevisionId;
  final SyncState state;
  final JsonMap? pendingVerify;
  final JsonMap? resumableSession;
  final JsonMap? createIntent;
  final List<JsonMap> conflicts;
  final List<JsonMap> unsentSidecars;
  final JsonMap? lastError;
  final JsonMap extra;

  /// The greatest `seq` seen in a merged remote note; the next operation takes
  /// `max(page.seq, this) + 1` (spec `merge.seqAfterMerge`). An unknown key of
  /// `sync.json`, so older readers keep it.
  int get lastSeenRemoteSeq {
    final v = extra['lastSeenRemoteSeq'];
    return v is int && v > 0 ? v : 0;
  }

  /// The entries of [conflicts] nobody has resolved yet.
  List<JsonMap> get unresolvedConflicts => [
    for (final c in conflicts)
      if (c['resolvedAt'] == null) c,
  ];

  static const _known = {
    'fileId',
    'baseHeadRevisionId',
    'state',
    'pendingVerify',
    'resumableSession',
    'createIntent',
    'conflicts',
    'unsentSidecars',
    'lastError',
  };

  /// Null when [json] is not a well-formed `sync.json`. A missing key takes
  /// its default.
  static SyncInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final m = {for (final e in json.entries) '${e.key}': e.value};
    String? str(String k, [RegExp? p]) {
      final v = m[k];
      return v is String && (p == null || p.hasMatch(v)) ? v : null;
    }

    bool badStr(String k, [RegExp? p]) =>
        m[k] != null && str(k, p) == null; // present but not a valid string
    if (badStr('fileId') || badStr('baseHeadRevisionId', revisionIdPattern)) {
      return null;
    }
    final state = m['state'] == null
        ? SyncState.pending
        : SyncState.values.where((s) => s.name == m['state']).firstOrNull;
    if (state == null) return null;

    JsonMap? obj(String k, bool Function(JsonMap) ok) {
      final v = m[k];
      if (v == null) return null;
      if (v is! Map) throw const FormatException();
      final o = {for (final e in v.entries) '${e.key}': e.value};
      if (!ok(o)) throw const FormatException();
      return o;
    }

    List<JsonMap> list(String k, bool Function(JsonMap) ok) {
      final v = m[k];
      if (v == null) return const [];
      if (v is! List) throw const FormatException();
      return [
        for (final e in v)
          if (e is Map && ok({for (final x in e.entries) '${x.key}': x.value}))
            {for (final x in e.entries) '${x.key}': x.value}
          else
            throw const FormatException(),
      ];
    }

    bool s(Object? v) => v is String;
    bool sOrNull(Object? v) => v == null || v is String;
    try {
      return SyncInfo(
        fileId: str('fileId'),
        baseHeadRevisionId: str('baseHeadRevisionId'),
        state: state,
        pendingVerify: obj(
          'pendingVerify',
          (o) =>
              sOrNull(o['parentRevisionId']) &&
              sOrNull(o['oursRevisionId']) &&
              o['round'] is int &&
              (o['round'] as int) >= 1 &&
              (o['round'] as int) <= 3,
        ),
        resumableSession: obj(
          'resumableSession',
          (o) => s(o['uri']) && o['size'] is int && (o['size'] as int) >= 0,
        ),
        createIntent: obj(
          'createIntent',
          (o) => s(o['kkeujeokId']) && s(o['parentId']),
        ),
        conflicts: list(
          'conflicts',
          (o) => s(o['pageId']) && s(o['rev']) && sOrNull(o['resolvedAt']),
        ),
        unsentSidecars: list(
          'unsentSidecars',
          (o) => s(o['pageId']) && s(o['rev']),
        ),
        lastError: obj(
          'lastError',
          (o) =>
              s(o['class']) &&
              (o['status'] == null ||
                  (o['status'] is int &&
                      (o['status'] as int) >= 100 &&
                      (o['status'] as int) <= 599)) &&
              sOrNull(o['reason']),
        ),
        extra: {
          for (final e in m.entries)
            if (!_known.contains(e.key)) e.key: e.value,
        },
      );
    } on FormatException {
      return null;
    }
  }

  static const _keep = Object();

  /// A copy with the given fields replaced. The nullable fields can be set to
  /// null; a field left out is kept.
  SyncInfo copyWith({
    Object? fileId = _keep,
    Object? baseHeadRevisionId = _keep,
    SyncState? state,
    Object? pendingVerify = _keep,
    Object? resumableSession = _keep,
    Object? createIntent = _keep,
    List<JsonMap>? conflicts,
    List<JsonMap>? unsentSidecars,
    Object? lastError = _keep,
    JsonMap? extra,
  }) => SyncInfo(
    fileId: identical(fileId, _keep) ? this.fileId : fileId as String?,
    baseHeadRevisionId: identical(baseHeadRevisionId, _keep)
        ? this.baseHeadRevisionId
        : baseHeadRevisionId as String?,
    state: state ?? this.state,
    pendingVerify: identical(pendingVerify, _keep)
        ? this.pendingVerify
        : pendingVerify as JsonMap?,
    resumableSession: identical(resumableSession, _keep)
        ? this.resumableSession
        : resumableSession as JsonMap?,
    createIntent: identical(createIntent, _keep)
        ? this.createIntent
        : createIntent as JsonMap?,
    conflicts: conflicts ?? this.conflicts,
    unsentSidecars: unsentSidecars ?? this.unsentSidecars,
    lastError: identical(lastError, _keep)
        ? this.lastError
        : lastError as JsonMap?,
    extra: extra ?? this.extra,
  );

  JsonMap toJson() => {
    ...extra,
    'fileId': fileId,
    'baseHeadRevisionId': baseHeadRevisionId,
    'state': state.name,
    'pendingVerify': pendingVerify,
    'resumableSession': resumableSession,
    'createIntent': createIntent,
    'conflicts': conflicts,
    'unsentSidecars': unsentSidecars,
    'lastError': lastError,
  };
}
