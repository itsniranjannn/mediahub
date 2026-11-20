# MediaHub's vendored copy of video_player_android 2.12.2

This folder is `video_player_android` **2.12.2** exactly as published on pub.dev
(the version `pubspec.lock` resolved before vendoring, sha256
`d27054dea34d748a44f06d433a57005d2aac69944485b0abbaed3303dbcfa3f1`), with a
three-part patch. The root `pubspec.yaml` points at it through
`dependency_overrides`. The licence is unchanged (BSD 3-clause, see `LICENSE`,
Copyright 2013 The Flutter Authors).

## Why

MediaHub's video player offers a volume boost up to 200 % (owner request:
"volume raiser"), like MX Player and VLC. Android can only boost what one app
plays with an audio effect (`android.media.audiofx.LoudnessEnhancer`) on that
player's own audio session, and the plugin does not tell anyone its
ExoPlayer's session id. MediaHub never boosts session 0 (the global mix) or
the music player.

## What changed (search for "MediaHub patch")

1. `android/src/main/java/io/flutter/plugins/videoplayer/AudioSessions.java`
   (new): a static map from the player id (the one the Dart
   `VideoPlayerController` uses) to that player's `ExoPlayer`, and
   `AudioSessions.sessionIdFor(playerId)`, which returns
   `exoPlayer.getAudioSessionId()` (0 when unknown). The app's
   `DeviceControlsChannel.kt` reads it to attach the `LoudnessEnhancer`.
   No pigeon or Dart API change.
2. `VideoPlayerPlugin.java`: three lines keep that map in step
   (`registerPlayerInstance` adds, `dispose` and `disposeAllPlayers` remove).
3. `VideoPlayer.java`: `exoPlayer.setHandleAudioBecomingNoisy(true)` so a
   video pauses when headphones are unplugged or a Bluetooth headset
   disconnects (the app also pauses from Dart; this is the second layer).

Left out of the copy: `example/` (2.5 MB demo app, not needed to build).
Everything else (Dart code, generated pigeon code, tests, Gradle files) is
byte-for-byte the published package. The plugin's own Java unit tests were
not re-run against the patch.

## Updating

To move to a newer video_player_android: copy the new version from the pub
cache over this folder (again without `example/`), re-apply the three changes
above, update the version and checksum in this README, then run
`flutter pub get` and an Android build. If upstream ever exposes the audio
session id, drop this folder and the `dependency_overrides` entry.

---

# video\_player\_android

The Android implementation of [`video_player`][1].

## Usage

This package is [endorsed][2], which means you can simply use `video_player`
normally. This package will be automatically included in your app when you do,
so you do not need to add it to your `pubspec.yaml`.

However, if you `import` this package to use any of its APIs directly, you
should add it to your `pubspec.yaml` as usual.

## Known issues

Using `VideoViewType.platformView` is not currently recommended on Android due to a known [issue][3] affecting platform views on Android.

[1]: https://pub.dev/packages/video_player
[2]: https://flutter.dev/to/endorsed-federated-plugin
[3]: https://github.com/flutter/flutter/issues/164899
