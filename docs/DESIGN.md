# MediaHub design system: "Bijuli · Volt on Ink"

Status: final spec for the full redesign (Android + iOS, dark + light, theme follows the phone).
Written 2026-11-17. Replaces "Midnight Violet" (`AppColors` near-black blue + violet + teal, Inter everywhere).

Visual specimen with both themes side by side (open in a browser; fonts load from GitHub):
`C:/Users/NIRANJ~1.KAT/AppData/Local/Temp/claude/74ef1ad76cd92579/a5efaf5b-88c3-4c58-bb08-e9db94fe4afd/scratchpad/design_dir/specimen.html`
(a scratch folder, so copy it somewhere permanent if you want to keep it).

---

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

**Bijuli (बिजुली, "electricity") · Volt on Ink.** One loud colour, Volt lime `#CCFF3A`, sits on a deep ultraviolet ink
`#180A2E`. Lime and violet are complementary, so the app reads like a gig poster rather than a dashboard, and no
competitor owns either half. Spotify is a darker green at hue 141 on neutral black, YouTube and Apple Music are red,
VLC and SoundCloud orange, Amazon cyan.
In the light theme the canvas becomes warm ivory paper `#F7F2E8`. Text is ink, the reading accent becomes
Ultraviolet `#5A32D6`, and Volt turns into a highlighter **sticker**: Volt fill, ink label, 1.5dp ink edge. The signature
**Ink Dock** (mini player + bottom navigation) and the playback **stage** (Now Playing, video player) stay ink in both
themes, so the place the family spends most time looks the same on every phone. Type has four voices with clear
jobs:

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
- Ink Dock, Now Playing and the video player wrap themselves in `Theme(data: AppTheme.darkTheme, child: ...)`, so
  `context.palette` inside them is always the dark palette.

### 2.2 Token table

`#AARRGGBB` = alpha first, as Flutter's `Color(0xAARRGGBB)`. "Same" = identical value in both themes.

**Canvas and surfaces**

| Role | Dark | Light | Use |
|---|---|---|---|
| background | `#180A2E` | `#F7F2E8` | Scaffold canvas. Also the brand **ink**: every label on Volt, light-theme text, the icon's deep stop. |
| surface | `#22123E` | `#FFFCF6` | Cards, sheets, list groups, search field (light: white). |
| surfaceElevated | `#2B1A50` | `#FFFFFF` | Dialogs, menus, chips (dark), input fill, dark snackbar. |
| surfacePressed | `#382664` | `#ECE4D3` | Pressed rows/cards, progress tracks, the floor every text colour is tested on. |

**Brand (scheme roles)**

| Role | Dark | Light | Use |
|---|---|---|---|
| primary | `#CCFF3A` Volt | `#5A32D6` Ultraviolet | Text/icon accent: links, "See all", active toggles, now-playing title and bar, slider, progress, focus, FilledButton fill. Safe as text in both. |
| primaryBase | `#B8F000` | `#6A45E6` | Base for tints: ripple/highlight at 12%, empty-state halo at 28%. Never text. |
| primaryPressed | `#A9DC14` | `#4723B5` | Pressed fill for anything filled with `primary`. |
| onPrimary | `#180A2E` | `#FFFFFF` | Label/glyph on `primary` fills. |
| primaryContainer | `#33225E` | `#EAE1FF` | Tonal brand fill: tonal buttons, Downloads type tiles, selected list row tint. |
| onPrimaryContainer | `#D9FF73` | `#38189A` | Label on primaryContainer. |
| secondary | `#78C4FF` | `#00658A` | = accent (M3 `secondary`). |
| onSecondary | `#180A2E` | `#FFFFFF` | Label on accent fills. |
| secondaryContainer | `#33225E` | `#EAE1FF` | Same as primaryContainer. `FilledButton.tonal` reads this slot. |
| onSecondaryContainer | `#D9FF73` | `#38189A` | Tonal button label. |

**Volt sticker (brand fills; only through `VoltButton`, `VoltDisc`, `VoltSlab`, `chipTheme`)**

| Role | Dark | Light | Use |
|---|---|---|---|
| voltFill | `#CCFF3A` | `#CCFF3A` | The loud brand fill: Play all, play discs, Download, Continue card, selected chip, nav indicator. Never text or icon colour on paper (1.05:1). |
| voltPressed | `#A9DC14` | `#A9DC14` | Pressed Volt fill. |
| onVoltFill | `#180A2E` | `#180A2E` | Ink label and glyph on Volt. |
| onVoltMuted | `#4A3B66` | `#4A3B66` | Secondary text on Volt (Continue card artist, kicker). |
| voltEdge | none (`#00000000`) | `#180A2E` | 1.5dp outline around every Volt fill on paper. |
| voltGlow | `#47CCFF3A` | none | Volt at 28%, blur 24, under the 72dp stage play disc only. |

**Accent, favourite, text**

| Role | Dark | Light | Use |
|---|---|---|---|
| accent | `#78C4FF` Ice | `#00658A` Deep ice | Video kind, "Downloaded" glyph, info, downloads count dot. Small roles only, never a large fill. |
| onAccent | `#180A2E` | `#FFFFFF` | On accent fills (count dot). |
| favorite | `#FF66B8` Flare | `#B5166B` | Hearts only (filled heart = on). |
| textPrimary | `#F6F2FF` | `#180A2E` | Titles, body. |
| textSecondary | `#C6BBDF` | `#4C4358` | Metadata, secondary icons, all text on artwork tints and the stage. |
| textMuted | `#A698C4` | `#655B71` | Captions, hints, durations in rows, unselected labels. Never on artwork tints or the stage. |

**Lines and focus**

| Role | Dark | Light | Use |
|---|---|---|---|
| divider | `#382A5C` | `#E4DACA` | Decorative hairlines, card edges (1dp). Never the only boundary of a control. |
| outlineVariant | `#382A5C` | `#E4DACA` | = divider (M3 slot). |
| outline | `#8E7EB4` | `#8A7F6B` | Control borders (outlined button, unselected light chip, switch off), drag handles, section rules. 3:1 or more on every surface. |
| rule | `#8E7EB4` | `#8A7F6B` | The 2dp rule above section kickers (= outline). |
| focusRing | `#CCFF3A` | `#5A32D6` | 2dp keyboard/D-pad focus outline. |
| dragHandle | `#8E7EB4` | `#8A7F6B` | Sheet handle, queue reorder handle. |

**States**

| Role | Dark | Light | Use |
|---|---|---|---|
| success | `#5CF0A8` | `#0B7446` | Saved / complete. Always with a check icon. |
| warning | `#FFC44D` | `#8A5500` | Queued, low storage, slow network. Always with an icon. |
| error | `#FF8A5C` coral | `#BE1E3E` crimson | Failed, destructive rows, field errors. Always icon + text. |
| onError | `#180A2E` | `#FFFFFF` | On error fills. |
| errorContainer | `#40192C` | `#FBE3E6` | Error banners, destructive tonal buttons. |
| onErrorContainer | `#FFDCCF` | `#5E0A1E` | Text on errorContainer. |
| liveFill | `#BE1E3E` | `#BE1E3E` | Solid LIVE chip (replaces the red dot, which measured 2.89 on the chip). |
| onLive | `#FFFFFF` | `#FFFFFF` | "LIVE" label. |

**Scrims, glass and overlays**

| Role | Dark | Light | Use |
|---|---|---|---|
| scrim | `#CC09050F` | `#99180A2E` | Behind sheets and dialogs. Stage veil uses the dark value. |
| glass | `#E022123E` | `#E0FFFCF6` | Scrolled-under app bars (blur 24); light YouTube toolbar. |
| overlay | `#B8180A2E` | same | Ink at 72% behind badges on images and video frames. |
| onOverlay | `#FFFFFF` | same | Text on overlay chips. |

