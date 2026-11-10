import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kk.dart';

import 'snack.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/settings_layout.dart';
import '../model/smooth.dart';
import '../model/pen_only.dart';
import '../storage/pen_slots_store.dart';
import '../storage/language_store.dart';
import '../storage/theme_store.dart';
import 'disconnect_dialog.dart';
import 'help_screen.dart';
import 'log_export.dart';
import 'pen_input_diagnostic.dart';
import 'pen_palette_editor.dart';
import 'pressure_curve_section.dart';
import 'providers.dart';
import 'unsent_widgets.dart';

/// "로그아웃할까요?": pops `true` on confirm. Cancel (also back) has the focus.
class _LogOutConfirm extends StatelessWidget {
  const _LogOutConfirm();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const hit = Size(0, KkjTokens.spacingHitMinAndroid);
    return AlertDialog(
      title: Text(l10n.logOutConfirmTitle),
      actions: [
        TextButton(
          autofocus: true, // default focus is the safe choice
          style: TextButton.styleFrom(minimumSize: hit),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: hit),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.logOut),
        ),
      ],
    );
  }
}

/// A row with a 48dp minimum touch target.
class _Row extends StatelessWidget {
  const _Row({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: KkjTokens.spacingHitMinAndroid,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkjTokens.spacing4,
          vertical: KkjTokens.spacing2,
        ),
        child: Align(alignment: AlignmentDirectional.centerStart, child: child),
      ),
    ),
  );
}

/// [Export sync log]: writes the log to a file and opens the share sheet.
/// A tap while one export runs is ignored.
class _ExportLogRow extends ConsumerStatefulWidget {
  const _ExportLogRow();

  @override
  ConsumerState<_ExportLogRow> createState() => _ExportLogRowState();
}

