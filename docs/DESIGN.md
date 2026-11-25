# MediaHub design system: "Sindur"

Status: final spec for the full redesign (Android + iOS, dark + light, theme follows the phone).
Written 2026-11-17. Replaces "Midnight Violet" (`AppColors` near-black blue + violet + teal, Inter everywhere).

Rebrand 2026-11-20: the default dark and light themes are now **Sindur** (crimson, wine and lavender on near-black
and on white). The original "Bijuli · Volt on Ink" dark theme lives on as the optional **Bijuli Classic** (Settings →
Appearance); its values are `AppPalette.classic`. Widget and token names keep the Volt / Ink Dock words: "Volt" means
the brand sticker fill, crimson in Sindur and lime in Bijuli Classic. Sections 5-9 describe the Sindur fonts and
components (Fraunces, Poppins, DM Mono; crimson glows on ink, soft shadows on paper).

**Sindur v2 (2026-11-20, later the same day).** Palette and pages revised for a more distinctive look:

- Dark: true black canvas (`#000000`, surfaces `#0A0A0A` / `#141216` / `#1E1A22`), dark red as the brand (wine
  `#81021F` in the hero and print shadow, crimson `#CC324C` as the loud fill), dark purple as the second voice (plum
  `#381932` and indigo `#32396F`: hero, tonal containers, dock tint), **amber `#F69E1C` as the spark** (selected nav
  pill, sliders and progress, focus ring, resume lines, section marks), milk `#FFF3E6` text, blush / periwinkle tints.
  `primary` as text is a lighter crimson step, `#FF7A92` (raw crimson is 4.0:1 on black, under the 4.5 floor).
- Light: sand canvas `#F6EBCF` (surfaces `#FBF4E2`, `#FFFAF0`, pressed `#EFE2C2`), wine `#81021F` as primary and as
  the brand fill with milk labels, lavender `#AAA6E3` / periwinkle `#C6CBE8` / `#E7EEFE` for containers and the hero,
  plum `#381932` ink and indigo `#32396F` accent. Derived steps (raw colours failed as text): textSecondary
  `#56404F`, textMuted `#5E4A58`, success `#0A6A40`, warning `#5A4F00`, error `#A8231C`, favourite `#9C1458` (dark:
  `#FFA0B8`, moved off pink so it stays 6+ CIEDE2000 from lavender under protan vision).
- No ink edge on paper any more (`voltEdge` none in both): the wine fill clears 3:1 on sand by itself, and no single
  edge colour could reach 3:1 against both sand and wine. The sheen (`primaryGradient`) is `#C42A46 → #A8203A`,
  dark enough for milk labels (5.1:1).
- Pages: Home, Videos and Downloads redesigned (sections 7.18-7.20). The checker that produced the values is
  re-implemented from `palette_contrast_test` / `card_contrast_test`: 490 pairs, 0 below their floor.

The old HTML specimen (`docs/design-specimen.html`, still the Bijuli look) was removed on 2026-11-25; the
current screens in both themes come from `tools/design_previews/preview_test.dart`.

---

## Sindur notes (2026-11-20)

- Ink Dock: always an opaque fill behind its 24 dp top corners (page colour; dock colour on Online, so it reads
  square there). Nav labels follow text size up to 1.3x, then shrink together; icons only as a last resort.
- Home bento: `VoltTile` shine (diagonal, 14% onVoltFill, 1.4 s every 6 s, none with reduced motion), press 0.97,
  `PressGlyph` (-0.03 turn, 1.12 scale) on press; small tiles glow in their icon colour on ink only.
- Settings rows: 32 dp icon slot, 13/18 subtitles, 48 dp minimum.
- Settings (2026-11-25): the top level is two cards of small group rows (Appearance, Playback & audio, Downloads,
  Online | Privacy & security, Backup, About), each opening its own page; then the footer strip: launch-screen logo
  (`assets/brand/mediahub_mark.png`) and the Fraunces wordmark ("Hub" in primary) on one side, the author from
  `CoreWatermark.fullName` in spaced DM Mono capitals on the other, and a small "Open-source licences" link.
  Home's byline uses the same pair. Pickers use `showChoiceDialog`, destructive confirms `confirmDestructive`
  (`lib/shared/widgets/choice_dialogs.dart`).
- Quality sheet: segmented Video | Audio at the top.
- Notification placeholder: #4A0A1A to #2A0F26 field, #CC324C to #E89A2C note.

## 0. Decision record

Three directions were scored by three judges (brand distinctiveness, accessibility, Flutter feasibility):

| Direction | Brand | Accessibility | Flutter | Total |
|---|---|---|---|---|
| **electric-ink: "Bijuli: Volt on Ink"** | 8.5 | 8 | 6 | **22.5** (winner) |
| editorial-contrast: "Lokta Press" (cobalt slabs, Eczar) | 7.5 | 6 | 8 | 21.5 |
| himalayan-bold: "Temple Night / Lokta Day" (marigold, Eczar) | 6.5 | 7 | 7 | 20.5 |

Bijuli won on the top total and two of three judges' first place. It is the most recognisable on a home screen (no media
app owns lime at hue 75), it has the clearest three-voice type hierarchy, and its "Ink Dock" keeps playback identical in
both themes. Its weak spots (fragile Volt-on-paper, Moss olive in light, Devanagari titles falling back mid-heading,
pink error next to pink favourite, Latin-only display face) are fixed below. What changed against the proposal:

1. **Canvas made visibly violet.** `#150A24` measured as dark as Spotify's `#121212` at icon size. The ink is now
   `#180A2E` (OKLCH chroma 0.069, was 0.052) with re-stepped surfaces, and the app icon sits on the ultraviolet `#421E78`.
2. **Light `primary` is Ultraviolet ink `#5A32D6`, not Moss `#4A6A00`.** Moss collapsed against warning (deuteranopia
   dE2000 3.0) and error (7.1), sat next to the success green, and read drab. Ultraviolet: dE 61.7 against warning and 54.9 against error
   under deuteranopia, 7.34:1 with white, and it ties the light theme to the dark theme's violet. Volt stays the brand
   fill in both themes.
3. **Dark `error` is coral `#FF8A5C`.** The proposal's `#FF6B84` was the same pink as favourite `#FF66B8` (dE 13.1, luminance
   ratio 1.02) and they sit in adjacent sheet rows. Now dE 32.3.
4. **Ice nudged** `#6BD0FF → #78C4FF` (Amazon Music cyan distance 7.1 → 8.9) and kept to small roles. Light accent
   `#006496 → #00658A` for better separation from the Ultraviolet primary.
5. **Nepali-safe titles.** Everything a song, video, album, artist or person is called is set in **Anek Devanagari Wide**,
   which draws Latin and Devanagari natively. Unbounded (Latin only) is used only for strings the app itself writes.
   `letterSpacing` is 0 on every style that can carry user content.
