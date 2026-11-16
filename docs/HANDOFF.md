# Handoff: continue on another machine

Last updated: 2026-11-16. Branch: `feat/post-6-1-fixes`, not merged into `main` yet.
Read `docs/ROADMAP.md` for the goals checklist and security model, and `docs/DECISIONS.md` (items 15–19) for
why things are built the way they are.

## Where things stand

The 7 goals of the rework are written and covered by unit/widget tests. What's missing is the
**final design polish** (section A), **QA on a real phone/emulator** (B) and the **builds + merge** (C).

- `dart analyze lib test`: clean.
- `flutter test`: 335 pass. 3 tests in `test/unit/download_streaming_engine_test.dart` can fail when the
  whole suite runs on a slow machine; they pass when that file runs on its own. They use real sockets with
  fixed delays and a 30 s limit. See D1.
- Not verified on a device yet: everything online (Explore search/stream/download, yt-dlp update/reset),
  picture-in-picture, Bluetooth controls, gestures, rotation, the new artwork look on a real screen.
  The old PC's network blocked YouTube TLS, so the online parts could only be unit-tested.

## Set up a new machine

1. `git clone https://github.com/itsniranjannn/mediahub.git`, then `git checkout feat/post-6-1-fixes`.
2. Flutter 3.47.x (Dart 3.13.7+): `flutter pub get`, then `dart analyze lib test` and `flutter test`.
3. Android: SDK platform 37, build-tools, a JDK (Gradle downloads its own toolchain if needed).
   If your SDK installs the platform as `android-37.0` and AGP can't find `android-37`, build with
   `SDK_PLATFORM_FIX=1 tools/device/build_apks.sh <mode>` (it patches a scratch copy, never the repo).
4. **Release signing**: copy the family keystore (`mediahub-family.jks`) and `android/key.properties`
   from your backup. Fix `storeFile=` in `key.properties` to the keystore's path on the new machine.
   Never commit either file (both are git-ignored). Check that it's the right key:
   `keytool -list -v -keystore <path>/mediahub-family.jks -alias mediahub` must show SHA-256
   `DA:DD:95:6A:...:AD:64:D3` (full value in ROADMAP section 3). Release builds refuse to build without
   the key. Without it, only debug builds work, and those can't update the installed family app.
5. iOS needs a Mac with Xcode (`cd ios && pod install`, then `flutter build ios`).

### Helper tools in this repo

- `tools/device/build_apks.sh test|emulator|family|relx64` builds APKs from a scratch copy
  (`$BUILD_COPY`, default `~/.mediahub/build-copy`). Every mode except `family` uses the app id
  `com.mediahub.app.audit` ("MediaHub Test"), so it installs next to the real app without touching it.
- `tools/device/dev.py` is a small adb helper (screenshots, UI dump, tap by label, swipes, crash log).
  `tools/device/qa_pass.py <round> [--install APK] [--only home,music,...]` visits every screen and saves
  screenshots to `tools/device/shots/` (git-ignored). `gen_media.py <dir>` makes tagged test WAV files.
  Tip: real test videos come from `adb shell screenrecord --bugreport --time-limit 8 --size 1280x720 /sdcard/Movies/x.mp4`.
  In Git Bash, set `MSYS_NO_PATHCONV=1` before `adb push` to `/sdcard/...`.
- `flutter test tools/design_previews/preview_test.dart` renders Music, Now Playing, Home, Videos, Explore,
  Album and Queue at 360x800 with fake data into `build/design_previews/`. Use it to check the section A fixes.

## A. Design polish still to do (from the designer review of the artwork round)

The artwork system is in: gradient covers per item (8 palettes, picked by a stable FNV-1a hash of the uri),
real 16:9 video thumbnails with fade-in, a shared `DurationBadge`, and Now Playing tinted with the song's
palette. A designer reviewed the rendered screens. The polish pass that should apply that review was
stopped before it changed anything. The full list, highest impact first:

