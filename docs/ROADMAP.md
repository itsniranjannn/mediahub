# MediaHub roadmap

MediaHub is a private media app for one family: play local music and video, find things online,
save them offline. It is never published, so the bar is "safe, fast and pleasant on our own
phones" rather than store rules.

Status keys: **Done** = in the code and covered by tests where possible · **Needs device check** =
written but only verifiable on a real phone · **Planned** = not started.

## 1. Your goals (checklist)

| # | Goal | Status | Where |
|---|------|--------|-------|
| 1 | UI first: palette, fonts, typography, consistent components | Done (design system) · screens restyled in this round · Needs device check | `lib/app/theme/*`, `lib/shared/widgets/ui_kit.dart` |
| 2 | Security: no unwanted permissions, nothing that threatens the device, no data loss | Done for permissions, backup, network, release signing · data-loss work below | see section 3 |
| 3 | Android **and** iOS, private family use only | Android: full. iOS: playback, Explore (search / stream / download of ready-made streams), direct-link downloads. iOS local library import is Planned. iOS needs a Mac to build. | `PlatformInfo` |
| 4 | Online section: search YouTube, play and download from there | Done · Needs device check | `lib/features/explore/` |
| 5 | Picture-in-picture for video | Android: Done (button + auto when leaving) · Needs device check. iOS: Planned (needs native AVKit code and a Mac) | `DeviceControlsChannel.kt`, `video_player_screen.dart` |
| 6 | High-quality build | Release build: R8 shrinking, not debuggable, signed with a private family key | `android/app/build.gradle.kts`, `proguard-rules.pro` |
| 7 | One app that does it all: links -> downloads -> library -> playback, plus browsing YouTube | Done end to end · Needs device check | Downloads, Explore, Music, Videos |

## 2. What was added in this round

- **Design system "Midnight Violet"**: near-black blue canvas, one violet accent with dark ink on
  it, teal for video/success, rose only for favourites. Inter with a fixed type scale (32/26/22/18/
  15/13/12/11) and real semibold for bold weights. Global themes for cards, buttons, inputs, chips,
  sliders, sheets, dialogs, snackbars and page transitions.
- **Navigation**: Home, Music, Videos, Explore, Downloads on a glass bar with a pill indicator.
  Settings moved to the gear on Home.
- **Explore**: YouTube search with recent searches, result cards with thumbnail and duration,
  *Listen* (audio in the music player with notification controls), *Watch* (video player),
  *Download* (every quality up to 4K through yt-dlp on Android; ready-made streams on iOS).
  Works the same way on both platforms because the search/stream code is pure Dart.
- **Video player**: picture-in-picture, rotate button, brightness/volume/seek swipes, tidier top bar.
- **Artwork identity**: songs and videos without art get a gradient cover (8 palettes picked by a
  stable hash of the file, so an item looks the same everywhere). Video cards use real 16:9 thumbnails
  that fade in. One shared duration badge. Now Playing is tinted with the song's palette. The
  remaining design polish is listed in `docs/HANDOFF.md`.
- **No data loss**: the library rescans once per start. Favourites, play counts, playlists and video
  progress carry over when a file comes back with a new system id. A download whose bytes were already
  complete finishes instead of failing.
- **Security**: removed the partial-media permission, no cloud backup or device-transfer of app data,
  cleartext traffic off (also in the manifest), release builds shrunk and signed with a private key
  stored outside the repository.

## 3. Security model (what the app can touch)

| Area | Decision |
|------|----------|
| Permissions | Read audio, read video, notifications, internet, foreground service (media playback, downloads), wake lock. Nothing else: no contacts, location, camera, microphone, storage write, partial photo access, Bluetooth scanning. The notification permission is only asked when you start your first download. |
| Other apps | No deep links (`flutter_deeplinking_enabled=false`), no share/view intent filters. The download service is private. The media service is visible to the system (needed for Bluetooth, lock screen and car controls). |
| Network | HTTPS only (cleartext disabled twice). Direct downloads refuse private/local addresses (DNS checked, connection pinned to the checked address). Explore only plays and downloads from YouTube's own media hosts. |
| yt-dlp | Runs only for links you start, on an allowlist of sites, with fixed safe options (no config files, no cookies, one item per link, live streams refused, playlists/channels refused, link lookups killed after 85 s). Output stays inside the app folder. "Update" fetches the newest yt-dlp from its official GitHub releases; **Reset to bundled** in Settings goes back to the copy shipped in the app if an update ever misbehaves. |
| Data | Everything stays on the phone. No account, no analytics, nothing in Google cloud backup. Phone-to-phone transfer (when *you* set up a new phone) carries the library, settings and downloads. Uninstalling from Settings offers "Keep app data" (Android 10+). Diagnostics log stays local and strips links and file paths. |
| Downloads | 2 GB per file, free space checked before every download (twice the size for yt-dlp merges), partial files cleaned only by their exact internal names so a finished file can never be swept away, stuck downloads end as "failed" instead of keeping the phone awake. |
| Builds | Release: not debuggable, R8-shrunk (with keep rules for the notification icons), signed with the private family key. A release build **refuses to build** without the key, so the phones can always be updated in place. |

### Family signing key (back this up!)

- Keystore: `%USERPROFILE%\.mediahub\mediahub-family.jks`, alias `mediahub`, valid until 2054.
- Passwords: `android/key.properties` (git-ignored, never commit it).
- Certificate SHA-256 (to check a restored key):
  `DA:DD:95:6A:FB:8E:83:04:85:CF:BD:5F:FE:FF:91:6D:A2:1C:56:80:BD:59:13:66:FF:F5:FE:82:9C:AD:64:D3`
- Keep two copies: e.g. a password-manager entry (file + passwords) and an encrypted USB stick.
  Without them the installed app can't be updated; Android would ask to uninstall first.

## 4. My recommendations (next, in priority order)

1. **Library backup & restore** (favourites, playlists, play counts, settings) to a file you keep,
   so a reinstall or a new phone never loses them. Today they live only in the app database.
2. **"Save to phone" for downloads**: copy finished downloads into the shared Music/Movies folders
   so they survive an uninstall and show up in other apps.
3. **Explore extras**: play the next result automatically, "add to queue", channel pages,
   search suggestions while typing, and a mini "Up next" list in the video player.
4. **App lock** (fingerprint / PIN) for the Downloads and Explore tabs if children use the phones.
5. **iOS**: build on a Mac, add picture-in-picture (AVKit) and file import for the local library.
6. **Offline-first polish**: lyrics/metadata editing, sleep timer, equalizer presets, gapless
   album playback, Android Auto media browsing.
7. **Release hygiene**: rename the Kotlin package from `com.example.mediahub`, add a small CI
   that runs `flutter analyze` and the tests on every push.
