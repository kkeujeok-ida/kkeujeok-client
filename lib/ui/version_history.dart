import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design_tokens/build/tokens.dart';
import '../drive/drive_client.dart';
import '../l10n/app_localizations.dart';
import '../model/ids.dart';
import '../render/page_painter.dart';
import '../sync/version_history.dart';
import '../sync/version_list.dart';
import 'providers.dart';

/// Runs the restore of one `version.list` entry (spec `version-history`);
/// null = restored.
typedef RestoreEntry = Future<RestoreFailure?> Function(
  Map<String, Object?> entry,
  String fileId,
);

/// Opens the version history of a note over the editor. Completes with true
/// when a version was restored (the screen is closed then).
Future<bool> showVersionHistory(
  BuildContext context, {
  required String noteId,
  required RestoreEntry onRestore,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            VersionHistoryScreen(noteId: noteId, onRestore: onRestore),
      ),
    ) ==
    true;

enum _Phase { loading, offline, failed, ready }

/// Story 3.24: the versions of a note, newest first, and the restore.
class VersionHistoryScreen extends ConsumerStatefulWidget {
  const VersionHistoryScreen({
    super.key,
    required this.noteId,
    required this.onRestore,
  });

  final String noteId;
  final RestoreEntry onRestore;

  @override
  ConsumerState<VersionHistoryScreen> createState() => _VersionHistoryState();
}

class _VersionHistoryState extends ConsumerState<VersionHistoryScreen> {
  _Phase _phase = _Phase.loading;
  String? _fileId;
  VersionData? _data;

  // What the downloads showed, by key (`r:<revision id>`, `s:<kkeujeokId>`).
  final _infos = <String, Map<String, Object?>>{};
  final _pages = <String, Map<String, dynamic>>{};
  final _started = <String>{};
  final _unreachable = <String>{}; // a download failed: preview unavailable
  final _sidecarFiles = <String, String>{}; // kkeujeokId -> Drive file id

  String? _armed; // the entry whose restore button was tapped once
  final _armedButton = GlobalKey();
  bool _busy = false;

