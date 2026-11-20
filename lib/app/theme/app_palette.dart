// Keep the roles in the order of docs/DESIGN.md 2.2;
// test/unit/palette_tokens_test.dart checks every value against that table.
import 'package:flutter/material.dart';

/// The Sindur colour tokens (docs/DESIGN.md section 2) as a
/// [ThemeExtension], so every widget reads the colours of the theme it sits
/// in: `context.palette.textPrimary`.
///
/// [dark] is the near-black theme, [light] the white theme and [classic]
/// the original Bijuli "Volt on Ink" theme. `AppTheme` registers the
/// matching instance in each [ThemeData]; the Ink Dock, Now Playing and the
/// video player wrap themselves in `InkTheme.of(context)`, so `context.palette`
/// is always a dark palette ([dark] or [classic]) inside them.
///
/// Volt fills ([voltFill], [primaryGradient], [onVoltFill]) reach the screen
/// only through `VoltButton`, `VoltDisc`, `VoltSlab` (lib/shared/widgets/
/// ui_kit.dart) and the chip theme; test/unit/volt_usage_test.dart fails on
/// any other use. Use [primary] for brand-coloured text and icons: it is
/// readable in both themes.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfacePressed,
    required this.primary,
    required this.primaryBase,
    required this.primaryPressed,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.voltFill,
    required this.voltPressed,
    required this.onVoltFill,
    required this.onVoltMuted,
    required this.voltEdge,
    required this.voltGlow,
    required this.accent,
    required this.onAccent,
    required this.favorite,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.outlineVariant,
    required this.outline,
    required this.rule,
    required this.focusRing,
    required this.dragHandle,
    required this.success,
    required this.warning,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.liveFill,
    required this.onLive,
    required this.scrim,
    required this.glass,
    required this.overlay,
    required this.onOverlay,
    required this.dock,
    required this.onDock,
    required this.onDockMuted,
    required this.dockLine,
    required this.navIndicator,
    required this.onNavIndicator,
    required this.sliderActive,
    required this.sliderInactive,
    required this.sliderThumb,
    required this.snackbar,
    required this.onSnackbar,
    required this.snackbarAction,
    required this.shadow,
    required this.printShadow,
    required this.onTertiary,
    required this.schemeShadow,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.heroGradient,
    required this.primaryGradient,
    required this.artworkGradients,
  });

  /// Sindur dark: near-black canvas, crimson brand fill, rose text accent,
  /// lavender second accent and milk text.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: _Sindur.background,
    surface: _Sindur.surface,
    surfaceElevated: _Sindur.surfaceElevated,
    surfacePressed: _Sindur.surfacePressed,
    primary: _Sindur.primary,
    primaryBase: _Sindur.primaryBase,
    primaryPressed: _Sindur.primaryPressed,
    onPrimary: _Sindur.onPrimary,
    primaryContainer: _Sindur.primaryContainer,
    onPrimaryContainer: _Sindur.onPrimaryContainer,
    secondary: _Sindur.secondary,
    onSecondary: _Sindur.onSecondary,
    secondaryContainer: _Sindur.secondaryContainer,
    onSecondaryContainer: _Sindur.onSecondaryContainer,
    voltFill: _Sindur.voltFill,
    voltPressed: _Sindur.voltPressed,
    onVoltFill: _Sindur.onVoltFill,
    onVoltMuted: _Sindur.onVoltMuted,
    voltEdge: _Sindur.voltEdge,
    voltGlow: _Sindur.voltGlow,
    accent: _Sindur.accent,
    onAccent: _Sindur.onAccent,
    favorite: _Sindur.favorite,
    textPrimary: _Sindur.textPrimary,
    textSecondary: _Sindur.textSecondary,
    textMuted: _Sindur.textMuted,
    divider: _Sindur.divider,
    outlineVariant: _Sindur.outlineVariant,
    outline: _Sindur.outline,
    rule: _Sindur.rule,
    focusRing: _Sindur.focusRing,
    dragHandle: _Sindur.dragHandle,
    success: _Sindur.success,
    warning: _Sindur.warning,
    error: _Sindur.error,
    onError: _Sindur.onError,
    errorContainer: _Sindur.errorContainer,
    onErrorContainer: _Sindur.onErrorContainer,
    liveFill: _Sindur.liveFill,
    onLive: _Sindur.onLive,
    scrim: _Sindur.scrim,
    glass: _Sindur.glass,
    overlay: _Sindur.overlay,
    onOverlay: _Sindur.onOverlay,
    dock: _Sindur.dock,
    onDock: _Sindur.onDock,
    onDockMuted: _Sindur.onDockMuted,
    dockLine: _Sindur.dockLine,
    navIndicator: _Sindur.navIndicator,
    onNavIndicator: _Sindur.onNavIndicator,
    sliderActive: _Sindur.sliderActive,
    sliderInactive: _Sindur.sliderInactive,
    sliderThumb: _Sindur.sliderThumb,
    snackbar: _Sindur.snackbar,
    onSnackbar: _Sindur.onSnackbar,
    snackbarAction: _Sindur.snackbarAction,
    shadow: _Sindur.shadow,
    printShadow: _Sindur.printShadow,
    onTertiary: _Sindur.onTertiary,
    schemeShadow: _Sindur.schemeShadow,
    inverseSurface: _Sindur.inverseSurface,
    onInverseSurface: _Sindur.onInverseSurface,
    inversePrimary: _Sindur.inversePrimary,
    heroGradient: _Sindur.heroGradient,
    primaryGradient: _Sindur.primaryGradient,
    artworkGradients: _Sindur.artworkGradients,
  );

  /// Sindur light: white canvas with blush steps, wine text accent, crimson
  /// fill (ink-edged sticker), purple accent and near-black text.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: _SindurPaper.background,
    surface: _SindurPaper.surface,
    surfaceElevated: _SindurPaper.surfaceElevated,
    surfacePressed: _SindurPaper.surfacePressed,
    primary: _SindurPaper.primary,
    primaryBase: _SindurPaper.primaryBase,
    primaryPressed: _SindurPaper.primaryPressed,
    onPrimary: _SindurPaper.onPrimary,
    primaryContainer: _SindurPaper.primaryContainer,
    onPrimaryContainer: _SindurPaper.onPrimaryContainer,
    secondary: _SindurPaper.secondary,
    onSecondary: _SindurPaper.onSecondary,
    secondaryContainer: _SindurPaper.secondaryContainer,
    onSecondaryContainer: _SindurPaper.onSecondaryContainer,
    voltFill: _SindurPaper.voltFill,
    voltPressed: _SindurPaper.voltPressed,
    onVoltFill: _SindurPaper.onVoltFill,
    onVoltMuted: _SindurPaper.onVoltMuted,
    voltEdge: _SindurPaper.voltEdge,
    voltGlow: _SindurPaper.voltGlow,
    accent: _SindurPaper.accent,
    onAccent: _SindurPaper.onAccent,
    favorite: _SindurPaper.favorite,
    textPrimary: _SindurPaper.textPrimary,
    textSecondary: _SindurPaper.textSecondary,
    textMuted: _SindurPaper.textMuted,
    divider: _SindurPaper.divider,
    outlineVariant: _SindurPaper.outlineVariant,
    outline: _SindurPaper.outline,
    rule: _SindurPaper.rule,
    focusRing: _SindurPaper.focusRing,
    dragHandle: _SindurPaper.dragHandle,
    success: _SindurPaper.success,
    warning: _SindurPaper.warning,
    error: _SindurPaper.error,
    onError: _SindurPaper.onError,
    errorContainer: _SindurPaper.errorContainer,
    onErrorContainer: _SindurPaper.onErrorContainer,
    liveFill: _SindurPaper.liveFill,
    onLive: _SindurPaper.onLive,
    scrim: _SindurPaper.scrim,
    glass: _SindurPaper.glass,
    overlay: _SindurPaper.overlay,
    onOverlay: _SindurPaper.onOverlay,
    dock: _SindurPaper.dock,
    onDock: _SindurPaper.onDock,
    onDockMuted: _SindurPaper.onDockMuted,
    dockLine: _SindurPaper.dockLine,
    navIndicator: _SindurPaper.navIndicator,
    onNavIndicator: _SindurPaper.onNavIndicator,
    sliderActive: _SindurPaper.sliderActive,
    sliderInactive: _SindurPaper.sliderInactive,
    sliderThumb: _SindurPaper.sliderThumb,
    snackbar: _SindurPaper.snackbar,
    onSnackbar: _SindurPaper.onSnackbar,
    snackbarAction: _SindurPaper.snackbarAction,
    shadow: _SindurPaper.shadow,
    printShadow: _SindurPaper.printShadow,
    onTertiary: _SindurPaper.onTertiary,
    schemeShadow: _SindurPaper.schemeShadow,
    inverseSurface: _SindurPaper.inverseSurface,
    onInverseSurface: _SindurPaper.onInverseSurface,
    inversePrimary: _SindurPaper.inversePrimary,
    heroGradient: _SindurPaper.heroGradient,
    primaryGradient: _SindurPaper.primaryGradient,
    artworkGradients: _SindurPaper.artworkGradients,
  );

  /// Bijuli Classic: the original deep ultraviolet ink with Volt lime.
  /// Always dark; chosen in Settings > Appearance.
  static const AppPalette classic = AppPalette(
    brightness: Brightness.dark,
    background: _Ink.background,
    surface: _Ink.surface,
    surfaceElevated: _Ink.surfaceElevated,
    surfacePressed: _Ink.surfacePressed,
    primary: _Ink.primary,
    primaryBase: _Ink.primaryBase,
    primaryPressed: _Ink.primaryPressed,
    onPrimary: _Ink.onPrimary,
    primaryContainer: _Ink.primaryContainer,
    onPrimaryContainer: _Ink.onPrimaryContainer,
    secondary: _Ink.secondary,
    onSecondary: _Ink.onSecondary,
    secondaryContainer: _Ink.secondaryContainer,
    onSecondaryContainer: _Ink.onSecondaryContainer,
    voltFill: _Ink.voltFill,
    voltPressed: _Ink.voltPressed,
    onVoltFill: _Ink.onVoltFill,
    onVoltMuted: _Ink.onVoltMuted,
    voltEdge: _Ink.voltEdge,
    voltGlow: _Ink.voltGlow,
    accent: _Ink.accent,
    onAccent: _Ink.onAccent,
    favorite: _Ink.favorite,
    textPrimary: _Ink.textPrimary,
    textSecondary: _Ink.textSecondary,
    textMuted: _Ink.textMuted,
    divider: _Ink.divider,
    outlineVariant: _Ink.outlineVariant,
    outline: _Ink.outline,
    rule: _Ink.rule,
    focusRing: _Ink.focusRing,
    dragHandle: _Ink.dragHandle,
    success: _Ink.success,
    warning: _Ink.warning,
    error: _Ink.error,
    onError: _Ink.onError,
    errorContainer: _Ink.errorContainer,
    onErrorContainer: _Ink.onErrorContainer,
    liveFill: _Ink.liveFill,
    onLive: _Ink.onLive,
    scrim: _Ink.scrim,
    glass: _Ink.glass,
    overlay: _Ink.overlay,
    onOverlay: _Ink.onOverlay,
    dock: _Ink.dock,
    onDock: _Ink.onDock,
    onDockMuted: _Ink.onDockMuted,
    dockLine: _Ink.dockLine,
    navIndicator: _Ink.navIndicator,
    onNavIndicator: _Ink.onNavIndicator,
    sliderActive: _Ink.sliderActive,
    sliderInactive: _Ink.sliderInactive,
    sliderThumb: _Ink.sliderThumb,
    snackbar: _Ink.snackbar,
    onSnackbar: _Ink.onSnackbar,
    snackbarAction: _Ink.snackbarAction,
    shadow: _Ink.shadow,
    printShadow: _Ink.printShadow,
    onTertiary: _Ink.onTertiary,
    schemeShadow: _Ink.schemeShadow,
    inverseSurface: _Ink.inverseSurface,
    onInverseSurface: _Ink.onInverseSurface,
    inversePrimary: _Ink.inversePrimary,
    heroGradient: _Ink.heroGradient,
    primaryGradient: _Ink.primaryGradient,
    artworkGradients: _Ink.artworkGradients,
  );

  /// The palette for [brightness]: [dark] or [light].
  static AppPalette of(Brightness brightness) => brightness == Brightness.dark ? dark : light;

  /// Whether this is the ink (dark) or the paper (light) palette.
  final Brightness brightness;

  /// True for the ink palette.
  bool get isDark => brightness == Brightness.dark;

  // Canvas and surfaces

  /// Scaffold canvas. In the dark theme also the brand ink.
  final Color background;

  /// Cards, sheets, list groups, search field.
  final Color surface;

  /// Dialogs, menus, chips (dark), input fill, dark snackbar.
  final Color surfaceElevated;

  /// Pressed rows and cards, progress tracks; the floor every text colour is tested on.
  final Color surfacePressed;

  // Brand (scheme roles)

  /// Text and icon accent (Volt on ink, Ultraviolet on paper). Safe as text in both themes.
  final Color primary;

  /// Base for tints: ripple and highlight at 12 %, empty-state halo at 28 %. Never text.
  final Color primaryBase;

  /// Pressed fill for anything filled with [primary].
  final Color primaryPressed;

  /// Label and glyph on [primary] fills.
  final Color onPrimary;

  /// Tonal brand fill: tonal buttons, Downloads type tiles, selected row tint.
  final Color primaryContainer;

  /// Label on [primaryContainer].
  final Color onPrimaryContainer;

  /// The M3 `secondary` slot (= [accent]).
  final Color secondary;

  /// Label on [secondary] fills.
  final Color onSecondary;

  /// Same as [primaryContainer]; `FilledButton.tonal` reads this slot.
  final Color secondaryContainer;

  /// Tonal button label.
  final Color onSecondaryContainer;

  // Volt sticker (brand fills, only through VoltButton, VoltDisc, VoltSlab and the chip theme)

  /// The loud brand fill. Never a text or icon colour on paper (1.05:1).
  final Color voltFill;

  /// Pressed Volt fill.
  final Color voltPressed;

  /// Ink label and glyph on Volt.
  final Color onVoltFill;

  /// Secondary text on Volt (Continue card artist, kicker).
  final Color onVoltMuted;

  /// 1.5 dp outline around every Volt fill on paper; transparent on ink.
  final Color voltEdge;

  /// Volt at 28 %, blur 24, under the 72 dp stage play disc only; none on paper.
  final Color voltGlow;

  // Accent, favourite, text

  /// Ice: video kind, "Downloaded" glyph, info, downloads count dot. Small roles only.
  final Color accent;

  /// On [accent] fills (count dot).
  final Color onAccent;

  /// Hearts only (filled heart = on).
  final Color favorite;

  /// Titles and body text.
  final Color textPrimary;

  /// Metadata, secondary icons, all text on artwork tints and the stage.
  final Color textSecondary;

  /// Captions, hints, durations in rows. Never on artwork tints or the stage.
  final Color textMuted;

  // Lines and focus

  /// Decorative hairlines and 1 dp card edges. Never the only boundary of a control.
  final Color divider;

  /// The M3 `outlineVariant` slot (= [divider]).
  final Color outlineVariant;

  /// Control borders, drag handles, section rules: 3:1 or more on every surface.
  final Color outline;

  /// The 2 dp rule above section kickers (= [outline]).
  final Color rule;

  /// 2 dp keyboard / D-pad focus outline.
  final Color focusRing;

  /// Sheet handle and queue reorder handle.
  final Color dragHandle;

  // States (always with an icon and a word, never colour alone)

  /// Saved / complete.
  final Color success;

  /// Queued, low storage, slow network.
  final Color warning;

  /// Failed, destructive rows, field errors (coral on ink, crimson on paper).
  final Color error;

  /// On [error] fills.
  final Color onError;

  /// Error banners, destructive tonal buttons.
  final Color errorContainer;

  /// Text on [errorContainer].
  final Color onErrorContainer;

  /// Solid LIVE chip.
  final Color liveFill;

  /// "LIVE" label.
  final Color onLive;

  // Scrims, glass and overlays

  /// Behind sheets and dialogs. The stage veil uses the dark value.
  final Color scrim;

  /// Scrolled-under app bars (blur 24); the light YouTube toolbar.
  final Color glass;

  /// Ink at 72 % behind badges on images and video frames.
  final Color overlay;

  /// Text on [overlay] chips.
  final Color onOverlay;

  // Ink Dock (identical in both themes)

  /// Mini player + nav fill (94 %), backdrop blur 24.
  final Color dock;

  /// Dock titles, selected nav label, controls.
  final Color onDock;

  /// Artist line, unselected nav icon and label.
  final Color onDockMuted;

  /// 1 dp top line, mini-player progress track.
  final Color dockLine;

  /// 56x32 selected-tab pill.
  final Color navIndicator;

  /// Filled icon in the pill.
  final Color onNavIndicator;

  // Controls and depth

  /// Active slider track (6 dp).
  final Color sliderActive;

  /// Inactive slider track (4 dp).
  final Color sliderInactive;

  /// 14 dp thumb (20 dp while dragging).
  final Color sliderThumb;

  /// Snackbar and tooltip fill (light: ink, matching the dock).
  final Color snackbar;

  /// Snackbar text.
  final Color onSnackbar;

  /// Snackbar action (both themes sit on a dark fill).
  final Color snackbarAction;

  /// Light only: sheets, dialogs, menus, snackbars (0 8 24). None on ink.
  final Color shadow;

  /// Hard 6x6 dp offset, no blur, under hero and stage covers.
  final Color printShadow;

  // ColorScheme extras (docs/DESIGN.md 2.3)

  /// ColorScheme.onTertiary (label on [favorite]).
  final Color onTertiary;

  /// ColorScheme.shadow.
  final Color schemeShadow;

  /// ColorScheme.inverseSurface.
  final Color inverseSurface;

  /// ColorScheme.onInverseSurface.
  final Color onInverseSurface;

  /// ColorScheme.inversePrimary.
  final Color inversePrimary;

  // Gradients (docs/DESIGN.md section 3; all run topLeft to bottomRight)

  /// Detail headers, the Home top band and the empty-state band.
  final LinearGradient heroGradient;

  /// The subtle Volt sheen of `VoltButton` and `VoltSlab` (same in both
  /// themes). Carries the ink edge on paper.
  final LinearGradient primaryGradient;

  /// Eight cover gradients for items without art, picked by a stable hash of
  /// the item's uri (`ArtworkPlaceholder`). The top-left stop is the same in
  /// both themes, so an item keeps its colour when the phone switches theme;
  /// on paper the deep stop is lifted one step.
  final List<LinearGradient> artworkGradients;

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfacePressed,
    Color? primary,
    Color? primaryBase,
    Color? primaryPressed,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? voltFill,
    Color? voltPressed,
    Color? onVoltFill,
    Color? onVoltMuted,
    Color? voltEdge,
    Color? voltGlow,
    Color? accent,
    Color? onAccent,
    Color? favorite,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? divider,
    Color? outlineVariant,
    Color? outline,
    Color? rule,
    Color? focusRing,
    Color? dragHandle,
    Color? success,
    Color? warning,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? liveFill,
    Color? onLive,
    Color? scrim,
    Color? glass,
    Color? overlay,
    Color? onOverlay,
    Color? dock,
    Color? onDock,
    Color? onDockMuted,
    Color? dockLine,
    Color? navIndicator,
    Color? onNavIndicator,
    Color? sliderActive,
    Color? sliderInactive,
    Color? sliderThumb,
    Color? snackbar,
    Color? onSnackbar,
    Color? snackbarAction,
    Color? shadow,
    Color? printShadow,
    Color? onTertiary,
    Color? schemeShadow,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    LinearGradient? heroGradient,
    LinearGradient? primaryGradient,
    List<LinearGradient>? artworkGradients,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      primary: primary ?? this.primary,
      primaryBase: primaryBase ?? this.primaryBase,
      primaryPressed: primaryPressed ?? this.primaryPressed,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      onSecondaryContainer: onSecondaryContainer ?? this.onSecondaryContainer,
      voltFill: voltFill ?? this.voltFill,
      voltPressed: voltPressed ?? this.voltPressed,
      onVoltFill: onVoltFill ?? this.onVoltFill,
      onVoltMuted: onVoltMuted ?? this.onVoltMuted,
      voltEdge: voltEdge ?? this.voltEdge,
      voltGlow: voltGlow ?? this.voltGlow,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      favorite: favorite ?? this.favorite,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      divider: divider ?? this.divider,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      outline: outline ?? this.outline,
      rule: rule ?? this.rule,
      focusRing: focusRing ?? this.focusRing,
      dragHandle: dragHandle ?? this.dragHandle,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      liveFill: liveFill ?? this.liveFill,
      onLive: onLive ?? this.onLive,
      scrim: scrim ?? this.scrim,
      glass: glass ?? this.glass,
      overlay: overlay ?? this.overlay,
      onOverlay: onOverlay ?? this.onOverlay,
      dock: dock ?? this.dock,
      onDock: onDock ?? this.onDock,
      onDockMuted: onDockMuted ?? this.onDockMuted,
      dockLine: dockLine ?? this.dockLine,
      navIndicator: navIndicator ?? this.navIndicator,
      onNavIndicator: onNavIndicator ?? this.onNavIndicator,
      sliderActive: sliderActive ?? this.sliderActive,
      sliderInactive: sliderInactive ?? this.sliderInactive,
      sliderThumb: sliderThumb ?? this.sliderThumb,
      snackbar: snackbar ?? this.snackbar,
      onSnackbar: onSnackbar ?? this.onSnackbar,
      snackbarAction: snackbarAction ?? this.snackbarAction,
      shadow: shadow ?? this.shadow,
      printShadow: printShadow ?? this.printShadow,
      onTertiary: onTertiary ?? this.onTertiary,
      schemeShadow: schemeShadow ?? this.schemeShadow,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      onInverseSurface: onInverseSurface ?? this.onInverseSurface,
      inversePrimary: inversePrimary ?? this.inversePrimary,
      heroGradient: heroGradient ?? this.heroGradient,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      artworkGradients: artworkGradients ?? this.artworkGradients,
    );
  }

  @override
  AppPalette lerp(covariant ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette || identical(other, this)) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    LinearGradient g(LinearGradient a, LinearGradient b) => LinearGradient.lerp(a, b, t)!;
    final count = artworkGradients.length < other.artworkGradients.length
        ? artworkGradients.length
        : other.artworkGradients.length;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      surfacePressed: c(surfacePressed, other.surfacePressed),
      primary: c(primary, other.primary),
      primaryBase: c(primaryBase, other.primaryBase),
      primaryPressed: c(primaryPressed, other.primaryPressed),
      onPrimary: c(onPrimary, other.onPrimary),
      primaryContainer: c(primaryContainer, other.primaryContainer),
      onPrimaryContainer: c(onPrimaryContainer, other.onPrimaryContainer),
      secondary: c(secondary, other.secondary),
      onSecondary: c(onSecondary, other.onSecondary),
      secondaryContainer: c(secondaryContainer, other.secondaryContainer),
      onSecondaryContainer: c(onSecondaryContainer, other.onSecondaryContainer),
      voltFill: c(voltFill, other.voltFill),
      voltPressed: c(voltPressed, other.voltPressed),
      onVoltFill: c(onVoltFill, other.onVoltFill),
      onVoltMuted: c(onVoltMuted, other.onVoltMuted),
      voltEdge: c(voltEdge, other.voltEdge),
      voltGlow: c(voltGlow, other.voltGlow),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      favorite: c(favorite, other.favorite),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      divider: c(divider, other.divider),
      outlineVariant: c(outlineVariant, other.outlineVariant),
      outline: c(outline, other.outline),
      rule: c(rule, other.rule),
      focusRing: c(focusRing, other.focusRing),
      dragHandle: c(dragHandle, other.dragHandle),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      error: c(error, other.error),
      onError: c(onError, other.onError),
      errorContainer: c(errorContainer, other.errorContainer),
      onErrorContainer: c(onErrorContainer, other.onErrorContainer),
      liveFill: c(liveFill, other.liveFill),
      onLive: c(onLive, other.onLive),
      scrim: c(scrim, other.scrim),
      glass: c(glass, other.glass),
      overlay: c(overlay, other.overlay),
      onOverlay: c(onOverlay, other.onOverlay),
      dock: c(dock, other.dock),
      onDock: c(onDock, other.onDock),
      onDockMuted: c(onDockMuted, other.onDockMuted),
      dockLine: c(dockLine, other.dockLine),
      navIndicator: c(navIndicator, other.navIndicator),
      onNavIndicator: c(onNavIndicator, other.onNavIndicator),
      sliderActive: c(sliderActive, other.sliderActive),
      sliderInactive: c(sliderInactive, other.sliderInactive),
      sliderThumb: c(sliderThumb, other.sliderThumb),
      snackbar: c(snackbar, other.snackbar),
      onSnackbar: c(onSnackbar, other.onSnackbar),
      snackbarAction: c(snackbarAction, other.snackbarAction),
      shadow: c(shadow, other.shadow),
      printShadow: c(printShadow, other.printShadow),
      onTertiary: c(onTertiary, other.onTertiary),
      schemeShadow: c(schemeShadow, other.schemeShadow),
      inverseSurface: c(inverseSurface, other.inverseSurface),
      onInverseSurface: c(onInverseSurface, other.onInverseSurface),
      inversePrimary: c(inversePrimary, other.inversePrimary),
      heroGradient: g(heroGradient, other.heroGradient),
      primaryGradient: g(primaryGradient, other.primaryGradient),
      artworkGradients: [
        for (var i = 0; i < count; i++) g(artworkGradients[i], other.artworkGradients[i]),
      ],
    );
  }
}

