# Handoff: continue on another machine

Last updated: 2026-11-20. `feat/post-6-1-fixes` was merged into `main` on 2026-11-20; start new work on
a fresh branch from `main`. The 2026-11-19
round (section A0) is committed on top of `cc43807` in five area commits.
Read `docs/ROADMAP.md` for the goals checklist and security model, `docs/DESIGN.md` for the
"Sindur" design system, `docs/IOS.md` for the iPhone, and `docs/DECISIONS.md` (items 15–19) for why
things are built the way they are.

## Where things stand

Everything the owner asked for is in the code, covered by tests and was driven by hand on the Android
emulator (section B), except **Block ads** in the Online tab (A0): it has tests only and has not been
tried with real YouTube yet. What is left needs the family phone, a Mac, or a decision (sections B.3
and D).

- `dart analyze lib test tools`: clean.
- `flutter test`: 1593 pass (`flutter test --concurrency=3`, about 4 minutes).
- `node --test "test/js/*_test.js"` (the YouTube page bridge): 73 pass.
- Emulator: release build (`relx64`) and the Online stand-in build (`emulator`), dark and light, on
  2026-11-18. The 2026-11-19 round was driven on the emulator too (section B.0); the phone checks are
  in B.3.

## Set up a new machine

1. `git clone https://github.com/itsniranjannn/mediahub.git` (everything is on `main`).
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
5. iOS needs a Mac: follow `docs/IOS.md` section 6. Do **not** start with `cd ios && pod install`:
   there is no `ios/Podfile` until the first `flutter build ios --release` (or `flutter run --release`)
   writes it and runs CocoaPods itself.
6. Fonts are bundled (Fraunces, Poppins (Latin and Devanagari), DM Mono, all
   OFL; licences in `assets/fonts/licenses/`). `tools/fonts/README.md` shows how the subsets were made.

### Helper tools in this repo

- `tools/device/update_ytdlp_asset.py [version]` packs a current yt-dlp from PyPI into the app (run it
  before a release).
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

## A0. What changed on 2026-11-19 (the owner's phone report)

The owner installed the release APK from `cc43807` on the Samsung and reported: YouTube sign-in in
Online did not work; a 1080p YouTube download failed with "Requested format is not available"; the
mini player should not sit on the Online and Videos tabs; music should pause for another app and come
back after it; videos should land in Videos and audio in Music; downloads should work for any link.
Five work packages and two reviews followed; everything below has tests and the Android parts were
driven on the emulator (B.0), except Block ads (tests only). Nothing has run on a phone yet (B.3).