**Ink Dock (identical in both themes)**

| Role | Dark | Light | Use |
|---|---|---|---|
| dock | `#F01C0E36` | same | Mini player + nav fill (94%), backdrop blur 24. |
| onDock | `#F6F2FF` | same | Dock titles, selected nav label, controls. |
| onDockMuted | `#B4A8CF` | same | Artist line, unselected nav icon and label. |
| dockLine | `#3E2E62` | same | 1dp top line, mini-player progress track. |
| navIndicator | `#CCFF3A` | same | 56x32 selected-tab pill. |
| onNavIndicator | `#180A2E` | same | Filled icon in the pill. |

**Controls and depth**

| Role | Dark | Light | Use |
|---|---|---|---|
| sliderActive | `#CCFF3A` | `#5A32D6` | Active track (6dp). |
| sliderInactive | `#382664` | `#DDD3C0` | Inactive track (4dp). |
| sliderThumb | `#F6F2FF` | `#5A32D6` | 14dp thumb (20dp while dragging). |
| snackbar | `#2B1A50` | `#180A2E` | Snackbar and tooltip fill (light: ink, matching the dock). |
| onSnackbar | `#F6F2FF` | `#F6F2FF` | Snackbar text. |
| snackbarAction | `#CCFF3A` | `#CCFF3A` | Snackbar action (both sit on a dark fill). |
| shadow | none | `#1A180A2E` | Light only: sheets, dialogs, menus, snackbars (0 8 24). |
| printShadow | `#CCFF3A` | `#180A2E` | Hard 6x6dp offset, no blur, under hero and stage covers. |

### 2.3 ColorScheme mapping (both themes, from the palette)

| ColorScheme | From |
|---|---|
| brightness | dark / light |
| primary, onPrimary, primaryContainer, onPrimaryContainer | same-named roles |
| secondary, onSecondary | accent, onAccent |
| secondaryContainer, onSecondaryContainer | same-named roles |
| tertiary, onTertiary | favorite; `#180A2E` (dark) / `#FFFFFF` (light) |
| error, onError, errorContainer, onErrorContainer | same-named roles |
| surface, onSurface, onSurfaceVariant | surface, textPrimary, textSecondary |
| surfaceContainerLowest / Low / (default) / High / Highest | background / surface / surface / surfaceElevated / surfaceElevated (as today) |
| surfaceTint | `Colors.transparent` |
| outline, outlineVariant | outline, outlineVariant |
| shadow, scrim | `#000000` (dark) / `#180A2E` (light); scrim |
| inverseSurface, onInverseSurface, inversePrimary | dark: `#F6F2FF`, `#180A2E`, `#5A32D6` · light: `#180A2E`, `#F6F2FF`, `#CCFF3A` |

---

## 3. Gradients

All gradients run `topLeft → bottomRight` unless stated.

**heroGradient** (detail headers, Home top band, empty-state band)