  VersionSource get _source => VersionSource(ref.read(driveClientProvider));

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _armed = null;
    });
    try {
      final online =
          ref.read(uploadsAllowedProvider) &&
          await ref
              .read(networkProbeProvider)()
              .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!mounted) return;
      if (!online) return setState(() => _phase = _Phase.offline);
      final fileId = (await ref.read(noteStoreProvider).readSync(widget.noteId))
          .info
          .fileId;
      if (!mounted) return;
      _fileId = fileId;
      // A note that was never uploaded has no history.
      final data = fileId == null
          ? const VersionData(null, [], [])
          : await _source.load(widget.noteId, fileId);
      if (!mounted) return;
      for (final f in data.sidecars.reversed) {
        final id = f.appProperties['kkeujeokId'];
        if (id != null) _sidecarFiles[id] = f.id; // the first file wins
      }
      setState(() {
        _data = data;
        _phase = _Phase.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  String _key(Map<String, Object?> e) => e['kind'] == 'revision'
      ? 'r:${e['revisionId']}'
      : 's:sc:${widget.noteId}:${e['pageId']}:${e['rev']}';

  /// `version.list` over what is known now; the older versions only (the
  /// current one is what the note shows).
  List<Map<String, Object?>> _entries() {
    final d = _data;
    if (d == null) return const [];
    final r = versionListRule({
      'now': canonicalNow(DateTime.now()),
      'noteId': widget.noteId,
      'headRevisionId': d.headRevisionId,
      'revisions': [
        for (final v in d.revisions)
          {
            'id': v.id,
            'modifiedTime': v.modifiedTime,
            'keepForever': v.keepForever,
            'info': _infos['r:${v.id}'],
          },
      ],
      'sidecars': [
        for (final f in d.sidecars)
          {
            'appProperties': f.appProperties,
            'info': _infos['s:${f.appProperties['kkeujeokId']}'],
          },
      ],
    });
    final list = r['entries'];
    return list is List
        ? [
            for (final e in list.cast<Map<String, Object?>>())
              if (e['current'] != true) e,
          ]
        : const [];
  }

  /// Downloads the version once, for its preview and device name.
  void _ensure(Map<String, Object?> e) {
    final key = _key(e);
    final fileId = _fileId;
    if (fileId == null || !_started.add(key)) return;
    // A microtask: the first failure must not setState during the build.
    unawaited(
      Future.microtask(() async {
        try {
          final Inspection r;
          if (e['kind'] == 'revision') {
            r = await _source.inspectRevision(
              widget.noteId,
              fileId,
              e['revisionId'] as String,
            );
          } else {
            final id = key.substring(2);
            final file = _sidecarFiles[id];
            if (file == null) throw const DriveError('parse');
            r = await _source.inspectSidecar(
              widget.noteId,
              file,
              e['pageId'] as String,
              e['rev'] as String,
            );
          }
          if (!mounted) return;
          setState(() {
            _infos[key] = r.info;
            final p = r.page;
            if (r.ok && p != null) _pages[key] = p;
          });
        } catch (_) {
          // Unknown, not unreadable: no preview, the restore stays possible.
          if (mounted) setState(() => _unreachable.add(key));
        }
      }),
    );
  }

  Future<void> _restoreTap(Map<String, Object?> e) async {
    final fileId = _fileId;
    if (_busy || fileId == null) return;
    final key = _key(e);
    if (_armed != key) {
      setState(() => _armed = key);
      return;
    }
    setState(() {
      _busy = true;
      _armed = null;
    });
    RestoreFailure? failure = RestoreFailure.notApplied;
    try {
      failure = await widget.onRestore(e, fileId);
    } catch (_) {}
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = false);
    final l = AppLocalizations.of(context);
    var offline = false;
    if (failure == RestoreFailure.notSaved) {
      offline = !await ref
          .read(networkProbeProvider)()
          .timeout(const Duration(seconds: 3), onTimeout: () => true);
      if (!mounted) return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (failure) {
            RestoreFailure.unreadable => l.versionRestoreUnreadable,
            RestoreFailure.notSaved =>
              offline ? l.versionRestoreOffline : l.versionRestoreNotSaved,
            RestoreFailure.notPinned => l.versionRestorePinFailed,
            _ => l.versionRestoreFailed,
          }),
        ),
      );
  }

  /// A tap anywhere but on the armed button takes the question back.
  void _pointerDown(PointerDownEvent e) {
    if (_armed == null) return;
    final box = _armedButton.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.attached) {
      if ((box.localToGlobal(Offset.zero) & box.size).contains(e.position)) {
        return;
      }
    }
    setState(() => _armed = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final entries = _phase == _Phase.ready ? _entries() : const [];
    final Widget body;
    switch (_phase) {
      case _Phase.loading:
        body = Semantics(
          liveRegion: true,
          label: l.versionHistoryLoading,
          excludeSemantics: true,
          child: ListView(
            padding: const EdgeInsets.all(KkjTokens.spacing4),
            physics: const NeverScrollableScrollPhysics(),
            children: [for (var i = 0; i < 3; i++) const _Placeholder()],
          ),
        );
      case _Phase.offline:
        body = _Message(l.versionHistoryOffline);
      case _Phase.failed:
        body = _Message(
          l.versionHistoryFailed,
          action: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
            ),
            onPressed: _load,
            child: Text(l.retry),
          ),
        );
      case _Phase.ready:
        body = entries.isEmpty
            ? _Message(l.versionHistoryEmpty)
            : ListView.separated(
                padding: const EdgeInsets.all(KkjTokens.spacing4),
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: KkjTokens.spacing3),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  final key = _key(e);
                  return _VersionTile(
                    key: ValueKey(key),
                    entry: e,
                    page: _pages[key],
                    unavailable:
                        _unreachable.contains(key) ||
                        (_infos[key] != null && _infos[key]!['ok'] != true),
                    armed: _armed == key,
                    busy: _busy,
                    buttonKey: _armed == key ? _armedButton : null,
                    onVisible: () => _ensure(e),
                    onRestore: () => _restoreTap(e),
                  );
                },
              );
    }

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: l.versionHistory,
      explicitChildNodes: true,
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: KkjLight.colorSurfaceBase,
          body: SafeArea(
            child: Listener(
              onPointerDown: _pointerDown,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        constraints: const BoxConstraints(
                          minWidth: KkjTokens.spacingHitMinAndroid,
                          minHeight: KkjTokens.spacingHitMinAndroid,
                        ),
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            l.versionHistory,
                            style: text.titleMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(child: body),
                  if (_busy)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.all(KkjTokens.spacing3),
                        child: Text(
                          l.versionRestoring,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(KkjTokens.spacing5),
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            ?action,
          ],
        ),
      ),
    ),
  );
}

