# Architecture & Product Decisions

1. **Target Platforms:** Android & iOS supported.
2. **Theming:** Dark theme only at launch (`#0B0D12` dark background palette).
3. **Playback Architecture:** Local player first, followed by direct-URL downloads.
4. **Trimming:** Duration trim only (no video frame cropping).
5. **Downloading Scope:** Direct URL downloads only (no YouTube or third-party provider extraction).
6. **Android Minimum SDK:** Set to `minSdk = 26` (Android 8.0+).
7. **HTTP Response Header Size Limit in Dart:** `dart:io` `HttpClient` does not expose a configuration limit for incoming HTTP response headers. Header parsing occurs in native C++ runtime buffers within the Dart VM before any userland Dart code executes; checking header sizes post-parsing does not prevent memory allocation. The accepted risk is bounded by strict connection and read timeouts (`connectionTimeout = 10s`, `readTimeout = 20s`), which abort slow or abusive header streams.
8. **INTERNET Permission:** Added `android.permission.INTERNET` to the main AndroidManifest.xml solely for user-initiated direct media downloads via `DownloadEngine`. Cleartext traffic remains strictly blocked via `network_security_config.xml` (`cleartextTrafficPermitted="false"`).
9. **Background Downloads via Foreground Service:** A native Kotlin `DownloadService` (`foregroundServiceType="dataSync"`) and partial wake lock keep the Android process alive while downloads are transferring in the background. If the user explicitly swipes MediaHub away from the Android recents screen, Flutter's engine is destroyed and downloads stop. They are recovered as paused and resume automatically upon the next app launch.
10. **Personal Extractor (Android Only, TASK 6.1):**
    - **Scope & Compliance:** Strictly personal-use tool for public videos only. No logins, no cookies, no cookies-from-browser, no private or paid content, no DRM circumvention.
    - **Architecture & Isolation:** All extractor code lives isolated in `lib/personal/` (Dart) and `android/app/src/main/kotlin/com/example/mediahub/personal/` (Kotlin). Gated by a single toggle `PERSONAL_TOOLS = true` at compile time and disabled by default at runtime under `Settings > Personal tools > "Enable web link downloader"` with legal responsibility notice.
    - **Platform Gate:** Android only. On iOS, the Downloads tab is hidden (`Platform.isAndroid` gate) and all extractor backend operations throw or safely no-op, maintaining clean compilation on iOS.
    - **Spike Findings (youtubedl-android 0.18.1):**
      - Dependency: `io.github.junkfood02.youtubedl-android:library:0.18.1` and `:ffmpeg:0.18.1` from JitPack repository.
      - Licenses: `youtubedl-android` (GPL-3.0), bundled `yt-dlp` (Unlicense), bundled `ffmpeg` (LGPL-2.1 / GPL-3.0).
      - Toolchain compatibility: Fully compatible with AGP 9.1.0, compileSdk 37, minSdk 26 (app requirement, library requires minSdk 24).
      - Packaging requirement: `packaging.jniLibs.useLegacyPackaging = true` and `android:extractNativeLibs="true"` in `AndroidManifest.xml` to correctly extract python/ffmpeg binaries without compression.
      - Binary footprint: ~35–45 MB total APK for `arm64-v8a` containing Python stdlib and FFmpeg binary.
      - First-run extraction: 3–8s initialization off the main thread; subsequent calls take milliseconds.
      - Fixed safety options: `--no-playlist`, `--ignore-config`, no cookies, output template `"<taskId>.%(ext)s"`, `--max-filesize 2G`. Host allowlist and UrlPolicy enforced before invocation.