| | Stops | Notes |
|---|---|---|
| Dark | `#421E78 → #25133F → #180A2E` | Ultraviolet bloom melting into ink. Brightest stop still gives textMuted 4.68. |
| Light | `#E6DAFF → #F1EAF2 → #F7F2E8` | Lavender wash fading into paper (replaces the proposal's lime wash, which read sallow). |

Items **with** a real cover use the brand hero. Items **without** a cover tint the hero and the stage with their own
artwork pair (see `ArtworkTint` below), so per-song colour survives.

**primaryGradient**: same in both themes, `#DAFF63 → #B4EE14`, a subtle Volt sheen for `VoltButton` and `VoltSlab`. Ink
label 16.46 / 13.53. On paper it always carries the 1.5dp ink edge.

**Artwork gradients**: 8 pairs, picked per item by uri hash as today. White glyph at 85%. The top stop is identical in
both themes so an item keeps its colour when the phone switches theme; on paper the deep stop is lifted one step so tiles
look like objects, not holes.

| # | Name | Top stop (both) | Deep stop, dark | Deep stop, light |
|---|---|---|---|---|
| 1 | ultraviolet | `#7A4BF0` | `#240F5C` | `#3A1E86` |
| 2 | ice | `#1C86B0` | `#0A2848` | `#0E3F6A` |
| 3 | flare | `#C93A8C` | `#460E38` | `#6A1654` |
| 4 | moss | `#567A0C` | `#192506` | `#2A3C08` |
| 5 | ember | `#C8502F` | `#4A1320` | `#6E1D2C` |
| 6 | cobalt | `#4363E0` | `#131D58` | `#1F2C82` |
| 7 | orchid | `#A042C4` | `#33104C` | `#4E1A72` |
| 8 | jade | `#12806E` | `#062E2B` | `#0A4842` |

White glyph at 85%: top stops 3.44 (ice) to 4.19, floor 3. Midpoints 6.18 to 7.21 in dark and 5.32 to 6.22 in light,
floor 4.5. Full white on deep stops 10.40 or more. Volt itself is never a cover colour (a white glyph on lime fails).

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

Computed with `C:/Users/NIRANJ~1.KAT/AppData/Local/Temp/claude/74ef1ad76cd92579/a5efaf5b-88c3-4c58-bb08-e9db94fe4afd/scratchpad/design_dir/final/contrast_final.py`
(palette in `palette_final.py`, full output in `contrast_final_report.md` in that folder; run with `python -I contrast_final.py`).

- Method: WCAG 2.x relative luminance. Alpha colours are composited over the named backdrop first. Flutter's
  `Color.lerp` is reproduced for tints. Colour vision uses Machado 2009 at full severity, compared in CIEDE2000.
- Floors: text 4.5:1 on every surface it can sit on; large text, icons and control boundaries 3:1; labels on fills 4.5:1.
- **Result: 0 failures in either theme.**
- The scratch folder can be cleared, so port these checks into `test/unit/palette_contrast_test.dart` (section 10).

| Pair | Need | Dark | Light |
|---|---|---|---|
| textPrimary on background / surface / surfaceElevated / surfacePressed | 4.5 | 17.00 / 15.57 / 13.95 / 11.70 | 16.78 / 18.28 / 18.72 / 14.80 |
| textPrimary on glass over a white / black page | 4.5 | 10.98 / 16.12 | 18.29 / 13.82 |
| textSecondary on the four surfaces | 4.5 | 10.32 / 9.46 / 8.47 / 7.10 | 8.36 / 9.11 / 9.33 / 7.38 |
| textSecondary on glass over white / black | 4.5 | 6.67 / 9.79 | 9.12 / 6.89 |
| textMuted on the four surfaces | 4.5 | 7.05 / 6.46 / 5.79 / 4.85 | 5.72 / 6.24 / 6.39 / 5.05 |
| textMuted on glass over white / black | 4.5 | 4.56 / 6.69 | 6.24 / 4.71 |
| primary on the four surfaces | 4.5 | 15.99 / 14.65 / 13.12 / 11.01 | 6.58 / 7.17 / 7.34 / 5.80 |
| primary on glass over white / black | 4.5 | 10.33 / 15.16 | 7.17 / 5.42 |
| accent as text on the four surfaces | 4.5 | 9.93 / 9.10 / 8.15 / 6.84 | 5.83 / 6.35 / 6.50 / 5.14 |
| favorite as text on the four surfaces | 4.5 | 6.99 / 6.41 / 5.74 / 4.81 | 5.72 / 6.23 / 6.38 / 5.04 |
| success as text on the four surfaces | 4.5 | 12.91 / 11.83 / 10.60 / 8.89 | 5.23 / 5.70 / 5.83 / 4.61 |
| warning as text on the four surfaces | 4.5 | 11.82 / 10.83 / 9.70 / 8.13 | 5.57 / 6.07 / 6.21 / 4.91 |
| error as text on the four surfaces | 4.5 | 8.06 / 7.39 / 6.62 / 5.55 | 5.46 / 5.95 / 6.10 / 4.82 |
| onPrimary on primary / primaryPressed | 4.5 | 15.99 / 11.53 | 7.34 / 9.65 |
| onVoltFill on voltFill / voltPressed / primaryGradient[0] / [1] | 4.5 | 15.99 / 11.53 / 16.46 / 13.53 | same |
| onVoltMuted on voltFill / voltPressed / primaryGradient[1] | 4.5 | 8.50 / 6.13 / 7.20 | same |
| Volt glyph on the ink disc (Continue card) | 4.5 | 15.99 | 15.99 |
| onSecondaryContainer on secondaryContainer (tonal) | 4.5 | 12.08 | 9.47 |
| primary on primaryContainer | 4.5 | 11.71 | 5.84 |
| onAccent on accent | 4.5 | 9.93 | 6.50 |
| onError on error | 4.5 | 8.06 | 6.10 |
| onErrorContainer / error on errorContainer | 4.5 | 11.76 / 6.49 | 11.20 / 5.00 |
| onLive on liveFill | 4.5 | 6.10 | 6.10 |
| onSnackbar / snackbarAction on snackbar | 4.5 | 13.95 / 13.12 | 17.00 / 15.99 |
| PillTag text on its own colour at 14% (surface / elevated): primary | 4.5 | 10.42 / 9.22 | 5.68 / 5.83 |
| ... accent | 4.5 | 6.94 / 6.13 | 5.14 / 5.24 |
| ... favorite | 4.5 | 5.15 / 4.58 | 4.93 / 5.02 |
| ... success | 4.5 | 8.81 / 7.80 | 4.66 / 4.75 |
| ... warning | 4.5 | 8.06 / 7.14 | 4.93 / 5.06 |
| ... error | 4.5 | 5.86 / 5.21 | 4.73 / 4.82 |
| outline on the four surfaces | 3 | 5.16 / 4.73 / 4.24 / 3.56 | 3.53 / 3.85 / 3.94 / 3.12 |
| focusRing on the four surfaces | 3 | 15.99 / 14.65 / 13.12 / 11.01 | 6.58 / 7.17 / 7.34 / 5.80 |
| sliderActive vs sliderInactive / thumb vs surface | 3 | 11.01 / 15.57 | 4.95 / 7.17 |
| Volt fill as a shape on background / surface / elevated (dark) | 3 | 15.99 / 14.65 / 13.12 | - |
| voltEdge (ink) on background / surface / white / Volt (light) | 3 | - | 16.78 / 18.28 / 18.72 / 15.99 |
| primary / accent glyph on the tonal tile | 3 | 11.71 / 7.27 | 5.84 / 5.18 |
| empty-state icon on its 28% halo | 3 | 7.39 | 4.17 |
| textPrimary on hero stops [0] / [1] / [2] | 4.5 | 11.29 / 15.33 / 17.00 | 14.12 / 15.86 / 16.78 |
| textSecondary on hero stops | 4.5 | 6.85 / 9.31 / 10.32 | 7.04 / 7.90 / 8.36 |
| textMuted on hero stops | 4.5 | 4.68 / 6.36 / 7.05 | 4.82 / 5.41 / 5.72 |
| primary on hero stops | 4.5 | 10.62 / 14.42 / 15.99 | 5.53 / 6.22 / 6.58 |
| onDock on dock over a white page / black page / background | 4.5 | 14.24 / 16.59 / 16.36 | 14.24 / 16.59 / 14.39 |
| onDockMuted on dock (same backdrops) | 4.5 | 7.05 / 8.22 / 8.10 | 7.05 / 8.22 / 7.13 |
| Volt indicator / play disc vs dock (same backdrops) | 3 | 13.39 / 15.60 / 15.39 | 13.39 / 15.60 / 13.53 |
| Ice count dot vs dock / ink count on the dot | 3 / 4.5 | 8.32 or more / 9.93 | same |
| Volt progress vs dockLine | 3 | 10.12 | 10.12 |
| Stage textPrimary / textSecondary on the veil over a white glow (worst case) | 4.5 | 10.60 / 6.44 | same (stage is dark) |
| Stage Volt (seek, play disc) on the veil over white | 3 | 9.97 | same |
| onOverlay on overlay over a white / Volt / yellow / black frame | 4.5 | 7.76 / 8.66 / 8.31 / 19.51 | same |
| Ice glyph (MediaBadge) on overlay, same frames | 3 | 4.12 / 4.59 / 4.41 / 10.35 | same |
| Volt resume line on its overlay track over white / black | 3 | 6.63 / 16.66 | same |
| White glyph 85% on artwork top stops (8) | 3 | min 3.44 | min 3.44 |
| White glyph 85% on artwork midpoints (8) | 4.5 | min 6.18 | min 5.32 |
| textPrimary / textSecondary / textMuted / primary on surfaceGradient s0, s1 (8 hues) | 4.5 | min 14.77 / 8.97 / 6.13 / 13.89 | min 13.67 / 6.81 / 4.66 / 5.36 |

Not pass/fail, but worth knowing:

- **Volt fill on paper is 1.05:1**, hence the mandatory ink edge.
- **Tonal fills against the canvas** are 1.37 (dark) and 1.13 (light). They are identified by their label, as every M3
  tonal button is.
- **The inactive slider track** is 1.33 against its canvas. The active part is 2dp taller (6 vs 4), and time labels mark both ends.

**Colour-vision separation** (smallest CIEDE2000 between any two of primary, accent, favourite, success, warning, error):

| | Normal | Deutan | Protan | Tritan |
|---|---|---|---|---|
| Dark | 22.0 (primary/success) | 6.3 (primary/warning) | 10.8 (primary/warning) | 6.5 (favourite/error) |
| Light | 14.2 (favourite/error) | 7.2 (warning/error) | 8.5 (accent/favourite) | 6.2 (accent/success) |

Key pairs (normal / deutan / protan / tritan):

- Dark favourite/error: 32.3 / 30.6 / 40.2 / 6.5 (was 13.1 / - / - / 4.0).
- Light primary/warning: 56.1 / 61.7 / 59.2 / 42.4 (Moss was 27.9 / 3.0 / 3.2 / 37.7).
- Light primary/error: 36.0 / 54.9 / 40.1 / 51.9 (Moss was 7.1 under deuteranopia).

Every remaining close pair is covered by the rule "state = icon + text, never colour alone".

**Brand distance** (OKLab dE x100, nearest competitor):

- Volt: Spotify in-app green 18.7.
- Ice: Amazon Music 8.9, so small roles only.
- Ultraviolet `#5A32D6`: Deezer 14.6.
- Flare: Apple Music 14.9, hearts only.
- Icon field `#421E78`: Deezer 28.5.
- Canvas vs black: 20.2 (Spotify's `#121212`: 18.2).

---

## 5. Fonts

All five families are SIL OFL 1.1 with no Reserved Font Name (checked in each `OFL.txt` header). All are bundled, with
no runtime fetching. Every URL below answered **HTTP 200** to `curl -I` on 2026-11-17 (sizes are the reported
`Content-Length`).

| Family (pubspec name) | Role | Files to put in `assets/fonts/` | Source (HTTP 200, bytes) | Static or variable |
|---|---|---|---|---|
| **Unbounded** (`Unbounded`) | App-authored headings: `display`, `sectionTitle` | `Unbounded-SemiBold.ttf` (600), `Unbounded-Bold.ttf` (700) | `https://raw.githubusercontent.com/googlefonts/unbounded/main/fonts/ttf/Unbounded-SemiBold.ttf` (501,444); `.../Unbounded-Bold.ttf` (507,828) | Static. No FontVariation. |
| **Anek Devanagari**, pinned to SemiExpanded (`AnekWide`) | Every user-content title (`greeting`, `screenTitle`, `playerTitle`, `cardTitle`); Devanagari fallback of Unbounded | `AnekDevanagariWide-SemiBold.ttf` (600), `AnekDevanagariWide-Bold.ttf` (700) | Variable source `https://raw.githubusercontent.com/google/fonts/main/ofl/anekdevanagari/AnekDevanagari%5Bwdth,wght%5D.ttf` (2,190,532; axes wdth 75-125, wght 100-800; subsets devanagari, latin, latin-ext) | Static instances built once (below) and committed. No FontVariation. |
| **Atkinson Hyperlegible Next** (`AtkinsonNext`) | All reading text: `body`, `bodyStrong`, `metadata`, `label`, `chipLabel`, `button`, `caption`. Replaces Inter. | `AtkinsonHyperlegibleNext-Regular.ttf` (400), `-Medium.ttf` (500), `-SemiBold.ttf` (600), `-Bold.ttf` (700) | `https://raw.githubusercontent.com/googlefonts/atkinson-hyperlegible-next/main/fonts/ttf/AtkinsonHyperlegibleNext-Regular.ttf` (65,068), `...-Medium.ttf` (67,080), `...-SemiBold.ttf` (66,680), `...-Bold.ttf` (66,792) | Static. No FontVariation. |
| **Mukta** (`Mukta`) | Devanagari fallback for AtkinsonNext and DMMono | `Mukta-Regular.ttf` (400), `Mukta-Medium.ttf` (500), `Mukta-SemiBold.ttf` (600), `Mukta-Bold.ttf` (700) | `https://raw.githubusercontent.com/google/fonts/main/ofl/mukta/Mukta-Regular.ttf` (432,248), `.../Mukta-Medium.ttf` (419,736), `.../Mukta-SemiBold.ttf` (411,160), `.../Mukta-Bold.ttf` (418,416) | Static. No FontVariation. |
| **DM Mono** (`DMMono`) | `tabularFigures`, `index`, `overline`, `badge`, `figureLarge`; Diagnostics log text (replaces the `monospace` family in `diagnostics_screen.dart`) | `DMMono-Regular.ttf` (400), `DMMono-Medium.ttf` (500) | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmmono/DMMono-Regular.ttf` (49,744), `.../DMMono-Medium.ttf` (50,360) | Static. No FontVariation. |

Licences go to `assets/fonts/licenses/`, one per family:

| File | Source (HTTP 200) |
|---|---|
| `Unbounded-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/unbounded/OFL.txt` |
| `AnekDevanagari-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/anekdevanagari/OFL.txt` |
| `AtkinsonHyperlegibleNext-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/atkinsonhyperlegiblenext/OFL.txt` |
| `Mukta-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/mukta/OFL.txt` |
| `DMMono-OFL.txt` | `https://raw.githubusercontent.com/google/fonts/main/ofl/dmmono/OFL.txt` |

Register each in `main()` with `LicenseRegistry.addLicense` so they appear on the licences page. Then delete
`Inter-*.otf` and Inter's `OFL.txt`.

Variable alternatives, if ever wanted (all HTTP 200):

- `https://raw.githubusercontent.com/google/fonts/main/ofl/unbounded/Unbounded%5Bwght%5D.ttf` (778,272)
- `https://raw.githubusercontent.com/google/fonts/main/ofl/atkinsonhyperlegiblenext/AtkinsonHyperlegibleNext%5Bwght%5D.ttf` (114,552)

Flutter's `fontWeight` does not drive a variable font's `wght` axis. A variable file needs
`fontVariations: [FontVariation.weight(n)]` (and `FontVariation('wdth', 112.5)` for Anek) on every style. Those
variations also apply to the fallback fonts of that style, which is why this spec ships static files only.

**Building the Anek statics** (once, on any machine with Python; commit the outputs and this command in
`tools/fonts/README.md`):

```sh
pip install fonttools
fonttools varLib.instancer "AnekDevanagari[wdth,wght].ttf" wdth=112.5 wght=600 -o AnekDevanagariWide-SemiBold.ttf
fonttools varLib.instancer "AnekDevanagari[wdth,wght].ttf" wdth=112.5 wght=700 -o AnekDevanagariWide-Bold.ttf
```

`--update-name-table` is optional. Flutter registers fonts by the pubspec family, not the internal name, so omit the flag
if it complains about a missing STAT entry. Measure the output sizes and record them in `DECISIONS.md`; they were not
measured here (estimate 0.5-0.9 MB each).

**Optional size cuts** (pyftsubset ships with fonttools; write to a build folder, then copy over):

- Unbounded to Latin, about 500 KB down to about 80 KB each:
  `pyftsubset Unbounded-Bold.ttf --unicodes="U+0000-024F,U+2000-206F,U+20B9,U+2122,U+2190-2199,U+2212" --layout-features='*' --output-file=out/Unbounded-Bold.ttf`
- Mukta to Devanagari plus ASCII (Latin comes from Atkinson), about 40% smaller:
  `pyftsubset Mukta-Regular.ttf --unicodes="U+0020-007E,U+00A0,U+0900-097F,U+1CD0-1CFF,U+200B-200D,U+20B9,U+25CC,U+A8E0-A8FF" --layout-features='*' --output-file=out/Mukta-Regular.ttf`
- Leave Anek as instanced: it carries only Latin and Devanagari, and both are needed.

Payload, measured where the file exists and estimated for Anek:

| | Before subsetting | After subsetting |
|---|---|---|
| Unbounded (2 files) | 1.01 MB | about 0.16 MB |
| Anek instances (2 files) | estimate 1.0-1.8 MB (0.5-0.9 MB each) | same |
| Mukta (4 files) | 1.68 MB | about 1.0 MB |
| Atkinson (4 files) | 0.27 MB | 0.27 MB |
| DM Mono (2 files) | 0.10 MB | 0.10 MB |
| **Total** | **about 4-5 MB** | **about 2.5-3.3 MB** |

Removing Inter's OTFs offsets part of this.

**Devanagari strategy**

1. User-content titles use Anek, which draws Latin and Devanagari in one design, so a Nepali title never switches font
   mid-heading.
2. App-authored headings use Unbounded with `fontFamilyFallback: ['AnekWide']`. Anek is the same width class, so a
   Nepali word inside a static heading (the Home greeting, a translated label later) still matches.
3. Reading text uses Atkinson with `fontFamilyFallback: ['Mukta']`. Mukta was chosen over Anek here because it is
   built for text sizes and is widely used on Nepali sites.
4. DM Mono also falls back to Mukta.
5. Every style sets `leadingDistribution: TextLeadingDistribution.even`.
6. User-content styles use `letterSpacing: 0`, because tracking breaks the shirorekha (headline bar) and collides
   conjuncts.
7. Line heights stay at 1.33 or more wherever Devanagari can appear.
8. File-style names go through the existing `breakableTitle()` (`lib/core/utils/formatters.dart`) for display, so
   `Audit_Long_Tone_5min` wraps at underscores. Semantics labels keep the original.

**pubspec.yaml**

```yaml
  fonts:
    - family: Unbounded
      fonts:
        - { asset: assets/fonts/Unbounded-SemiBold.ttf, weight: 600 }
        - { asset: assets/fonts/Unbounded-Bold.ttf, weight: 700 }
    - family: AnekWide
      fonts:
        - { asset: assets/fonts/AnekDevanagariWide-SemiBold.ttf, weight: 600 }
        - { asset: assets/fonts/AnekDevanagariWide-Bold.ttf, weight: 700 }
    - family: AtkinsonNext
      fonts:
        - { asset: assets/fonts/AtkinsonHyperlegibleNext-Regular.ttf, weight: 400 }
        - { asset: assets/fonts/AtkinsonHyperlegibleNext-Medium.ttf, weight: 500 }
        - { asset: assets/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf, weight: 600 }
        - { asset: assets/fonts/AtkinsonHyperlegibleNext-Bold.ttf, weight: 700 }
    - family: Mukta
      fonts:
        - { asset: assets/fonts/Mukta-Regular.ttf, weight: 400 }
        - { asset: assets/fonts/Mukta-Medium.ttf, weight: 500 }
        - { asset: assets/fonts/Mukta-SemiBold.ttf, weight: 600 }
        - { asset: assets/fonts/Mukta-Bold.ttf, weight: 700 }
    - family: DMMono
      fonts:
        - { asset: assets/fonts/DMMono-Regular.ttf, weight: 400 }
        - { asset: assets/fonts/DMMono-Medium.ttf, weight: 500 }
```

`ThemeData(fontFamily: 'AtkinsonNext', fontFamilyFallback: const ['Mukta'], ...)`.

---

## 6. Type scale

`AppTypography.of(AppPalette p)` builds every style with the palette's colours; `AppTypography.textTheme(p)` maps them
onto M3. Height is Flutter's multiplier (line px / size). U = Unbounded (fallback AnekWide), A = AnekWide (fallback
AtkinsonNext), T = AtkinsonNext (fallback Mukta), M = DMMono (fallback Mukta).

| Role | Family | Size / line | Weight | letterSpacing | height | Case | Default colour | M3 slot | Used for |
|---|---|---|---|---|---|---|---|---|---|
| display | U | 32 / 40 | 700 | -0.5 | 1.25 | Sentence | textPrimary | displaySmall | Tab mastheads only: "Music", "Videos", "Online", "Downloads", "Settings". App strings, one line. |
| greeting (new) | A | 30 / 42 | 700 | 0 | 1.40 | As written | textPrimary | headlineLarge | Home: "नमस्ते" (always), with "Good evening" etc. under it in `body`/textSecondary. |
| screenTitle | A | 24 / 34 | 700 | 0 | 1.4167 | As written | textPrimary | headlineMedium | App bar titles, album/artist/playlist headers, video title on the watch screen. Max 2 lines. |
| playerTitle | A | 22 / 30 | 600 | 0 | 1.3636 | As written | textPrimary | titleMedium | Now Playing title, video player title. Max 2 lines + ellipsis, through `breakableTitle()`. |
| cardTitle (new) | A | 20 / 28 | 700 | 0 | 1.40 | As written | onVoltFill / textPrimary | headlineSmall | Continue-listening slab, hero tiles. 1-2 lines. |
| sectionTitle | U | 18 / 26 | 600 | 0 | 1.4444 | Sentence | textPrimary | titleLarge | "Recently played", sheet and dialog titles (app strings only; put user content in the body). |
| body | T | 16 / 24 | 400 | 0 | 1.50 | Sentence | textPrimary | bodyLarge | Paragraphs, sheet rows, dialog body, inputs. (Was 15.) |
| bodyStrong | T | 16 / 24 | 600 | 0 | 1.50 | As written | textPrimary | titleSmall | Song/video titles in rows. Mini player uses 15/20. |
| metadata | T | 14 / 20 | 400 | 0 | 1.4286 | As written | textSecondary | bodyMedium | "Artist · Album", "Channel · 1.2 GB". (Was 13.) |
| label | T | 12 / 16 | 600 | 0.2 | 1.3333 | Sentence | textMuted | labelMedium | Nav labels, form labels. App strings only. |
| chipLabel (new) | T | 14 / 20 | 600 | 0 | 1.4286 | As written | textPrimary | (chipTheme) | Chips (may carry artist names). |
| button | T | 15 / 20 | 700 | 0.15 | 1.3333 | Sentence, never caps | from button | labelLarge | Every button label. |
| caption | T | 12 / 16 | 400 | 0 | 1.3333 | Sentence | textMuted | bodySmall | Helper, error and empty-state fine print, tooltips. (Was 11.) |
| tabularFigures | M | 13 / 18 | 500 | 0 | 1.3846 | - | textSecondary | - | Seek times "1:23" / "-2:41", durations, sizes, %, speeds. `fontFeatures: [FontFeature.tabularFigures()]`. In a meta line, use a `TextSpan` at 14. |
| index (new) | M | 13 / 18 | 500 | 0 | 1.3846 | - | textMuted | - | Track numbers "01 02 03"; the playing row shows `primary`. |
| overline (new) | M | 11 / 16 | 500 | 1.1 | 1.4545 | UPPERCASE | textSecondary or primary | labelSmall | Kickers: "NOW PLAYING · 3 / 24", "FROM YOUR LIBRARY", "3 ACTIVE · 1.2 GB FREE". App strings only, never user content. |
| badge (new) | M | 12 / 16 | 500 | 0.2 | 1.3333 | Codes in caps | onOverlay | - | Duration badge, "1080P", "MP3", "LIVE", PillTag. Replaces `_overlayTextStyle`. |
| figureLarge (new) | M | 28 / 32 | 500 | -0.5 | 1.1429 | Digits only | textPrimary | - | Download %, storage totals, sleep-timer countdown. |

Rules:

- **Unbounded** is never used below 18, in list rows, or for any string that came from a file, tag, URL or person.
  **Anek** is never used below 20.
- **Text scale.** Layouts must hold at `textScaler` 1.3 on a 320 and a 360dp phone without clipping. Rows use
  `minHeight`, not a fixed height, so they grow beyond 1.3. Keep the existing `line(style)` height helpers; they read
  these styles.
- **Atkinson Hyperlegible Next** keeps I / l / 1 and O / 0 apart. Do not swap it for a "nicer" geometric sans in rows.

---

## 7. Components

### 7.1 Shape, spacing, depth, motion (both themes)

- **Grid:** 4dp. Phone gutter 16, tablet (600dp or wider) 24. Section header padding 24 top / 8 bottom. Card padding 16.
  Row gap between art and text 12; between stacked text lines 2. Chip gaps 8. Scrolling content ends with a bottom
  padding of Ink Dock height (64 mini + 64 nav + system inset) + 16.
- **Radii** (`AppSpacing`):

  | Radius | Applies to |
  |---|---|
  | `radiusBadge` 6 | Overlay chips, PillTag |
  | `radiusArtSmall` 10 | Art 56dp and smaller |
  | `radiusThumb` 14 | Thumbnails, tiles, grid covers |
  | `cardRadius` 20 (was 18) | Cards, Continue slab |
  | `radiusMenu` 16 | Popup menus, form fields, snackbars |
  | `radiusSheet` 28 | Sheets (top corners), dialogs |
  | `radiusCover` 24 | Now Playing cover |
  | Stadium | Every button, chip, search field, nav indicator and play disc. `buttonRadius` is retired. |
- **Touch:** 48dp minimum target everywhere, including 36dp chips (`materialTapTargetSize: padded`). Icons are Material
  Symbols Rounded at 24dp, filled when selected or on.
- **Depth:**
  - Dark: tone steps plus 1dp `divider` card edges. No shadows, no glows except `voltGlow` under the 72dp stage play
    disc.
  - Light: 1dp `divider` hairline on cards, and `shadow` (0 8 24, `#1A180A2E`) only on sheets, dialogs, menus and
    snackbars.
  - Both: the signature **print offset**, a hard `BoxShadow(offset: Offset(6, 6), blurRadius: 0, color: printShadow)`
    with the cover's radius. It is used only under the detail-header cover and the Now Playing cover (Volt on ink,
    ink on paper).