/// `context.palette`: the [AppPalette] of the nearest [Theme].
extension PaletteX on BuildContext {
  /// The palette registered in the surrounding theme. Falls back to
  /// [AppPalette.dark] where no app theme is installed (a bare
  /// `Directionality` in a widget test), which is how every screen looked
  /// before the light theme existed.
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

const LinearGradient _primaryGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFDAFF63), Color(0xFFB4EE14)],
);

/// Raw values of [AppPalette.classic], the original Bijuli "Volt on Ink" dark theme.
abstract final class _Ink {
  static const Color background = Color(0xFF180A2E);
  static const Color surface = Color(0xFF22123E);
  static const Color surfaceElevated = Color(0xFF2B1A50);
  static const Color surfacePressed = Color(0xFF382664);
  static const Color primary = Color(0xFFCCFF3A);
  static const Color primaryBase = Color(0xFFB8F000);
  static const Color primaryPressed = Color(0xFFA9DC14);
  static const Color onPrimary = Color(0xFF180A2E);
  static const Color primaryContainer = Color(0xFF33225E);
  static const Color onPrimaryContainer = Color(0xFFD9FF73);
  static const Color secondary = Color(0xFF78C4FF);
  static const Color onSecondary = Color(0xFF180A2E);
  static const Color secondaryContainer = Color(0xFF33225E);
  static const Color onSecondaryContainer = Color(0xFFD9FF73);
  static const Color voltFill = Color(0xFFCCFF3A);
  static const Color voltPressed = Color(0xFFA9DC14);
  static const Color onVoltFill = Color(0xFF180A2E);
  static const Color onVoltMuted = Color(0xFF4A3B66);
  static const Color voltEdge = Color(0x00000000);
  static const Color voltGlow = Color(0x47CCFF3A);
  static const Color accent = Color(0xFF78C4FF);
  static const Color onAccent = Color(0xFF180A2E);
  static const Color favorite = Color(0xFFFF66B8);
  static const Color textPrimary = Color(0xFFF6F2FF);
  static const Color textSecondary = Color(0xFFC6BBDF);
  static const Color textMuted = Color(0xFFA698C4);
  static const Color divider = Color(0xFF382A5C);
  static const Color outlineVariant = Color(0xFF382A5C);
  static const Color outline = Color(0xFF8E7EB4);
  static const Color rule = Color(0xFF8E7EB4);
  static const Color focusRing = Color(0xFFCCFF3A);
  static const Color dragHandle = Color(0xFF8E7EB4);
  static const Color success = Color(0xFF5CF0A8);
  static const Color warning = Color(0xFFFFC44D);
  static const Color error = Color(0xFFFF8A5C);
  static const Color onError = Color(0xFF180A2E);
  static const Color errorContainer = Color(0xFF40192C);
  static const Color onErrorContainer = Color(0xFFFFDCCF);
  static const Color liveFill = Color(0xFFBE1E3E);
  static const Color onLive = Color(0xFFFFFFFF);
  static const Color scrim = Color(0xCC09050F);
  static const Color glass = Color(0xE022123E);
  static const Color overlay = Color(0xB8180A2E);
  static const Color onOverlay = Color(0xFFFFFFFF);
  static const Color dock = Color(0xF01C0E36);
  static const Color onDock = Color(0xFFF6F2FF);
  static const Color onDockMuted = Color(0xFFB4A8CF);
  static const Color dockLine = Color(0xFF3E2E62);
  static const Color navIndicator = Color(0xFFCCFF3A);
  static const Color onNavIndicator = Color(0xFF180A2E);
  static const Color sliderActive = Color(0xFFCCFF3A);
  static const Color sliderInactive = Color(0xFF382664);
  static const Color sliderThumb = Color(0xFFF6F2FF);
  static const Color snackbar = Color(0xFF2B1A50);
  static const Color onSnackbar = Color(0xFFF6F2FF);
  static const Color snackbarAction = Color(0xFFCCFF3A);
  static const Color shadow = Color(0x00000000);
  static const Color printShadow = Color(0xFFCCFF3A);
  static const Color onTertiary = Color(0xFF180A2E);
  static const Color schemeShadow = Color(0xFF000000);
  static const Color inverseSurface = Color(0xFFF6F2FF);
  static const Color onInverseSurface = Color(0xFF180A2E);
  static const Color inversePrimary = Color(0xFF5A32D6);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF421E78), Color(0xFF25133F), Color(0xFF180A2E)],
  );

  static const LinearGradient primaryGradient = _primaryGradient;

  static const List<LinearGradient> artworkGradients = [
    // ultraviolet
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7A4BF0), Color(0xFF240F5C)],
    ),
    // ice
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1C86B0), Color(0xFF0A2848)],
    ),
    // flare
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFC93A8C), Color(0xFF460E38)],
    ),
    // moss
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF567A0C), Color(0xFF192506)],
    ),
    // ember
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFC8502F), Color(0xFF4A1320)],
    ),
    // cobalt
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF4363E0), Color(0xFF131D58)],
    ),
    // orchid
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFA042C4), Color(0xFF33104C)],
    ),
    // jade
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF12806E), Color(0xFF062E2B)],
    ),
  ];
}

