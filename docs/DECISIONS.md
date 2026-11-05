# Architecture & Product Decisions

1. **Target Platforms:** Android & iOS supported.
2. **Theming:** Dark theme only at launch (`#0B0D12` dark background palette).
3. **Playback Architecture:** Local player first, followed by direct-URL downloads.
4. **Trimming:** Duration trim only (no video frame cropping).
5. **Downloading Scope:** Direct URL downloads only (no YouTube or third-party provider extraction).
6. **Android Minimum SDK:** Set to `minSdk = 26` (Android 8.0+).
7. **HTTP Response Header Size Limit in Dart:** `dart:io` `HttpClient` does not expose a configuration limit for incoming HTTP response headers. Header parsing occurs in native C++ runtime buffers within the Dart VM before any userland Dart code executes; checking header sizes post-parsing does not prevent memory allocation. The accepted risk is bounded by strict connection and read timeouts (`connectionTimeout = 10s`, `readTimeout = 20s`), which abort slow or abusive header streams.
8. **INTERNET Permission:** Added `android.permission.INTERNET` to the main AndroidManifest.xml solely for user-initiated direct media downloads via `DownloadEngine`. Cleartext traffic remains strictly blocked via `network_security_config.xml` (`cleartextTrafficPermitted="false"`).