- **Motion** (`MotionTokens`, everything through `MotionTokens.duration`, so reduced motion means 0ms):

  | Duration | What |
  |---|---|
  | 120ms `easeOut` | Press feedback (Volt widgets scale to 0.97) |
  | 160ms | Play/pause icon morph |
  | 240ms | Page transitions (FadeForwards on Android, Cupertino on iOS); nav indicator slide with new `MotionTokens.emphasized = Cubic(0.05, 0.7, 0.1, 1.0)` |
  | 280ms | Sheets; mini player → Now Playing container transform |
  | 600ms | Tint drift (`ambient`) |

  The equaliser animates only while playing. Nothing pulses.

### 7.2 Buttons

**Theme rule:** `filledButtonTheme` sets shape, size and text style but **no colours**. FilledButton then takes
`primary`/`onPrimary` and FilledButton.tonal takes `secondaryContainer`/`onSecondaryContainer`, as the current comment in
`app_theme.dart` requires.

| Kind | Dark | Light | Shape and size |
|---|---|---|---|
| **VoltButton** (new `ui_kit`). The "play" and "get" actions: Play all, Download, Save offline, Fetch link. | primaryGradient fill, ink label, no edge | Same fill + 1.5dp ink `voltEdge` | Stadium, 52dp (40dp `compact` in toolbars), 20dp leading icon, `button` text, 24 horizontal padding. Pressed: `voltPressed` + scale 0.97. Disabled: surfacePressed fill, textMuted label (light keeps an `outline` edge). |
| FilledButton (other primary actions: Save, Retry, dialog confirm) | Volt fill, ink label | Ultraviolet fill, white label | Stadium, 48dp, M3 state layer for pressed. |
| FilledButton.tonal (Shuffle, Add to queue, Listen) | `#33225E` / `#D9FF73` | `#EAE1FF` / `#38189A` | Stadium, 48dp. |
| OutlinedButton (Add to playlist, Copy link, PiP) | 1.5dp `outline`, textPrimary label | same roles | Stadium, 48dp (40 compact). |
| TextButton (See all, Cancel) | `primary` label | `primary` label | Stadium, 12 horizontal padding (`SectionHeader.actionStyle`). |
| Destructive | TextButton in `error`, or tonal `errorContainer`/`onErrorContainer`. Always followed by a confirm dialog. | same | - |
| IconButton | 48dp target, 24 glyph, textPrimary (secondary actions textSecondary), highlight `primaryBase` 12% | same | Circle. |
| **VoltDisc** (new `ui_kit`) | Volt circle, ink glyph | + ink edge | Sizes: 44 (mini player, 24 glyph), 56 (detail hero, 28), 72 (stage, 36 glyph + `voltGlow`). |