class _ExportLogRowState extends ConsumerState<_ExportLogRow> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await exportSyncLog(ref, context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = AppLocalizations.of(context).syncLogExport;
    final onTap = _busy ? null : _export;
    return Semantics(
      button: true,
      enabled: !_busy,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: _Row(
        onTap: onTap,
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _busy ? theme.disabledColor : null,
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _scroll = ScrollController();
  final _viewKey = GlobalKey();
  final _keys = <String, GlobalKey>{};
  List<String> _ids = const [];
  String _active = 'general';
  final _chipKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Scroll-spy: highlight follows settings.activeSection (offset 8).
  void _spy(ScrollMetrics m) {
    final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || _ids.isEmpty) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final hs = <({String id, double top})>[];
    for (final id in _ids) {
      final o = _keys[id]?.currentContext?.findRenderObject() as RenderBox?;
      if (o == null || !o.attached) return;
      hs.add((id: id, top: o.localToGlobal(Offset.zero).dy));
    }
    final a = activeSettingsSection(
      hs,
      viewportTop: top,
      offset: 8,
      atEnd: m.pixels >= m.maxScrollExtent - 1,
    );
    if (a != _active) _setActive(a);
  }

  // Keeps the active chip visible in the horizontal row.
  void _setActive(String id) {
    setState(() => _active = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _chipKeys[id]?.currentContext;
      if (mounted && c != null) Scrollable.ensureVisible(c);
    });
  }

  void _goTo(String id) {
    _setActive(id);
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
    );
  }

  bool _counting = false; // single-flight: one unsent count at a time

  /// The notes with unsent changes, or null (unknown). Null `busy` result
  /// means a count is already running or this screen was left meanwhile.
  Future<({List<String>? ids})?> _count() async {
    if (_counting) return null;
    _counting = true;
    try {
      final ids = await ref.read(unsentIdsProvider)();
      return (ids: ids);
    } finally {
      _counting = false;
    }
  }

  Future<void> _logOut() async {
    final nav = Navigator.of(context);
    final counted = await _count();
    if (counted == null || !mounted) return;
    var ids = counted.ids;
    if (ids != null && ids.isEmpty) {
      // Nothing unsent: the plain confirm. The unsent warning below replaces
      // it, so two boxes never follow each other.
      final yes = await showDialog<bool>(
        context: context,
        builder: (_) => const _LogOutConfirm(),
      );
      if (yes != true || !mounted) return;
      // Edited while the box was open: count again, warn if it grew.
      try {
        ids = await ref.read(unsentIdsProvider)();
      } catch (_) {
        ids = null; // unknown: warn
      }
      if (!mounted) return;
      if (ids != null && ids.isEmpty) {
        await ref.read(authProvider.notifier).signOut();
        nav.popUntil((r) => r.isFirst);
        return;
      }
    }
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => UnsentLogoutDialog(count: ids?.length),
    );
    // A failed erase leaves the session ended: nothing to stay on.
    if (done == true || ref.read(authProvider).phase != AuthPhase.signedIn) {
      nav.popUntil((r) => r.isFirst);
    }
  }

  Future<void> _disconnect() async {
    final nav = Navigator.of(context);
    final counted = await _count();
    if (counted == null || !mounted) return;
    final ids = counted.ids;
    final warn = ids == null || ids.isNotEmpty;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => DisconnectDialog(warn: warn, unsent: ids?.length),
    );
    if (done == true) nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final choice = ref.watch(languageProvider);
    final privacyUrl = ref.watch(privacyUrlProvider);
    final options = {
      LanguageChoice.system: l10n.languageSystem,
      LanguageChoice.ko: l10n.languageKo,
      LanguageChoice.en: l10n.languageEn,
    };

    final themes = {
      ThemeChoice.light: l10n.themeLight,
      ThemeChoice.dark: l10n.themeDark,
      ThemeChoice.allDark: l10n.themeAllDark,
    };

    // A titled single-choice list (language, theme).
    Widget group<T>(
      String title,
      Map<T, String> opts,
      T current,
      void Function(T) pick,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KkjTokens.spacing4,
            KkjTokens.spacing3,
            KkjTokens.spacing4,
            KkjTokens.spacing1,
          ),
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.labelMedium),
          ),
        ),
        for (final e in opts.entries)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: current == e.key,
            label: e.value,
            excludeSemantics: true,
            onTap: () => pick(e.key),
            child: _Row(
              onTap: () => pick(e.key),
              child: Row(
                children: [
                  Expanded(
                    child: Text(e.value, style: theme.textTheme.bodyMedium),
                  ),
                  if (current == e.key)
                    Icon(Icons.check, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
      ],
    );

    final uri = privacyUri(privacyUrl);
    final hasPrivacy = uri != null;

    Future<void> openPrivacy() async {
      final messenger = ScaffoldMessenger.of(context);
      var ok = false;
      try {
        ok = await ref.read(urlOpenerProvider)(uri!);
      } catch (_) {}
      if (!ok) {
        messenger.showSnackBar(
          appSnackBar(content: Text(l10n.privacyOpenFailed)),
        );
      }
    }

    final signedIn = ref.watch(authProvider).phase == AuthPhase.signedIn;

    // The sign-in screen replaces the shell underneath; drop what is above it.
    Widget action(String label, VoidCallback onTap, {Color? color}) =>
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: _Row(
            onTap: onTap,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        );

    final items = <String, Widget>{
      'language': group(l10n.language, options, choice, (v) {
        ref.read(languageProvider.notifier).select(v);
      }),
      'theme': Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KkjTokens.spacing4,
              KkjTokens.spacing3,
              KkjTokens.spacing4,
              KkjTokens.spacing1,
            ),
            child: Semantics(
              header: true,
              child: Text(l10n.theme, style: theme.textTheme.labelMedium),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KkjTokens.spacing4),
            child: Align(
              alignment: Alignment.centerRight,
              child: SegmentedButton<ThemeChoice>(
                showSelectedIcon: false,
                segments: [
                  for (final e in themes.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {ref.watch(themeProvider)},
                onSelectionChanged: (v) =>
                    ref.read(themeProvider.notifier).select(v.first),
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                  // Reduce-motion: no slide animation on the selection change.
                  animationDuration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : kThemeChangeDuration,
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected)
                        ? Kk.colorAccentSoft
                        : Kk.colorSurfaceRaised,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected)
                        ? Kk.colorAccentText
                        : Kk.colorInkPrimary,
                  ),
                  side: WidgetStatePropertyAll(
                    BorderSide(color: Kk.colorBorderControl),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      'leftHanded': SwitchListTile(
        title: Text(l10n.leftHanded),
        value: ref.watch(leftHandedProvider),
        onChanged: ref.read(leftHandedProvider.notifier).set,
      ),
      'penOnly': Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KkjTokens.spacing4,
              KkjTokens.spacing3,
              KkjTokens.spacing4,
              KkjTokens.spacing1,
            ),
            child: Semantics(
              header: true,
              child: Text(
                l10n.penOnlyTitle,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KkjTokens.spacing4),
            child: Align(
              alignment: Alignment.centerRight,
              child: SegmentedButton<PenOnlyMode>(
                showSelectedIcon: false,
                segments: [
                  for (final e in {
                    PenOnlyMode.auto: l10n.penOnlyAuto,
                    PenOnlyMode.on: l10n.penOnlyOn,
                    PenOnlyMode.off: l10n.penOnlyOff,
                  }.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {ref.watch(penOnlyProvider)},
                onSelectionChanged: (s) =>
                    ref.read(penOnlyProvider.notifier).select(s.first),
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                  // Reduce-motion: no slide animation on the selection change.
                  animationDuration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : kThemeChangeDuration,
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected)
                        ? Kk.colorAccentSoft
                        : Kk.colorSurfaceRaised,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (st) => st.contains(WidgetState.selected)
                        ? Kk.colorAccentText
                        : Kk.colorInkPrimary,
                  ),
                  side: WidgetStatePropertyAll(
                    BorderSide(color: Kk.colorBorderControl),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      'straighten': SwitchListTile(
        title: Text(l10n.straighten),
        subtitle: Text(l10n.straightenHint),
        value: ref.watch(straightenProvider),
        onChanged: ref.read(straightenProvider.notifier).set,
      ),
      'smooth': Padding(
        padding: const EdgeInsets.symmetric(horizontal: KkjTokens.spacing4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KkjTokens.spacing2),
              child: Semantics(
                header: true,
                child: Text(l10n.smooth, style: theme.textTheme.labelMedium),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 280,
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: l10n.smooth,
                        child: Slider(
                          min: 0,
                          max: smoothMax.toDouble(),
                          divisions: smoothMax,
                          value: ref.watch(smoothProvider).toDouble(),
                          onChanged: (v) =>
                              ref.read(smoothProvider.notifier).set(v.round()),
                          semanticFormatterCallback: (v) =>
                              v == 0 ? l10n.smoothOff : '${v.round()}',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: ExcludeSemantics(
                        child: Text(
                          '${ref.watch(smoothProvider)}',
                          textAlign: TextAlign.end,
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
      'pressureCurve': const PressureCurveSection(),
      'visibleTools': Builder(
        builder: (_) {
          final n = ref.watch(visibleToolsProvider);
          final set = ref.read(visibleToolsProvider.notifier).set;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: KkjTokens.spacing4),
            child: Row(
              children: [
                Expanded(child: Text(l10n.visibleToolsTitle)),
                IconButton(
                  tooltip: l10n.visibleToolsLess,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.remove),
                  onPressed: n > PenSlotsStore.visibleToolsMin
                      ? () => set(n - 1)
                      : null,
                ),
                Semantics(
                  liveRegion: true,
                  child: Text('$n', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: l10n.visibleToolsMore,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.add),
                  onPressed: n < PenSlotsStore.visibleToolsMax
                      ? () => set(n + 1)
                      : null,
                ),
              ],
            ),
          );
        },
      ),
      'penPalette': const PenPaletteEditor(),
      'help': action(
        l10n.helpTitle,
        () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const HelpScreen())),
      ),
      'privacy': Semantics(
        button: true,
        enabled: hasPrivacy,
        label: l10n.privacyPolicy,
        hint: hasPrivacy ? null : l10n.privacyUnavailable,
        excludeSemantics: true,
        onTap: hasPrivacy ? openPrivacy : null,
        child: _Row(
          onTap: hasPrivacy ? openPrivacy : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.privacyPolicy,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hasPrivacy ? null : theme.disabledColor,
                ),
              ),
              if (!hasPrivacy)
                Text(l10n.privacyUnavailable, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      'exportLog': const _ExportLogRow(),
      'penDiag': action(
        l10n.penDiagTitle,
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PenInputDiagnosticScreen(),
          ),
        ),
      ),
      'logOut': action(l10n.logOut, _logOut),
      'disconnect': action(
        l10n.disconnect,
        _disconnect,
        color: theme.colorScheme.error,
      ),
    };
    final names = {
      'general': l10n.settingsCategoryGeneral,
      'input': l10n.settingsCategoryInput,
      'tools': l10n.settingsCategoryTools,
      'support': l10n.settingsCategorySupport,
      'account': l10n.settingsCategoryAccount,
    };
    final secs = settingsSections(signedIn: signedIn, platform: 'android');
    _ids = [for (final s in secs) s.id];
    for (final id in _ids) {
      _keys.putIfAbsent(id, GlobalKey.new);
      _chipKeys.putIfAbsent(id, GlobalKey.new);
    }
    if (!_ids.contains(_active)) _active = _ids.first;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings, style: theme.textTheme.titleLarge),
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          // Width measured after text scale: big text switches to the chip row.
          final wide =
              box.maxWidth / MediaQuery.textScalerOf(context).scale(1) >= 720;
          final nav = _Nav(
            ids: _ids,
            names: names,
            active: _active,
            wide: wide,
            label: l10n.settingsCategoriesLabel,
            onTap: _goTo,
            keys: _chipKeys,
          );
          // Right highlight on open and resize, not only after a scroll.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scroll.hasClients) _spy(_scroll.position);
          });
          final main = LayoutBuilder(
            builder: (context, view) => NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.vertical) _spy(n.metrics);
                return false;
              },
              child: SingleChildScrollView(
                key: _viewKey,
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, s) in secs.indexed)
                      // The last section is at least a viewport tall so it can
                      // reach the top.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: i == secs.length - 1 ? view.maxHeight : 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              key: _keys[s.id],
                              padding: const EdgeInsets.fromLTRB(
                                KkjTokens.spacing4,
                                KkjTokens.spacing4,
                                KkjTokens.spacing4,
                                KkjTokens.spacing2,
                              ),
                              child: Semantics(
                                header: true,
                                child: Text(
                                  names[s.id]!,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            ),
                            for (final (j, id) in s.items.indexed) ...[
                              if (j > 0)
                                Divider(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              items[id]!,
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
          return wide
              ? Row(
                  children: [
                    SizedBox(width: 200, child: nav),
                    VerticalDivider(
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Expanded(child: main),
                  ],
                )
              : Column(
                  children: [
                    nav,
                    Expanded(child: main),
                  ],
                );
        },
      ),
    );
  }
}

