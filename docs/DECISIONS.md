# Architecture & Product Decisions

1. **Target Platforms:** Android & iOS supported.
2. **Theming:** Dark theme only at launch (`#0B0D12` dark background palette).
3. **Playback Architecture:** Local player first, followed by direct-URL downloads.
4. **Trimming:** Duration trim only (no video frame cropping).
5. **Downloading Scope:** Direct URL downloads only (no YouTube or third-party provider extraction).
6. **Android Minimum SDK:** Set to `minSdk = 26` (Android 8.0+).