**Toggles** (shuffle, repeat, background play):

- On = `primary` glyph plus a 4dp `primary` dot 2dp below it. Off = textPrimary glyph, no dot. Repeat-one uses the
  `repeat_one` glyph.
- **Favourite:** outline heart (textSecondary) becomes a filled heart in `favorite`, and the label/semantics toggle.

### 7.3 Chips

- Size: 36dp tall inside a 48dp target. Stadium, 14 horizontal padding, `chipLabel`.
- Unselected: dark `surfaceElevated` with no border; light `surface` with a 1dp `outline` border.
- **Selected (both themes): Volt fill, ink label, 18dp ink check** (`showCheckmark: true`, so state never depends on
  colour). Light adds the 1.5dp ink edge (`side` via `WidgetStateBorderSide`).
- Set it in `chipTheme` with a `WidgetStateColor` label colour.
- Filter rows scroll horizontally with 16 gutters.

### 7.4 Cards

- **SurfaceCard:** `surface` fill, radius 20, 1dp `divider` edge, padding 16. Pressed: `surfacePressed` (InkWell
  highlight). Tinted cards take `ArtworkTint.surfaceGradient` (section 3).
- **VoltSlab, the Continue-listening card** (new `ui_kit`, Home top). It is the one loud brand block on the home screen.

  | Part | Spec |
  |---|---|
  | Fill | primaryGradient, radius 20, padding 16; light adds the ink edge |
  | Overline | "CONTINUE LISTENING", `overline` in onVoltMuted |
  | Title | `cardTitle` in ink, 1 line (2 at large text), through `breakableTitle()` |
  | Artist / time left | `metadata` in onVoltMuted |
  | Play button | Trailing 48dp ink disc with a Volt play glyph |
  | Progress | 3dp ink line on ink-20% track, 8dp above the bottom edge |
  | Gestures | Tap = resume; long-press = media sheet |