- **YouTube sign-in**: Google's sign-in pages (accounts.google.com, accounts.youtube.com,
  gds.google.com, https only, exact hosts) now load inside the Online tab, with a "Sign in to YouTube"
  row in the ⋮ menu. The WebView presents itself as Chrome and sends no X-Requested-With header. The
  page bridge stays off on those pages. Google may still refuse ("This browser or app may not be
  secure"); the tab works without an account. Clear site data now also signs you out.
- **YouTube downloads**: every quality choice ends in yt-dlp's catch-all, so a missing 1080p saves the
  nearest quality instead of failing; up to 3 YouTube clients are tried at the chosen quality first.
  The chip then says what was saved ("360p · lower quality"). yt-dlp updates itself after a failure
  it may fix (at most every 12 hours; downloads that fail together wait for each other and share one
  update) and checks weekly at app start (not on mobile data). If YouTube still refuses, the file
  YouTube serves directly is saved instead ("· lower quality"). YouTube's "try again later" is now its
  own message, not "removed". Dailymotion and Reddit were added.
- **Any link**: direct links without an extension, with odd names, redirects or a generic type now
  work; files from servers that compress them are no longer rejected; a file over 2 GB is refused on
  the card. Web
  pages from sites yt-dlp does not read no longer offer "Choose quality".
- **Videos in Videos, audio in Music**: each finished file is checked for a picture track. Sound you
  asked for ("Original audio", MP3) always stays in Music. Wrongly placed downloads move once at the
  next start.
- **Mini player**: folds away on the Videos and Online tabs and comes back on the others; the music and
  its notification keep going.
- **Resume after other apps** (Android, Settings → Audio & headset, on by default): when another app
  takes the sound and plays, MediaHub pauses; about 10 seconds after that app goes quiet the music plays
  again, within 30 minutes. Not after you pressed play, pause, stop or skip, during a call, after a
  video or the Online tab took over, or if the other app takes the sound back within a minute of the
  resume. MediaHub's own player is never taken for "another app".
- **Songs that cannot play** skip to the next one with a "Can't play ..." message (both phones).
- **Search** treats curly and straight quotes and dashes the same; search boxes no longer autocorrect.
  Albums and artists whose names differ only in those marks are now grouped together.
- **"Resume when headphones reconnect"** turned off now stays off from launch (it used to wait for
  Settings to be opened).
- **iPhone**: many fixes made without a Mac (calls and Siri resume, stored paths after reinstall,
  expired YouTube links, covers from the file, wording, Online and video details) and the app id is now
  `com.mediahub.app`. See `docs/IOS.md`.
- **Error wording**: a failed download shows one plain sentence and what to do. The technical
  "Reason:" line is no longer on the card; the reason is kept in Settings → Diagnostics.
- **Block ads** (Online tab; Settings → Online and the ⋮ menu, on by default; changing it opens the
  page again): the page script takes the ad fields out of YouTube's player data, mutes an ad that
  still plays and presses its Skip button (it is run to its end only when it is surely a short
  mid-roll, never a pre-roll, an ad stitched into the video or anything around the next video), keeps
  the video's own title in the notification, hides sponsored boxes, and fails the page's own ad
  requests. iOS also gets a WebKit content rule list for ad addresses; Android has no native blocking
  (the WebView plugin has no cheap way that works there). Tests only: not yet checked on the emulator
  or a phone with real YouTube (B.3). ROADMAP section 3 has the limits. Reviewed in three rounds; one
  narrow case is left: only media of 31.5 s or less is ever run to its end, so at worst a real clip
  that short (a Short right after an ad, say) could be skipped; anything longer is only muted.
- **Found on the emulator later that day, with real YouTube** (B.0b): direct links timing out on a
  network where IPv4 or IPv6 is broken (now raced like a browser), YouTube pausing itself in
  picture-in-picture (now keeps playing and shows only the video), and yt-dlp stalling on such a
  network (now told which family works).

## Latest: Sindur

- **Sindur rebrand (branch feat/rebrand)**: near-black #0B0B0D canvas with crimson #CC324C fills, rose #FF6E86 accent,
  lavender #B98FFF and milk #FFF3E6 text; light is white + wine #81021F + purple #5B2FC2 (Bijuli Classic stays in
  Settings). Fonts: Fraunces headings, Poppins names/body (draws Devanagari), DM Mono figures. Screen mastheads
  sit in a `HeroBand` (heroGradient) with an `EntranceFade` stagger (off with reduced motion); icons are the rounded
  set. App icon: crimson play-bolt on #0B0B0D to #4A0F24 (`assets/icon/draw_icon.py`), splash and launch screen #0B0B0D.
  The Bijuli notes below describe the earlier look.
- **Owner's round on Sindur (2026-11-20, uncommitted on feat/rebrand)**:
  - Quality sheet: a Video | Audio switch (Video first). Audio offers "Original · M4A (~N kbps)", "Original · Opus"
    when the site has both (no re-encode), and MP3 320/256/192/128 kbps (sizes = duration x bitrate). MP3 is stored
    as `audioFormat` "mp3-320" etc.; `AudioConversion.parse` whitelists codec + bitrate and the runner sends
    `audioFormat` + `audioQuality` ("320K") to `ExtractorChannel.kt`, which checks `AUDIO_QUALITIES` again
    (`-x --audio-format mp3 --audio-quality 320K`). Old rows with plain "mp3" keep best VBR ("0"). Audio still lands in Music.
  - "Liked songs" / "Liked" read "Favourites" (British) in the UI, notification action, snackbars, Online Save;
    providers, DB columns and the `liked:songs` cover seed are unchanged.
  - Settings compact: 32 dp leading slots, 12 dp heading padding, rows ~10 dp vertical with density -2 (still >= 48 dp),
    subtitles 13/18.
  - Home bento: Shuffle block shine sweep every 6 s (off with reduced motion), Volt glow, press 0.97 + ripple + icon
    turn (`PressGlyph`); small tiles glow in their icon colour on ink; Downloads strip has a faint sheen.
  - Dock: opaque backing behind the rounded corners (scaffold colour; dock colour = square look on Online), WebView
    clipped to its box, bottom inset = max(padding, viewPadding), nav labels capped at 1.3x (icons only if they would
    drop under 6 dp). Still to check on the Samsung: corners on Online and labels with gesture and 3-button nav.
  - Notification cover for songs without art: branded wine-to-plum field with a crimson-to-amber note.

