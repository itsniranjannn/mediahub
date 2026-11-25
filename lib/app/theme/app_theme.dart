// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// The Sindur themes (docs/DESIGN.md sections 2.3, 7 and 8), both built from
/// an [AppPalette] by one recipe: [darkTheme] (ink) and [lightTheme] (paper).
/// The app follows the phone by default ([themeMode]); Settings → Appearance
/// can pin it to dark, light or Bijuli Classic (`appearanceSettingProvider`).
///
/// Each theme carries its palette as an extension (`context.palette`). The
/// Ink Dock, Now Playing and the video player wrap themselves in
/// `InkTheme.of(context)` ([darkTheme], or [classicTheme] when Bijuli Classic
/// is chosen), so they look the same in both modes.
abstract final class AppTheme {
  /// The default `MaterialApp.themeMode`: the phone's own setting, paper by
  /// day and ink at night (DESIGN.md 8.2). Settings → Appearance overrides it.
  static const ThemeMode themeMode = ThemeMode.system;

  /// System bars over ink: light icons (Android), light content (iOS). The
  /// dark theme's app bars, the Ink Dock, Now Playing and the video player.
  static const SystemUiOverlayStyle barsOnInk = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  /// System bars over paper: dark icons. The light theme's app bars and
  /// full-screen light routes without the dock.
  static const SystemUiOverlayStyle barsOnPaper = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  /// The bar style that suits [palette]'s canvas.
  static SystemUiOverlayStyle barsFor(AppPalette palette) => palette.isDark ? barsOnInk : barsOnPaper;

  /// Sindur dark: crimson and rose on a near-black canvas.
  static ThemeData get darkTheme => _cached(AppPalette.dark);

  /// Sindur light: wine and crimson on white, fills as ink-edged stickers.
  static ThemeData get lightTheme => _cached(AppPalette.light);

  /// Bijuli Classic: the original Volt on ultraviolet ink (always dark).
  static ThemeData get classicTheme => _cached(AppPalette.classic);

  /// [darkTheme] or [lightTheme].
  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? darkTheme : lightTheme;

  // ThemeData captures the target platform when it is built (page
  // transitions, typography), so the cache is per platform: a test that
  // overrides the platform still gets a matching theme.
  // Keyed by palette identity (AppPalette keeps Object's identity ==), so
  // dark and classic, both Brightness.dark, get their own entries.
  static final Map<(AppPalette, TargetPlatform), ThemeData> _cache = {};

  static ThemeData _cached(AppPalette palette) =>
      _cache.putIfAbsent((palette, defaultTargetPlatform), () => build(palette));

  /// Builds a theme from any palette (the two built-in ones are cached by
  /// [darkTheme] and [lightTheme]).
  static ThemeData build(AppPalette p) {
    final dark = p.isDark;
    final t = AppTypography.of(p);
    const stadium = StadiumBorder();

    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primaryContainer,
      onPrimaryContainer: p.onPrimaryContainer,
      secondary: p.accent,
      onSecondary: p.onAccent,
      secondaryContainer: p.secondaryContainer,
      onSecondaryContainer: p.onSecondaryContainer,
      tertiary: p.favorite,
      onTertiary: p.onTertiary,
      error: p.error,
      onError: p.onError,
      errorContainer: p.errorContainer,
      onErrorContainer: p.onErrorContainer,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceElevated,
      surfaceContainerHighest: p.surfaceElevated,
      surfaceTint: Colors.transparent,
      outline: p.outline,
      outlineVariant: p.outlineVariant,
      shadow: p.schemeShadow,
      scrim: p.scrim,
      inverseSurface: p.inverseSurface,
      onInverseSurface: p.onInverseSurface,
      inversePrimary: p.inversePrimary,
    );

    // Depth: tone steps and hairlines on ink; on paper a soft ink shadow
    // under sheets, dialogs, menus and snackbars.
    final double floatingElevation = dark ? 0 : 6;
    final Color floatingShadow = dark ? Colors.transparent : scheme.shadow;