### 7.5 Section headers

`SectionHeader` gains an optional `kicker`, top to bottom:

1. A 2dp `rule` line across the gutter.
2. 12dp gap.
3. The kicker in `overline`, coloured `primary`.
4. 4dp gap.
5. The title in `sectionTitle`, with the trailing "See all" TextButton.

Use the rule only on screen-level sections, never inside sheets or cards.

### 7.6 List rows

- **Song row**, 64dp minimum height:
  - Leading: 48dp art at radius 10, or a 32dp `index` column ("01") in album/playlist lists.
  - Middle: `bodyStrong` title (1 line, Mukta for Nepali), then a `metadata` line "Artist · 4:05" with the duration as a
    `tabularFigures` `TextSpan` at 14.
  - Trailing: a 48dp `more_vert` that opens the media sheet.
- **Now-playing row.** Not colour alone, and semantics say "Now playing":
  - A 3dp `primary` bar on the leading edge (12dp inset top and bottom, radius 2).
  - A 3-bar equaliser in Volt on an `overlay` veil over the art. Index lists show it in place of the number.
  - The title in `primary`.
- **Downloaded marker:** a 16dp `download_done` glyph in `accent` before the meta line.
- **Pressed:** surfacePressed. **Selected** (multi-select): primaryContainer fill with a leading check circle.

### 7.7 Ink Dock: nav bar + mini player (dark in both themes)

- **Container:** wrap in `Theme(data: AppTheme.darkTheme)` and an `AnnotatedRegion<SystemUiOverlayStyle>` (section
  8.2). Fill `dock` with `BackdropFilter` blur 24, top corners radius 24, a 1dp `dockLine` top line, and the system
  bottom inset below the nav.
- **Mini player** (top row, 64dp, padding 12 start / 4 end):
  - Art: 44dp at radius 10.
  - Text: title `bodyStrong` 15/20 in onDock, artist 13/18 in onDockMuted, 1 line each.
  - Controls:
    - Previous: 48dp target, 28 glyph.
    - Play/pause: a 44dp **VoltDisc**.
    - Next: 48dp target, 28 glyph.
    - At a queue end with repeat off, previous/next show at 38% and are disabled for semantics.
  - Progress: a 2dp Volt line along the top edge over `dockLine`.
  - Gestures: swipe left/right = next/previous (with `HapticFeedback.selectionClick`), tap or swipe up = Now Playing,
    long-press = media sheet.
  - When the Online tab is playing in the background, the mini player shows the YouTube title, a small accent PillTag
    "YOUTUBE", and play/pause (next only if the page exposes one).
- **Nav** (`NavigationBar`, 64dp + inset, transparent background, `labelBehavior: alwaysShow`):
  - Destinations: Home, Music, Videos, **Online** (replaces "Explore"), Downloads. Settings opens from a Home app-bar
    icon.
  - Selected: a 56x32 Volt `navIndicator` pill with a filled ink icon, and the `label` in onDock.
  - Unselected: outline icon and label in onDockMuted.
  - The indicator slides in 240ms with `MotionTokens.emphasized`.
  - Downloads badge: a 16dp Ice dot with an ink DM Mono count (11/16), shown while downloads are active.

### 7.8 Now Playing (the stage, identical in both themes)

- `Theme(data: AppTheme.darkTheme)`, status bar icons light.
- **Background:** ink plus the item's ArtworkTint backdrop and the existing veil. A real cover gives the neutral
  ultraviolet glow (`#421E78`); a cover-less item gives its own pair. Cross-fade 600ms.
- **Top bar:** chevron-down (48), the kicker "NOW PLAYING · 3 / 24" in `overline`/textSecondary (never textMuted on the
  stage), and `more_vert` (media sheet).