6. **Volt is contained.** It reaches the screen only through three `ui_kit` widgets plus the chip theme, and the light
   theme always draws the 1.5dp ink edge. Contract tests enforce both. `filledButtonTheme` stays colourless so tonal
   buttons keep their own fill.
7. **Grafts from the other two directions:** hard "print offset" under hero and Now Playing covers, kicker + rule section
   headers, mono track numbers, a Volt "Continue listening" slab, a Nepali greeting on Home, item tints for cover-less
   items, explicit Picture-in-picture / Background play controls in the YouTube toolbar, the light `ArtworkTint` recipe,
   glass and dock contrast tested over a white and a black page, and an active/inactive slider height step.
8. **Corrected figures.** The proposal's "Ice glyph on the overlay over a white frame 5.07" was really 4.54. With the
   new Ice and ink it measures 4.12 (floor 3).

---

## 1. Name and concept

**Sindur (सिन्दूर)**, the crimson-vermilion powder of Nepali tika and weddings. Crimson `#CC324C` is the brand fill
(the "Volt" sticker role: Play all, play discs, Download, selected chip) on a near-black canvas `#0B0B0D` stepping up to
`#222226`. Text is milk `#FFF3E6`, the reading accent is a crimson tint (rose `#FF6E86`), lavender `#B98FFF` is the
second accent and blush `#F9E8F2` the light tint. Amber `#F69E1C` is only a small spark (warning, snackbar action).
In the light theme the canvas is white `#FFFFFF` with blush steps, text is near-black `#121214`, the reading accent is
wine `#81021F` and the crimson fill becomes an ink-edged **sticker**. The **Ink Dock** (mini player + bottom navigation)
and the playback **stage** (Now Playing, video player) use the dark palette in both themes.

**Bijuli Classic** keeps the original Volt lime `#CCFF3A` on ultraviolet ink `#180A2E` as a third, always-dark choice;
while it is chosen the dock and the stage use it too (`InkTheme`). Type has four voices with clear jobs:

- **Unbounded**, wide and poster-like, writes the app's own headings.
- **Anek Devanagari Wide** writes every name of a thing (रेशम फिरिरी and "Audit_Long_Tone_5min" in the same voice).
- **Atkinson Hyperlegible Next**, drawn for low-vision readers, sets every line people read, with **Mukta** for Nepali.
- **DM Mono** sets times, sizes and small instrument-style kickers.

The result is built for kids through grandparents.

---

## 2. Colour tokens

### 2.1 How the code carries them

Today `AppColors` is static `const` (394 call sites). Replace it with a `ThemeExtension`:

```dart
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.background, /* ...every role in 2.2... */});
  static const dark = AppPalette(background: Color(0xFF180A2E), /* ... */);
  static const light = AppPalette(background: Color(0xFFF7F2E8), /* ... */);
  final Color background; // ...
  final LinearGradient heroGradient, primaryGradient;
  final List<LinearGradient> artworkGradients;
  @override AppPalette copyWith({...});
  @override AppPalette lerp(AppPalette? other, double t); // Color.lerp per field, Gradient.lerp per gradient
}

extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
```

- Migration: `AppColors.x` becomes `context.palette.x`. Drop `const` where a palette value is used. During the move,
  keep `AppColors` as a deprecated alias of `AppPalette.dark` so the app keeps compiling screen by screen.
- `AppPalette.primary` is always safe as text and icon colour in both themes (Volt on ink, Ultraviolet on paper). The
  89 existing `AppColors.primary` call sites can therefore be migrated mechanically, and stay readable in light without
  hand classification. Only brand fills move to `voltFill`, through the `ui_kit` widgets in section 7.
- Ink Dock, Now Playing and the video player wrap themselves in `Theme(data: InkTheme.of(context), child: ...)`, so
  `context.palette` inside them is always a dark palette: `AppPalette.dark`, or `AppPalette.classic` while Bijuli
  Classic is chosen (`MediaHubApp` installs the `InkTheme` above the router).

### 2.2 Token table

`#AARRGGBB` = alpha first, as Flutter's `Color(0xAARRGGBB)`. "Same" = identical value in both themes.

**Canvas and surfaces**

| Role | Dark | Light | Use |
|---|---|---|---|
| background | `#000000` | `#F6EBCF` | Scaffold canvas (dark: true black; light: sand). |
| surface | `#0A0A0A` | `#FBF4E2` | Cards, sheets, list groups, search field (light: lighter sand). |
| surfaceElevated | `#141216` | `#FFFAF0` | Dialogs, menus, chips (dark), input fill, dark snackbar. |
| surfacePressed | `#1E1A22` | `#EFE2C2` | Pressed rows/cards, progress tracks, the floor every text colour is tested on. |

**Brand (scheme roles)**

| Role | Dark | Light | Use |
|---|---|---|---|
| primary | `#FF7A92` | `#81021F` | Text/icon accent: links, "See all", active toggles, now-playing title and bar, slider, progress, focus, FilledButton fill. Safe as text in both. |
| primaryBase | `#CC324C` | `#9E0A2C` | Base for tints: ripple/highlight at 12%, empty-state halo at 28%. Never text. |
| primaryPressed | `#E8667E` | `#5E0016` | Pressed fill for anything filled with `primary`. |
| onPrimary | `#000000` | `#FFF3E6` | Label/glyph on `primary` fills. |
| primaryContainer | `#3D0612` | `#C6CBE8` | Tonal brand fill: tonal buttons, Downloads type tiles, selected list row tint. |
| onPrimaryContainer | `#F9E8F2` | `#381932` | Label on primaryContainer. |
| secondary | `#AAA6E3` | `#32396F` | = accent (M3 `secondary`). |
| onSecondary | `#000000` | `#FFF3E6` | Label on accent fills. |
| secondaryContainer | `#32396F` | `#AAA6E3` | Same as primaryContainer. `FilledButton.tonal` reads this slot. |
| onSecondaryContainer | `#E7EEFE` | `#381932` | Tonal button label. |

**Volt sticker (brand fills; only through `VoltButton`, `VoltDisc`, `VoltSlab`, `chipTheme`)**

| Role | Dark | Light | Use |
|---|---|---|---|
| voltFill | `#CC324C` | `#81021F` | The loud brand fill: Play all, play discs, Download, Continue card, selected chip (Crimson). Not a text colour: use primary. |
| voltPressed | `#B32A42` | `#5E0016` | Pressed Volt fill. |
| onVoltFill | `#FFF3E6` | same | Milk label and glyph on the crimson (dark) / wine (light) fill. |
| onVoltMuted | `#FFF3E6` | `#F9E8F2` | Secondary text on Volt (Continue card artist, kicker). |
| voltEdge | none (`#00000000`) | same | Sindur v2: no edge in either theme (wine clears 3:1 on sand). A non-transparent value would draw a 1.5dp outline. |
| voltGlow | `#47CC324C` | none | Volt at 28%, blur 24, under the 72dp stage play disc only. |