## A. What changed in the previous round

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

### B.0 Checked on the emulator (2026-11-19, Pixel AVD, Android 14, debug x86_64 build)

| Area | Checked | Result |
|------|---------|--------|
| Mini player | a song playing, then Music, Videos, Online, Downloads, Home | Pass: hidden on Videos and Online, back on the others; the media session stays PLAYING |
| Resume after other apps (temporary) | YouTube Music's audio preview (it asks for temporary focus), then closed | Pass: MediaHub paused, and Android gave the sound back at once |
| Resume after other apps (for good) | Chrome played a 40 s song (it takes focus for good) | Pass: MediaHub paused; Chrome stopped at 38 s and MediaHub was PLAYING at 48 s (`play() called by: other_app_stopped`), no button pressed |
| Broken song | a copied song overwritten with random bytes, then tapped | Pass: snackbar `Can't play "Broken_Test_Song"`, the next song played by itself |
| Settings | Audio & headset, Online, Personal tools | Pass: "Resume after other apps" (on), the YouTube sign-in text, the yt-dlp version line |
| Online sign-in | ⋮ → Sign in to YouTube | Pass: Google's "Sign in to continue to YouTube" opened inside the tab (nothing typed) |
| Direct link | a public 8.5 MB MP3 (soundhelix.com): Inspect, Download | Pass: saved, tagged Audio, listed in Music and not in Videos. Its title showed "….mp3"; a media extension is now dropped from the title (`DownloadEngine.libraryTitleFor`) |
| Crashes | `logcat -b crash` after all of the above | None |

The Online stand-in page plays by itself when the tab opens (it calls `play()` on load), which takes
the sound from a playing song. The real YouTube home page does not.

### B.0b Second emulator pass (2026-11-19 afternoon, release and debug x86_64, real YouTube)

This PC could reach YouTube and Google this time (not GitHub), so the real site was tested. The emulator
turned out to have a half-broken network: IPv4 to Google and Cloudflare hosts hangs while IPv6 works
(the opposite of the usual phone case, where IPv6 is the broken one). That exposed two real bugs.

| Area | Checked | Result |
|------|---------|--------|
| Music | 20 quick Next, 20 quick Previous, a mixed burst, notification player, 65 s screen off | Pass |
| Resume after other apps | Chrome 40 s song; then the same with the setting off | Pass: resumed 9 s after Chrome went quiet; stayed paused with the setting off |
| Mini player | every tab with a song playing | Pass: hidden on Videos and Online only |
| Broken song | corrupted copy, tapped | Pass: `Can't play ...`, next song plays |
| Direct links | MP4 and M4A and MP3 (filesamples.com, Cloudflare), MP4 (test-videos.co.uk, Cloudflare), MP3 (soundhelix.com) | **Was failing** ("Inspection timed out") on the Cloudflare hosts: fixed (1). After the fix: all saved; MP4s in Videos, MP3 and M4A in Music, titles without the extension, the MP4 plays |
| Online, real YouTube | search, watch page, watch strip, 30 s screen off, no mini player | Pass |
| Online picture-in-picture | by the PiP button and by pressing Home while playing | **Was failing**: YouTube paused itself the moment the window shrank, and its top bar and "Next" banner covered the video. Fixed (2): keeps playing (193 s → 205 s in PiP, 222 s → 234 s after Home), only the video shows |
| YouTube download, RpkAZYU8AAA at 1080p | lookup and download in the app | **Lookup was stalling** (85 s limit): fixed (3), now 24 s. With the bundled yt-dlp 2025.11.12 the 1080p file fails at about 13% (HTTP 403); the app then saved YouTube's own 360p file, labelled "360p · lower quality". With yt-dlp 2026.10.26 put in place by hand (what the self-update does; GitHub is blocked on this PC): **saved at 1080p**, 65.3 MB, in 85 s, MKV (VP9 + AAC), plays |

What was fixed:
1. **Direct links on a network with one broken address family** (`SafeHttpClient`): the checked
   addresses were tried one after another, 10 s each, so two dead addresses ran past the 15 s Inspect
   limit. Now TCP is raced the way browsers do (RFC 8305: families interleaved, next address after
   250 ms, losers cancelled), then one TLS handshake on the winner; a TLS failure moves on to the
   addresses not yet tried. Every address is still checked against the private-network block first.
   Two independent reviews; tests in `safe_http_happy_eyeballs_test.dart` (fake races and real HTTPS).
