import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';

/// Static help: gestures, pen-only mode, keyboard. Opened only from Settings.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    Widget header(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(
        KkjTokens.spacing4,
        KkjTokens.spacing4,
        KkjTokens.spacing4,
        KkjTokens.spacing1,
      ),
      child: Semantics(header: true, child: Text(s, style: t.labelMedium)),
    );
    Widget item(String title, String body) => Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkjTokens.spacing4,
          vertical: KkjTokens.spacing2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.bodyMedium),
            Text(
              body,
              style: t.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    Widget line(String s) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkjTokens.spacing4,
        vertical: KkjTokens.spacing1,
      ),
      child: Text(s, style: t.bodyMedium),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.helpTitle, style: t.titleLarge),
        backgroundColor: Theme.of(context).colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          header(l.helpGesturesHeader),
          item(l.helpOneFinger, l.helpOneFingerBody),
          item(l.helpTwoFingers, l.helpTwoFingersBody),
          item(l.helpThreeFingers, l.helpThreeFingersBody),
          item(l.helpPenButton, l.helpPenButtonBody),
          header(l.helpPenOnlyHeader),
          line(l.helpPenOnlyBody),
          header(l.helpKeysHeader),
          line(l.helpKeyTools),
          line(l.helpKeyUndo),
          line(l.helpKeyArrows),
        ],
      ),
    );
  }
}