**Accent, favourite, text**

| Role | Dark | Light | Use |
|---|---|---|---|
| accent | `#AAA6E3` | `#32396F` | Video kind, "Downloaded" glyph, info, downloads count dot. Small roles only, never a large fill. |
| onAccent | `#000000` | `#FFF3E6` | On accent fills (count dot). |
| favorite | `#FFA0B8` | `#9C1458` | Hearts only (filled heart = on). |
| textPrimary | `#FFF3E6` | `#381932` | Titles, body. |
| textSecondary | `#D9CEC4` | `#56404F` | Metadata, secondary icons, all text on artwork tints and the stage. |
| textMuted | `#ABA3AD` | `#5E4A58` | Captions, hints, durations in rows, unselected labels. Never on artwork tints or the stage. |

**Lines and focus**

| Role | Dark | Light | Use |
|---|---|---|---|
| divider | `#26222A` | `#E6D7B2` | Decorative hairlines, card edges (1dp). Never the only boundary of a control. |
| outlineVariant | `#26222A` | `#E6D7B2` | = divider (M3 slot). |
| outline | `#857F8C` | `#857565` | Control borders (outlined button, unselected light chip, switch off), drag handles, section rules. 3:1 or more on every surface. |
| rule | `#857F8C` | `#857565` | The 2dp rule above section kickers (= outline). |
| focusRing | `#F69E1C` | `#81021F` | 2dp keyboard/D-pad focus outline. |
| dragHandle | `#857F8C` | `#857565` | Sheet handle, queue reorder handle. |

**States**

| Role | Dark | Light | Use |
|---|---|---|---|
| success | `#4FD8C4` | `#0A6A40` | Saved / complete. Always with a check icon. |
| warning | `#F69E1C` | `#5A4F00` | Queued, low storage, slow network. Always with an icon. |
| error | `#FF9466` | `#A8231C` | Failed, destructive rows, field errors. Always icon + text. |
| onError | `#000000` | `#FFF3E6` | On error fills. |
| errorContainer | `#3A1A16` | `#FCE4DC` | Error banners, destructive tonal buttons. |
| onErrorContainer | `#FFDCCF` | `#5E1608` | Text on errorContainer. |
| liveFill | `#B3132F` | same | Solid LIVE chip (replaces the red dot, which measured 2.89 on the chip). |
| onLive | `#FFFFFF` | same | "LIVE" label. |

**Scrims, glass and overlays**

| Role | Dark | Light | Use |
|---|---|---|---|
| scrim | `#CC000000` | `#99381932` | Behind sheets and dialogs. Stage veil uses the dark value. |
| glass | `#EB0A0A0A` | `#E0FBF4E2` | Scrolled-under app bars (blur 24); light YouTube toolbar. |
| overlay | `#B8000000` | same | Ink at 72% behind badges on images and video frames. |
| onOverlay | `#FFFFFF` | same | Text on overlay chips. |

**Ink Dock (identical in both themes)**

| Role | Dark | Light | Use |
|---|---|---|---|
| dock | `#F00C0A10` | same | Mini player + nav fill (94%), backdrop blur 24. |
| onDock | `#FFF3E6` | same | Dock titles, selected nav label, controls. |
| onDockMuted | `#B7AFBE` | same | Artist line, unselected nav icon and label. |
| dockLine | `#2E2638` | same | 1dp top line, mini-player progress track. |
| navIndicator | `#F69E1C` | same | 56x32 selected-tab pill; the amber spark (section marks, resume lines). |
| onNavIndicator | `#000000` | same | Filled icon in the pill. |

**Controls and depth**

| Role | Dark | Light | Use |
|---|---|---|---|
| sliderActive | `#F69E1C` | `#81021F` | Active track (6dp). |
| sliderInactive | `#2E2836` | `#E2D2A8` | Inactive track (4dp). |
| sliderThumb | `#FFF3E6` | `#81021F` | 14dp thumb (20dp while dragging). |
| snackbar | `#141216` | `#381932` | Snackbar and tooltip fill (light: ink, matching the dock). |
| onSnackbar | `#FFF3E6` | same | Snackbar text. |
| snackbarAction | `#F69E1C` | same | Snackbar action (both sit on a dark fill). |
| shadow | none (`#00000000`) | `#1A381932` | Light only: sheets, dialogs, menus, snackbars (0 8 24). |
| printShadow | `#81021F` | `#381932` | Hard 6x6dp offset, no blur, under hero and stage covers. |

### 2.3 ColorScheme mapping (both themes, from the palette)

| ColorScheme | From |
|---|---|
| brightness | dark / light |
| primary, onPrimary, primaryContainer, onPrimaryContainer | same-named roles |
| secondary, onSecondary | accent, onAccent |
| secondaryContainer, onSecondaryContainer | same-named roles |
| tertiary, onTertiary | favorite; palette `onTertiary`: `#0B0B0D` (dark) / `#FFFFFF` (light) |
| error, onError, errorContainer, onErrorContainer | same-named roles |
| surface, onSurface, onSurfaceVariant | surface, textPrimary, textSecondary |
| surfaceContainerLowest / Low / (default) / High / Highest | background / surface / surface / surfaceElevated / surfaceElevated (as today) |
| surfaceTint | `Colors.transparent` |
| outline, outlineVariant | outline, outlineVariant |
| shadow, scrim | palette `schemeShadow`: `#000000` (dark) / `#121214` (light); scrim |
| inverseSurface, onInverseSurface, inversePrimary | palette roles. dark: `#FFF3E6`, `#0B0B0D`, `#81021F` · light: `#121214`, `#FFF3E6`, `#FF6E86` · Bijuli Classic: `#F6F2FF`, `#180A2E`, `#5A32D6` |

---

## 3. Gradients

All gradients run `topLeft → bottomRight` unless stated.

**heroGradient** (detail headers, Home top band, empty-state band)

| | Stops | Notes |
|---|---|---|
| Dark | `#5A0418 → #2A1230 → #000000` | Deep wine through plum into the black canvas. `HeroBand(glow: true)` adds a soft crimson orb (top end) and an indigo one (bottom start), decorative only. |
| Light | `#C6CBE8 → #E7EEFE → #F6EBCF` | Periwinkle wash fading into sand. |

Items **with** a real cover use the brand hero. Items **without** a cover tint the hero and the stage with their own
artwork pair (see `ArtworkTint` below), so per-song colour survives.