2. **YouTube pausing in picture-in-picture** (`youtube_bridge.js`): YouTube compares the window's outer
   size with the screen on every resize and pauses non-Premium playback when the window is much
   smaller (found with the WebView's DevTools: `pauseVideo()` from that check). The page now sees an
   outer size at least as large as the screen (the layout still follows the real window), and the PiP
   layout hides everything but the video (and its captions, when turned on).
3. **yt-dlp stalling on a network with one broken address family** (`ExtractorChannel.kt`): yt-dlp has
   no IPv4/IPv6 race, so it waited out timeouts (4+ minutes for one lookup). Before each run, one TCP
   connection per family is tried at once (1.5 s at most, cached 5 minutes per host); when only one
   answers, yt-dlp gets `--force-ipv4` or `--force-ipv6`. The answer is kept per network (Wi-Fi and
   mobile data are asked separately) and only when it is clear; a run with a forced family that
   fails as "offline" asks again and carries on.

Also learned: current yt-dlp versions want a JavaScript engine for YouTube. youtubedl-android ships
QuickJS (`libqjs.so`) and passes it to yt-dlp itself (`--js-runtimes quickjs:...`, seen in the
process list); a hand-run on the emulator with it crashed once (segmentation fault), the app's own
runs did not (D.10). yt-dlp 2026.10.26 downloaded this video at 1080p on this PC with no engine at all.

### B.0c Later the same day: a network that inspects HTTPS

The owner moved to another network. There, IPv6 is refused and IPv4 connections to YouTube fail the
certificate check ("unable to get local issuer certificate": the network inspects HTTPS); GitHub
was unreachable too. Every yt-dlp run then failed in about 7 s, the app treated it as "the site may
have changed" (other clients, an update, the fallback) and the lookup ended with a vague message;
the Diagnostics log showed nothing about lookups. Not an app bug, but two changes came out of it:
- **`NETWORK_BLOCKED`**: a certificate failure is its own code (`ExtractorChannel.mapException`,
  checked early) and message: "This network is blocking a secure connection to the site. Try another
  Wi-Fi or mobile data." No other client, update or fallback is tried for it.
- **Lookups in Diagnostics**: every quality lookup logs `extractor_lookup_ok` (host, time) or
  `extractor_lookup_failed` (host, code, yt-dlp's short reason, time), and an update it triggers.
Also seen: youtubedl-android passes `--js-runtimes quickjs:<libqjs.so>` to yt-dlp by itself.
- **Online tab on such a network**: it stayed blank black. Android's WebView already refused the bad
  certificate (the plugin's default when the app does not answer), but nothing told the screen, so
  the page just stayed blank. Now the app refuses it explicitly, and when it is the page's own (its
  host, or before any page loaded) the tab says "This network is blocking a secure connection to
  YouTube. Try another Wi-Fi or mobile data." with Retry; one on a picture or a video segment never
  covers a working page. iOS: WebKit refuses it itself, and its certificate errors show the same words.

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

From the 2026-11-19 round (install a new build first):

- **YouTube sign-in**: Online → ⋮ → Sign in to YouTube. Google's page should open inside the tab. Sign
  in (password and any 2-step code): you should land back on YouTube with your picture top right. If
  Google refuses, write down its exact words. Also try YouTube's own Sign in button; swipe the app away
  and reopen: still signed in. "Learn more" and "Help" links on Google's page open in Chrome.
  Clear site data: the dialog starts "Signs you out..." and you are signed out after.
- **YouTube downloads**: retry the failed 1080p download (RpkAZYU8AAA). It should finish at 1080p or the
  nearest quality, and the chip says which. Try a Short, a music.youtube.com link, 720p and Best
  available (they play in Videos), and Original audio and MP3 (they land in Music). Queue two or three
  1080p videos at once. A private or age-restricted video gets that exact message. Airplane mode during
  a download: a quick network message with Retry, no "Reason:" line. Settings → Personal tools shows
  the yt-dlp version with "Updated ..." or "Checked ...".
- **Other links**: an Instagram reel, a TikTok, Dailymotion and a v.redd.it link with Choose quality; a
  direct .mp3 or .mp4 on any site (Download); a link to a news page (no Choose quality); a file over
  2 GB (refused on the card).
- **Resume after other apps**: play a song, start a video in the YouTube app: MediaHub pauses. Pause or
  close that video: about 10 seconds later the song plays again. Then: press pause on MediaHub's
  notification while the other app plays (it must stay paused); open a video in MediaHub's Videos tab
  while the other app plays (must stay paused); turn the setting off (must stay paused). A YouTube
  playlist with autoplay must not make the music start and stop between every video. Notifications,
  Maps directions and phone calls work as before.
- **YouTube picture-in-picture**: play a video in Online, tap the PiP button, then press Home on another
  video: both keep playing in the small window and show only the video (no YouTube bars).
- **First YouTube download after installing**: open the app once on Wi-Fi first (it updates yt-dlp at
  start; Settings → Personal tools then says "Updated ..."), then download RpkAZYU8AAA at 1080p.
- **Mini player**: play a song, switch to Videos and Online: the bar slides away, the music and the
  notification keep going; back on Home, Music and Downloads it slides back.
- **Broken song**: rename one downloaded song in a file manager and play its album: the next song plays
  by itself and "Can't play ..." shows once.
- **Online on a network that inspects HTTPS** (B.0c): the tab shows "This network is blocking a secure
  connection to YouTube..." instead of a blank page; on mobile data YouTube loads.
- **Block ads** (A0, on by default): play a few videos in Online until one shows an ad. The ad must be
  silent and skipped as soon as YouTube offers Skip (a short unskippable one may play on silently),
  the video must then play from where it was with its sound, and the notification must show the
  video's title, never the ad's. Let autoplay or a playlist run into the next video: it must play from
  the start, never jump to its end. In YouTube Music, after an ad the notification must show the
  song's own title and artist. Sponsored boxes on Home and under the player are gone. Turn Block ads
  off and on (Settings → Online and the ⋮ menu): the page opens again each time and still plays. If
  YouTube shows "Ad blockers are not allowed" or will not play, write down what it said.

From earlier rounds:

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
3. Done: `feat/post-6-1-fixes` was merged into `main` on 2026-11-20.

The 2026-11-19 builds are in the git-ignored `build/` folder: `MediaHub-Test-arm64.apk`
(`com.mediahub.app.audit`) and `MediaHub-Family-arm64.apk` (`com.mediahub.app`), both release builds
signed with the family key (SHA-256 `DA:DD:95:6A:…:AD:64:D3`). The family APK updates the installed
app in place and keeps its data.

## D. Known follow-ups and accepted risks

1. Accepted (see DECISIONS 18): redirects through yt-dlp's generic extractor, yt-dlp self-update isn't
   signature-checked (Use the built-in yt-dlp restores the bundled copy), the media service is exported
   (needed for Bluetooth and lock screen), jackson version inside youtubedl-android.
2. Deferred, owner's decision: taking links shared from other apps (share intents, SEC-7). It would let
   any app hand MediaHub a link; today you paste links yourself.
3. Android "Delete from phone" for songs and videos that came with the phone needs Android's delete
   consent dialog (`MediaStore.createDeleteRequest`); downloads can already be deleted.
4. iOS: everything that is the same, different or missing on iPhone, what was fixed without a Mac,
   the first-build checklist and the device test list are in `docs/IOS.md`. Picture-in-picture for the
   Online tab needs no Swift (WebKit's own); for local videos it does.
5. Resume after other apps: an app that plays sound without asking Android for it (some games and
   video apps) still plays over MediaHub, and nothing pauses the music then. If a phone call ends with
   no playback change, a waiting song may stay paused (safe; as before). Resuming also happens with the
   screen off (the other app stopped); say if that should change.
6. yt-dlp reads 16 sites (YouTube, YouTube Music, Instagram, Facebook, TikTok, X, Vimeo, SoundCloud,
   Dailymotion, Reddit and their short links). Other sites work only for direct file links. Letting
   yt-dlp try any site is a security decision (it would fetch pages the app has not checked).
7. The YouTube fallback replaces the failed download with the lower-quality one; the chosen quality
   is not kept for a later retry.
8. A direct-link download's `<id>.part` is only removed at the next app start after you delete the row.
9. Next features: ROADMAP section 4.
10. The yt-dlp inside youtubedl-android 0.18.1 is 2025.11.12, a year old: YouTube refuses its 1080p
    files part-way (HTTP 403). MediaHub therefore ships its own newer yt-dlp (2026.10.26, Android
    asset `assets/ytdlp/`, made by `python tools/device/update_ytdlp_asset.py [version]` from PyPI)
    and installs it on first use; re-run that script before a release to ship the newest. The
    self-update from GitHub still runs on top of it. Current yt-dlp also asks for a JavaScript engine for YouTube;
    youtubedl-android hands it the QuickJS it ships (`libqjs.so`). One hand-run with it crashed on the
    emulator; if YouTube lookups ever end in a crash on the phone, that is the first suspect.
