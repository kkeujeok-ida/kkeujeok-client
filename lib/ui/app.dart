import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../storage/language_store.dart';
import 'providers.dart';
import 'shell.dart';
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

ThemeData lightTheme() {
  final scheme = ColorScheme.light(
    primary: KkjLight.colorAccent,
    onPrimary: KkjLight.colorOnAccent,
    primaryContainer: KkjLight.colorAccentSoft,
    onPrimaryContainer: KkjLight.colorAccentText,
    surface: KkjLight.colorSurfaceBase,
    onSurface: KkjLight.colorInkPrimary,
    onSurfaceVariant: KkjLight.colorInkSecondary,
    surfaceContainerLowest: KkjLight.colorSurfaceRaised,
    surfaceContainerHighest: KkjLight.colorSurfaceSunken,
    outline: KkjLight.colorBorderControl,
    outlineVariant: KkjLight.colorBorderHairline,
    error: KkjLight.colorStatusError,
    onError: KkjLight.colorOnError,
    scrim: KkjLight.colorScrim,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: KkjLight.colorSurfaceBase,
    disabledColor: KkjLight.colorInkDisabled,
    fontFamily: KkjTokens.typographyBodyFontFamily,
    textTheme: TextTheme(
      titleLarge: _text(
        KkjTokens.typographyTitleFontFamily,
        KkjTokens.typographyTitleFontSize,
        KkjTokens.typographyTitleFontWeight,
        KkjTokens.typographyTitleLineHeight,
        KkjLight.colorInkPrimary,
      ),
      bodyMedium: _text(
        KkjTokens.typographyBodyFontFamily,
        KkjTokens.typographyBodyFontSize,
        KkjTokens.typographyBodyFontWeight,
        KkjTokens.typographyBodyLineHeight,
        KkjLight.colorInkPrimary,
      ),
      labelMedium: _text(
        KkjTokens.typographyLabelFontFamily,
        KkjTokens.typographyLabelFontSize,
        KkjTokens.typographyLabelFontWeight,
        KkjTokens.typographyLabelLineHeight,
        KkjLight.colorInkPrimary,
      ),
      bodySmall: _text(
        KkjTokens.typographyCaptionFontFamily,
        KkjTokens.typographyCaptionFontSize,
        KkjTokens.typographyCaptionFontWeight,
        KkjTokens.typographyCaptionLineHeight,
        KkjLight.colorInkSecondary,
      ),
    ),
  );
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(languageProvider);
    return MaterialApp(
      onGenerateTitle: (c) => AppLocalizations.of(c).productName,
      theme: lightTheme(),
      // An explicit choice wins; "system" is resolved from the device list.
      locale: choice == LanguageChoice.system
          ? null
          : resolveLocale(choice, null),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: (locales, _) =>
          resolveLocale(LanguageChoice.system, locales),
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
        AuthPhase.signedIn => const Shell(),
        AuthPhase.checking => const Scaffold(),
        _ => const SignInScreen(),
      };
}
