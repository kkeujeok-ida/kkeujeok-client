import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/build/tokens.dart';
import '../l10n/app_localizations.dart';
import '../model/eraser.dart';
import 'providers.dart';

/// Eraser options popover: stroke / partial and return-to-pen. Every change
/// is stored at once; tapping outside closes it keeping the changes.
class EraserDialog extends ConsumerWidget {
  const EraserDialog({super.key});

  static const _cell = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(eraserSettingsProvider);
    final notifier = ref.read(eraserSettingsProvider.notifier);

    void setMode(EraserMode m) {
      if (m == s.mode) return;
      notifier.setMode(m);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          m == EraserMode.partial
              ? l10n.eraserAnnouncePartial
              : l10n.eraserAnnounceStroke,
          Directionality.of(context),
        ),
      );
    }

    Widget seg(EraserMode m, String text) {
      final active = s.mode == m;
      return Expanded(
        child: Semantics(
          button: true,
          inMutuallyExclusiveGroup: true,
          checked: active,
          label: text,
          onTap: () => setMode(m),
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
            onTap: () => setMode(m),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _cell),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: active ? KkjLight.colorAccentSoft : null,
                  borderRadius: BorderRadius.circular(KkjTokens.roundedSm),
                  border: Border.all(color: KkjLight.colorBorderControl),
                ),
                child: Center(child: Text(text)),
              ),
            ),
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: KkjLight.componentsPopoverBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KkjLight.componentsPopoverRounded),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(KkjLight.componentsPopoverPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.eraserOptionsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: KkjTokens.spacing3),
              Semantics(
                container: true,
                role: SemanticsRole.radioGroup,
                child: Row(
                  children: [
                    seg(EraserMode.stroke, l10n.eraserModeStroke),
                    const SizedBox(width: KkjTokens.spacing2),
                    seg(EraserMode.partial, l10n.eraserModePartial),
                  ],
                ),
              ),
              const SizedBox(height: KkjTokens.spacing2),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.eraserReturnToPen),
                value: s.returnToPen,
                onChanged: notifier.setReturnToPen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
