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
| 3 | Android **and** iOS, private family use only | Android: full. iOS: **never built or run** (needs a Mac). In the code: playback, the library of MediaHub's own downloads, the basic video player, the Online tab (screen-off sound hands over to the iPhone's own player) and direct-link and YouTube downloads (no 1080p, no yt-dlp sites). Missing without Swift: picture-in-picture for local videos, the volume raiser, the share sheet, importing the iPhone's own files. Same / different / missing, today's fixes and the first-build checklist: `docs/IOS.md` | `PlatformInfo`, `docs/IOS.md` |
| 4 | Online section: YouTube where you can search and see everything, with picture-in-picture and background play like Brave | Done · Checked on the emulator with real YouTube (2026-11-19: search, watch, screen off, picture-in-picture by button and by Home) · Needs phone for sign-in and long screen-off | `lib/features/online/` |
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
- The mobile YouTube site inside the app: browse, search, watch, everything the site offers. Background
  play (screen off or another app), picture-in-picture (only the video shows, and it keeps playing:
  YouTube's own small-window check is answered), media controls in the notification,
  headphone-unplug pause. YouTube Music is one tap away in the menu.
- A Wi-Fi that breaks the secure connection (it inspects HTTPS) no longer leaves the tab blank: it says
  "This network is blocking a secure connection to YouTube. Try another Wi-Fi or mobile data.", with Retry.
- **Sign in to YouTube** (⋮ menu, or YouTube's own button): Google's sign-in pages open inside the tab,
  and the login is kept. Google may still refuse an app's web view for some accounts; the tab works
  without an account too. Clear site data signs you out.
- The watch strip: **Download** (opens Downloads with the link filled in), picture-in-picture, Background,
  **Save** (to Liked songs or a playlist) and **Copy link**.
- **Block ads** (Settings → Online and the ⋮ menu, on by default): video ads are taken out of YouTube's
  player data before the player sees them; an ad that still starts is muted and its Skip pressed (run to
  its end only when it is surely a short mid-roll ad, so the video itself is never skipped; a pre-roll
  or an ad stitched into the video plays on muted until Skip shows), and the notification keeps showing
  the video, never the ad; sponsored boxes in the feed and under the player are hidden; the page's ad and
  ad-tracking requests fail (on iOS every request to an ad address; Android has no native blocking, see
  section 3). Changing it opens the page again. If YouTube ever
  refuses to play with it on (its "Ad blockers are not allowed" message, which is also removed when it
  comes in the player data), turn it off. In the code; not yet checked on the emulator with real YouTube.

**Downloads**: paste a YouTube, Instagram (or another yt-dlp site) or direct https link, pick a quality,
and the file joins the library: videos in Videos, sound in Music (checked from the file itself; sound
you asked for always stays in Music). A missing quality saves the nearest one and the chip says so.
yt-dlp **updates itself**: after a failure a newer version may fix (at most every 12 hours, never under
a running download), and with a quiet weekly check at app start (not on mobile data). Spotify songs are
refused with a plain explanation (they are protected).

**Save to phone and delete from phone** (2026-11-25): Settings → Downloads → **Save downloads to**:
Inside MediaHub (private, the default) or Phone storage. Phone storage on Android 10+ moves each finished
download into MediaStore (Music/MediaHub for sound, Movies/MediaHub for video, written with IS_PENDING,
no storage permission); it keeps its library id, so favourites, play counts, playlists and video
positions stay, and the phone scan never shows it twice. Every download's menu also has **Save to
phone**. Android 8 and 9 keep downloads inside MediaHub (no permission-free way). **Delete from phone**
now also works for the phone's own songs and videos (Android 11+: the system's consent dialog; Android
10: its RecoverableSecurityException dialog); favourites, playlists, history and the queue are cleaned.
iPhone: songs show in the Files app, videos are also added to Photos; it deletes its own downloads only.

**App lock** (2026-11-25, Settings → App lock, off by default): fingerprint, face or the phone's PIN
(local_auth); locks at start and after 0, 1, 5, 15 or 30 minutes in the background; covers the whole app
(default) or only Downloads and Online. Music, the notification, headset buttons, picture-in-picture and
downloads keep working while locked; the lock never covers the picture-in-picture window.

**Lyrics, equalizer, Android Auto** (2026-11-25): the Now Playing footer has **Lyrics** (a `.lrc` next to
the file, then the file's own tag, then, only when Settings → Audio → Find lyrics online is on, LRCLIB;
synced lines follow the music and a tap seeks) and, on Android, an **Equalizer** (seven presets, custom
bands, loudness boost up to +10 dB; saved; music only). **Android Auto** browses Songs, Albums, Playlists
and Favourites; a song picked there plays its whole list. CarPlay needs Apple's entitlement (not possible).

**Playback with other apps** (Android): when another app plays, the music pauses, and it plays again
about 10 seconds after that app stops (Settings → Audio & headset → Resume after other apps, on by
default, within 30 minutes).

## 3. Security model (what the app can touch)

| Area | Decision |
|------|----------|
| Permissions | Read audio, read video, notifications, internet, foreground service (media playback, downloads), wake lock, biometric (App lock, no prompt). Nothing else: no contacts, location, camera, microphone, storage write, partial photo access, Bluetooth scanning. The notification permission is only asked when you start your first download. |
| Other apps | No deep links; the router ignores routes handed in by the platform and always starts on Home. No share/view intent filters (taking shared links from other apps is deferred, see HANDOFF D). The download service is private. The media service is visible to the system (needed for Bluetooth, lock screen and car controls). Sharing a download goes through a private, read-only provider that serves only files inside the app's downloads folder. |
| Online tab | Only YouTube's own page hosts, plus Google's three sign-in hosts (`accounts.google.com`, `accounts.youtube.com`, `gds.google.com`; https only, exact names, no other port), can load as the page (`youtube_urls.dart`); everything else, other Google pages included, opens outside or is blocked. The JavaScript bridge answers only YouTube origins, checks a per-page secret token on every message, and is off on the sign-in pages: no command goes into them and no message from them counts, so MediaHub never sees or touches the password. The login lives only in the WebView's own cookies on the phone; Settings → Online → **Clear YouTube data** removes it with the cache and site data. The WebView presents itself as Chrome and sends no `X-Requested-With` header (so Google treats it like a browser); third-party cookies stay off. A certificate the phone does not trust is always refused, never let through; when it is the page's own (an HTTPS-inspecting Wi-Fi), the tab says "This network is blocking a secure connection to YouTube" instead of staying blank, and a bad certificate on a picture or a video segment never covers a page that works. |
| Block ads (Online tab) | All inside the bridge's own limits: YouTube pages only, main frame only, off on the sign-in pages; it sends no new kind of message to Dart. The page script removes only the ad keys (`adPlacements`, `playerAds`, `adSlots`, and the enforcement message) from YouTube's player data, hides ad boxes with CSS, mutes and skips an ad from the player's class change (no timer), and fails the page's own requests (fetch, XHR, sendBeacon) to ad hosts (doubleclick.net, googleadservices.com, googlesyndication.com, googletagservices.com, imasdk.googleapis.com) and YouTube's ad paths (`/pagead/`, `/api/stats/ads`, `/ptracking`, `/get_midroll_`). An ad is run to its end only when it is surely a mid-roll: just before the ad class came on, the same player element was seen playing the address's own video (its length, not near its end, the address and the latest player data naming it), and the ad is another stream, 30 s or shorter (an ad nobody can skip), clearly shorter than the video and not as long as another video seen; only the break's first stream is ever run to its end. On any doubt (a pre-roll, no video in the address, the address or the player data moved on, the video ended, the next video loading, an ad stitched into the video's stream, a longer ad, a second stream in the same break) it is only muted and its Skip pressed, so the video itself is never skipped. Native rules: iOS a WebKit content rule list. Android has **none**: the WebView plugin's Android content blockers send an extra HEAD request for every resource (video segments included), and its sub-frame pattern is never consulted for an http(s) frame, so on Android an ad `<script>`, `<img>` or `<iframe>` the page loads still loads (only the page's own fetch, XHR and sendBeacon calls fail). Never blocked: `googlevideo.com/videoplayback`, `/youtubei/v1/...`, `i.ytimg.com`. Risk: YouTube can detect ad blocking and show its "Ad blockers are not allowed" message or delay playback; the message is pruned and hidden, and the setting can be turned off. |
| Lyrics online | Off by default. When on, only for a song without its own lyrics: one `GET https://lrclib.net/api/get` with its title, artist, album and length, through the safe HTTP client (https, public addresses, pinned DNS, 1 MB cap); an answer from any other host (a redirect) is dropped. The answer is kept on the phone (app support folder), so a song is asked about once. |
| Save to / delete from phone | Writes only through MediaStore into Music/MediaHub and Movies/MediaHub, and only files from MediaHub's own downloads folder (checked natively). Deletes only `content://media` items, through the system's own consent dialog (Android 10+). |
| Network | HTTPS only (cleartext disabled twice). Direct downloads refuse private/local addresses (DNS checked, every address checked, connections pinned to the checked addresses). The checked addresses are tried the way browsers do (IPv4 and IPv6 raced, RFC 8305), so a broken address family costs a quarter of a second, not a timeout. |
| yt-dlp | Runs only for links you start, on an allowlist of 16 sites, with fixed safe options (no config files, no cookies, one item per link, live streams and playlists refused, lookups killed after 85 s; when only IPv4 or only IPv6 reaches the site, yt-dlp is told to use it). Output stays inside the app folder. Updates come from yt-dlp's official GitHub releases (not signature-checked, see HANDOFF D): by hand in Settings, after a failure a newer version may fix (at most every 12 hours), or in a weekly check at app start (release builds only, not on mobile data; a failed check waits a day). An update never replaces yt-dlp while it runs (a native lock, and downloads wait for each other). MediaHub ships its own, newer yt-dlp (from yt-dlp's PyPI package, `tools/device/update_ytdlp_asset.py`; 2026.10.26 today, the library's own is 2025.11.12) and installs it on first use when it is newer than the phone's copy, only while no yt-dlp runs. **Use the built-in yt-dlp** goes back to that shipped copy. |
| Data | Everything stays on the phone. No account, no analytics, nothing in Google cloud backup. Diagnostics log stays local and strips links and file paths. Deleting a download removes its playlist entries and progress in one transaction; files are only ever deleted inside the downloads folder. |
| Downloads | 2 GB per file (refused on the link card when the size is known), free space checked first, file names kept within 255 bytes, partial files cleaned only by their exact internal names, stuck downloads end as "failed". Direct links of any site go through the same checks (https, no private addresses, the first bytes must be media). |
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
2. ~~**Library backup & restore**~~: done on `feat/size-backup-data` (Android; iPhone needs a document
   picker). Also there: arm64-only APKs and "Ask before big downloads on mobile data".
3. ~~**"Save to phone" for downloads**~~: done (2026-11-25).
4. ~~**Delete from phone** for songs and videos that came with the phone~~: done (2026-11-25).
5. **iOS on a Mac**: the first build and a pass on a real iPhone (`docs/IOS.md` sections 6 and 7),
   then the share sheet, keeping downloads out of iCloud backup, Files import, picture-in-picture for
   local videos.
6. ~~**App lock** (fingerprint / PIN)~~: done (2026-11-25), whole app or Downloads + Online.
7. **Offline extras**: ~~lyrics, equalizer presets, Android Auto browsing~~ done (2026-11-25); still open:
   gapless albums, Folders and Genres chips (the data is already scanned), multi-select in the song list.
8. **Release hygiene**: rename the Kotlin package from `com.example.mediahub`, a small CI that runs the
   analyzer and the tests on every push.