/// Raw values of [AppPalette.dark] (docs/DESIGN.md 2.2, "Dark" column).
abstract final class _Sindur {
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0A0A0A);
  static const Color surfaceElevated = Color(0xFF141216);
  static const Color surfacePressed = Color(0xFF1E1A22);
  static const Color primary = Color(0xFFFF7A92);
  static const Color primaryBase = Color(0xFFCC324C);
  static const Color primaryPressed = Color(0xFFE8667E);
  static const Color onPrimary = Color(0xFF000000);
  static const Color primaryContainer = Color(0xFF3D0612);
  static const Color onPrimaryContainer = Color(0xFFF9E8F2);
  static const Color secondary = Color(0xFFAAA6E3);
  static const Color onSecondary = Color(0xFF000000);
  static const Color secondaryContainer = Color(0xFF32396F);
  static const Color onSecondaryContainer = Color(0xFFE7EEFE);
  static const Color voltFill = Color(0xFFCC324C);
  static const Color voltPressed = Color(0xFFB32A42);
  static const Color onVoltFill = Color(0xFFFFF3E6);
  static const Color onVoltMuted = Color(0xFFFFF3E6);
  static const Color voltEdge = Color(0x00000000);
  static const Color voltGlow = Color(0x47CC324C);
  static const Color accent = Color(0xFFAAA6E3);
  static const Color onAccent = Color(0xFF000000);
  static const Color favorite = Color(0xFFFFA0B8);
  static const Color textPrimary = Color(0xFFFFF3E6);
  static const Color textSecondary = Color(0xFFD9CEC4);
  static const Color textMuted = Color(0xFFABA3AD);
  static const Color divider = Color(0xFF26222A);
  static const Color outlineVariant = Color(0xFF26222A);
  static const Color outline = Color(0xFF857F8C);
  static const Color rule = Color(0xFF857F8C);
  static const Color focusRing = Color(0xFFF69E1C);
  static const Color dragHandle = Color(0xFF857F8C);
  static const Color success = Color(0xFF4FD8C4);
  static const Color warning = Color(0xFFF69E1C);
  static const Color error = Color(0xFFFF9466);
  static const Color onError = Color(0xFF000000);
  static const Color errorContainer = Color(0xFF3A1A16);
  static const Color onErrorContainer = Color(0xFFFFDCCF);
  static const Color liveFill = Color(0xFFB3132F);
  static const Color onLive = Color(0xFFFFFFFF);
  static const Color scrim = Color(0xCC000000);
  static const Color glass = Color(0xEB0A0A0A);
  static const Color overlay = Color(0xB8000000);
  static const Color onOverlay = Color(0xFFFFFFFF);
  static const Color dock = Color(0xF00C0A10);
  static const Color onDock = Color(0xFFFFF3E6);
  static const Color onDockMuted = Color(0xFFB7AFBE);
  static const Color dockLine = Color(0xFF2E2638);
  static const Color navIndicator = Color(0xFFF69E1C);
  static const Color onNavIndicator = Color(0xFF000000);
  static const Color sliderActive = Color(0xFFF69E1C);
  static const Color sliderInactive = Color(0xFF2E2836);
  static const Color sliderThumb = Color(0xFFFFF3E6);
  static const Color snackbar = Color(0xFF141216);
  static const Color onSnackbar = Color(0xFFFFF3E6);
  static const Color snackbarAction = Color(0xFFF69E1C);
  static const Color shadow = Color(0x00000000);
  static const Color printShadow = Color(0xFF81021F);
  static const Color onTertiary = Color(0xFF000000);
  static const Color schemeShadow = Color(0xFF000000);
  static const Color inverseSurface = Color(0xFFFFF3E6);
  static const Color onInverseSurface = Color(0xFF000000);
  static const Color inversePrimary = Color(0xFF81021F);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5A0418), Color(0xFF2A1230), Color(0xFF000000)],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFC42A46), Color(0xFFA8203A)],
  );

  static const List<LinearGradient> artworkGradients = [
    // crimson
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFCC324C), Color(0xFF4A0A1A)],
    ),
    // wine
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF9A0A2C), Color(0xFF3A0010)],
    ),
    // lavender
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7A3A6E), Color(0xFF2A0F26)],
    ),
    // navy
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF4A54A8), Color(0xFF161A40)],
    ),
    // amber
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFB5600A), Color(0xFF4A2204)],
    ),
    // graphite
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF55525E), Color(0xFF0A0A0A)],
    ),
    // ocean
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7E6FD0), Color(0xFF241A50)],
    ),
    // rose
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFB0407A), Color(0xFF40102C)],
    ),
  ];
}

