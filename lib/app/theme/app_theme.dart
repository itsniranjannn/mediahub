import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// The Bijuli themes (docs/DESIGN.md sections 2.3, 7 and 8), both built from
/// an [AppPalette] by one recipe: [darkTheme] (ink) and [lightTheme] (paper).
/// The app follows the phone ([themeMode]) once [lightThemeReady] is on.
///
/// Each theme carries its palette as an extension (`context.palette`). The
/// Ink Dock, Now Playing and the video player wrap themselves in
/// `Theme(data: AppTheme.darkTheme)`, so they look the same in both modes.
abstract final class AppTheme {
  /// Whether every screen reads its colours from `context.palette` /
  /// `context.typography` yet (DESIGN.md 10, step 5). Until then most screens
  /// still paint the dark-only `AppColors`, which would draw near-white text
  /// on paper, so the app stays on ink whatever the phone says. Turning this
  /// on is the last step of the screen migration; nothing else changes.
  static const bool lightThemeReady = false;

  /// The `MaterialApp.themeMode`: the phone's setting (DESIGN.md 8.2) once
  /// [lightThemeReady], ink until then.
  static const ThemeMode themeMode = lightThemeReady ? ThemeMode.system : ThemeMode.dark;

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

  /// Ink: Volt on the deep ultraviolet canvas.
  static ThemeData get darkTheme => _cached(AppPalette.dark);

  /// Paper: Ultraviolet ink on warm ivory, Volt fills as ink-edged stickers.
  static ThemeData get lightTheme => _cached(AppPalette.light);

  /// [darkTheme] or [lightTheme].
  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? darkTheme : lightTheme;

  // ThemeData captures the target platform when it is built (page
  // transitions, typography), so the cache is per platform: a test that
  // overrides the platform still gets a matching theme.
  static final Map<(Brightness, TargetPlatform), ThemeData> _cache = {};

  static ThemeData _cached(AppPalette palette) =>
      _cache.putIfAbsent((palette.brightness, defaultTargetPlatform), () => build(palette));

  /// Builds a theme from any palette (the two built-in ones are cached by
  /// [darkTheme] and [lightTheme]).
  static ThemeData build(AppPalette p) {
    final dark = p.isDark;
    final t = AppTypography.of(p);
    const ink = Color(0xFF180A2E);
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
      onTertiary: dark ? ink : Colors.white,
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
      shadow: dark ? Colors.black : ink,
      scrim: p.scrim,
      inverseSurface: dark ? const Color(0xFFF6F2FF) : ink,
      onInverseSurface: dark ? ink : const Color(0xFFF6F2FF),
      inversePrimary: dark ? const Color(0xFF5A32D6) : const Color(0xFFCCFF3A),
    );

    // Depth: tone steps and hairlines on ink; on paper a soft ink shadow
    // under sheets, dialogs, menus and snackbars.
    final double floatingElevation = dark ? 0 : 6;
    final Color floatingShadow = dark ? Colors.transparent : scheme.shadow;

    const minButton = Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget);
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xxl24);
    final radius16 = BorderRadius.circular(AppSpacing.radiusMenu);

    OutlineInputBorder field(BorderSide side) => OutlineInputBorder(borderRadius: radius16, borderSide: side);

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
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: BorderSide(color: p.divider),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.textPrimary,
          highlightColor: p.primaryBase.withValues(alpha: 0.12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
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
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          textStyle: t.button,
          minimumSize: minButton,
          padding: buttonPadding,
          shape: stadium,
        ).copyWith(
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: s.contains(WidgetState.disabled) ? p.outline.withValues(alpha: 0.38) : p.outline,
              width: 1.5,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          textStyle: t.button,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md12),
          shape: stadium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? p.surfaceElevated : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: t.body.copyWith(color: p.textMuted),
        labelStyle: t.metadata,
        floatingLabelStyle: t.metadata.copyWith(color: p.primary),
        helperStyle: t.caption,
        errorStyle: t.caption.copyWith(color: p.error),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
        border: field(dark ? BorderSide.none : BorderSide(color: p.outline)),
        enabledBorder: field(dark ? BorderSide.none : BorderSide(color: p.outline)),
        disabledBorder: field(dark ? BorderSide.none : BorderSide(color: p.divider)),
        focusedBorder: field(BorderSide(color: p.focusRing, width: 2)),
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
          return dark ? p.surfaceElevated : p.surface;
        }),
        side: WidgetStateBorderSide.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return dark ? BorderSide.none : BorderSide(color: p.voltEdge, width: 1.5);
          }
          return dark ? BorderSide.none : BorderSide(color: p.outline);
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
        // 8 + 6 = 14 dp each side; 8 + 20 + 8 = 36 dp tall at 1x text.
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
        thumbShape: const VoltSliderThumbShape(),
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
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(p.onPrimary),
        side: BorderSide(color: p.outline, width: 2),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primary : p.outline,
        ),
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusSheet)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSheet)),
      ),
    );
  }
}

/// The slider thumb of docs/DESIGN.md 7.8 / 7.11: 14 dp at rest, growing to
/// 20 dp while it is dragged (or focused), in the theme's thumb colour.
class VoltSliderThumbShape extends SliderComponentShape {
  const VoltSliderThumbShape({this.radius = 7, this.activeRadius = 10});

  /// Radius at rest and while dragging.
  final double radius;
  final double activeRadius;

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
    context.canvas.drawCircle(center, r, Paint()..color = color);
  }
}