1. **[high] Now Playing** (`lib/features/music_player/now_playing_sheet.dart`)
   - Problem: contrast is wrong in both directions. (a) On a bright or white real cover, the "Now Playing"
     header is 3.5:1 and the "1 of 8" caption about 1.8:1. (b) Without art, the glow sits behind the cover
     and every song gets the same faint navy wash. No song tint is visible.
   - Fix: `_kBackdropScrim` alphas `[0.82, 0.82, 0.60, 0.90, 1.0]` at stops `[0.0, 0.16, 0.26, 0.72, 1.0]`.
     `_PaletteGlow`: `_lightCenter = Alignment(0, -0.30)`, light radius 0.9 (was 1.05). In
     `artwork_placeholder.dart`: `ArtworkTint.backdropLightAlpha = 0.9`, `backdropDeepAlpha = 0.6`.
     Update the contrast unit test to measure where text actually sits (0.82 at the header, ≥0.9 at the title).
2. **[high] Tonal buttons look like primary buttons** (`lib/app/theme/app_theme.dart`)
   - Problem: `filledButtonTheme` sets background/foreground, so `FilledButton.tonal` ("Listen" in Explore)
     looks the same as `FilledButton` ("Watch"). This also affects `videos_screen.dart`, `router.dart` and
     `settings_screen.dart`.
   - Fix: remove `backgroundColor`/`foregroundColor` from `filledButtonTheme`. Add
     `secondaryContainer: Color(0xFF25253F)` and `onSecondaryContainer: AppColors.primary` to the dark
     `ColorScheme` (4.98:1). Then delete the local `_tonalStyle` in `detail_screens.dart` and `music_screen.dart`.
3. **[high] Song titles cut off at about 12 characters** (`lib/features/library/media_song_row.dart`)
   - Problem: duration + heart + more button take about 140 dp of a 360 dp row.
   - Fix: remove the standalone duration `Text` and its `SizedBox(width: 8)`. Show the duration at the end of
     the meta line instead: `Row([Expanded(artistText), Text(' · <duration>', style: metadata, textMuted,
     tabular figures)])`, for both the plain and the download variants. Add `SizedBox(width: AppSpacing.xs4)`
     before the heart. The title gains about 44 dp.
4. **[high] Small covers look like app icons** (`lib/shared/widgets/artwork_placeholder.dart` + call sites)
   - Fix: in `_CoverPainter`, draw the rings only when `shortest >= 96`. Radii: `media_song_row` `_artworkRadius`,
     `mini_player.dart:196`, `queue_sheet.dart:283`, `media_context_menu.dart:322/330` → `AppSpacing.sm8`.
     Home continue card (80 dp) → `AppSpacing.md12`. `detail_screens.dart` `_kHeroArtRadius` → `AppSpacing.lg16`.
     Now Playing stays at 24.
5. **[high] Tints ignore real artwork** (`home_screen.dart`, `detail_screens.dart`, `now_playing_sheet.dart`)
   - Problem: the hash tint shows even when the item has a real cover, e.g. a red cover on a teal card.
   - Fix: `_hasRealArt(item) = artworkPath not empty || ArtworkService.instance.peek(uri, size: 256/512) != null`.
     When it's true, use `AppColors.heroGradient` or the neutral violet fallback instead of `ArtworkTint`. In Now
     Playing, use `_PaletteGlow(seed: hasArt ? null : item.uri)`. Better later: average the 64 px blurred
     swatch into one colour.
6. **[medium] Now Playing cover size**: `_kArtworkMaxSize = 400` (was 300), so a 360 dp screen gets a
   328 dp cover lined up with the 16 dp text and slider edges.
7. **[medium] Now Playing title**: `maxLines: 2`. Artist in `AppTypography.body` + `textSecondary`. Adjust
   `_snackMarginAboveInfo` (infoHeight = max(48, 2 × title line + 4 + body line)).
8. **[medium] Palette**: emerald looks like teal and like the success green. Replace it with "dusk",
   `[Color(0xFF7A6CC0), Color(0xFF221B4A)]`.
9. **[medium] "Downloaded" pill over video covers disappears on violet covers** (`media_item_tile.dart`):
   add a `MediaBadge({icon, text})` to `ui_kit.dart` in the overlay style (like `DurationBadge`, icon 12 in
   `AppColors.accent`). Keep the text "Downloaded" (a test looks for it).
