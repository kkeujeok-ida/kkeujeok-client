import 'package:flutter/material.dart';

import '../design_tokens/build/tokens.dart';
import '../storage/theme_store.dart';

/// Theme-aware color tokens: the Light or the Dark (also All Dark) value of
/// the same token, by [Kk.dark]. Generated list; the values stay in tokens.dart.
class Kk {
  Kk._();

  /// Set by the app when the chosen theme is Dark or All Dark.
  static bool dark = false;

  /// All Dark: page, writing and text are shown inverted (spec/invert.md).
  static bool allDark = false;

  /// Makes [choice] the current theme. A change rebuilds every element once
  /// after the frame, so widgets that read [Kk] getters pick up the new colors.
  static void applyTheme(ThemeChoice choice) {
    final d = choice != ThemeChoice.light, a = choice == ThemeChoice.allDark;
    if (d == dark && a == allDark) return;
    dark = d;
    allDark = a;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(mark);
    });
  }

  static Color get colorAccent =>
      dark ? KkjDark.colorAccent : KkjLight.colorAccent;
  static Color get colorAccentSoft =>
      dark ? KkjDark.colorAccentSoft : KkjLight.colorAccentSoft;
  static Color get colorAccentText =>
      dark ? KkjDark.colorAccentText : KkjLight.colorAccentText;
  static Color get colorBorderControl =>
      dark ? KkjDark.colorBorderControl : KkjLight.colorBorderControl;
  static Color get colorBorderHairline =>
      dark ? KkjDark.colorBorderHairline : KkjLight.colorBorderHairline;
  static Color get colorInkDisabled =>
      dark ? KkjDark.colorInkDisabled : KkjLight.colorInkDisabled;
  static Color get colorInkPrimary =>
      dark ? KkjDark.colorInkPrimary : KkjLight.colorInkPrimary;
  static Color get colorInkSecondary =>
      dark ? KkjDark.colorInkSecondary : KkjLight.colorInkSecondary;
  static Color get colorOnAccent =>
      dark ? KkjDark.colorOnAccent : KkjLight.colorOnAccent;
  static Color get colorOnError =>
      dark ? KkjDark.colorOnError : KkjLight.colorOnError;
  static Color get colorOnWarning =>
      dark ? KkjDark.colorOnWarning : KkjLight.colorOnWarning;
  static Color get colorPenGlyphOutline =>
      dark ? KkjDark.colorPenGlyphOutline : KkjLight.colorPenGlyphOutline;
  static Color get colorScrim =>
      dark ? KkjDark.colorScrim : KkjLight.colorScrim;
  static Color get colorStatusError =>
      dark ? KkjDark.colorStatusError : KkjLight.colorStatusError;
  static Color get colorStatusWarning =>
      dark ? KkjDark.colorStatusWarning : KkjLight.colorStatusWarning;
  static Color get colorStatusWarningText =>
      dark ? KkjDark.colorStatusWarningText : KkjLight.colorStatusWarningText;
  static Color get colorSurfaceBase =>
      dark ? KkjDark.colorSurfaceBase : KkjLight.colorSurfaceBase;
  static Color get colorSurfaceRaised =>
      dark ? KkjDark.colorSurfaceRaised : KkjLight.colorSurfaceRaised;
  static Color get colorSurfaceSunken =>
      dark ? KkjDark.colorSurfaceSunken : KkjLight.colorSurfaceSunken;
  static Color get componentsBadgeConflictBackground => dark
      ? KkjDark.componentsBadgeConflictBackground
      : KkjLight.componentsBadgeConflictBackground;
  static Color get componentsBadgeConflictText => dark
      ? KkjDark.componentsBadgeConflictText
      : KkjLight.componentsBadgeConflictText;
  static Color get componentsBadgeErrorBackground => dark
      ? KkjDark.componentsBadgeErrorBackground
      : KkjLight.componentsBadgeErrorBackground;
  static Color get componentsBadgeErrorText => dark
      ? KkjDark.componentsBadgeErrorText
      : KkjLight.componentsBadgeErrorText;
  static Color get componentsBadgeNeutralBackground => dark
      ? KkjDark.componentsBadgeNeutralBackground
      : KkjLight.componentsBadgeNeutralBackground;
  static Color get componentsBadgeNeutralText => dark
      ? KkjDark.componentsBadgeNeutralText
      : KkjLight.componentsBadgeNeutralText;
  static Color get componentsBannerBackground => dark
      ? KkjDark.componentsBannerBackground
      : KkjLight.componentsBannerBackground;
  static Color get componentsBannerText =>
      dark ? KkjDark.componentsBannerText : KkjLight.componentsBannerText;
  static Color get componentsButtonDestructiveBackground => dark
      ? KkjDark.componentsButtonDestructiveBackground
      : KkjLight.componentsButtonDestructiveBackground;
  static Color get componentsButtonDestructiveText => dark
      ? KkjDark.componentsButtonDestructiveText
      : KkjLight.componentsButtonDestructiveText;
  static Color get componentsButtonPrimaryBackground => dark
      ? KkjDark.componentsButtonPrimaryBackground
      : KkjLight.componentsButtonPrimaryBackground;
  static Color get componentsButtonPrimaryText => dark
      ? KkjDark.componentsButtonPrimaryText
      : KkjLight.componentsButtonPrimaryText;
  static Color get componentsButtonSecondaryBackground => dark
      ? KkjDark.componentsButtonSecondaryBackground
      : KkjLight.componentsButtonSecondaryBackground;
  static Color get componentsButtonSecondaryBorder => dark
      ? KkjDark.componentsButtonSecondaryBorder
      : KkjLight.componentsButtonSecondaryBorder;
  static Color get componentsButtonSecondaryText => dark
      ? KkjDark.componentsButtonSecondaryText
      : KkjLight.componentsButtonSecondaryText;
  static Color get componentsConflictSheetBackground => dark
      ? KkjDark.componentsConflictSheetBackground
      : KkjLight.componentsConflictSheetBackground;
  static Color get componentsConflictSheetChangeOutline => dark
      ? KkjDark.componentsConflictSheetChangeOutline
      : KkjLight.componentsConflictSheetChangeOutline;
  static Color get componentsConflictSheetPreviewBorder => dark
      ? KkjDark.componentsConflictSheetPreviewBorder
      : KkjLight.componentsConflictSheetPreviewBorder;
  static Color get componentsConflictSheetPrimaryBackground => dark
      ? KkjDark.componentsConflictSheetPrimaryBackground
      : KkjLight.componentsConflictSheetPrimaryBackground;
  static Color get componentsConflictSheetPrimaryText => dark
      ? KkjDark.componentsConflictSheetPrimaryText
      : KkjLight.componentsConflictSheetPrimaryText;
  static Color get componentsConflictSheetScrim => dark
      ? KkjDark.componentsConflictSheetScrim
      : KkjLight.componentsConflictSheetScrim;
  static Color get componentsConflictSheetTagBackground => dark
      ? KkjDark.componentsConflictSheetTagBackground
      : KkjLight.componentsConflictSheetTagBackground;
  static Color get componentsConflictSheetTagText => dark
      ? KkjDark.componentsConflictSheetTagText
      : KkjLight.componentsConflictSheetTagText;
  static Color get componentsConflictSheetVersionButtonBackground => dark
      ? KkjDark.componentsConflictSheetVersionButtonBackground
      : KkjLight.componentsConflictSheetVersionButtonBackground;
  static Color get componentsConflictSheetVersionButtonBorder => dark
      ? KkjDark.componentsConflictSheetVersionButtonBorder
      : KkjLight.componentsConflictSheetVersionButtonBorder;
  static Color get componentsConflictSheetVersionButtonText => dark
      ? KkjDark.componentsConflictSheetVersionButtonText
      : KkjLight.componentsConflictSheetVersionButtonText;
  static Color get componentsCoverCardFallbackBackground => dark
      ? KkjDark.componentsCoverCardFallbackBackground
      : KkjLight.componentsCoverCardFallbackBackground;
  static Color get componentsCoverCardFallbackBorder => dark
      ? KkjDark.componentsCoverCardFallbackBorder
      : KkjLight.componentsCoverCardFallbackBorder;
  static String get componentsCoverCardShadow => dark
      ? KkjDark.componentsCoverCardShadow
      : KkjLight.componentsCoverCardShadow;
  static Color get componentsEditorCornerBackground => dark
      ? KkjDark.componentsEditorCornerBackground
      : KkjLight.componentsEditorCornerBackground;
  static Color get componentsEditorCornerBorder => dark
      ? KkjDark.componentsEditorCornerBorder
      : KkjLight.componentsEditorCornerBorder;
  static Color get componentsFabBackground =>
      dark ? KkjDark.componentsFabBackground : KkjLight.componentsFabBackground;
  static Color get componentsFabIcon =>
      dark ? KkjDark.componentsFabIcon : KkjLight.componentsFabIcon;
  static Color get componentsFabItemBackground => dark
      ? KkjDark.componentsFabItemBackground
      : KkjLight.componentsFabItemBackground;
  static Color get componentsFabItemIcon =>
      dark ? KkjDark.componentsFabItemIcon : KkjLight.componentsFabItemIcon;
  static Color get componentsFabLabelColor =>
      dark ? KkjDark.componentsFabLabelColor : KkjLight.componentsFabLabelColor;
  static String get componentsFabShadow =>
      dark ? KkjDark.componentsFabShadow : KkjLight.componentsFabShadow;
  static Color get componentsFabVeil =>
      dark ? KkjDark.componentsFabVeil : KkjLight.componentsFabVeil;
  static Color get componentsFocusRingColor => dark
      ? KkjDark.componentsFocusRingColor
      : KkjLight.componentsFocusRingColor;
  static Color get componentsInlineHintColor => dark
      ? KkjDark.componentsInlineHintColor
      : KkjLight.componentsInlineHintColor;
  static Color get componentsInputBorder =>
      dark ? KkjDark.componentsInputBorder : KkjLight.componentsInputBorder;
  static Color get componentsInputPlaceholder => dark
      ? KkjDark.componentsInputPlaceholder
      : KkjLight.componentsInputPlaceholder;
  static Color get componentsPageThumbnailBorder => dark
      ? KkjDark.componentsPageThumbnailBorder
      : KkjLight.componentsPageThumbnailBorder;
  static Color get componentsPageThumbnailCurrentRing => dark
      ? KkjDark.componentsPageThumbnailCurrentRing
      : KkjLight.componentsPageThumbnailCurrentRing;
  static Color get componentsPdfPlaceholderBackground => dark
      ? KkjDark.componentsPdfPlaceholderBackground
      : KkjLight.componentsPdfPlaceholderBackground;
  static Color get componentsPdfPlaceholderColor => dark
      ? KkjDark.componentsPdfPlaceholderColor
      : KkjLight.componentsPdfPlaceholderColor;
  static Color get componentsPenSlotAddIcon => dark
      ? KkjDark.componentsPenSlotAddIcon
      : KkjLight.componentsPenSlotAddIcon;
  static Color get componentsPenSlotCaret =>
      dark ? KkjDark.componentsPenSlotCaret : KkjLight.componentsPenSlotCaret;
  static Color get componentsPenSlotSelectedIndicator => dark
      ? KkjDark.componentsPenSlotSelectedIndicator
      : KkjLight.componentsPenSlotSelectedIndicator;
  static Color get componentsPenSlotThicknessDotOutline => dark
      ? KkjDark.componentsPenSlotThicknessDotOutline
      : KkjLight.componentsPenSlotThicknessDotOutline;
  static Color get componentsPopoverBackground => dark
      ? KkjDark.componentsPopoverBackground
      : KkjLight.componentsPopoverBackground;
  static String get componentsPopoverShadow =>
      dark ? KkjDark.componentsPopoverShadow : KkjLight.componentsPopoverShadow;
  static Color get componentsPullToAddProgress => dark
      ? KkjDark.componentsPullToAddProgress
      : KkjLight.componentsPullToAddProgress;
  static Color get componentsPullToAddTrack => dark
      ? KkjDark.componentsPullToAddTrack
      : KkjLight.componentsPullToAddTrack;
  static Color get componentsSelectionHandleBorder => dark
      ? KkjDark.componentsSelectionHandleBorder
      : KkjLight.componentsSelectionHandleBorder;
  static Color get componentsSelectionHandleFill => dark
      ? KkjDark.componentsSelectionHandleFill
      : KkjLight.componentsSelectionHandleFill;
  static Color get componentsSelectionOutline => dark
      ? KkjDark.componentsSelectionOutline
      : KkjLight.componentsSelectionOutline;
  static Color get componentsSnackbarAction => dark
      ? KkjDark.componentsSnackbarAction
      : KkjLight.componentsSnackbarAction;
  static Color get componentsSnackbarBackground => dark
      ? KkjDark.componentsSnackbarBackground
      : KkjLight.componentsSnackbarBackground;
  static Color get componentsSnackbarText =>
      dark ? KkjDark.componentsSnackbarText : KkjLight.componentsSnackbarText;
  static Color get componentsSyncIndicatorConflictIcon => dark
      ? KkjDark.componentsSyncIndicatorConflictIcon
      : KkjLight.componentsSyncIndicatorConflictIcon;
  static Color get componentsSyncIndicatorConflictText => dark
      ? KkjDark.componentsSyncIndicatorConflictText
      : KkjLight.componentsSyncIndicatorConflictText;
  static Color get componentsSyncIndicatorError => dark
      ? KkjDark.componentsSyncIndicatorError
      : KkjLight.componentsSyncIndicatorError;
  static Color get componentsSyncIndicatorIncoming => dark
      ? KkjDark.componentsSyncIndicatorIncoming
      : KkjLight.componentsSyncIndicatorIncoming;
  static Color get componentsSyncIndicatorOffline => dark
      ? KkjDark.componentsSyncIndicatorOffline
      : KkjLight.componentsSyncIndicatorOffline;
  static Color get componentsSyncIndicatorPending => dark
      ? KkjDark.componentsSyncIndicatorPending
      : KkjLight.componentsSyncIndicatorPending;
  static Color get componentsSyncIndicatorSynced => dark
      ? KkjDark.componentsSyncIndicatorSynced
      : KkjLight.componentsSyncIndicatorSynced;
  static Color get componentsSyncIndicatorSyncing => dark
      ? KkjDark.componentsSyncIndicatorSyncing
      : KkjLight.componentsSyncIndicatorSyncing;
  static Color get componentsTextFormatBarBackground => dark
      ? KkjDark.componentsTextFormatBarBackground
      : KkjLight.componentsTextFormatBarBackground;
  static String get componentsTextFormatBarShadow => dark
      ? KkjDark.componentsTextFormatBarShadow
      : KkjLight.componentsTextFormatBarShadow;
  static Color get componentsToolSelectedIndicator => dark
      ? KkjDark.componentsToolSelectedIndicator
      : KkjLight.componentsToolSelectedIndicator;
  static Color get componentsToolbarBackground => dark
      ? KkjDark.componentsToolbarBackground
      : KkjLight.componentsToolbarBackground;
  static Color get componentsToolbarGripGlyph => dark
      ? KkjDark.componentsToolbarGripGlyph
      : KkjLight.componentsToolbarGripGlyph;
  static String get componentsToolbarShadow =>
      dark ? KkjDark.componentsToolbarShadow : KkjLight.componentsToolbarShadow;
}