- **Cover:** square, screen width - 32 (max 360), radius 24, with the hard **6x6 Volt print offset**. No soft shadow.
- **Text:** `playerTitle` (2 lines), artist in `body`/textSecondary (1 line), and a 48dp heart (Flare when on).
- **Seek bar** (`SliderTheme`):
  - Track: height 4 (`RoundedRectSliderTrackShape` draws the active part 2dp taller); active Volt, inactive
    `#382664`.
  - Thumb: 14dp `#F6F2FF`, growing to 20dp while dragging, with an 18% Volt overlay.
  - Times: `tabularFigures` in textSecondary, elapsed at the left, remaining "-2:41" at the right.
- **Transport:** shuffle 48 (toggle + dot), previous 56 (36 glyph), **VoltDisc 72** with `voltGlow`, next 56, repeat 48.
- **Footer:** Up next (queue sheet), sleep timer (countdown in `figureLarge` in its sheet; while active, an overline chip
  "SLEEP 12:30" under the title), output/speed, ⋮.
- **Light mode:** nothing changes. The stage is the deliberate always-dark signature. Theme mode only changes the
  sheets that open from it (the queue sheet and media sheet use the app theme).

### 7.9 Video cards and badges

- **Thumbnail:** 16:9 at radius 14.
- **Overlay badges** (`radiusBadge` 6 chips on `overlay`, `badge` type, onOverlay):
  - DurationBadge "12:48" at the bottom right.
  - MediaBadge "Downloaded" with a 16dp Ice glyph at the top left.
  - **LIVE** is a solid `liveFill` chip with white "LIVE". The dot is removed.
- **Resume:** a 3dp Volt line on a 3dp `overlay` track along the thumbnail's bottom edge.
- **Below:** `bodyStrong` title (2 lines), then a `metadata` line (source · size · date) with an accent "VIDEO" PillTag
  only in mixed lists, and a 48dp ⋮.
- **PillTag:** tinted = colour text on colour at 14%, radius 6, `badge` type. Filled = on-colour pairs only:
  voltFill/onVoltFill, accent/onAccent, liveFill/onLive, primary/onPrimary. PillTag gets an `onColor` parameter instead
  of always using onPrimary.
- **Video player:** pure `#000000` stage, controls white on `overlay`, Volt scrubber, PiP and audio-only buttons as today.

### 7.10 Sheets ("media dropdown"), menus, dialogs, snackbars

- **Media sheet**: every ⋮ and long-press on a phone opens a modal bottom sheet.
  - Shell: `surface` fill, top radius 28, a 36x4 `dragHandle` handle, and `scrim` behind; light adds `shadow`.
    Maximum height 90%, scrollable.
  - Header: 56dp art (radius 10), `bodyStrong` title (2 lines, `breakableTitle()`) and a `metadata` line, then a
    `divider`.
  - Rows: 56dp, 24dp textSecondary icon, `body` label.
  - Songs: Play next · Add to queue · Add to playlist… · Favourite (filled Flare heart, label "Remove from
    favourites") · Go to album · Go to artist · Share · Details · divider · **Delete from phone** (`error` icon and
    label, then a confirm dialog).
  - Videos: Play · Play as audio · Picture-in-picture · Save offline (if online) · Share · Details · Delete.
  - Online items: Download · Copy link · Open in Online.
- **Width 600dp or more, or landscape:** a `PopupMenu` anchored to the ⋮ replaces the sheet. `surfaceElevated`,
  radius 16, 1dp `outlineVariant` border, 48dp rows, light `shadow`.
- **Queue sheet**: the same shell. Rows show `index` and a 24dp `dragHandle` reorder grip; the current row gets the 3dp
  `primary` bar.
- **Dialogs:**
  - Shell: `surfaceElevated`, radius 28, padding 24.
  - Title: `sectionTitle`, app strings only, such as "Delete download?".
  - Body: `body`/textSecondary, where user content goes (through `breakableTitle()`).
  - Actions: a TextButton plus a FilledButton confirm, or a TextButton in `error` for destructive confirms.
- **Snackbars:**
  - Floating, radius 16, height 48, 16 start padding.
  - `snackbar` fill with `onSnackbar` body 15/20 text and a `snackbarAction` (Volt) action.
  - Dark adds a 1dp `divider` edge; light adds `shadow`.
  - Bottom margin = Ink Dock height + 8, so they never cover the controls.
- **Tooltips:** `snackbar`/`onSnackbar` fill, `caption` text, radius 8.

### 7.11 Inputs and controls

- **Search field:**
  - Stadium, 48dp. Fill `surfaceElevated` (dark) or `#FFFFFF` with a 1dp `outline` (light).
  - Leading search glyph in textSecondary; hint `body` in textMuted.
  - Focus: a 2dp `focusRing` border. Cursor and selection handles `primary`; selection highlight `primary` at 30%.
- **Form fields:** radius 16, same fill. Error: a 1.5dp `error` border plus a `caption` error line with a 16dp error
  icon.
- **Switch:**

  | State | Dark | Light |
  |---|---|---|
  | On | Volt track, ink thumb with a check icon | Ultraviolet track, white thumb with a check icon |
  | Off | `sliderInactive` track, 1.5dp `outline` border, textMuted thumb | same roles |

- **Checkbox / radio:** `primary` fill with an `onPrimary` mark.
- **Sliders** (volume, speed): `sliderActive` / `sliderInactive` / `sliderThumb`, track 4 (active 6).

### 7.12 Progress and seek bars

- **Linear:** 4dp, stadium ends, `primary` on `surfacePressed`; download rows use the same.
- **Page-load:** 2dp indeterminate `primary` line, no track (Online toolbar).
- **Circular:** 3dp stroke, `primary`.
- **Seek bars:** see Now Playing.
- **Mini player:** 2dp Volt on `dockLine`.
- **Continue slab:** 3dp ink on ink-20%.

### 7.13 Online (YouTube) tab

The app's own chrome around a WebView of `m.youtube.com`. Never recolour the page, never use YouTube's logo or red in
our chrome.

- **Toolbar background:** dark `background` with a 1dp `divider` bottom edge; light `glass` (blur 24) with a
  `divider` edge. Both rows collapse when the page scrolls down and come back on scroll up (like Brave).
- **Row 1, 56dp:**

  | Slot | Spec |
  |---|---|
  | Back, forward | 48dp each. Disabled at 38% with no history. |
  | Address pill | Flexible, 40dp tall, stadium. Fill `surfaceElevated` (dark) or `#FFFFFF` + 1dp `outline` (light). 20dp search glyph and the page title or host in `metadata` textSecondary, 1 line. Tap opens YouTube's own search box (focus the page's search field via JS) or our search sheet. |
  | Reload | 48dp. Becomes "stop" (close glyph) while loading. |
  | ⋮ | Reload · Open Downloads · Background play (switch) · Auto picture-in-picture (switch) · Clear site data (confirm dialog). |

- **Row 2, the "watch strip"** (52dp), shown on `/watch`, `/shorts/` and `/live` URLs:
  - It slides down in 240ms.
  - It is a horizontal list with 16 gutters, 8 gaps, and a 24dp fade at the end hinting more.
  - Items, in priority order:

    | Item | Spec | Result |
    |---|---|---|
    | Download | **VoltButton compact** (40dp, download glyph + "Download") | Sends the canonical URL to Downloads (and the existing format sheet if needed), then snackbar "Sent to Downloads · View". |
    | Copy link | OutlinedButton compact (link glyph + "Copy link") | Copies `https://youtu.be/<id>` (tracking parameters such as `si`, `pp`, `feature` stripped), then snackbar "Link copied". Skip the snackbar on Android 13+, where the system shows its own clipboard confirmation. |
    | Picture-in-picture | OutlinedButton compact (PiP glyph + "PiP") | Enters PiP now. If PiP is off in system settings, snackbar "Picture-in-picture is off · Settings". |
    | Background play | FilterChip toggle; selected = Volt sticker + check | Keeps audio playing with the screen off or the app in the background. |
    | Auto PiP | FilterChip toggle; selected = Volt sticker + check | Enters PiP automatically when leaving the app during a video. |

  - Both toggles are also in ⋮ and in Settings → Online. Defaults: Background play on, Auto PiP on.