/// A grey row while the list is read.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: KkjTokens.spacing3),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: KkjLight.colorSurfaceSunken,
        borderRadius: BorderRadius.circular(KkjTokens.roundedMd),
      ),
      child: const SizedBox(height: 96, width: double.infinity),
    ),
  );
}

class _VersionTile extends StatefulWidget {
  const _VersionTile({
    super.key,
    required this.entry,
    required this.page,
    required this.unavailable,
    required this.armed,
    required this.busy,
    required this.buttonKey,
    required this.onVisible,
    required this.onRestore,
  });

  final Map<String, Object?> entry;
  final Map<String, dynamic>? page;

  /// The preview cannot be drawn (purged, unreadable, a failed download).
  final bool unavailable;
  final bool armed, busy;
  final GlobalKey? buttonKey;
  final VoidCallback onVisible, onRestore;

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  final _cache = StrokePathCache();

  @override
  void initState() {
    super.initState();
    widget.onVisible(); // the download starts when the row is built
  }

  static double _ratio(num w, num h) {
    final r = w / h;
    return r.isFinite && r > 0 ? r.clamp(0.4, 2.5).toDouble() : 1.0;
  }

  Widget _preview(AppLocalizations l) {
    final page = widget.page;
    final Widget child;
    if (page != null) {
      child = AspectRatio(
        aspectRatio: _ratio(page['width'] as num, page['height'] as num),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: KkjLight.colorBorderHairline),
            borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
          ),
          child: ClipRect(
            child: CustomPaint(
              painter: PagePainter(page: page, cache: _cache),
            ),
          ),
        ),
      );
    } else {
      child = AspectRatio(
        aspectRatio: 0.7,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: KkjLight.colorSurfaceSunken,
            borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
          ),
          child: widget.unavailable
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(KkjTokens.spacing1),
                    child: Text(
                      l.versionPreviewUnavailable,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                )
              : null,
        ),
      );
    }
    return SizedBox(width: 72, height: 96, child: Center(child: child));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final e = widget.entry;
    final at = DateTime.tryParse('${e['at']}')?.toLocal();
    final time = at == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(at);
    final device = e['deviceName'];
    final tags = [
      if (e['kind'] == 'sidecar') l.versionTagConflict,
      if (e['beforeRestore'] == true) l.versionTagBeforeRestore,
    ];
    final label = [
      time,
      if (device is String && device.isNotEmpty) device,
      ...tags,
    ].join(', ');
    final restorable = e['restorable'] == true && !widget.busy;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: KkjLight.colorSurfaceRaised,
        border: Border.all(color: KkjLight.colorBorderHairline),
        borderRadius: BorderRadius.circular(KkjTokens.roundedMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(KkjTokens.spacing3),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                label: label,
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _preview(l),
                    const SizedBox(width: KkjTokens.spacing3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(time, style: text.titleSmall),
                          if (device is String && device.isNotEmpty)
                            Text(device, style: text.bodySmall),
                          if (tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: KkjTokens.spacing1,
                              ),
                              child: Wrap(
                                spacing: KkjTokens.spacing1,
                                runSpacing: KkjTokens.spacing1,
                                children: [for (final t in tags) _Tag(t)],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KkjTokens.spacing2),
              OutlinedButton(
                key: widget.buttonKey,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, KkjTokens.spacingHitMinAndroid),
                ),
                onPressed: restorable ? widget.onRestore : null,
                child: Text(
                  widget.armed ? l.versionRestoreConfirm : l.versionRestore,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: KkjLight.componentsBadgeNeutralBackground,
      borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkjTokens.spacing2,
        vertical: KkjTokens.spacing1,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: KkjLight.componentsBadgeNeutralText),
      ),
    ),
  );
}