10. **[medium] One duration format**: add `formatClock(Duration)` to `lib/core/utils/formatters.dart`, which drops
    the leading zero under 10 minutes and keeps hours padded. Use it in the Now Playing seek labels,
    `DurationBadge`, `media_item_tile.dart` and `MediaSongRow._trackDuration`.
11. **[medium] Now-playing row highlight**: make `MediaSongRow` match the queue: an inset pill at 12% violet with
    radius `AppSpacing.buttonRadius` and 8 dp side padding, keeping the 64 dp row and the art at 16 dp.
12. **[medium] Album tile vs album page**: add `coverUri` (`uri.min()` in the albums query) to `AlbumGroup`.
    Use it for `_AlbumCard` (`ArtworkThumbnail`) and pick the same song for the album header.
13. **[low]** `SectionHeader` "See all" ends 28 dp from the edge instead of 16. Use right padding `AppSpacing.xs4`.
14. **[low]** Use one separator everywhere: ` · ` (U+00B7) instead of ` • `. Leave `online_stream_sheet.dart:62`
    alone, because a test expects "MP4 • size unknown".
15. **[low]** In `format_selection_sheet.dart:161`, use `Icons.play_circle_outline_rounded`, the same glyph as the Explore card.

Also: in `ArtworkThumbnail`, stop painting the placeholder under a cover once it has faded in (extra painting
in long lists). When re-rendering previews, pick a second Now Playing song that lands on a different palette,
so the tint change is visible.

## B. QA still to do (emulator first, then the phone)

Build `emulator` (demo data for Explore) and run `qa_pass.py`, then check by hand:
- Home (continue listening, sections, Show all), Music (songs/albums/artists/playlists), long titles.
- Now Playing: favourite + snackbar with Undo, shuffle/repeat, prev/next, seek, queue reorder.
- Videos → player: rotate, brightness/volume/seek swipes, skip buttons, picture-in-picture (button and
  leaving the app), back to portrait.
- Explore (demo data on the emulator, real YouTube on the phone): search, Listen, Watch, Download qualities.
- Downloads: paste a YouTube / Instagram / direct link, qualities, sizes while downloading, pause/resume,
  Cancel during link lookup, delete, play from the card, thumbnails.
- Settings: yt-dlp update, **Use the built-in yt-dlp** (reset), diagnostics, privacy notes.
- Phone only: Bluetooth headset play/pause/next, lock-screen and notification controls, no pauses in
  playback, auto-rescan after adding files, favourite kept after a file is re-added (identity carry-over).
- `relx64` release build on the emulator: R8 didn't strip anything. Check the notification icons and
  audio_service icons (kept via `res/raw/keep.xml`) and that the app starts with no crash in `adb logcat -b crash`.

## C. Builds and merge

1. `tools/device/build_apks.sh test` gives an APK for the phone that installs next to the real app.
2. `tools/device/build_apks.sh family` gives the release APK signed with the family key, which updates the real app in place.
   If the phone has an older build signed with a different key, Android asks to uninstall first, and that
   deletes the app's data.
3. When QA passes: open a PR `feat/post-6-1-fixes` → `main` and merge.

## D. Known follow-ups and accepted risks

1. Make `download_streaming_engine_test.dart` robust under load: wait for the final progress event before
   asserting, and raise the timeout for test 6 (`timeout: Timeout(Duration(minutes: 2))`).
2. A direct-link download's `<id>.part` is only removed at the next app start after you delete the row. That's fine.
3. Accepted (see DECISIONS 18): redirects through yt-dlp's generic extractor, yt-dlp self-update isn't
   signature-checked (Reset restores the bundled copy), the media service is exported (needed for Bluetooth and
   lock screen), iOS backup policy, jackson version inside youtubedl-android.
4. iOS: picture-in-picture (AVKit) and importing the local library need native work on a Mac.
5. Next features, in priority order: ROADMAP section 4 (library backup/restore file, "Save to phone",
   Explore extras, app lock, iOS, offline polish, CI + package rename).