    const minButton = Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget);
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xxl24);
    final radius16 = BorderRadius.circular(AppSpacing.radiusMenu);

    OutlineInputBorder field(BorderSide side) => OutlineInputBorder(borderRadius: radius16, borderSide: side);

    // Press, hover and focus washes of every Material button: the brand base
    // at low strength, so a press reads as crimson on both canvases.
    WidgetStateProperty<Color?> wash(Color base) => WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) return base.withValues(alpha: 0.16);
          if (s.contains(WidgetState.focused)) return base.withValues(alpha: 0.14);
          if (s.contains(WidgetState.hovered)) return base.withValues(alpha: 0.08);
          return null;
        });
    final disabledFill = p.textPrimary.withValues(alpha: 0.12);
    final disabledLabel = p.textPrimary.withValues(alpha: 0.38);

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      extensions: [p],
      fontFamily: AppTypography.defaultFamily,
      fontFamilyFallback: AppTypography.readingFallback,
      textTheme: AppTypography.textTheme(p),
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      cardColor: p.surface,
      dividerColor: p.divider,
      shadowColor: scheme.shadow,
      iconTheme: IconThemeData(color: p.textPrimary),
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: t.screenTitle,
        iconTheme: IconThemeData(color: p.textPrimary),
        actionsIconTheme: IconThemeData(color: p.textSecondary),
        systemOverlayStyle: barsFor(p),
      ),
      dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      // The nav lives in the Ink Dock, which is ink in both themes: the dock
      // draws the fill, the bar stays transparent on top of it.
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        indicatorColor: p.navIndicator,
        indicatorShape: stadium,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        overlayColor: WidgetStatePropertyAll(p.navIndicator.withValues(alpha: 0.12)),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? p.onNavIndicator : p.onDockMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => t.label.copyWith(color: s.contains(WidgetState.selected) ? p.onDock : p.onDockMuted),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        // A hairline on ink; a soft ink shadow (no edge) on paper.
        elevation: dark ? 0 : 2,
        shadowColor: dark ? Colors.transparent : p.schemeShadow.withValues(alpha: 0.18),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: dark ? BorderSide(color: p.divider) : BorderSide.none,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        titleTextStyle: t.bodyStrong,
        subtitleTextStyle: t.metadata,
        selectedColor: p.primary,
        selectedTileColor: p.primaryBase.withValues(alpha: 0.10),
        minVerticalPadding: AppSpacing.sm8,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
        shape: RoundedRectangleBorder(borderRadius: radius16),
      ),
      iconButtonTheme: IconButtonThemeData(
        // Round, with a tonal crimson wash on press; TonalIconButton adds
        // the secondaryContainer disc.
        style: IconButton.styleFrom(
          foregroundColor: p.textPrimary,
          disabledForegroundColor: disabledLabel,
          shape: const CircleBorder(),
        ).copyWith(overlayColor: wash(p.primaryBase)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: disabledFill,
          disabledForegroundColor: disabledLabel,
          elevation: 0,
          textStyle: t.button,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: stadium,
        ),
      ),
      // No colours here: one theme styles both FilledButton (primary /
      // onPrimary) and FilledButton.tonal (secondaryContainer /
      // onSecondaryContainer), and the scheme already gives each its own.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: t.button,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: stadium,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          disabledForegroundColor: disabledLabel,
          textStyle: t.button,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: stadium,
        ).copyWith(
          overlayColor: wash(p.primaryBase),
          // The edge turns brand while pressed or focused.
          side: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return BorderSide(color: p.outline.withValues(alpha: 0.38), width: 1.5);
            if (s.contains(WidgetState.pressed) || s.contains(WidgetState.focused)) {
              return BorderSide(color: p.primary, width: 1.5);
            }
            return BorderSide(color: p.outline, width: 1.5);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          disabledForegroundColor: disabledLabel,
          textStyle: t.button,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md12),
          shape: stadium,
        ).copyWith(overlayColor: wash(p.primaryBase)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? p.surfaceElevated : p.surface,
        hoverColor: p.primaryBase.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: t.body.copyWith(color: p.textMuted),
        labelStyle: t.metadata,
        floatingLabelStyle: t.metadata.copyWith(color: p.primary),
        helperStyle: t.caption,
        errorStyle: t.caption.copyWith(color: p.error),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
        // Filled, radius 16: a hairline on ink, the outline on paper; the
        // focus ring is the brand text colour (rose on ink, wine on paper).
        border: field(BorderSide(color: dark ? p.divider : p.outline)),
        enabledBorder: field(BorderSide(color: dark ? p.divider : p.outline)),
        disabledBorder: field(BorderSide(color: p.divider)),
        focusedBorder: field(BorderSide(color: p.primary, width: 2)),
        errorBorder: field(BorderSide(color: p.error, width: 1.5)),
        focusedErrorBorder: field(BorderSide(color: p.error, width: 2)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primary.withValues(alpha: 0.3),
        selectionHandleColor: p.primary,
      ),
      // Selected = the Volt sticker (ink label and check; the ink edge on
      // paper), so state never depends on colour alone.
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith((s) {
          final disabled = s.contains(WidgetState.disabled);
          if (s.contains(WidgetState.selected)) return disabled ? p.voltFill.withValues(alpha: 0.38) : p.voltFill;
          if (disabled) return p.surfacePressed;
          if (s.contains(WidgetState.pressed)) return p.surfacePressed;
          return dark ? p.surfaceElevated : p.surface;
        }),
        side: WidgetStateBorderSide.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return p.voltEdge.a == 0 ? BorderSide.none : BorderSide(color: p.voltEdge, width: 1.5);
          }
          // Unselected: the surface with an outline (a hairline on ink).
          return BorderSide(color: dark ? p.outlineVariant : p.outline);
        }),
        shape: stadium,
        labelStyle: t.chipLabel.copyWith(
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.onVoltFill : p.textPrimary,
          ),
        ),
        secondaryLabelStyle: t.chipLabel.copyWith(color: p.onVoltFill),
        checkmarkColor: p.onVoltFill,
        showCheckmark: true,
        // 8 + 4 = 12 dp each side (Poppins runs wide); 8 + 20 + 8 = 36 dp
        // tall at 1x text.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        iconTheme: IconThemeData(color: p.textSecondary, size: 18),
        elevation: 0,
        pressElevation: 0,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: p.sliderActive,
        inactiveTrackColor: p.sliderInactive,
        thumbColor: p.sliderThumb,
        overlayColor: p.primary.withValues(alpha: 0.18),
        thumbShape: VoltSliderThumbShape(glowColor: p.voltGlow),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        // Draws the active part 2 dp taller (6 vs 4).
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      // A disabled switch is dimmed to 38 % (M3), so it never looks tappable.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          if (s.contains(WidgetState.disabled)) {
            return selected ? p.onPrimary : p.textMuted.withValues(alpha: 0.38);
          }
          return selected ? p.onPrimary : p.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          if (s.contains(WidgetState.disabled)) {
            return (selected ? p.primary : p.sliderInactive).withValues(alpha: 0.38);
          }
          return selected ? p.primary : p.sliderInactive;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return Colors.transparent;
          return s.contains(WidgetState.disabled) ? p.outline.withValues(alpha: 0.38) : p.outline;
        }),
        trackOutlineWidth: const WidgetStatePropertyAll(1.5),
        thumbIcon: WidgetStateProperty.resolveWith((s) {
          if (!s.contains(WidgetState.selected)) return null;
          final color = s.contains(WidgetState.disabled) ? p.primary.withValues(alpha: 0.38) : p.primary;
          return Icon(Icons.check_rounded, color: color);
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (!s.contains(WidgetState.selected)) return Colors.transparent;
          return s.contains(WidgetState.disabled) ? p.primary.withValues(alpha: 0.38) : p.primary;
        }),
        checkColor: WidgetStatePropertyAll(p.onPrimary),
        overlayColor: wash(p.primaryBase),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: WidgetStateBorderSide.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return BorderSide(color: p.primary, width: 2);
          if (s.contains(WidgetState.disabled)) return BorderSide(color: p.outline.withValues(alpha: 0.38), width: 2);
          return BorderSide(color: p.outline, width: 2);
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          final c = s.contains(WidgetState.selected) ? p.primary : p.outline;
          return s.contains(WidgetState.disabled) ? c.withValues(alpha: 0.38) : c;
        }),
        overlayColor: wash(p.primaryBase),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.surfacePressed,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
        strokeWidth: 3,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.snackbar,
        contentTextStyle: t.body.copyWith(fontSize: 15, height: 20 / 15, color: p.onSnackbar),
        actionTextColor: p.snackbarAction,
        closeIconColor: p.onSnackbar,
        elevation: floatingElevation,
        insetPadding: const EdgeInsets.fromLTRB(AppSpacing.lg16, 0, AppSpacing.lg16, AppSpacing.lg16),
        shape: RoundedRectangleBorder(
          borderRadius: radius16,
          side: dark ? BorderSide(color: p.divider) : BorderSide.none,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.snackbar, borderRadius: BorderRadius.circular(8)),
        textStyle: t.caption.copyWith(color: p.onSnackbar),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: p.scrim,
        elevation: floatingElevation,
        modalElevation: floatingElevation,
        shadowColor: floatingShadow,
        showDragHandle: true,
        dragHandleColor: p.dragHandle,
        dragHandleSize: const Size(36, 4),
        // A hairline along the top on ink, where there is no shadow.
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusSheet)),
          side: dark ? BorderSide(color: p.divider) : BorderSide.none,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: floatingElevation,
        shadowColor: floatingShadow,
        // Material 3 menu items read labelTextStyle (else labelLarge, the
        // bold button role); textStyle stays for Material 2 parity.
        textStyle: t.body,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => t.body.copyWith(
            color: s.contains(WidgetState.disabled) ? p.textPrimary.withValues(alpha: 0.38) : p.textPrimary,
          ),
        ),
        iconColor: p.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: radius16,
          side: BorderSide(color: p.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: floatingElevation,
        shadowColor: floatingShadow,
        barrierColor: p.scrim,
        titleTextStyle: t.sectionTitle,
        contentTextStyle: t.body.copyWith(color: p.textSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSheet),
          side: dark ? BorderSide(color: p.divider) : BorderSide.none,
        ),
      ),
    );
  }
}

/// The slider thumb of docs/DESIGN.md 7.8 / 7.11: a round 14 dp thumb at
/// rest, growing to 20 dp while it is dragged (or focused), in the theme's
/// thumb colour, over a soft [glowColor] halo (the palette's Volt glow: on
/// ink only, transparent on paper).
class VoltSliderThumbShape extends SliderComponentShape {
  const VoltSliderThumbShape({this.radius = 7, this.activeRadius = 10, this.glowColor = Colors.transparent});

  /// Radius at rest and while dragging.
  final double radius;
  final double activeRadius;

  /// Halo under the enabled thumb; nothing is drawn when transparent.
  final Color glowColor;

  /// Blur of the halo.
  static const double glowBlur = 8;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.fromRadius(activeRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    ).evaluate(enableAnimation);
    if (color == null) return;
    final r = lerpDouble(radius, activeRadius, activationAnimation.value)!;
    final glow = Color.lerp(Colors.transparent, glowColor, enableAnimation.value)!;
    if (glow.a > 0) {
      context.canvas.drawCircle(
        center,
        r + 2,
        Paint()
          ..color = glow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, glowBlur / 2),
      );
    }
    context.canvas.drawCircle(center, r, Paint()..color = color);
  }
}
