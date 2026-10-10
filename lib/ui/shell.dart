import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import 'settings.dart';

const double expandedMinWidth = 840; // dp: sidebar expanded at or above
const double collapsedMinWidth = 600; // dp: collapsed rail at or above
// Scale-based: 5 x spacing-7. The tokens define no sidebar width.
const double _sidebarWidth = KkjTokens.spacing7 * 5;

const _hitBox = BoxConstraints(
  minWidth: KkjTokens.spacingHitMinAndroid,
  minHeight: KkjTokens.spacingHitMinAndroid,
);

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _openSettings() {
    final nav = Navigator.of(context);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) nav.pop();
    nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final expanded = width >= expandedMinWidth;
    final collapsed = !expanded && width >= collapsedMinWidth;
    final sidebarColor = theme.colorScheme.surfaceContainerHighest;

    final sidebar = _Sidebar(
      width: _sidebarWidth,
      color: sidebarColor,
      onSettings: _openSettings,
    );

    // The library area stays empty until later stories fill it.
    final library = Semantics(
      label: l10n.library,
      container: true,
      child: const SizedBox.expand(),
    );

    final Widget body;
    if (expanded) {
      body = Row(
        children: [
          sidebar,
          Expanded(child: library),
        ],
      );
    } else if (collapsed) {
      body = Row(
        children: [
          Container(
            color: sidebarColor,
            padding: const EdgeInsets.all(KkjTokens.spacing2),
            child: Column(
              children: [
                IconButton(
                  tooltip: l10n.openSidebar,
                  constraints: _hitBox,
                  icon: const Icon(Icons.menu),
                  onPressed: _openDrawer,
                ),
                const Spacer(),
                IconButton(
                  tooltip: l10n.settings,
                  constraints: _hitBox,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _openSettings,
                ),
              ],
            ),
          ),
          Expanded(child: library),
        ],
      );
    } else {
      body = Stack(
        children: [
          library,
          PositionedDirectional(
            top: KkjTokens.spacing2,
            start: KkjTokens.spacing2,
            child: IconButton(
              tooltip: l10n.openSidebar,
              constraints: _hitBox,
              icon: const Icon(Icons.menu),
              onPressed: _openDrawer,
            ),
          ),
        ],
      );
    }

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: l10n.productName,
      explicitChildNodes: true,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: expanded ? null : Drawer(child: sidebar),
        body: SafeArea(child: body),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.width,
    required this.color,
    required this.onSettings,
  });

  final double width;
  final Color color;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      width: width,
      color: color,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(KkjTokens.spacing4),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.productName,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            const Spacer(),
            Semantics(
              button: true,
              label: l10n.settings,
              excludeSemantics: true,
              onTap: onSettings,
              child: InkWell(
                onTap: onSettings,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: KkjTokens.spacingHitMinAndroid,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KkjTokens.spacing4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: KkjTokens.spacing3),
                        Text(l10n.settings, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: KkjTokens.spacing2),
          ],
        ),
      ),
    );
  }
}
