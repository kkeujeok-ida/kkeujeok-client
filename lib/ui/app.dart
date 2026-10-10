import 'package:flutter/material.dart';

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

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kkeujeok',
      theme: lightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(KkjTokens.spacing5),
              child: Text(
                'Kkeujeok',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