**primaryGradient**: same in both themes, `#C42A46 → #A8203A` running `topCenter → bottomCenter`, a subtle crimson sheen for `VoltButton`, `VoltSlab` and `VoltTile`, milk label.
Sindur v2 draws no edge around it on paper. Bijuli Classic keeps its Volt sheen (lime, in `AppPalette.classic`).

**Artwork gradients**: 8 pairs, picked per item by uri hash. White glyph at 85%. The top stop is identical in both
themes so an item keeps its colour when the phone switches theme; on paper the deep stop is lifted one step so tiles
look like objects, not holes. Bijuli Classic keeps its original eight (ultraviolet, ice, flare, moss, ember, cobalt,
orchid, jade).

| # | Name | Top stop (both) | Deep stop, dark | Deep stop, light |
|---|---|---|---|---|
| 1 | crimson | `#CC324C` | `#4A0A1A` | `#7A1028` |
| 2 | wine | `#9A0A2C` | `#3A0010` | `#5E0016` |
| 3 | plum | `#7A3A6E` | `#2A0F26` | `#4A1A40` |
| 4 | indigo | `#4A54A8` | `#161A40` | `#252C6A` |
| 5 | amber | `#B5600A` | `#4A2204` | `#6E3606` |
| 6 | graphite | `#55525E` | `#0A0A0A` | `#2C2A32` |
| 7 | lavender | `#7E6FD0` | `#241A50` | `#3E3488` |
| 8 | rose | `#B0407A` | `#40102C` | `#6A1A48` |

The floors (85% glyph 3:1 on top stops, 4.5:1 on midpoints, white 4.5:1 on deep stops) are checked by
`test/unit/palette_contrast_test.dart`.

**ArtworkTint.surfaceGradient** (cards and headers that carry text, cover-less items):

