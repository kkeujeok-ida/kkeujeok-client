import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/page_bounds.dart';
import '../render/page_painter.dart';

/// Story 6.2: the full-screen page overview. Pops with the tapped page index,
/// or null when closed. [+], [선택] and ⋯ are entry points that stay disabled
/// until the page operations (Stories 6.4-6.8).
class PageOverview extends StatelessWidget {
  const PageOverview({
    super.key,
    required this.pages,
    required this.current,
    required this.conflicted,
  });

  final List<Map<String, dynamic>> pages;
  final int current;

  /// Ids of the pages with an unresolved conflict.
  final Set<String> conflicted;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: KkjLight.colorSurfaceBase,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: KkjLight.colorSurfaceBase,
        title: Semantics(header: true, child: Text(l.pageOverviewTitle)),
        actions: [
          IconButton(
            tooltip: l.pageAdd,
            icon: const Icon(Icons.add),
            onPressed: null,
          ),
          TextButton(onPressed: null, child: Text(l.pageSelect)),
          IconButton(
            tooltip: l.close,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      // Built lazily: only the thumbnails in view are drawn (NFR2).
      body: GridView.builder(
        padding: const EdgeInsets.all(KkjTokens.spacing3),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: KkjTokens.spacing3,
          crossAxisSpacing: KkjTokens.spacing3,
          childAspectRatio: 0.72,
        ),
        itemCount: pages.length,
        itemBuilder: (context, i) => _Cell(
          page: pages[i],
          index: i,
          total: pages.length,
          isCurrent: i == current,
          conflict: conflicted.contains(pages[i]['id']),
          onTap: () => Navigator.of(context).pop(i),
        ),
      ),
    );
  }
}

class _Cell extends StatefulWidget {
  const _Cell({
    required this.page,
    required this.index,
    required this.total,
    required this.isCurrent,
    required this.conflict,
    required this.onTap,
  });

  final Map<String, dynamic> page;
  final int index, total;
  final bool isCurrent, conflict;
  final VoidCallback onTap;

  @override
  State<_Cell> createState() => _CellState();
}

class _CellState extends State<_Cell> {
  final _cache = StrokePathCache();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = widget.page;
    final w = (p['width'] as num).toDouble(),
        h = (p['height'] as num).toDouble();
    final ratio = (w / h).isFinite && w > 0 && h > 0
        ? (w / h).clamp(0.2, 5.0).toDouble()
        : 0.7;
    final out = pageOutOfBounds(w, h, [
      for (final e in p['elements'] as List) (e as Map).cast<String, dynamic>(),
    ]).length;
    final n = widget.index + 1;
    final label = [
      l.pageSemantics(
        n,
        widget.total,
        w > h ? l.pageLandscape : l.pagePortrait,
      ),
      if (widget.isCurrent) l.pageCurrent,
      if (widget.conflict) l.pageConflictBadge,
      if (out > 0) l.pageOutOfBoundsBadge(out),
    ].join(', ');
    const radius = KkjLight.componentsPageThumbnailRounded;
    final badge = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: KkjLight.colorStatusWarningText);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Semantics(
                    button: true,
                    label: label,
                    excludeSemantics: true,
                    onTap: widget.onTap,
                    child: GestureDetector(
                      onTap: widget.onTap,
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: widget.isCurrent
                                ? KkjLight.componentsPageThumbnailCurrentRing
                                : KkjLight.componentsPageThumbnailBorder,
                            width: widget.isCurrent ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(radius),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(radius),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: PagePainter(page: p, cache: _cache),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: l.pageMenu,
                      iconSize: 18,
                      constraints: const BoxConstraints(
                        minWidth: KkjLight.componentsPageThumbnailMenuButton,
                        minHeight: KkjLight.componentsPageThumbnailMenuButton,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_horiz),
                      onPressed: null,
                    ),
                  ),
                  if (widget.conflict || out > 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      right: 4,
                      child: ExcludeSemantics(
                        child: Wrap(
                          spacing: 4,
                          children: [
                            for (final t in [
                              if (widget.conflict) l.pageConflictBadge,
                              if (out > 0) l.pageOutOfBoundsBadge(out),
                            ])
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: KkjLight.colorSurfaceRaised,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.warning_amber,
                                        size: 12,
                                        color: KkjLight.colorStatusWarningText,
                                      ),
                                      const SizedBox(width: 2),
                                      Flexible(child: Text(t, style: badge)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        ExcludeSemantics(
          child: Text(
            widget.isCurrent ? '$n · ${l.pageCurrent}' : '$n',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}
