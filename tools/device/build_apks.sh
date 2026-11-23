#!/usr/bin/env bash
# Builds MediaHub APKs from a scratch copy of the repo, so the real tree is never touched.
#
# Usage: tools/device/build_apks.sh <mode>
#   test      side-by-side "MediaHub Test" (com.mediahub.app.audit), debug, arm64 (phone)
#   emulator  same app id, debug, x86_64, demo data (--dart-define=MEDIAHUB_DEMO=true) and the
#             offline Online-tab fixture (--dart-define=MEDIAHUB_ONLINE_FIXTURE=true: a local stand-in
#             for a YouTube watch page, since the emulator's network may not reach YouTube; debug only)
#   family    real app id com.mediahub.app, RELEASE, arm64, signed with the family key
#   relx64    side-by-side id, RELEASE, x86_64 (R8 smoke test on the emulator)
#   testrel   side-by-side id, RELEASE, arm64 (real-speed test build for the phone)
#
# Env:
#   BUILD_COPY        scratch copy location (default: $HOME/.mediahub/build-copy)
#   FLUTTER_BIN       folder to put first on PATH (e.g. /c/Users/me/flutter-sdk/bin)
#   SDK_PLATFORM_FIX  set to 1 if your Android SDK installs the platform as "android-37.0"
#                     (AGP then can't find "android-37"; this patches compileSdk in the copy)
#
# Release modes need android/key.properties and the family keystore it points to
# (both are git-ignored; restore them from your backup, see docs/ROADMAP.md).
set -euo pipefail
MODE="${1:-test}"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
A="${BUILD_COPY:-$HOME/.mediahub/build-copy}"
if [ -n "${FLUTTER_BIN:-}" ]; then export PATH="$FLUTTER_BIN:$PATH"; fi

case "$MODE" in test|emulator|family|relx64|testrel) ;; *) echo "unknown mode: $MODE"; exit 2 ;; esac
if [ "$MODE" = family ] || [ "$MODE" = relx64 ] || [ "$MODE" = testrel ]; then
  [ -f "$SRC/android/key.properties" ] || { echo "Release modes need android/key.properties (see docs/ROADMAP.md)."; exit 1; }
fi

# First run: full copy. Later runs: refresh the parts that change.
if [ ! -f "$A/pubspec.yaml" ]; then
  mkdir -p "$A"
  (cd "$SRC" && tar --exclude=./build --exclude=./.dart_tool --exclude=./android/.gradle \
     --exclude=./android/build --exclude=./tools/device/shots -cf - .) | (cd "$A" && tar -xf -)
fi
rm -rf "$A/lib" "$A/assets" "$A/android/app/src/main"
cp -r "$SRC/lib" "$A/lib"
cp -r "$SRC/assets" "$A/assets"
mkdir -p "$A/android/app/src"
cp -r "$SRC/android/app/src/main" "$A/android/app/src/main"
# pubspec.yaml overrides video_player_android with the patched copy in third_party/ (a path
# dependency): refresh it too, or pub get fails on an older build copy and patch edits are lost.
rm -rf "$A/third_party"
if [ -d "$SRC/third_party" ]; then cp -r "$SRC/third_party" "$A/third_party"; fi
cp "$SRC/pubspec.yaml" "$SRC/pubspec.lock" "$A/"
cp "$SRC/android/app/build.gradle.kts" "$SRC/android/app/proguard-rules.pro" "$A/android/app/"
# gradle.properties carries android.r8.proguardAndroidTxt.disallowed=false, which AGP 9 needs for
# flutter_inappwebview_android 1.1.3 (see the comment in that file).
cp "$SRC/android/build.gradle.kts" "$SRC/android/settings.gradle.kts" "$SRC/android/gradle.properties" "$A/android/"
if [ -f "$SRC/android/key.properties" ]; then cp "$SRC/android/key.properties" "$A/android/key.properties"; fi

if [ "${SDK_PLATFORM_FIX:-0}" = 1 ]; then
  sed -i 's/compileSdk = 37/compileSdkVersion("android-37.0")/' "$A/android/app/build.gradle.kts"
fi
if [ "$MODE" != family ]; then
  sed -i 's/applicationId = "com.mediahub.app"/applicationId = "com.mediahub.app.audit"/' "$A/android/app/build.gradle.kts"
  sed -i 's#>MediaHub<#>MediaHub Test<#' "$A/android/app/src/main/res/values/strings.xml"
fi

cd "$A"
flutter pub get >/dev/null
# Phones are arm64 only: phone modes ship arm64-v8a native libraries, emulator modes x86_64
# (android/app/build.gradle.kts reads mediahub.abis). No --split-per-abi: it changes version codes.
ARM=(--target-platform android-arm64 -P mediahub.abis=arm64-v8a)
X64=(--target-platform android-x64 -P mediahub.abis=x86_64)
case "$MODE" in
  test)     flutter build apk --debug "${ARM[@]}" ;;
  emulator) flutter build apk --debug "${X64[@]}" --dart-define=MEDIAHUB_DEMO=true --dart-define=MEDIAHUB_ONLINE_FIXTURE=true ;;
  family)   flutter build apk --release "${ARM[@]}" ;;
  relx64)   flutter build apk --release "${X64[@]}" ;;
  testrel)  flutter build apk --release "${ARM[@]}" ;;
esac
ls -la build/app/outputs/flutter-apk/ | tail -3
echo "APKs are in $A/build/app/outputs/flutter-apk/"
