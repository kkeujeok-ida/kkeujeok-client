import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../storage/language_store.dart';
import 'library.dart' show libraryRouteObserver;
import 'kk.dart';
import 'providers.dart';
import 'account_gate.dart';
import 'sign_in.dart';

// Generated from kkeujeok-web/design_tokens (symlinked as lib/design_tokens).
// The only place colours, type and spacing come from.
import '../design_tokens/build/tokens.dart';

TextStyle _text(
  String family,
  double size,
  FontWeight weight,
  double lineHeight,
  Color color,
) => TextStyle(
  fontFamily: family,
  fontSize: size, // sp: follows the system font scale
  fontWeight: weight,
  height: lineHeight / size, // line height grows with the text
  color: color,
);

/// The Material theme for the Light or the Dark tokens ([Kk.dark]).
ThemeData appTheme() {
  final scheme =
      (Kk.dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: Kk.colorAccent,
        onPrimary: Kk.colorOnAccent,
        primaryContainer: Kk.colorAccentSoft,
        onPrimaryContainer: Kk.colorAccentText,
        secondaryContainer: Kk.colorAccentSoft, // selected rows: the brand color, not Material's tint
        onSecondaryContainer: Kk.colorAccentText,
        surface: Kk.colorSurfaceBase,
        onSurface: Kk.colorInkPrimary,
        onSurfaceVariant: Kk.colorInkSecondary,
        surfaceContainerLowest: Kk.colorSurfaceRaised,
        surfaceContainerHighest: Kk.colorSurfaceSunken,
        outline: Kk.colorBorderControl,
        outlineVariant: Kk.colorBorderHairline,
        error: Kk.colorStatusError,
        onError: Kk.colorOnError,
        scrim: Kk.colorScrim,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Kk.colorSurfaceBase,
    disabledColor: Kk.colorInkDisabled,
    fontFamily: KkjTokens.typographyBodyFontFamily,
    textTheme: TextTheme(
      titleLarge: _text(
        KkjTokens.typographyTitleFontFamily,
        KkjTokens.typographyTitleFontSize,
        KkjTokens.typographyTitleFontWeight,
        KkjTokens.typographyTitleLineHeight,
        Kk.colorInkPrimary,
      ),
      bodyMedium: _text(
        KkjTokens.typographyBodyFontFamily,
        KkjTokens.typographyBodyFontSize,
        KkjTokens.typographyBodyFontWeight,
        KkjTokens.typographyBodyLineHeight,
        Kk.colorInkPrimary,
      ),
      labelMedium: _text(
        KkjTokens.typographyLabelFontFamily,
        KkjTokens.typographyLabelFontSize,
        KkjTokens.typographyLabelFontWeight,
        KkjTokens.typographyLabelLineHeight,
        Kk.colorInkPrimary,
      ),
      bodySmall: _text(
        KkjTokens.typographyCaptionFontFamily,
        KkjTokens.typographyCaptionFontSize,
        KkjTokens.typographyCaptionFontWeight,
        KkjTokens.typographyCaptionLineHeight,
        Kk.colorInkSecondary,
      ),
    ),
  );
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(languageProvider);
    Kk.applyTheme(ref.watch(themeProvider));
    return MaterialApp(
      onGenerateTitle: (c) => AppLocalizations.of(c).productName,
      theme: appTheme(),
      // An explicit choice wins; "system" is resolved from the device list.
      locale: choice == LanguageChoice.system
          ? null
          : resolveLocale(choice, null),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (locales, _) =>
          resolveLocale(LanguageChoice.system, locales),
      navigatorObservers: [libraryRouteObserver],
      home: const _Gate(),
    );
  }
}

/// Only a signed-in user reaches the shell; everyone else sees sign-in.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(authProvider).phase) {
        AuthPhase.signedIn => const AccountGate(),
        AuthPhase.checking => const Scaffold(),
        _ => const SignInScreen(),
      };
}