- **Loading:** a 2dp `primary` load line under the toolbar.
- **Offline:** an EmptyHint "You're offline" with a Retry button.
- **Platform notes** (not visual, listed so the design works):

  | Platform | Needs |
  |---|---|
  | Android | `android:supportsPictureInPicture="true"` on the activity; a `mediaPlayback` foreground service while background audio plays; `setAutoEnterEnabled` for Auto PiP on Android 12+ |
  | iOS | `UIBackgroundModes: audio`; `AVAudioSession` category `.playback`; `WKWebViewConfiguration.allowsInlineMediaPlayback` and `allowsPictureInPictureMediaPlayback = true` |
  | Both | The media session/notification shows the YouTube title with play/pause |

### 7.14 Downloads screen

- **Header:** `display` "Downloads" plus an `overline` summary ("3 ACTIVE · 1.2 GB FREE").
- **Link input:** a stadium search-style field with a paste IconButton, and a **VoltButton** "Download" under it at
  full width.
- **Rows** (SurfaceCard list):
  - Leading: a 48dp `primaryContainer` tile (radius 14) with a `primary` music glyph or an `accent` video glyph.
  - Title: `bodyStrong` file name through `breakableTitle()`.
  - Progress: a 4dp `primary` bar on `surfacePressed`.
  - Figures: % in `tabularFigures` (textPrimary); speed, size and ETA in `tabularFigures` at 12 (textMuted).
- **States** (icon + text, never colour alone):

  | State | Shown as |
  |---|---|
  | Queued | `warning` schedule icon + "Queued" |
  | Paused | textSecondary pause icon + "Paused" |
  | Saved | `success` check + "Saved" |
  | Failed | `error` icon + "Failed" + a Retry TextButton |

### 7.15 Empty states

- `EmptyHint` keeps its layout:
  - An 84dp halo (`primaryBase` at 28% → 4%) holding a 38dp `primary` icon.
  - A `sectionTitle` headline and a `body`/textSecondary message.
  - One action: a VoltButton if the action plays or gets media, else a FilledButton.
- Copy is short and friendly ("No songs yet", "Paste a link to save a video").
- An optional `overline` kicker goes above the headline.

### 7.16 App icon and splash

- **Adaptive icon:** background `#421E78` (pubspec `adaptive_icon_background: "#421E78"`, was `#0B0D12`). Foreground is
  a Volt play-bolt (a play triangle cut by a lightning notch) with a 2dp ink keyline. The monochrome (themed) icon is
  the same glyph silhouette.
- **iOS icon:** a full-bleed `#421E78 → #180A2E` diagonal with the Volt glyph.
- **Android 12+ splash:** `windowSplashScreenBackground #180A2E`, icon background `#421E78`, in both themes.

### 7.17 Playback behaviour (the basics have to work)

- **Previous:** if position is over 3s, restart the track; otherwise go to the previous item.
- **Next:** at the end of the queue with repeat off, disabled.
- **Notification / lock screen / Bluetooth / headset** (`audio_service`): previous, play/pause and next, with compact
  actions `[0, 1, 2]` on Android and `MPRemoteCommandCenter` on iOS. They mirror the mini player exactly.
- **Haptics:** selection click on swipe-skip; light impact on favourite.

---

## 8. Light theme specifics and system bars

### 8.1 What changes besides colour

| Thing | Dark | Light |
|---|---|---|
| Brand reading colour (`primary`) | Volt | Ultraviolet ink `#5A32D6` |
| Volt fills | Plain | Always with the 1.5dp ink edge (the sticker) |
| FilledButton | Volt / ink | Ultraviolet / white |
| Depth | Tone steps, card hairlines, `voltGlow` under the stage play disc | Card hairlines + soft `shadow` on sheets, dialogs, menus, snackbars; no glows |
| Print offset | Volt | Ink |
| Hero | Ultraviolet bloom | Lavender wash |
| Artwork deep stops | Melt into ink | Lifted one step |
| ArtworkTint surface recipe | lerp deep → ink | lerp top → paper (section 3) |
| Snackbar | `#2B1A50` | Ink `#180A2E` (matches the dock) |
| YouTube toolbar | Solid ink | Glass paper |
| Ink Dock, Now Playing, video player | Ink | **Ink (unchanged)** |

### 8.2 Theme mode and system bars

- **Theme mode:** `MaterialApp(theme: AppTheme.lightTheme, darkTheme: AppTheme.darkTheme, themeMode: ThemeMode.system)`.
  Settings → Appearance (System / Dark / Light, default System) is built: `themeMode` reads
  `themeModeSettingProvider`, so a choice applies at once (section 10.1).
- **Edge-to-edge:** at startup, `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` (enforced on Android 15
  anyway).
- **System bar styles.** Flutter reads the `AnnotatedRegion` at the top of the screen for the status bar and at the
  bottom for the Android navigation bar, so wrapping the Ink Dock is enough to keep the gesture bar light over ink.

```dart
const _barsOnInk = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,   // Android: light icons
  statusBarBrightness: Brightness.dark,        // iOS: light content
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);
const _barsOnPaper = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);
```

Where each style applies:

- `AppBarTheme.systemOverlayStyle`: `_barsOnInk` in the dark theme, `_barsOnPaper` in the light theme. Screens without
  an AppBar wrap their body in `AnnotatedRegion` with the same value.
- The Ink Dock wraps itself in `AnnotatedRegion(value: _barsOnInk)`, so the Android nav bar icons are light wherever
  the dock is visible, in both themes. Full-screen light routes without the dock fall back to `_barsOnPaper`.
- Now Playing and the video player use `_barsOnInk` in both themes. Fullscreen landscape video keeps today's
  `immersiveSticky`.
- iOS draws the home indicator itself, adapting to the content.

---

## 9. Do / don't

**Do**

- Use `primary` for any brand-coloured text, icon, track or focus ring. It is readable in both themes.
- Use `VoltButton`, `VoltDisc`, `VoltSlab` (or the chip theme) for every Volt fill. They draw the ink edge on paper.
- Keep Volt for "play" and "get" actions (Play, Play all, Download, Save offline, Continue) and selection.
- Set anything named by a file, tag, URL or person in Anek (`greeting`, `screenTitle`, `playerTitle`, `cardTitle`) or
  Atkinson. Pass file-style names through `breakableTitle()`.
- Pair every state with an icon and a word: check + "Saved", error icon + "Failed", dot + toggled glyph.
- Use textSecondary (not textMuted) on artwork tints, heroes and the stage.
- Test both palettes, at `textScaler` 1.3, on 320 and 360dp, with Nepali titles.

**Don't**

- Don't put Volt (`voltFill`) as text or icon colour on paper (1.05:1), or ship a Volt fill on paper without the edge.
- Don't use Unbounded for user content, below 18sp, or in rows. Don't use Anek below 20sp.
- Don't add `letterSpacing` to any style that can carry user content (it breaks Devanagari).
- Don't give `filledButtonTheme` colours (it would repaint every tonal button).
- Don't use Ice as a large fill, nav indicator or big icon (it is near Amazon Music's cyan), or Flare for anything but
  hearts (near Apple Music).
- Don't recolour the YouTube page or copy YouTube's red or logo into our chrome.
- Don't add soft glows, pulses or coloured shadows. Depth is tone steps, hairlines and the one hard print offset.
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
