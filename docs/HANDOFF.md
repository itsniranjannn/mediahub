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

- `tools/device/build_apks.sh test|emulator|family|relx64|testrel` builds APKs from a scratch copy
  (`$BUILD_COPY`, default `~/.mediahub/build-copy`). Every mode except `family` uses the app id
  `com.mediahub.app.audit` ("MediaHub Test"), so it installs next to the real app without touching it.
  `testrel` is a release (fast) build of that test app for the phone. `family` and `testrel` both write
  `app-release.apk`, so copy it away before building the other one.
- `tools/device/dev.py` is a small adb helper (screenshots, UI dump, tap by label, swipes, crash log).
  `tools/device/qa_pass.py <round> [--install APK] [--only home,music,...]` visits every screen and saves
  screenshots to `tools/device/shots/` (git-ignored). `gen_media.py <dir>` makes tagged test WAV files.
  Tip: real test videos come from `adb shell screenrecord --bugreport --time-limit 8 --size 1280x720 /sdcard/Movies/x.mp4`.
  In Git Bash, set `MSYS_NO_PATHCONV=1` before `adb push` to `/sdcard/...`.
- `flutter test tools/design_previews/preview_test.dart` renders Music, Now Playing, Home, Videos, Explore,
  Album and Queue at 360x800 with fake data into `build/design_previews/`. It now has 22 scenes (real covers, a white cover, 1.3x text, 320 dp, empty states).

## A. Design polish (done)

Two designer reviews of rendered screens were applied, and a code review checked the result. What changed:

- **Now Playing**: darker veil where text sits (header and "1 of 8" now pass 4.5:1 over a white cover), the glow
  takes the song's palette and goes neutral violet when the song has real art, very bright covers are dimmed
  (mean brightness capped at 0.40), 328 dp cover on a 360 dp phone lined up with the text, 2-line titles,
  time labels sit with the seek bar. A widget test measures contrast where every text and icon really sits.
- **Buttons**: `FilledButton.tonal` is now really tonal (`secondaryContainer` in the theme), so "Listen" and
  "Shuffle" sit quietly next to the solid "Watch" and "Play".
- **Song rows**: the duration ends the meta line ("Artist · 4:05") so titles get about 36 dp more; at large text
  or on 320 dp phones titles wrap to 2 lines. The playing row is an inset violet pill, and its equaliser glyph
  has a dark veil that stays readable on white covers. "Downloaded" is teal (violet means "playing").
- **Covers**: rings only on covers of 96 dp or more; radii 8 (rows, mini player, queue, menus), 12 (Home card),
  16 (album header), 24 (Now Playing). Palette "emerald" was replaced by "dusk". Tinted surfaces (Home card,
  album/artist headers) go neutral when the item has real art and fade instead of flashing.
- **Albums**: the tile and the album page use the same song's cover (`AlbumGroup.coverUri` and
  `coverArtworkPath`, so downloaded albums show their saved thumbnail).
- **Video cards**: no grey bottom scrim (bright family videos stay bright); "Downloaded" and duration chips
  share one overlay style (`MediaBadge`, `DurationBadge`); the resume bar sits on a dark track.
- **Queue**: the position numbers are gone, covers start on the 16 dp edge, titles gain 40 dp.
- **One clock format** everywhere visible (`formatClock`: 4:05, 12:30, 1:02:03), including the video player.
  Screen-reader labels keep the old format.
- **Small fixes**: "See all" ends on the 16 dp edge, ` · ` as the one separator, the same play glyph in the
  format sheet and Explore, Explore card buttons on the 16 dp edge with a 48 dp download button, "Scan device"
  button on the empty Songs/Videos tabs, "Search your music" hint, mini player skip-previous no longer looks
  disabled.

Not done on purpose: averaging the cover into one glow colour (the blurred cover already covers the glow).

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

1. (Done) `download_streaming_engine_test.dart` no longer depends on timing: the test server holds the
   response until the test has seen bytes on disk, and every real-socket test has an explicit timeout
   (test 1: 12 min, because it moves 100 MB and a busy PC can be slow). It passed 3 times alone and twice
   under a CPU stress loop.
2. A direct-link download's `<id>.part` is only removed at the next app start after you delete the row. That's fine.
3. Accepted (see DECISIONS 18): redirects through yt-dlp's generic extractor, yt-dlp self-update isn't
   signature-checked (Reset restores the bundled copy), the media service is exported (needed for Bluetooth and
   lock screen), iOS backup policy, jackson version inside youtubedl-android.
4. iOS: picture-in-picture (AVKit) and importing the local library need native work on a Mac.
5. Next features, in priority order: ROADMAP section 4 (library backup/restore file, "Save to phone",
   Explore extras, app lock, iOS, offline polish, CI + package rename).
