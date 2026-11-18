# Handoff: continue on another machine

Last updated: 2026-11-18. Branch: `feat/post-6-1-fixes`, not merged into `main` yet.
Read `docs/ROADMAP.md` for the goals checklist and security model, `docs/DESIGN.md` for the
"Bijuli" design system, and `docs/DECISIONS.md` (items 15–19) for why things are built the way they are.

## Where things stand

Everything the owner asked for is in the code, covered by tests and was driven by hand on the Android
emulator (section B). What is left needs the family phone, a Mac, or a decision (sections B.3 and D).

- `dart analyze lib test tools`: clean.
- `flutter test`: 1144 pass (`flutter test --concurrency=3`, about 3 minutes).
- `node --test "test/js/*_test.js"` (the YouTube page bridge): 37 pass.
- Emulator: release build (`relx64`) and the Online stand-in build (`emulator`), dark and light.

## Set up a new machine

1. `git clone https://github.com/itsniranjannn/mediahub.git`, then `git checkout feat/post-6-1-fixes`.
2. Flutter 3.47.x (Dart 3.13.7+): `flutter pub get`, then `dart analyze lib test` and `flutter test`.
   Node 18+ for the bridge tests: `node --test "test/js/*_test.js"`.
3. Android: SDK platform 37, build-tools, a JDK (Gradle downloads its own toolchain if needed).
   - If your SDK installs the platform as `android-37.0` and AGP can't find `android-37`, build with
     `SDK_PLATFORM_FIX=1 tools/device/build_apks.sh <mode>` (it patches a scratch copy, never the repo).
   - `android/gradle.properties` sets `android.r8.proguardAndroidTxt.disallowed=false`: AGP 9.1 refuses
     flutter_inappwebview's consumer ProGuard file without it.
   - `third_party/video_player_android` is a vendored copy of the official plugin (2.12.2) with a
     3-part patch for the volume boost (see its README). `pubspec.yaml` points at it with
     `dependency_overrides`; when you update `video_player`, re-vendor the matching version.
4. **Release signing**: copy the family keystore (`mediahub-family.jks`) and `android/key.properties`
   from your backup. Fix `storeFile=` in `key.properties` to the keystore's path on the new machine.
   Never commit either file (both are git-ignored). Check that it's the right key:
   `keytool -list -v -keystore <path>/mediahub-family.jks -alias mediahub` must show SHA-256
   `DA:DD:95:6A:...:AD:64:D3` (full value in ROADMAP section 3). Release builds refuse to build without
   the key. Without it, only debug builds work, and those can't update the installed family app.
5. iOS needs a Mac with Xcode (`cd ios && pod install`, then `flutter build ios`).
6. Fonts are bundled (Unbounded, Anek Devanagari Wide, Atkinson Hyperlegible Next, Mukta, DM Mono, all
   OFL; licences in `assets/fonts/licenses/`). `tools/fonts/README.md` shows how the subsets were made.

### Helper tools in this repo

