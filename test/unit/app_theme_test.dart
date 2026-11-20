// Smoke tests for the Sindur themes and Bijuli Classic (docs/DESIGN.md 2.3, 5, 6, 7 and 8):
// both build from their palette, the type roles use the right families, and
// the component themes carry the rules the spec calls out.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_palette.dart';
import 'package:mediahub/app/theme/app_spacing.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/app/theme/app_typography.dart';
import 'package:mediahub/app/theme/ink_theme.dart';

void main() {
  final themes = {
    'dark': (AppPalette.dark, AppTheme.darkTheme),
    'light': (AppPalette.light, AppTheme.lightTheme),
    'classic': (AppPalette.classic, AppTheme.classicTheme),
  };

  for (final MapEntry(key: name, value: (p, theme)) in themes.entries) {
    group('$name theme', () {
      test('is built from its palette and registers it as an extension', () {
        expect(theme.brightness, p.brightness);
        expect(theme.useMaterial3, isTrue);
        expect(theme.extension<AppPalette>(), same(p));
        expect(theme.scaffoldBackgroundColor, p.background);
        if (!identical(p, AppPalette.classic)) expect(AppTheme.of(p.brightness), same(theme), reason: 'cached');
        expect(AppTheme.build(p), isNot(same(theme)));
      });

      test('ColorScheme follows docs/DESIGN.md 2.3', () {
        final s = theme.colorScheme;
        expect(s.brightness, p.brightness);
        expect(s.primary, p.primary);
        expect(s.onPrimary, p.onPrimary);
        expect(s.primaryContainer, p.primaryContainer);
        expect(s.onPrimaryContainer, p.onPrimaryContainer);
        expect(s.secondary, p.accent);
        expect(s.onSecondary, p.onAccent);
        expect(s.secondaryContainer, p.secondaryContainer);
        expect(s.onSecondaryContainer, p.onSecondaryContainer);
        expect(s.tertiary, p.favorite);
        expect(s.onTertiary, p.onTertiary);
        expect(s.error, p.error);
        expect(s.onError, p.onError);
        expect(s.errorContainer, p.errorContainer);
        expect(s.onErrorContainer, p.onErrorContainer);
        expect(s.surface, p.surface);
        expect(s.onSurface, p.textPrimary);
        expect(s.onSurfaceVariant, p.textSecondary);
        expect(s.surfaceContainerLowest, p.background);
        expect(s.surfaceContainerLow, p.surface);
        expect(s.surfaceContainer, p.surface);
        expect(s.surfaceContainerHigh, p.surfaceElevated);
        expect(s.surfaceContainerHighest, p.surfaceElevated);
        expect(s.surfaceTint, Colors.transparent);
        expect(s.outline, p.outline);
        expect(s.outlineVariant, p.outlineVariant);
        expect(s.shadow, p.schemeShadow);
        expect(s.scrim, p.scrim);
        expect(s.inverseSurface, p.inverseSurface);
        expect(s.onInverseSurface, p.onInverseSurface);
        expect(s.inversePrimary, p.inversePrimary);
      });

      test('text roles use the three voices with even leading and Devanagari fallbacks', () {
        final t = theme.textTheme;
        expect(t.displaySmall!.fontFamily, 'Fraunces');
        expect(t.titleLarge!.fontFamily, 'Fraunces');
        expect(t.displaySmall!.fontFamilyFallback, ['Poppins']);
        for (final style in [t.headlineLarge!, t.headlineMedium!, t.headlineSmall!, t.titleMedium!]) {
          expect(style.fontFamily, 'Poppins');
          expect(style.letterSpacing, 0, reason: 'user content: no tracking');
        }
        for (final style in [t.bodyLarge!, t.bodyMedium!, t.bodySmall!, t.titleSmall!, t.labelLarge!, t.labelMedium!]) {
          expect(style.fontFamily, 'Poppins', reason: 'Poppins draws Devanagari itself');
          expect(style.fontFamilyFallback, isEmpty);
        }
        expect(t.labelSmall!.fontFamily, 'DMMono', reason: 'overline');
        expect(t.bodyLarge!.fontSize, 16);
        expect(t.bodyMedium!.fontSize, 14);
        expect(t.bodySmall!.fontSize, 12);
        expect(t.bodyLarge!.color, p.textPrimary);
        expect(t.bodyMedium!.color, p.textSecondary);
        expect(t.bodySmall!.color, p.textMuted);
        expect(theme.textTheme.bodyLarge!.leadingDistribution, TextLeadingDistribution.even);
      });

      test('filledButtonTheme has no colours; every button is a stadium', () {
        final filled = theme.filledButtonTheme.style!;
        expect(filled.backgroundColor, isNull);
        expect(filled.foregroundColor, isNull);
        for (final style in [
          filled,
          theme.outlinedButtonTheme.style!,
          theme.textButtonTheme.style!,
          theme.elevatedButtonTheme.style!,
        ]) {
          expect(style.shape!.resolve({}), isA<StadiumBorder>());
        }
        final side = theme.outlinedButtonTheme.style!.side!.resolve({})!;
        expect(side.color, p.outline);
        expect(side.width, 1.5);
        expect(theme.textButtonTheme.style!.foregroundColor!.resolve({}), p.primary);
      });

      test('selected chips are the Volt sticker with an ink label and check', () {
        final chip = theme.chipTheme;
        const selected = {WidgetState.selected};
        expect(chip.color!.resolve(selected), p.voltFill);
        expect(chip.color!.resolve({}), p.isDark ? p.surfaceElevated : p.surface);
        expect(chip.showCheckmark, isTrue);
        expect(chip.checkmarkColor, p.onVoltFill);
        expect(WidgetStateProperty.resolveAs<Color?>(chip.labelStyle!.color, selected), p.onVoltFill);
        expect(WidgetStateProperty.resolveAs<Color?>(chip.labelStyle!.color, {}), p.textPrimary);
        expect(chip.labelStyle!.fontFamily, 'Poppins');
        final selectedSide = WidgetStateProperty.resolveAs<BorderSide?>(chip.side, selected)!;
        final idleSide = WidgetStateProperty.resolveAs<BorderSide?>(chip.side, {})!;
        // Sindur v2: the wine fill stands out on sand by itself, so no edge in either theme.
        expect(selectedSide, BorderSide.none);
        expect(idleSide.color, p.isDark ? p.outlineVariant : p.outline);
      });

      test('nav bar (inside the ink dock), slider, switch and progress', () {
        final nav = theme.navigationBarTheme;
        expect(nav.backgroundColor, Colors.transparent);
        expect(nav.indicatorColor, p.navIndicator);
        expect(nav.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
        expect(nav.iconTheme!.resolve({WidgetState.selected})!.color, p.onNavIndicator);
        expect(nav.iconTheme!.resolve({})!.color, p.onDockMuted);

        final slider = theme.sliderTheme;
        expect(slider.activeTrackColor, p.sliderActive);
        expect(slider.inactiveTrackColor, p.sliderInactive);
        expect(slider.thumbColor, p.sliderThumb);
        expect(slider.trackHeight, 4);
        expect(slider.thumbShape, isA<VoltSliderThumbShape>());
        expect(slider.thumbShape!.getPreferredSize(true, false), const Size(20, 20));

        final sw = theme.switchTheme;
        const on = {WidgetState.selected};
        expect(sw.trackColor!.resolve(on), p.primary);
        expect(sw.thumbColor!.resolve(on), p.onPrimary);
        expect(sw.thumbIcon!.resolve(on)!.icon, Icons.check_rounded);
        expect(sw.trackColor!.resolve({}), p.sliderInactive);
        expect(sw.trackOutlineColor!.resolve({}), p.outline);

        // Disabled switches and chips are dimmed, so they never look tappable.
        const onDisabled = {WidgetState.selected, WidgetState.disabled};
        const offDisabled = {WidgetState.disabled};
        expect(sw.trackColor!.resolve(onDisabled), isNot(sw.trackColor!.resolve(on)));
        expect(sw.trackColor!.resolve(onDisabled)!.a, closeTo(0.38, 0.01));
        expect(sw.trackColor!.resolve(offDisabled)!.a, closeTo(0.38, 0.01));
        expect(sw.thumbColor!.resolve(offDisabled), isNot(sw.thumbColor!.resolve({})));
        expect(sw.trackOutlineColor!.resolve(offDisabled)!.a, closeTo(0.38, 0.01));
        expect(sw.thumbIcon!.resolve(onDisabled)!.color!.a, closeTo(0.38, 0.01));
        expect(theme.chipTheme.color!.resolve(onDisabled)!.a, closeTo(0.38, 0.01));

        expect(theme.progressIndicatorTheme.color, p.primary);
        expect(theme.progressIndicatorTheme.linearTrackColor, p.surfacePressed);
      });

      test('snackbar, sheet, menu, dialog and input', () {
        final snack = theme.snackBarTheme;
        expect(snack.behavior, SnackBarBehavior.floating);
        expect(snack.backgroundColor, p.snackbar);
        expect(snack.actionTextColor, p.snackbarAction);
        expect(snack.contentTextStyle!.color, p.onSnackbar);
        expect((snack.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(16));

        final sheet = theme.bottomSheetTheme;
        expect(sheet.backgroundColor, p.surface);
        expect(sheet.showDragHandle, isTrue);
        expect(sheet.dragHandleColor, p.dragHandle);
        expect(sheet.dragHandleSize, const Size(36, 4));
        expect(sheet.modalBarrierColor, p.scrim);

        final menu = theme.popupMenuTheme;
        expect(menu.color, p.surfaceElevated);
        expect((menu.shape! as RoundedRectangleBorder).side.color, p.outlineVariant);
        // Material 3 menu items read labelTextStyle: body, not the bold button role.
        final item = menu.labelTextStyle!.resolve({})!;
        expect(item.fontSize, AppTypography.of(p).body.fontSize);
        expect(item.fontWeight, AppTypography.of(p).body.fontWeight);
        expect(item.color, p.textPrimary);
        expect(menu.labelTextStyle!.resolve({WidgetState.disabled})!.color!.a, closeTo(0.38, 0.01));

        final dialog = theme.dialogTheme;
        expect(dialog.backgroundColor, p.surfaceElevated);
        expect((dialog.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(AppSpacing.radiusSheet));
        expect(dialog.titleTextStyle!.fontFamily, 'Fraunces');
        expect(dialog.contentTextStyle!.color, p.textSecondary);

        // Depth: no shadows on ink, a soft ink shadow on paper.
        expect(snack.elevation, p.isDark ? 0 : greaterThan(0));
        expect(dialog.elevation, p.isDark ? 0 : greaterThan(0));

        final input = theme.inputDecorationTheme;
        expect(input.fillColor, p.isDark ? p.surfaceElevated : p.surface);
        expect((input.focusedBorder! as OutlineInputBorder).borderRadius, BorderRadius.circular(16));
        expect((input.focusedBorder! as OutlineInputBorder).borderSide.color, p.primary, reason: 'rose / wine ring');
        expect((input.focusedBorder! as OutlineInputBorder).borderSide.width, 2);
        expect((input.enabledBorder! as OutlineInputBorder).borderSide,
            BorderSide(color: p.isDark ? p.divider : p.outline));
      });

      test('app bars set the system bar style of their canvas', () {
        final style = theme.appBarTheme.systemOverlayStyle!;
        expect(style, p.isDark ? AppTheme.barsOnInk : AppTheme.barsOnPaper);
        expect(style.statusBarColor, Colors.transparent);
        expect(style.systemNavigationBarColor, Colors.transparent);
        expect(style.systemNavigationBarContrastEnforced, isFalse);
        expect(style.statusBarIconBrightness, p.isDark ? Brightness.light : Brightness.dark);
        expect(style.statusBarBrightness, p.isDark ? Brightness.dark : Brightness.light);
        expect(theme.appBarTheme.titleTextStyle!.fontFamily, 'Poppins');
      });
    });
  }

  group('AppTypography', () {
    test('section 6 roles: family, size / line, weight, tracking', () {
      final s = AppTypography.of(AppPalette.dark);
      void role(TextStyle style, String family, double size, double line, FontWeight weight, double tracking) {
        expect(style.fontFamily, family);
        expect(style.fontSize, size);
        expect(style.height! * size, closeTo(line, 0.01));
        expect(style.fontWeight, weight);
        expect(style.letterSpacing, tracking);
        expect(style.leadingDistribution, TextLeadingDistribution.even);
      }

      role(s.display, 'Fraunces', 32, 40, FontWeight.w700, -0.5);
      role(s.greeting, 'Poppins', 30, 42, FontWeight.w700, 0);
      role(s.screenTitle, 'Poppins', 24, 34, FontWeight.w700, 0);
      role(s.playerTitle, 'Poppins', 22, 30, FontWeight.w600, 0);
      role(s.cardTitle, 'Poppins', 20, 28, FontWeight.w700, 0);
      role(s.sectionTitle, 'Fraunces', 18, 26, FontWeight.w600, 0);
      role(s.body, 'Poppins', 16, 24, FontWeight.w400, 0);
      role(s.bodyStrong, 'Poppins', 16, 24, FontWeight.w600, 0);
      role(s.metadata, 'Poppins', 14, 20, FontWeight.w400, 0);
      role(s.label, 'Poppins', 12, 16, FontWeight.w600, 0.2);
      role(s.chipLabel, 'Poppins', 14, 20, FontWeight.w600, 0);
      role(s.button, 'Poppins', 15, 20, FontWeight.w600, 0);
      role(s.caption, 'Poppins', 12, 16, FontWeight.w400, 0);
      role(s.tabularFigures, 'DMMono', 13, 18, FontWeight.w500, 0);
      role(s.index, 'DMMono', 13, 18, FontWeight.w500, 0);
      role(s.overline, 'DMMono', 11, 16, FontWeight.w500, 1.1);
      role(s.badge, 'DMMono', 12, 16, FontWeight.w500, 0.2);
      role(s.figureLarge, 'DMMono', 28, 32, FontWeight.w500, -0.5);

      expect(s.display.fontFamilyFallback, ['Poppins']);
      expect(s.screenTitle.fontFamilyFallback, isEmpty);
      expect(s.body.fontFamilyFallback, isEmpty);
      expect(s.tabularFigures.fontFamilyFallback, ['Poppins']);
      expect(s.tabularFigures.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(s.button.color, isNull, reason: 'the button gives the colour');
    });

    test('colours come from the palette', () {
      final dark = AppTypography.of(AppPalette.dark);
      final light = AppTypography.of(AppPalette.light);
      expect(AppTypography.of(AppPalette.dark), same(dark), reason: 'cached');
      expect(light.body.color, AppPalette.light.textPrimary);
      expect(light.metadata.color, AppPalette.light.textSecondary);
      expect(light.caption.color, AppPalette.light.textMuted);
      expect(light.badge.color, AppPalette.light.onOverlay);
      expect(dark.body.color, AppPalette.dark.textPrimary);
      expect(AppTypography.textTheme(AppPalette.light).bodyLarge, same(light.body));
      // A palette mid-way through a theme change builds its own styles.
      final mid = AppPalette.dark.lerp(AppPalette.light, 0.5);
      expect(AppTypography.of(mid).body.color, mid.textPrimary);
    });
  });

  testWidgets('context.palette reads the theme, and falls back to the ink palette', (tester) async {
    late AppPalette inLight;
    late AppPalette bare;
    late AppTextStyles type;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Builder(builder: (context) {
              bare = context.palette;
              return const SizedBox();
            }),
            Theme(
              data: AppTheme.lightTheme,
              child: Builder(builder: (context) {
                inLight = context.palette;
                type = context.typography;
                return const SizedBox();
              }),
            ),
          ],
        ),
      ),
    );
    expect(bare, same(AppPalette.dark));
    expect(inLight, same(AppPalette.light));
    expect(type.body.color, AppPalette.light.textPrimary);
  });

  test('the theme cache follows the target platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(AppTheme.darkTheme.platform, TargetPlatform.iOS);
    debugDefaultTargetPlatformOverride = null;
    expect(AppTheme.darkTheme.platform, TargetPlatform.android);
  });

  test('scheme extras: Bijuli Classic keeps the old hard-coded ink values', () {
    const c = AppPalette.classic;
    expect(c.onTertiary, const Color(0xFF180A2E));
    expect(c.schemeShadow, const Color(0xFF000000));
    expect(c.inverseSurface, const Color(0xFFF6F2FF));
    expect(c.onInverseSurface, const Color(0xFF180A2E));
    expect(c.inversePrimary, const Color(0xFF5A32D6));
    expect(c.background, const Color(0xFF180A2E));
    expect(c.voltFill, const Color(0xFFCCFF3A));
    expect(c.primaryGradient.colors, const [Color(0xFFDAFF63), Color(0xFFB4EE14)]);
    expect(c.isDark, isTrue);
    expect(AppPalette.dark.inversePrimary, AppPalette.light.primary);
  });

  test('the theme cache is keyed by palette: dark and classic are separate', () {
    expect(AppTheme.classicTheme, same(AppTheme.classicTheme));
    expect(AppTheme.classicTheme, isNot(same(AppTheme.darkTheme)));
    expect(AppTheme.classicTheme.extension<AppPalette>(), same(AppPalette.classic));
    expect(AppTypography.of(AppPalette.classic), same(AppTypography.of(AppPalette.classic)));
    expect(AppTypography.of(AppPalette.classic).body.color, AppPalette.classic.textPrimary);
  });

  testWidgets('InkTheme.of falls back to the Sindur dark theme', (tester) async {
    late ThemeData bare;
    late ThemeData inClassic;
    await tester.pumpWidget(Column(children: [
      Builder(builder: (context) {
        bare = InkTheme.of(context);
        return const SizedBox();
      }),
      InkTheme(
        data: AppTheme.classicTheme,
        child: Builder(builder: (context) {
          inClassic = InkTheme.of(context);
          expect(InkTheme.paletteOf(context), same(AppPalette.classic));
          return const SizedBox();
        }),
      ),
    ]));
    expect(bare, same(AppTheme.darkTheme));
    expect(inClassic, same(AppTheme.classicTheme));
  });

  test('by default the app follows the phone (DESIGN.md 8.2)', () {
    expect(AppTheme.themeMode, ThemeMode.system);
  });

  test('barsFor picks ink or paper bars', () {
    expect(AppTheme.barsFor(AppPalette.dark), AppTheme.barsOnInk);
    expect(AppTheme.barsFor(AppPalette.light), AppTheme.barsOnPaper);
    expect(AppTheme.barsOnInk.systemNavigationBarIconBrightness, Brightness.light);
    expect(AppTheme.barsOnPaper.systemNavigationBarIconBrightness, Brightness.dark);
  });
}