- Dark (today's recipe, new canvas): `[lerp(deep, background, 0.30), lerp(deep, background, 0.68), background]`.
- Light (new): `[lerp(top, background, 0.85), lerp(top, background, 0.93), background]` with ink text.
- Text on it: textPrimary and textSecondary only. textMuted passes (4.66 at worst in light) but is not used, so nothing
  sits near the floor on a tint.
- Now Playing always renders with the dark palette, so its backdrop glows (`backdropLightAlpha 0.9`,
  `backdropDeepAlpha 0.6`, the veil and the brightness cap) stay exactly as today, in both themes. A tint change
  cross-fades over 600ms (`MotionTokens.ambient`), or instantly with reduced motion.

---

## 4. Verified contrast

**`test/unit/palette_contrast_test.dart` is the source of truth** (with `test/unit/card_contrast_test.dart`): it checks
every pair against its floor for the dark, light and Bijuli Classic palettes and fails if one drops. No figures are
copied here, so they cannot go stale.

- Method: WCAG 2.x relative luminance. Alpha colours are composited over the named backdrop first. Flutter's
  `Color.lerp` is reproduced for tints.
- Floors: text 4.5:1 on every surface it can sit on; large text, icons and control boundaries 3:1; labels on fills 4.5:1.
- Colour vision: primary, accent, favourite, success, warning and error stay 6 or more CIEDE2000 apart under normal,
  deutan and protan vision (Machado 2009, full severity) in both Sindur themes. Every state still carries an icon and a
  word, never colour alone.

---

## 5. Fonts

Sindur bundles three families, all SIL OFL 1.1 with **no Reserved Font Name** (checked in each `OFL.txt` header: only
a copyright line, no "with Reserved Font Name" clause). All are bundled, with no runtime fetching. The licences are in
`assets/fonts/licenses/`, embedded verbatim in `lib/app/theme/font_licenses.dart` (test/unit/font_licenses_test.dart
keeps them equal) and registered on the licences page.

| Family (pubspec name) | Role | Files in `assets/fonts/` | Source | Licence file |
|---|---|---|---|---|
| **Fraunces** (`Fraunces`) | App-written headings only: `display`, `sectionTitle`. A warm, soft old-style serif that suits the crimson and wine brand. Latin only. | `Fraunces-SemiBold.ttf` (600), `Fraunces-Bold.ttf` (700), 73 KB each | Static instances of `https://raw.githubusercontent.com/google/fonts/main/ofl/fraunces/Fraunces%5BSOFT,WONK,opsz,wght%5D.ttf` at opsz 72, SOFT 50, WONK 0 | `Fraunces-OFL.txt` ("Copyright 2018 The Fraunces Project Authors") |
| **Poppins** (`Poppins`) | Every name of a thing and every line people read: `greeting`, `screenTitle`, `playerTitle`, `cardTitle`, `body`, `bodyStrong`, `metadata`, `label`, `chipLabel`, `button`, `caption`. Draws Latin **and Devanagari** in one design. | `Poppins-Regular.ttf` (400), `-Medium.ttf` (500), `-SemiBold.ttf` (600), `-Bold.ttf` (700), 155-160 KB each | `https://raw.githubusercontent.com/google/fonts/main/ofl/poppins/Poppins-{Regular,Medium,SemiBold,Bold}.ttf` (static, unmodified) | `Poppins-OFL.txt` ("Copyright 2020 The Poppins Project Authors") |
| **DM Mono** (`DMMono`) | `tabularFigures`, `index`, `overline`, `badge`, `figureLarge`; Diagnostics log text | `DMMono-Regular.ttf` (400), `DMMono-Medium.ttf` (500) | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmmono/` (unchanged) | `DMMono-OFL.txt` |

Total payload about 0.9 MB (was 2.9 MB with Unbounded, Anek Devanagari, Atkinson Hyperlegible Next and Mukta, which
are gone with their licences). Rebuild steps are in `tools/fonts/README.md`.

Flutter's `fontWeight` does not drive a variable font's `wght` axis, and `fontVariations` would also apply to the
fallback fonts, so only static files ship.

**Devanagari strategy**

1. Everything that can carry user content (song, artist, album and video names, body text, chips) is Poppins, which
   has its own Devanagari (94 glyphs in U+0900-097F plus conjunct forms), so a Nepali title never switches font
   mid-line. These styles have no fallback list.
2. App-written headings use Fraunces with `fontFamilyFallback: ['Poppins']`, so a Nepali word inside a static heading
   still draws.
3. DM Mono falls back to Poppins. `ThemeData(fontFamily: 'Poppins', fontFamilyFallback: ['Poppins'])`.
4. Every style sets `leadingDistribution: TextLeadingDistribution.even`.
5. User-content styles use `letterSpacing: 0`, because tracking breaks the shirorekha (headline bar) and collides
   conjuncts.
6. Line heights stay at 1.33 or more wherever Devanagari can appear.
7. File-style names go through `breakableTitle()` (`lib/core/utils/formatters.dart`) for display, so
   `Audit_Long_Tone_5min` wraps at underscores. Semantics labels keep the original.

---

## 6. Type scale

`AppTypography.of(AppPalette p)` builds every style with the palette's colours; `AppTypography.textTheme(p)` maps them
onto M3. Height is Flutter's multiplier (line px / size). F = Fraunces (fallback Poppins), P = Poppins (no fallback),
M = DMMono (fallback Poppins).

| Role | Family | Size / line | Weight | letterSpacing | Default colour | M3 slot | Used for |
|---|---|---|---|---|---|---|---|
| display | F | 32 / 40 | 700 | -0.5 | textPrimary | displaySmall | Tab mastheads only ("Music", "Videos", "Online", "Downloads", "Settings"). One line. |
| greeting | P | 30 / 42 | 700 | 0 | textPrimary | headlineLarge | Home: "नमस्ते". |
| screenTitle | P | 24 / 34 | 700 | 0 | textPrimary | headlineMedium | App bar titles, album / artist / playlist headers, the watch-screen title. Max 2 lines. |
| playerTitle | P | 22 / 30 | 600 | 0 | textPrimary | titleMedium | Now Playing and video player titles. Max 2 lines. |
| cardTitle | P | 20 / 28 | 700 | 0 | onVoltFill / textPrimary | headlineSmall | Continue-listening slab, hero tiles. |
| sectionTitle | F | 18 / 26 | 600 | 0 | textPrimary | titleLarge | "Recently played", sheet and dialog titles (app strings only). |
| body | P | 16 / 24 | 400 | 0 | textPrimary | bodyLarge | Paragraphs, sheet rows, dialog body, inputs. |
| bodyStrong | P | 16 / 24 | 600 | 0 | textPrimary | titleSmall | Song / video titles in rows, list-tile titles. Mini player 15/20. |
| metadata | P | 14 / 20 | 400 | 0 | textSecondary | bodyMedium | "Artist · Album", "Channel · 1.2 GB". |
| label | P | 12 / 16 | 600 | 0.2 | textMuted | labelMedium | Nav and form labels (app strings only). |
| chipLabel | P | 14 / 20 | 600 | 0 | textPrimary | (chipTheme) | Chips (may carry artist names). |
| button | P | 15 / 20 | 600 | 0 | from button | labelLarge | Every button label, sentence case. |
| caption | P | 12 / 16 | 400 | 0 | textMuted | bodySmall | Helper, error and empty-state fine print, tooltips. |
| tabularFigures | M | 13 / 18 | 500 | 0 | textSecondary | - | Seek times, durations, sizes, %. Tabular figures. |
| index | M | 13 / 18 | 500 | 0 | textMuted | - | Track numbers "01 02 03". |
| overline | M | 11 / 16 | 500 | 1.1 | textSecondary or primary | labelSmall | UPPERCASE kickers (app strings only). |
| badge | M | 12 / 16 | 500 | 0.2 | onOverlay | - | Duration badge, "1080P", "LIVE", PillTag. |
| figureLarge | M | 28 / 32 | 500 | -0.5 | textPrimary | - | Download %, storage totals, sleep-timer countdown. |

Rules:

- **Fraunces** is never used below 18, in list rows, or for any string that came from a file, tag, URL or person.
- Reading text is 16 (body) and never below 15 in rows that elders read; 12-14 only for metadata, labels and captions.
- **Text scale.** Layouts must hold at `textScaler` 1.3 on a 320 and a 360dp phone without clipping. Rows use
  `minHeight`, not a fixed height.

---

## 7. Components

### 7.18 Home (Sindur v2)

- Hero: `HeroBand(glow: true)` with a short amber `SparkMark`, "नमस्ते" in the greeting voice and the time of day.
- The Volt "Continue listening" slab (unchanged behaviour and labels).
- Bento quick actions: a tall `VoltTile` "Shuffle all" (as tall as the two tiles beside it), Liked and Online stacked
  on `surfaceElevated`, then a full-width tonal (`secondaryContainer`) Downloads strip. Without songs the Shuffle
  block goes; while songs load a skeleton holds its place.
- Cover rails (136 dp covers, radius 24, title + artist): Recently played, Most played, Recently added, Liked (See
  all opens Liked songs), then the Recent videos rail. Each heading is Fraunces with an amber `SparkMark`.

### 7.19 Videos (Sindur v2)

- Glowing hero with the count, refresh and sort; search field.
- Featured "Continue watching" card: full-width 16:9 still with a 4 dp amber resume line, kicker, title, time left
  and a play disc. More part-watched videos follow in a rail.
- Filter chips: All / Downloaded / On this phone, then a two-column grid of 16:9 cards (duration badge, amber
  resume line, two title lines; long press opens the media sheet). Cell height grows with the text scale.
- Empty and permission states unchanged.

### 7.20 Downloads (Sindur v2)

- The link field and its main action live inside the glowing hero, under the title and the active / free summary.
- Download cards: 8 dp progress bar in `sliderActive` (amber on ink, wine on sand), muted when paused or waiting.
- Saved list keeps the 5 newest + "Show all N saved" toggle, kind chips and kind icons; settings area unchanged.

### 7.1 Shape, spacing, depth, motion (both themes)

- **Grid:** 4dp. Phone gutter 16, tablet (600dp or wider) 24. Section header padding 24 top / 8 bottom. Card padding 16.
  Scrolling content ends with a bottom padding of Ink Dock height (64 mini + 64 nav + system inset) + 16.
- **Radii** (`AppSpacing`): `radiusBadge` 6 (overlay chips, PillTag) · `radiusArtSmall` 10 · `radiusThumb` 14 ·
  `cardRadius` 20 (cards, Continue slab) · `radiusMenu` 16 (menus, text fields, snackbars, list-tile ink) ·
  `radiusSheet` 28 (sheet top corners, dialogs) · `radiusCover` 24 · stadium for every button, chip, nav indicator and
  disc; circle for icon buttons.
- **Touch:** 48dp minimum target everywhere (`materialTapTargetSize: padded`).
- **Depth:**
  - Dark: tone steps plus 1dp `divider` hairlines on cards, dialogs, sheets and snackbars. The only soft light is the
    crimson `voltGlow`: under enabled VoltButtons (blur 18, offset 0/6, tightening to 8 / 0/2 while pressed), under the
    72dp stage disc, around slider thumbs, and as a glint across the middle of the Ink Dock's top edge.
  - Light: no glows anywhere (`voltGlow` is transparent). Cards get a soft two-layer ink shadow
    (`SurfaceCard.shadowsFor`, `cardTheme.elevation` 2); sheets, dialogs, menus and snackbars elevation 6.
  - Both: the hard **print offset** under the detail-header and Now Playing covers.
- **Motion** (`MotionTokens`, always through `MotionTokens.duration`, so reduced motion means 0ms):

  | Duration | What |
  |---|---|
  | 120ms `easeOut` | Press feedback: VoltButton, VoltDisc, VoltSlab and TonalIconButton scale to 0.97 |
  | 160ms | Play/pause icon morph |
  | 240ms | Page transitions; nav indicator slide (`MotionTokens.emphasized`) |
  | 280ms | Sheets |
  | 600ms | Tint drift (`ambient`) |

### 7.2 Buttons

`filledButtonTheme` sets shape, size, text style and elevation 0 but **no colours**, so FilledButton takes
`primary`/`onPrimary` and FilledButton.tonal takes `secondaryContainer`/`onSecondaryContainer`. Every Material button
gets the same press / focus / hover wash: `primaryBase` (crimson) at 16 / 14 / 8 %.

| Kind | Dark | Light | Shape, size, states |
|---|---|---|---|
| **VoltButton** (play / get: Play all, Download, Save offline, Fetch link) | Crimson sheen (`primaryGradient`, top to bottom), white label, soft crimson glow | Same sheen, no glow, no edge (Sindur v2) | Stadium, 52dp (40 `compact`, 12dp side padding), 20dp icon. Pressed: `voltPressed`, scale 0.97, tighter glow. Disabled: `surfacePressed` fill, textMuted label, no glow (light keeps an `outline` edge). Focus: 2dp `onVoltFill` ring. |
| FilledButton (Save, Retry, dialog confirm) | Rose fill, ink label | Wine fill, white label | Stadium, 48dp. |
| FilledButton.tonal | `secondaryContainer` / `onSecondaryContainer` | same roles | Stadium, 48dp. |
| ElevatedButton | `primary` / `onPrimary`; disabled textPrimary 12 % fill, 38 % label | same | Stadium, 48dp, no elevation. |
| OutlinedButton | 1.5dp `outline`, textPrimary label; the edge turns `primary` while pressed or focused | same roles | Stadium, 48dp. Disabled edge and label at 38 %. |
| TextButton (See all, Cancel) | `primary` label | same | Stadium, 12 horizontal padding. |
| IconButton | 48dp, textPrimary glyph, crimson wash | same | Circle. Disabled 38 %. |
| **TonalIconButton** (new) | `secondaryContainer` disc, `onSecondaryContainer` glyph | same roles | Circle, 48dp, crimson wash, scale 0.97 while pressed. |
| **VoltDisc** | Crimson circle, white glyph; 72dp adds `voltGlow` (blur 24, 12 while pressed) | + ink edge | 44 / 56 / 72. |
| Destructive | TextButton in `error`, or tonal `errorContainer`. Always confirmed. | same | - |

### 7.3 Chips

- 36dp tall inside a 48dp target, stadium, 12dp side padding, `chipLabel`.
- Unselected: `surfaceElevated` (dark) / `surface` (light) with an outline: 1dp `outlineVariant` hairline on ink, 1dp
  `outline` on paper. Pressed: `surfacePressed`.
- **Selected: crimson `voltFill`, white label and an 18dp white check** (state never depends on colour alone); paper adds
  the 1.5dp ink edge. Disabled at 38 %.

### 7.4 Cards

- **SurfaceCard:** `surface`, radius 20, 1dp `divider` edge, padding 16. Pressed: `surfacePressed` highlight with a 10 %
  crimson splash. Light adds the soft ink shadow; dark has none.
- **cardTheme:** dark hairline `divider`, elevation 0; light no edge, elevation 2 with an 18 % ink shadow.
- **VoltSlab** (Continue listening): crimson sheen, radius 20, padding 16 (paper adds the ink edge); `overline` kicker
  and `metadata` in onVoltMuted; `cardTitle` in onVoltFill; trailing 48dp disc; 3dp progress line 8dp above the
  bottom; scale 0.97 while pressed.

### 7.5 Section headers

`SectionHeader` with a `kicker`, top to bottom: a 2dp rule across the gutter, **led by a 28dp `primaryBase` segment**
(`ruleAccentWidth`), 12dp, the kicker in `overline` / `primary`, 4dp, then the `sectionTitle` row with the trailing
"See all" TextButton. Rule only on screen-level sections.

Screen mastheads (Home greeting, Music, Videos, Downloads, Settings) sit in a `HeroBand`: a radius-20 card filled
with `heroGradient`, 20dp padding, the title in `display` / `greeting`. Mastheads, Settings cards and empty states
enter with `EntranceFade` (fade + 8dp lift, `MotionTokens.page`, 40ms stagger capped at 6), instant with reduced motion.

### 7.6 List rows

- **Song row**, 64dp minimum: 48dp art (radius 10) or a 32dp `index` column; `bodyStrong` title; `metadata` line with the
  duration as `tabularFigures`; trailing 48dp `more_vert`.
- **Now-playing row:** a 3dp `primary` bar on the leading edge, the equaliser over the art, the title in `primary`.
- **ListTile theme:** `bodyStrong` titles, `metadata` subtitles, radius-16 ink, selected = `primary` content on
  `primaryBase` at 10 %.

### 7.7 Ink Dock: nav bar + mini player (dark in both themes)

- **Container:** `InkTheme.of(context)`, `AppTheme.barsOnInk`, `dock` fill over a 24 blur, 24dp top corners, a 1dp
  `dockLine` top edge with a crimson glint fading out to the corners (the palette's `voltGlow`).
- **Mini player** (64dp): 44dp art at radius 10; title `bodyStrong` 15/20 in onDock, artist 13/18 in onDockMuted; a 44dp
  VoltDisc between 48dp previous / next; a 2dp `primary` progress line along the top edge.
- **Nav:** `NavigationBar` 64dp, transparent; selected = a rose `navIndicator` pill with an ink icon and the label in
  onDock; unselected onDockMuted; the indicator slides in 240ms.

### 7.8 Now Playing (the stage, identical in both themes)

Dark theme always. Cover radius 24 with the print offset. Seek bar: track 4 (active 6), `sliderActive` on
`sliderInactive`, round thumb in `sliderThumb`, 14dp growing to 20dp while dragged, over a soft crimson halo
(`VoltSliderThumbShape.glowColor` = `voltGlow`, blur 8). Transport: VoltDisc 72 with its glow.

### 7.9 Video cards and badges

Thumbnails 16:9 at radius 14. Overlay badges on `overlay`: DurationBadge, MediaBadge (lavender glyph), LIVE in
`liveFill`. PillTag: tinted (colour text on colour at 14 %) or filled with on-colour pairs only.

### 7.10 Sheets, menus, dialogs, snackbars

- **Bottom sheets:** `surface`, top radius 28, 36x4 `dragHandle`, `scrim` behind; a 1dp `divider` edge on ink, elevation
  6 shadow on paper.
- **Menus:** `surfaceElevated`, radius 16, 1dp `outlineVariant` border, `body` items.
- **Dialogs:** `surfaceElevated`, radius 28, `sectionTitle` title, `body` / textSecondary content; hairline on ink,
  shadow on paper.
- **Snackbars:** floating, radius 16, 16dp side insets, `snackbar` / `onSnackbar` body 15/20, `snackbarAction`; hairline
  on ink, shadow on paper.
- **Tooltips:** `snackbar` fill, `caption` text, radius 8.

### 7.11 Inputs and controls

- **Text fields:** filled (`surfaceElevated` on ink, `surface` on paper), radius 16, 16dp padding; enabled edge 1dp
  `divider` (ink) / `outline` (paper); **focus ring 2dp `primary`** (rose on ink, wine on paper); error 1.5dp / 2dp
  `error`. Cursor and handles `primary`, selection `primary` at 30 %.
- **Switch:** on = `primary` track, `onPrimary` thumb with a check; off = `sliderInactive` track, 1.5dp `outline`, textMuted
  thumb. Disabled at 38 %.
- **Checkbox:** radius 6, `primary` fill and 2dp edge when on, `onPrimary` check; 2dp `outline` when off; crimson wash.
- **Radio:** `primary` when selected, `outline` otherwise, disabled at 38 %, crimson wash.
- **Sliders:** as the seek bar (7.8): crimson / rose active track, round thumb with the glow on ink only.

### 7.12 Progress

Linear 4dp `primary` on `surfacePressed`; page load 2dp; circular 3dp `primary`; mini player 2dp; Continue slab 3dp.

### 7.13 Online (YouTube) tab

The app's chrome around a WebView of `m.youtube.com`: never recolour the page or use YouTube's red or logo. Toolbar
with back / forward, the address pill, reload and ⋮; the watch strip with a compact VoltButton "Download", outlined
Copy link / PiP buttons, and FilterChip toggles for Background play and Auto PiP.

### 7.14 Downloads screen

`display` header with an `overline` summary; the link field with a full-width VoltButton; SurfaceCard rows with a 4dp
`primary` progress bar and `tabularFigures`; groups under `overline` kickers; states always icon + word.

### 7.15 Empty states

`EmptyHint`: an 84dp halo (`primaryBase` 28 % to 4 % with a 1dp `primaryBase` 22 % ring) holding a 38dp `primary` icon,
an optional `overline` kicker, a `sectionTitle` headline and a `body` / textSecondary message; one action at most (a
VoltButton for play / get, else a FilledButton).

### 7.16 App icon and splash

The play-bolt: a rounded play triangle split by a lightning notch, crimson `#CC324C` with a 2dp near-black
`#0B0B0D` keyline, a thin rose `#FF6E86` rim on its upper-left edges and a small milk `#FFF3E6` glint. Drawn by
`assets/icon/draw_icon.py` (Pillow, 4x supersampled):

- `app_icon.png`: 1024 full bleed on a `#0B0B0D` (top left) to `#4A0F24` (bottom right) diagonal, no alpha (iOS, legacy).
- `app_icon_foreground.png`: the glyph on transparent, inside the 66dp safe circle; `adaptive_icon_background` `#0B0B0D`.
- `app_icon_monochrome.png`: the glyph silhouette in white for themed icons.

Regenerate with `python -I assets/icon/draw_icon.py assets/icon` then `dart run flutter_launcher_icons`. The launch
screen (`launch_background.xml`, iOS `LaunchScreen.storyboard`) and the Android 12+ splash are `#0B0B0D`
(`mediahub_canvas`) in both system themes; the running window is white / `#0B0B0D` (`mediahub_window`). Settings →
About shows the icon in miniature with the same diagonal and crimson glyph.

### 7.17 Playback behaviour

Previous restarts after 3s; next is disabled at the queue end with repeat off; the notification, lock screen and
headset mirror the mini player; selection haptic on swipe-skip, light impact on favourite.

---

## 8. Light theme specifics and system bars

### 8.1 What changes besides colour

| Thing | Dark (Sindur) | Light (Sindur paper) |
|---|---|---|
| Brand reading colour (`primary`) | Rose `#FF6E86` | Wine `#81021F` |
| Volt fills | Crimson `#CC324C`, plain, with the crimson glow | Crimson with the 1.5dp ink edge, no glow |
| FilledButton | Rose / ink | Wine / white |
| Depth | Tone steps, hairlines, crimson glows | Soft ink shadows on cards, sheets, dialogs, menus, snackbars |
| Text-field edge | `divider` hairline | `outline` |
| Ink Dock, Now Playing, video player | Ink | **Ink (unchanged)** |

### 8.2 Theme mode and system bars

- `MaterialApp(theme: AppTheme.lightTheme, darkTheme: AppTheme.darkTheme, themeMode: ...)`; Settings → Appearance
  (System / Dark / Light / Bijuli Classic).
- Edge-to-edge at startup. `AppBarTheme.systemOverlayStyle` is `AppTheme.barsOnInk` on ink and `AppTheme.barsOnPaper` on
  paper; the Ink Dock, Now Playing and the video player always use `barsOnInk`.

---

## 9. Do / don't

**Do**

- Use `primary` for brand text, icons, tracks and focus rings; it is readable in both themes.
- Use `VoltButton`, `VoltDisc`, `VoltSlab` (or the chip theme) for every crimson fill; they draw the ink edge on paper
  and the glow on ink. Use `TonalIconButton` for round secondary actions.
- Keep crimson fills for "play" and "get" actions and selection.
- Set anything named by a file, tag, URL or person in Poppins roles; pass file-style names through `breakableTitle()`.
- Pair every state with an icon and a word.
- Run every press animation through `MotionTokens.duration` so reduced motion is instant.
- Test both palettes, at `textScaler` 1.3, on 320 and 360dp, with Nepali titles.

**Don't**

- Don't ship a crimson fill on paper without the ink edge, or a glow on paper.
- Don't use Fraunces for user content, below 18sp, or in rows (it has no Devanagari).
- Don't add `letterSpacing` to any style that can carry user content.
- Don't give `filledButtonTheme` colours (it would repaint every tonal button).
- Don't add glows beyond `voltGlow` (VoltButton, the stage disc, slider thumbs, the dock glint), or any pulse.
- Don't recolour the YouTube page or copy YouTube's red or logo into our chrome.
- Don't bring back `AppColors` `const` reads in new code.

---

## 10. Implementation order and tests

1. **Palette:**
   - `lib/app/theme/app_palette.dart`: the `AppPalette` ThemeExtension (2.2), with `dark`, `light`, `lerp` and the
     `context.palette` extension.
   - `AppColors` becomes a deprecated alias of `AppPalette.dark` until every call site moves.
2. **Type:**
   - Fonts into `assets/fonts/` (section 5) and the pubspec block.
   - `AppTypography.of(p)` / `textTheme(p)` with the section 6 roles, adding `greeting`, `cardTitle`, `chipLabel`,
     `index`, `overline`, `badge`, `figureLarge`.
   - Remove Inter; register the licences.
3. **Theme:**
   - `AppTheme._build(AppPalette p, Brightness b)` producing `darkTheme` and `lightTheme`, with the ColorScheme from 2.3.
   - Component themes per section 7: colourless `filledButtonTheme`, `chipTheme` with the Volt sticker,
     `navigationBarTheme`, `sliderTheme`, `switchTheme`, `snackBarTheme`, `bottomSheetTheme` (dragHandleColor =
     `dragHandle`), `popupMenuTheme`, `dialogTheme`, `inputDecorationTheme`, AppBar `systemOverlayStyle`.
   - `app.dart`: `theme`, `darkTheme`, `themeMode: ThemeMode.system`.
4. **ui_kit:**
   - New: `VoltButton`, `VoltDisc`, `VoltSlab`, `InkDock`.
   - Changed: `SectionHeader(kicker:)`, `PillTag(onColor:)`, `DurationBadge.live` as a solid chip, `MediaBadge` Ice
     glyph, `SurfaceCard` radius 20, `GlassContainer` reading `palette.glass`.
   - `ArtworkTint.surfaceGradient(seed, palette)` with the light recipe; artwork gradients from the palette.
5. **Screens:**
   - Shell: Ink Dock, nav rename Explore → Online.
   - Mini player: prev / play / next.
   - Now Playing: print offset, Volt disc.
   - Home: greeting and Continue slab.
   - Detail headers: hero, print offset, VoltButton "Play all".
   - Rows: indices, now-playing bar.
   - Downloads, the Online toolbar, sheets, dialogs, app icon.
6. **Tests:**
   - `test/unit/palette_contrast_test.dart`: port `contrast_final.py`. For both palettes:
     - every text role on all four surfaces;
     - every state colour on all four surfaces (including surfacePressed);
     - glass and dock over a white **and** a black page;
     - on-fill pairs;
     - outline at 3:1 or more;
     - artwork top stops, midpoints and surfaceGradient s0/s1 for 8 hues.
   - Update `card_contrast_test.dart` and `artwork_placeholder_test.dart` to run on both palettes.
   - `test/unit/volt_usage_test.dart`: fail if `voltFill`, `primaryGradient` or `onVoltFill` appear in `lib/` outside
     `ui_kit.dart`, `app_theme.dart` and `app_palette.dart`.
   - Widget test: `VoltButton`, `VoltDisc` and `VoltSlab` in the light theme paint a 1.5dp `#180A2E` border; selected
     chips in light have the ink side.
   - Golden/preview pass: extend `tools/design_previews/preview_test.dart` to render every scene in **both** themes at
     360x800 and 320dp, and at `textScaler` 1.3. Include "रेशम फिरिरी", "झिलिमिली साँझ", "क्षितिज पारि" and
     "Audit_Long_Tone_5min" in titles and the Home greeting. Check that no matra or conjunct clips and the mini player
     and nav labels do not overflow.

### 10.1 As built: deliberate deviations

The redesign shipped with light mode on (the old `lightThemeReady` gate and the legacy `AppColors` / static
`AppTypography` getters are gone; `volt_usage_test.dart` keeps them out). Where the build departs from the sections
above, on purpose:

| Where | Spec | As built, and why |
|---|---|---|
| 7.6 song rows | Trailing ⋮ only | Rows at 360dp or wider with text below 1.15x keep the 48dp heart before the ⋮ (one-tap favourite, existing behaviour). Smaller rows drop it, so the artist keeps its width, and mark a favourite with a 16dp Flare heart before the meta line ("Favorite" in the row's label); the media sheet toggles it. |
| 7.7 mini player | Previous and next at 38% at a queue end | Only Next dims: Previous always restarts the track or goes back (7.17). |
| 7.8 Now Playing | `#421E78` glow for a real cover; footer with sleep timer | The glow stays the first cover gradient (section 3 "exactly as today"). The footer has speed, the queue and the sleep timer (a moon button opening its sheet: 5, 15, 30, 45, 60 min or End of song, countdown in `figureLarge`); while it runs a `PillTag` "SLEEP 12:30" / "SLEEP · END OF SONG" sits under the artist. Stopping the session ends it. |
| 7.8 kicker | One line | Shrinks as a whole on small phones at large text, so "7 / 8" is never cut. |
| 7.10 media sheet | Share, Delete for every item | Share (before Details) is on Android only: iOS has no native share bridge yet (needs a Mac; see HANDOFF D.4). Delete is offered for downloads only (phone media needs a native MediaStore delete request). Video titles show without their file extension, as on the cards. The Add-to-playlist header puts "New playlist" under the title when both do not fit (320dp at large text), so the title is never cut. |
| 7.13 watch strip | Text buttons, 8dp gaps | Download stays the Volt text button; Picture-in-picture, Save and Copy link are 40dp round outlined icon buttons (name in the tooltip and for screen readers) and the chip reads "Background" (read as "Background play"), with 4dp between the 48dp targets, so Download, PiP and Background play are in full view on a 360dp phone. Order: Download, PiP, Background, Save, Copy link, Auto PiP. |
| 7.14 Downloads | VoltButton "Download" under the link field | It reads "Choose quality" (YouTube) or "Inspect" (other links), because it opens the quality sheet or checks the link; the real "Download" is the VoltButton in the result card. Figures wrap only between chunks, each later chunk led by its "·" or "/". |
| 7.17 notification | Mirrors the mini player exactly | On the last track with repeat off the notification drops Next, but the media session keeps `ACTION_SKIP_TO_NEXT`: without it Android 13+ moves Shuffle into Next's slot. A Next from there is ignored, like the app's disabled button. |

### Open risks

1. **Volt-on-paper discipline.** It is contained by the widgets and the two tests above. Review any PR that touches
   `voltFill`.
2. **Lime may still read "Spotify green" to some.** Hue 75 vs 141, the violet canvas and the ultraviolet icon field
   counter it.
3. **Mixed Latin/Devanagari metrics in rows.** Atkinson Latin and Mukta Devanagari have slightly different x-heights;
   acceptable, but check on real titles. Titles avoid this by using Anek.
4. **Size bumps** (body 16, metadata 14, caption 12) can overflow fixed heights in the mini player and nav. This is why
   `minHeight` and the 1.3 text-scale goldens are mandatory.
5. **Anek static sizes are not measured yet**; the instancing step must be run and recorded.
6. **The always-ink dock and stage in the light theme** are deliberate. If the family asks for "fully light", switch
   the dock to `glass` with an Ultraviolet indicator (onDock → textPrimary). Those pairs already pass in the light
   column.
7. **YouTube background play** in a WebView depends on the page's own behaviour and YouTube's terms. This is a private,
   never-published family app, so it is the owner's call; the chrome here works either way.