/// Raw values of [AppPalette.light] (docs/DESIGN.md 2.2, "Light" column).
abstract final class _SindurPaper {
  static const Color background = Color(0xFFF6EBCF);
  static const Color surface = Color(0xFFFBF4E2);
  static const Color surfaceElevated = Color(0xFFFFFAF0);
  static const Color surfacePressed = Color(0xFFEFE2C2);
  static const Color primary = Color(0xFF81021F);
  static const Color primaryBase = Color(0xFF9E0A2C);
  static const Color primaryPressed = Color(0xFF5E0016);
  static const Color onPrimary = Color(0xFFFFF3E6);
  static const Color primaryContainer = Color(0xFFC6CBE8);
  static const Color onPrimaryContainer = Color(0xFF381932);
  static const Color secondary = Color(0xFF32396F);
  static const Color onSecondary = Color(0xFFFFF3E6);
  static const Color secondaryContainer = Color(0xFFAAA6E3);
  static const Color onSecondaryContainer = Color(0xFF381932);
  static const Color voltFill = Color(0xFF81021F);
  static const Color voltPressed = Color(0xFF5E0016);
  static const Color onVoltFill = Color(0xFFFFF3E6);
  static const Color onVoltMuted = Color(0xFFF9E8F2);
  static const Color voltEdge = Color(0x00000000);
  static const Color voltGlow = Color(0x0081021F);
  static const Color accent = Color(0xFF32396F);
  static const Color onAccent = Color(0xFFFFF3E6);
  static const Color favorite = Color(0xFF9C1458);
  static const Color textPrimary = Color(0xFF381932);
  static const Color textSecondary = Color(0xFF56404F);
  static const Color textMuted = Color(0xFF5E4A58);
  static const Color divider = Color(0xFFE6D7B2);
  static const Color outlineVariant = Color(0xFFE6D7B2);
  static const Color outline = Color(0xFF857565);
  static const Color rule = Color(0xFF857565);
  static const Color focusRing = Color(0xFF81021F);
  static const Color dragHandle = Color(0xFF857565);
  static const Color success = Color(0xFF0A6A40);
  static const Color warning = Color(0xFF5A4F00);
  static const Color error = Color(0xFFA8231C);
  static const Color onError = Color(0xFFFFF3E6);
  static const Color errorContainer = Color(0xFFFCE4DC);
  static const Color onErrorContainer = Color(0xFF5E1608);
  static const Color liveFill = Color(0xFFB3132F);
  static const Color onLive = Color(0xFFFFFFFF);
  static const Color scrim = Color(0x99381932);
  static const Color glass = Color(0xE0FBF4E2);
  static const Color overlay = Color(0xB8000000);
  static const Color onOverlay = Color(0xFFFFFFFF);
  static const Color dock = Color(0xF00C0A10);
  static const Color onDock = Color(0xFFFFF3E6);
  static const Color onDockMuted = Color(0xFFB7AFBE);
  static const Color dockLine = Color(0xFF2E2638);
  static const Color navIndicator = Color(0xFFF69E1C);
  static const Color onNavIndicator = Color(0xFF000000);
  static const Color sliderActive = Color(0xFF81021F);
  static const Color sliderInactive = Color(0xFFE2D2A8);
  static const Color sliderThumb = Color(0xFF81021F);
  static const Color snackbar = Color(0xFF381932);
  static const Color onSnackbar = Color(0xFFFFF3E6);
  static const Color snackbarAction = Color(0xFFF69E1C);
  static const Color shadow = Color(0x1A381932);
  static const Color printShadow = Color(0xFF381932);
  static const Color onTertiary = Color(0xFFFFF3E6);
  static const Color schemeShadow = Color(0xFF381932);
  static const Color inverseSurface = Color(0xFF381932);
  static const Color onInverseSurface = Color(0xFFFFF3E6);
  static const Color inversePrimary = Color(0xFFFF7A92);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC6CBE8), Color(0xFFE7EEFE), Color(0xFFF6EBCF)],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFC42A46), Color(0xFFA8203A)],
  );

  static const List<LinearGradient> artworkGradients = [
    // crimson
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFCC324C), Color(0xFF7A1028)],
    ),
    // wine
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF9A0A2C), Color(0xFF5E0016)],
    ),
    // lavender
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7A3A6E), Color(0xFF4A1A40)],
    ),
    // navy
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF4A54A8), Color(0xFF252C6A)],
    ),
    // amber
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFB5600A), Color(0xFF6E3606)],
    ),
    // graphite
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF55525E), Color(0xFF2C2A32)],
    ),
    // ocean
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7E6FD0), Color(0xFF3E3488)],
    ),
    // rose
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFB0407A), Color(0xFF6A1A48)],
    ),
  ];
}