/// Category navigation: left list (wide) or sticky chip row (narrow).
class _Nav extends StatelessWidget {
  const _Nav({
    required this.ids,
    required this.names,
    required this.active,
    required this.wide,
    required this.label,
    required this.onTap,
    required this.keys,
  });

  final List<String> ids;
  final Map<String, String> names;
  final String active;
  final bool wide;
  final String label;
  final void Function(String) onTap;
  final Map<String, GlobalKey> keys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget entry(String id) {
      final sel = id == active;
      return Semantics(
        key: keys[id],
        button: true,
        selected: sel,
        label: names[id],
        excludeSemantics: true,
        onTap: () => onTap(id),
        child: Padding(
          padding: EdgeInsets.all(wide ? 0 : KkjTokens.spacing1),
          child: Material(
            color: sel ? Kk.colorAccentSoft : Kk.colorSurfaceRaised,
            shape: wide
                ? null
                : StadiumBorder(side: BorderSide(color: Kk.colorBorderControl)),
            child: InkWell(
              onTap: () => onTap(id),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: KkjTokens.spacingHitMinAndroid,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KkjTokens.spacing4,
                    vertical: KkjTokens.spacing2,
                  ),
                  child: Align(
                    alignment: wide
                        ? AlignmentDirectional.centerStart
                        : Alignment.center,
                    widthFactor: wide ? null : 1,
                    child: Text(
                      names[id]!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: sel ? Kk.colorAccentText : Kk.colorInkPrimary,
                        fontWeight: sel ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: label,
      child: wide
          ? SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final id in ids) entry(id)],
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: KkjTokens.spacing2,
              ),
              child: Row(children: [for (final id in ids) entry(id)]),
            ),
    );
  }
}