- `tools/device/build_apks.sh test|emulator|family|relx64|testrel` builds APKs from a scratch copy
  (`$BUILD_COPY`, default `~/.mediahub/build-copy`). Every mode except `family` uses the app id
  `com.mediahub.app.audit` ("MediaHub Test"), so it installs next to the real app without touching it.
  - `emulator`: debug x86_64 with demo data and an offline stand-in for a YouTube watch page
    (`MEDIAHUB_ONLINE_FIXTURE`), for PCs whose network blocks YouTube.
  - `relx64`: release x86_64 for the emulator (checks R8 didn't strip anything).
  - `testrel`: release arm64 test app for the phone. `family` and `testrel` both write `app-release.apk`,
    so copy it away before building the other one.
- `tools/device/dev.py` is a small adb helper (screenshots, UI dump, tap by label, swipes, crash log).
  `tools/device/qa_pass.py <round> [--install APK] [--only home,music,...]` visits every screen and saves
  screenshots to `tools/device/shots/` (git-ignored).
  - The UI dump (`uiautomator`) cannot read the screen while music or a video is playing; pause first.
  - In Git Bash, set `MSYS_NO_PATHCONV=1` before `adb push` to `/sdcard/...`.
  - Test videos: `adb shell screenrecord --bugreport --time-limit 8 --size 1280x720 /sdcard/Movies/x.mp4`.
- `flutter test tools/design_previews/preview_test.dart` renders the main screens in both themes at
  360 dp and 320 dp with fake data into `build/design_previews/`.
- Emulator tips: start it with `-gpu host` (the software renderer starves the CPU), and don't run it
  while a big test run or build is going on a 6-thread PC.

## A. What changed in this round

- **Design "Bijuli" (Volt on Ink)**: a deep ink canvas with an electric volt-yellow accent, dark and light
  themes (Settings → Appearance, default follows the phone; the players stay ink in both). Four type
  voices: Unbounded for headings, Anek for song and video titles (Latin and Devanagari), Atkinson
  Hyperlegible Next for body text, DM Mono for times and counts. Every screen was redone; `docs/DESIGN.md`
  is the spec.
- **Online tab** (was Explore): the mobile YouTube site in a locked-down WebView with background play,
  picture-in-picture, media controls and a watch strip (Download, PiP, Background, Save, Copy link).
- **Music**: a rewritten skip engine (fast presses add up, one seek), sticky shuffle, covers in the
  notification, Like in the notification, sleep timer, media resumption, Liked songs, real albums
  (album id, disc/track order), playlists with Undo, search with Devanagari and romanised Nepali,
  auto-rescan. Database schema v8 (migration tested on a real v7 file).
- **Video**: volume boost to 200%, rotation modes, next/previous with Up next, fit modes and pinch,
  subtitles, audio tracks, PiP buttons, save position on Back, pause on headphone unplug, one quiet retry
  after a decoder error.
- **Security**: see ROADMAP section 3. New since last time: the Online tab's host allowlist and bridge
  token, the private read-only share provider, deleting a download cleans its playlist entries,
  file names within 255 bytes, yt-dlp update blocked during downloads, Spotify songs refused.

## B. QA

### B.1 Checked on the emulator (2026-11-18, Pixel AVD, Android 14, release build)

| Area | Checked | Result |
|------|---------|--------|
| Music controls | play/pause, 20 quick Next, 20 quick Previous, a mixed burst of 30 presses (media keys, `dumpsys media_session`) | Pass: lands on the right song every time (stops at the last/first with repeat off), no crash or ANR |
| Notification ("media dropdown") | quick-settings player | Pass: song cover, title, artist, a live seek slider, Previous/Next, Like heart, shuffle |
| Screen off (music) | 65 s with the screen off | Pass: still PLAYING, position 0:00 → 1:05, the app's audio track `started`, foreground service kept |
| Now Playing | Like with Undo, shuffle, repeat, sleep timer (sheet + chip), queue | Pass |
| Library | Albums (track order, the "feat." track kept in its album), Artists, Liked songs, album Shuffle (random start, shuffle on), playlists (create, add one, "Add 2 songs" picker) | Pass |
| Search | "resham" → रेशम फिरिरी, "band raga" (two words) | Pass |
| Covers | list rows, mini player, Now Playing, album page, notification | Pass |
| Video | ±10 s buttons, double tap (+10 s), landscape for a wide video and portrait for a tall one, Volume panel with Boost (Android shows a Loudness Enhancer on the app's audio), Up next, picture-in-picture by button | Pass |
| Online (stand-in page) | plays, media session "YouTube", notification controls, media keys pause/play/next/previous, PiP by button and by leaving the app, Download hand-off (Downloads opens with `https://youtu.be/<id>` and starts the lookup) | Pass |
| Online screen off | 50 s and 65 s with the screen off | Pass: PLAYING, WebView audio `started`, foreground service kept; the 60 s stand-in tone played to its end |
| Themes | Home, Music, Albums, Now Playing, Videos, Settings, Downloads in dark and light | Pass |
| Release build | `relx64`: R8, notification icons kept, nothing in `logcat -b crash` | Pass |

The emulator's own H.264 decoder (`c2.goldfish.h264.decoder`) failed twice on one variable-frame-rate screen
recording ("Family Trip 2025"), once after the next video started and once in picture-in-picture. "Try again"
played it. The app now retries such a decoder error once by itself (B.2).

### B.2 Found on the emulator and fixed in this round

- **Now Playing header under the status bar**: `showModalBottomSheet(useSafeArea: false)` also strips the
  top inset, so the chevron and "NOW PLAYING · 1 / 11" sat under the clock. `RestoreTopInset`
  (`mini_player.dart`) gives the sheet the real inset back. Test: `now_playing_inset_test.dart`.
- **Keyboard popping back up**: search the library, open an album, press Back, and the keyboard came up
  again (Flutter gives focus back to the field). `UnfocusOnPush` (`lib/app/unfocus_on_push.dart`) on every
  navigator drops a text field's focus when a page, sheet or dialog opens. Test: `unfocus_on_push_test.dart`.
- **A decoder hiccup showed the error screen at once**: a decoder error now gets one quiet retry from the
  same position (once per video per 30 s, only while the viewer wants it playing: never after a pause,
  backgrounding, the end of the video or Back); the error screen only shows if that fails too.
- **Online toolbar gone until a restart**: once on the emulator the Online tab kept its picture-in-picture
  layout after the app was back in front. Not reproduced by expanding or closing the PiP window, so
  `MainActivity.onResume` now tells Dart "not in picture-in-picture" every time (a resumed Activity cannot
  be in it); a repeat changes nothing.
  Tests: `video_player_error_retry_test.dart`, group "a decoder error gets one quiet retry".
- **"Unknown Artist" vs "Unknown artist"**: the lists said one, the players the other; now "Unknown artist"
  everywhere.
- Tooling: `qa_pass.py` no longer stops at the first failed UI dump.

### B.3 Still to check on the phone (Samsung, Android 13)

- Real YouTube in Online: search, play, Download and Copy link hand-off, YouTube Music.
- Online background play with the screen off for 30 minutes or more (One UI's battery rules), and
  picture-in-picture from a real watch page.
- How loud the video boost is, and that it stays on the video only.
- Bluetooth headset: play/pause/next, cover art on the car or watch display.
- Sharing a download with spaces or Devanagari in its name to Gmail, Drive or Telegram (it must arrive as
  audio or video, not "unknown file").
- Auto-rescan after copying songs onto the phone; likes kept after a file is re-added.
- Real phone video decoders: the emulator's own decoder failed twice on one screen-recording file
  (B.1); a phone should play it without the retry.

## C. Builds and merge

1. `tools/device/build_apks.sh testrel` gives a fast release APK for the phone that installs next to the
   real app ("MediaHub Test").
2. `tools/device/build_apks.sh family` gives the release APK signed with the family key, which updates
   the real app in place. If the phone has an older build signed with a different key, Android asks to
   uninstall first, and that deletes the app's data.
3. When the phone check passes: open a PR `feat/post-6-1-fixes` → `main` and merge.

The 2026-11-18 builds are in the git-ignored `build/` folder: `MediaHub-Test-arm64.apk`
(`com.mediahub.app.audit`) and `MediaHub-Family-arm64.apk` (`com.mediahub.app`), both release builds
signed with the family key (SHA-256 `DA:DD:95:6A:…:AD:64:D3`).

## D. Known follow-ups and accepted risks

1. Accepted (see DECISIONS 18): redirects through yt-dlp's generic extractor, yt-dlp self-update isn't
   signature-checked (Use the built-in yt-dlp restores the bundled copy), the media service is exported
   (needed for Bluetooth and lock screen), jackson version inside youtubedl-android.
2. Deferred, owner's decision: taking links shared from other apps (share intents, SEC-7). It would let
   any app hand MediaHub a link; today you paste links yourself.
3. Android "Delete from phone" for songs and videos that came with the phone needs Android's delete
   consent dialog (`MediaStore.createDeleteRequest`); downloads can already be deleted.
4. iOS (needs a Mac): picture-in-picture (AVKit), native volume/brightness, the share sheet
   (`ShareChannel` 'mediahub/share' has only an Android side, so iPhone users get no Share row),
   Files import for the local library, excluding downloads from iCloud backup.
5. A direct-link download's `<id>.part` is only removed at the next app start after you delete the row.
6. Next features: ROADMAP section 4.
