# MediaHub roadmap

MediaHub is a private media app for one family: play local music and video, find things online,
save them offline. It is never published, so the bar is "safe, fast and pleasant on our own
phones" rather than store rules.

Status keys: **Done** = in the code and covered by tests where possible · **Checked on the emulator** =
also driven by hand on the Android emulator · **Needs phone** = only a real phone can prove it ·
**Needs a Mac** = iOS native work · **Planned** = not started.

## 1. Your goals (checklist)

| # | Goal | Status | Where |
|---|------|--------|-------|
| 1 | UI first: palette, fonts, type hierarchy, consistent components, dark **and** light | Done · Checked on the emulator. Design system "Bijuli" (Volt on Ink), see `docs/DESIGN.md` | `lib/app/theme/*`, `lib/shared/widgets/ui_kit.dart` |
| 2 | Security: no unwanted permissions, nothing that threatens the device, no data loss | Done (section 3) | see section 3 |
| 3 | Android **and** iOS, private family use only | Android: full. iOS: playback, the Online tab, downloads; background play hands over to the native audio stream. iOS picture-in-picture, the share sheet and library import need a Mac | `PlatformInfo` |
| 4 | Online section: YouTube where you can search and see everything, with picture-in-picture and background play like Brave | Done · Checked on the emulator with a local stand-in page (this PC's network blocks YouTube) · Needs phone for real YouTube | `lib/features/online/` |
| 5 | Copy a link in Online and download it from Downloads | Done: **Download** and **Copy link** on the watch strip hand the clean link to Downloads | `download_link_inbox.dart` |
| 6 | Music controls like Spotify / YouTube Music | Done · Checked on the emulator (section 2) | `lib/features/music_player/`, `lib/features/library/` |
| 7 | Video controls: ±10 s, double tap, landscape/portrait, volume and a volume raiser | Done · Checked on the emulator. How loud the boost sounds needs the phone | `lib/features/video_player/`, `DeviceControlsChannel.kt` |
| 8 | Online music keeps playing with the screen off | Android: Done (foreground media service, keep-alive, idle-prompt auto-confirm) · Needs phone for 30+ min on One UI. iOS: native hand-off · Needs a Mac | `online_media_session.dart`, `youtube_bridge.js` |
| 9 | High-quality build | Release: R8 shrinking, not debuggable, signed with the private family key | `android/app/build.gradle.kts` |

## 2. What the app does now

**Music (offline, from the phone and from downloads)**
- Play, pause, next, previous, seek, shuffle, repeat (off / all / one), queue with drag-to-reorder and
  remove. Fast presses add up into one jump: 20 quick Next presses land 20 songs on (or stop at the last
  song with repeat off), with no stutter or skipped seeks. A fuzz test runs 24 queue/shuffle/repeat
  combinations through 200 random operations each.
- Shuffle stays on when you tap a song (the tapped song plays first). Album, artist, playlist and Liked
  pages have Play all and Shuffle.
- The notification / lock-screen / quick-settings player shows the song's cover, a seek slider, Previous,
  Next, a Like heart and shuffle. Bluetooth and car controls use the same session. Android's media
  resumption brings the last song back.
- **Liked songs** (the heart), **playlists** (create, rename, reorder, remove with Undo, add several songs,
  duplicates asked about), **albums** grouped by the phone's album id in disc/track order,
  **artists**, sorting, and **search** over songs, albums, artists and playlists. Search matches every
  word, ignores case and accents, works in Devanagari, and finds Nepali titles from romanised words
  ("resham" finds रेशम फिरिरी).
- Sleep timer (5–60 min or end of song, fades out), playback speed, cover swipe to skip.
- The library rescans by itself when files are added or removed.

**Video**
- ±10 s buttons, double tap left/right (taps add up), seek bar, previous/next video with an "Up next"
  countdown, speed, fit modes (fit, fill, stretch, original) and pinch, subtitles from a sidecar `.srt`/`.vtt`,
  audio tracks, lock.
- Rotation: auto (follows the video's shape and the phone), landscape lock, portrait lock.
- Volume: swipe on the right or the Volume button; above the phone's maximum a **Boost** zone up to 200%
  (Android LoudnessEnhancer on the video's own audio only).
- Picture-in-picture by button or by leaving the app while it plays, with ±10 s and play/pause in the
  window. "Play as audio" hands the video to the music player.
- A decoder hiccup is retried once by itself; the error screen with Try again only shows if that fails.

**Online (YouTube)**
- The mobile YouTube site inside the app: browse, search, watch, everything the site offers, without
  signing in. Background play (screen off or another app), picture-in-picture, media controls in the
  notification, headphone-unplug pause. YouTube Music is one tap away in the menu.
- The watch strip: **Download** (opens Downloads with the link filled in), picture-in-picture, Background,
  **Save** (to Liked songs or a playlist) and **Copy link**.

**Downloads**: paste a YouTube, Instagram or direct https link, pick a quality, and the file joins the
library. Spotify songs are refused with a plain explanation (they are protected).

## 3. Security model (what the app can touch)

| Area | Decision |
|------|----------|
| Permissions | Read audio, read video, notifications, internet, foreground service (media playback, downloads), wake lock. Nothing else: no contacts, location, camera, microphone, storage write, partial photo access, Bluetooth scanning. The notification permission is only asked when you start your first download. |
| Other apps | No deep links; the router ignores routes handed in by the platform and always starts on Home. No share/view intent filters (taking shared links from other apps is deferred, see HANDOFF D). The download service is private. The media service is visible to the system (needed for Bluetooth, lock screen and car controls). Sharing a download goes through a private, read-only provider that serves only files inside the app's downloads folder. |
| Online tab | Only YouTube's own page hosts can load as the page (`youtube_urls.dart`); everything else opens outside or is blocked. The JavaScript bridge answers only YouTube origins and checks a per-page secret token on every message. No sign-in; Settings → Online → **Clear YouTube data** removes cookies, cache and site data. |
| Network | HTTPS only (cleartext disabled twice). Direct downloads refuse private/local addresses (DNS checked, connection pinned to the checked address). |
| yt-dlp | Runs only for links you start, on an allowlist of sites, with fixed safe options (no config files, no cookies, one item per link, live streams and playlists refused, lookups killed after 85 s). Output stays inside the app folder. "Update" fetches the newest yt-dlp from its official GitHub releases and is blocked while a download runs; **Use the built-in yt-dlp** goes back to the bundled copy. |
| Data | Everything stays on the phone. No account, no analytics, nothing in Google cloud backup. Diagnostics log stays local and strips links and file paths. Deleting a download removes its playlist entries and progress in one transaction; files are only ever deleted inside the downloads folder. |
| Downloads | 2 GB per file, free space checked first, file names kept within 255 bytes, partial files cleaned only by their exact internal names, stuck downloads end as "failed". |
| Builds | Release: not debuggable, R8-shrunk (keep rules for every icon named from Dart, checked by a test), signed with the private family key. A release build **refuses to build** without the key. |

### Family signing key (back this up!)

- Keystore: `%USERPROFILE%\.mediahub\mediahub-family.jks`, alias `mediahub`, valid until 2054.
- Passwords: `android/key.properties` (git-ignored, never commit it).
- Certificate SHA-256 (to check a restored key):
  `DA:DD:95:6A:FB:8E:83:04:85:CF:BD:5F:FE:FF:91:6D:A2:1C:56:80:BD:59:13:66:FF:F5:FE:82:9C:AD:64:D3`
- Keep two copies: e.g. a password-manager entry (file + passwords) and an encrypted USB stick.
  Without them the installed app can't be updated; Android would ask to uninstall first.

## 4. My recommendations (next, in priority order)

1. **Phone check** of the items in `docs/HANDOFF.md` section B (real YouTube, 30 min screen off,
   boost loudness, Bluetooth, sharing).
2. **Library backup & restore** (likes, playlists, play counts, settings) to a file you keep, so a
   reinstall or a new phone never loses them.
3. **"Save to phone" for downloads**: copy finished downloads into the shared Music/Movies folders.
4. **Delete from phone** for songs and videos that came with the phone (needs Android's delete consent dialog).
5. **iOS on a Mac**: build, picture-in-picture (AVKit), share sheet, Files import.
6. **App lock** (fingerprint / PIN) for Downloads and Online if children use the phones.
7. **Offline extras**: lyrics, equalizer presets, gapless albums, Android Auto browsing, Folders and Genres chips
   (the data is already scanned).
8. **Release hygiene**: rename the Kotlin package from `com.example.mediahub`, a small CI that runs the
   analyzer and the tests on every push.
