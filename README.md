<!-- ───────────────────────────── HEADER ───────────────────────────── -->
<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&height=120&color=0:000000,50:5A0418,100:CC324C&section=header" width="100%" alt=""/>

<img src="docs/readme/hero.svg" width="100%" alt="MediaHub — music, video and YouTube in one place"/>

<a href="https://github.com/itsniranjannn/mediahub">
  <img src="https://readme-typing-svg.demolab.com?font=Poppins&weight=600&size=22&duration=2800&pause=900&color=FF7A92&center=true&vCenter=true&width=640&lines=Play+your+music+like+Spotify.;Watch+videos+with+PiP+and+volume+boost.;YouTube+with+background+play+and+no+ads.;Download+in+1080p+or+MP3+320+kbps.;Made+in+Nepal+%E2%9D%A4+by+Niranjan." alt="Typing animation"/>
</a>

<br/>

![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-ready-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-in%20progress-000000?style=for-the-badge&logo=apple&logoColor=white)
<br/>
![Riverpod](https://img.shields.io/badge/State-Riverpod%203-81021F?style=flat-square)
![Drift](https://img.shields.io/badge/DB-Drift-381932?style=flat-square)
![Tests](https://img.shields.io/badge/tests-1690%2B%20passing-0A6A40?style=flat-square)
![Theme](https://img.shields.io/badge/design-Sindur-CC324C?style=flat-square)
![License](https://img.shields.io/badge/license-All%20rights%20reserved-F69E1C?style=flat-square)

**[Features](#-features) · [Screens](#-screens) · [Design](#-design-system-sindur) · [Architecture](#-architecture) · [Security](#-security--privacy) · [Build](#-getting-started) · [Roadmap](#-roadmap)**

</div>

---

## 🎧 What is MediaHub?

**MediaHub** is a private, all-in-one media app for the family: play the songs and videos already on the phone,
browse YouTube with background play and picture-in-picture, and save anything offline in the quality you want.
Everything stays on the phone — **no account, no analytics, no cloud**.

> [!TIP]
> Set your name in **Settings → You → Your name** and Home greets you with an animated **"नमस्ते, &lt;your name&gt;"**.

---

## ✨ Features

<table>
<tr>
<td width="50%" valign="top">

### 🎵 Music
- Play, pause, next/previous with **burst-safe** fast taps
- Shuffle, repeat (off / all / one), drag-to-reorder **queue**
- **Favourites**, playlists, albums, artists, smart search
  (finds रेशम फिरिरी from *"resham"*)
- Sleep timer with fade-out, playback speed
- Lock-screen, notification, Bluetooth & car controls
- **Android Auto**: browse Songs, Albums, Playlists, Favourites
- **Lyrics** from the file or a `.lrc`, synced scrolling; LRCLIB lookup (opt-in, with title cleanup & search fallback)
- **Equalizer** presets, custom bands and loudness boost (Android)
- Pauses for other apps and **resumes by itself**
- **Delete from phone** for the phone's own songs (Android's consent dialog)

</td>
<td width="50%" valign="top">

### 🎬 Video
- ±10 s buttons, **double-tap seek**, pinch & fit modes
- Auto landscape / portrait by the video's shape
- **Volume boost** up to 200 % (video audio only)
- Picture-in-picture, subtitles (`.srt` / `.vtt`), audio tracks
- *Continue watching* with amber progress lines
- "Play as audio" hands a video to the music player

</td>
</tr>
<tr>
<td valign="top">

### 🌐 Online (YouTube)
- The full mobile YouTube site inside the app
- **Background play** with the screen off — and it **keeps playing when you clear the app** (hands over to the native player instantly)
- Play / pause from the notification any number of times after a swipe-away
- **Picture-in-picture** that keeps playing
- **Block ads** (on by default) — video ads pruned, sponsored boxes hidden
- Google sign-in on Google's own page (the app never sees the password)
- One-tap **Download** / **Copy link** from the watch page

</td>
<td valign="top">

### ⬇️ Downloads
- Paste a YouTube, Instagram, TikTok… or direct `https` link
- **Share to MediaHub** from YouTube, Instagram, TikTok, Facebook or a browser: the link opens in Downloads, ready to pick a quality (Android)
- **Video** qualities up to 2160p, labelled with real sizes
- **Audio**: MP3 **320 / 256 / 192 / 128 kbps** or original M4A / Opus
- Videos land in *Videos*, sound in *Music* — automatically
- **Save to phone**: into Music/MediaHub and Movies/MediaHub (Gallery, Files), per download or for all
- yt-dlp **built in**, self-updating with checksum verification; IPv4/IPv6 racing
- **Pause & resume** that continues from the same byte — even after the app is closed; *Resume all* from the notification
- **Choose where downloads go**: inside MediaHub (private) or phone storage
- Clean list: 5 newest + *Show all*

</td>
</tr>
</table>

<details>
<summary><b>🧩 More details (click to expand)</b></summary>

| Area | Highlights |
|---|---|
| Home | Animated greeting hero, *Continue listening* card, bento quick-actions with shine sweep, rails for Recently played · Most played · Recently added · Favourites |
| Settings | Short grouped list (Appearance · Playback & audio · Downloads · Online · Privacy & security · Backup · About), animated planet backdrop with translucent cards, pinned signature footer, theme picker (System · Dark · Light · **Bijuli Classic**), your name, equalizer & online lyrics, **App lock** (fingerprint / face / PIN, whole app or Downloads + Online), Online, downloads, backup & restore |
| Accessibility | WCAG-checked contrast in every theme, large-text safe (tested at 1.3×), reduced-motion respected, screen-reader labels |
| Nepali | Devanagari drawn natively in every name and body style (Poppins) |
| Reliability | Decoder hiccups retried quietly, stuck downloads end cleanly, free-space check before saving, caches capped and cleaned (lyrics, covers, partial files) |

</details>

---

## 📱 Screens

<div align="center">

**Sindur light** — Home · Videos · Downloads

<img src="docs/readme/screens-light.png" width="820" alt="Sindur light theme: Home with the greeting and Continue listening, the Videos library with Continue watching, and Downloads"/>

**Sindur dark** — Home · Videos · Downloads

<img src="docs/readme/screens-dark.png" width="820" alt="Sindur dark theme: Home, Videos and Downloads"/>

**Settings and About** — the compact list with the pinned signature footer; About holds the open-source licences (light and dark)

<img src="docs/readme/settings.png" width="820" alt="Settings top level and the About page with the Open-source licences row, in the light and dark themes"/>

**Now playing** — the player, synced lyrics and the equalizer (the player is always dark)

<img src="docs/readme/player.png" width="820" alt="Now playing with album art, the synced lyrics sheet and the equalizer sheet"/>

<sub>Captured on the Android emulator (release build) with demo media.</sub>

</div>

---

## 🎨 Design system: Sindur

> **Sindur** (सिन्दूर) — the crimson of tika: festive red on black and on light sand.

<div align="center">

| Dark | | Light | |
|---|---|---|---|
| ![](https://img.shields.io/badge/-%20%20%20%20%20%20-000000?style=flat-square) | Black canvas `#000000` | ![](https://img.shields.io/badge/-%20%20%20%20%20%20-F6EBCF?style=flat-square) | Light sand `#F6EBCF` |
| ![](https://img.shields.io/badge/-%20%20%20%20%20%20-CC324C?style=flat-square) | Crimson fill `#CC324C` | ![](https://img.shields.io/badge/-%20%20%20%20%20%20-81021F?style=flat-square) | Wine red `#81021F` |
| ![](https://img.shields.io/badge/-%20%20%20%20%20%20-FF7A92?style=flat-square) | Rose accent `#FF7A92` | ![](https://img.shields.io/badge/-%20%20%20%20%20%20-AAA6E3?style=flat-square) | Lavender `#AAA6E3` |
| ![](https://img.shields.io/badge/-%20%20%20%20%20%20-381932?style=flat-square) | Plum `#381932` | ![](https://img.shields.io/badge/-%20%20%20%20%20%20-C6CBE8?style=flat-square) | Periwinkle `#C6CBE8` |
| ![](https://img.shields.io/badge/-%20%20%20%20%20%20-F69E1C?style=flat-square) | Amber spark `#F69E1C` | ![](https://img.shields.io/badge/-%20%20%20%20%20%20-32396F?style=flat-square) | Indigo `#32396F` |
| ![](https://img.shields.io/badge/-%20%20%20%20%20%20-FFF3E6?style=flat-square) | Milk text `#FFF3E6` | ![](https://img.shields.io/badge/-%20%20%20%20%20%20-381932?style=flat-square) | Plum text `#381932` |

</div>

- **Type:** *Fraunces* for headings · *Poppins* for names and reading text (Latin + Devanagari) · *DM Mono* for times and sizes · *Great Vibes* for the author signature
- **Signature pieces:** the dark **Ink Dock** (mini player + nav, same in both themes), crimson **sticker** buttons with a soft glow, glowing hero bands, amber section marks
- **Motion:** press-scale 0.97, shine sweeps, entrance fades — all switched off with *reduce motion*
- **Bijuli Classic:** the original lime-on-violet look, kept as an optional theme
- Full spec: [`docs/DESIGN.md`](docs/DESIGN.md) — every colour pair is contrast-tested in `test/unit/palette_contrast_test.dart`

---

## 🏗️ Architecture

```mermaid
flowchart LR
    UI["🎨 Flutter UI<br/>(features/*)"] --> ST["🧠 Riverpod<br/>providers"]
    ST --> DB[("🗄️ Drift / SQLite<br/>library, likes, playlists")]
    ST --> AU["🎵 audio_service<br/>+ just_audio"]
    ST --> VP["🎬 video_player<br/>(patched: boost)"]
    ST --> WV["🌐 InAppWebView<br/>YouTube + bridge JS"]
    ST --> DL["⬇️ Download engine"]
    DL --> HTTP["🔒 SafeHttpClient<br/>direct links"]
    DL --> YT["⚡ youtube_explode<br/>fast lookup"]
    DL --> NAT["🤖 Kotlin channel<br/>yt-dlp + ffmpeg"]
    style UI fill:#CC324C,color:#fff,stroke:#81021F
    style ST fill:#381932,color:#FFF3E6,stroke:#AAA6E3
    style DB fill:#32396F,color:#FFF3E6
    style DL fill:#F69E1C,color:#000
```

<details>
<summary><b>📂 Project layout</b></summary>

```text
lib/
├── app/          # theme (Sindur + Bijuli Classic), router, shell
├── core/         # security, storage, logging, downloads, platform
├── data/         # Drift database, repositories, download runners
├── features/     # home · library · music_player · video_player
│                 # online · downloads · playlists · settings
├── personal/     # yt-dlp backend, format options, quality sheet
└── shared/       # ui_kit (buttons, tiles, hero bands), ink dock
android/          # Kotlin: yt-dlp channel, device controls, PiP
ios/              # Swift + Codemagic workflow
docs/             # DESIGN, HANDOFF, ROADMAP, IOS, DECISIONS
test/             # ~1,900 unit + widget tests, JS bridge tests
```

</details>

---

## 🔐 Security & privacy

| | |
|---|---|
| 📵 **Minimal permissions** | Audio, video, notifications, internet, foreground media service — no contacts, location, camera or mic |
| 🔒 **HTTPS only** | Cleartext disabled; bad certificates are always refused (with a clear message on networks that inspect HTTPS) |
| 🏠 **No private-network access** | Every download address is checked and pinned before connecting |
| 🧪 **Sandboxed YouTube** | Only YouTube and Google sign-in hosts load; the JS bridge needs a per-page secret and is off on sign-in pages |
| 💾 **Data stays local** | No account, no analytics, no cloud backup; diagnostics strip links and paths |
| 🔐 **App lock** | Fingerprint / face / PIN; hides the app in Recents and blocks screenshots while on; can't be skipped by PiP or by changing the clock |
| 🛡️ **Verified updates** | yt-dlp updates are checked against the official SHA-256 sums before install |
| ✍️ **Signed releases** | Release builds are R8-shrunk, not debuggable, and refuse to build without the private signing key |
| ©️ **Proprietary** | All rights reserved — see [`LICENSE`](LICENSE); every source file carries the copyright notice |

---

## 🚀 Getting started

```bash
# 1. Get the code
git clone https://github.com/itsniranjannn/mediahub.git
cd mediahub

# 2. Install packages
flutter pub get

# 3. Check everything
dart analyze lib test
flutter test
node --test test/js/youtube_bridge_test.js

# 4. Run on a device or emulator
flutter run
```

<details>
<summary><b>📦 Release builds</b></summary>

```bash
# Signed release APK (needs android/key.properties + your keystore — never commit them)
bash tools/device/build_apks.sh family

# Refresh the bundled yt-dlp from PyPI before a release
python tools/device/update_ytdlp_asset.py
```

iOS builds run on Codemagic (`codemagic.yaml`); see [`docs/IOS.md`](docs/IOS.md).

</details>

---

## 🗺️ Roadmap

- [x] Sindur redesign — new colours, fonts, Home, Videos, Downloads
- [x] Video / Audio quality sections with MP3 bitrates
- [x] Built-in yt-dlp, ad blocker, PiP that keeps playing
- [x] Library backup & restore file
- [x] Smaller APK (64-bit only)
- [x] Save downloads to the phone's Music / Movies folders
- [x] Delete the phone's own songs and videos from MediaHub
- [x] App lock (fingerprint / face / PIN)
- [x] Lyrics (synced), equalizer, Android Auto browsing
- [x] Share links into MediaHub from other apps (Android)
- [ ] First run on a real iPhone

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the full list.

---

<div align="center">

### 👨‍💻 Author

**Niranjan Katwal**
<br/>
<a href="https://github.com/itsniranjannn"><img src="https://img.shields.io/badge/GitHub-itsniranjannn-181717?style=for-the-badge&logo=github"/></a>

<sub>Copyright © 2026 Niranjan Katwal. All rights reserved. See <a href="LICENSE">LICENSE</a>.</sub>

<img src="https://capsule-render.vercel.app/api?type=waving&height=100&color=0:CC324C,50:5A0418,100:000000&section=footer" width="100%" alt=""/>

</div>
