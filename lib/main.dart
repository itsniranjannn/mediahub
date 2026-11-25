// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/storage/settings_store.dart';
import 'core/logging/diagnostics_service.dart';
import 'core/platform/other_audio_watcher.dart';
import 'core/platform_info.dart';
import 'data/database/app_database.dart';
import 'data/repositories/library_repository_impl.dart';
import 'data/repositories/playback_repository_impl.dart';
import 'features/downloads/downloads_notifier.dart';
import 'features/music_player/audio_service_start.dart';
import 'features/music_player/music_audio_handler.dart';
import 'features/music_player/playback_notifier.dart';
import 'features/music_player/resume_after_other_apps.dart';
import 'features/settings/settings_notifier.dart';

void main() {
  // Release builds: keep full error text and stack traces out of logcat /
  // the device console (anything with adb access could read them). Errors
  // still reach the local Diagnostics log through the handlers below.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Every uncaught error ends up in the Diagnostics log instead of vanishing.
  runZonedGuarded(_bootstrap, (Object error, StackTrace stack) {
    DiagnosticsService.instance.logEvent('uncaught_error', {
      'type': error.runtimeType.toString(),
      'where': 'zone',
    });
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the system bars (DESIGN.md 8.2; Android 15 enforces it anyway).
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  await DiagnosticsService.instance.init();
  await SettingsStore.instance.load();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    DiagnosticsService.instance.logEvent('flutter_error', {
      'type': details.exception.runtimeType.toString(),
      'library': details.library ?? 'unknown',
    });
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    DiagnosticsService.instance.logEvent('uncaught_error', {
      'type': error.runtimeType.toString(),
      'where': 'platform',
    });
    return true; // handled: do not kill the app for a stray async error
  };

  final db = AppDatabase();
  final libraryRepo = LibraryRepositoryImpl(db);
  final playbackRepo = PlaybackRepositoryImpl(db);

  // The handler is made here and handed to AudioService.init, which only
  // connects it to the phone's media session: if that connection hangs, the
  // app still starts with the same handler (startAudioService).
  final handler = MusicAudioHandler(
    onRecordPlay: (id) => libraryRepo.recordPlay(id),
    onDurationKnown: (id, ms) => libraryRepo.updateDurationIfUnknown(id, ms),
    // The notification's heart (Like), live from the database like the
    // app's own heart.
    onToggleFavorite: (id) => libraryRepo.toggleFavorite(id),
    watchFavorite: (id) => (db.select(db.mediaItemsTable)..where((t) => t.id.equals(id)))
        .watchSingleOrNull()
        .map((row) => row?.isFavorite ?? false),
    // Media resumption (the quick-settings player after the app was
    // closed): the last saved session, without online items.
    loadLastSession: () async {
      final saved = await playbackRepo.loadLastPlaybackState();
      if (saved == null) return null;
      return PlaybackNotifier.alignIndexWithCurrentItem(PlaybackNotifier.withoutOnlineItems(saved));
    },
    // YouTube in the Online tab was the last source: after a restart in the
    // background the phone's controls must not start downloaded songs.
    loadExternalHeld: () => SettingsStore.instance.getBool(MusicAudioHandler.externalHeldPrefKey),
    saveExternalHeld: (held) => SettingsStore.instance.setBool(MusicAudioHandler.externalHeldPrefKey, held),
    loadExternalResume: () => SettingsStore.instance.getString(MusicAudioHandler.externalResumePrefKey),
    saveExternalResume: (encoded) => encoded == null
        ? SettingsStore.instance.remove(MusicAudioHandler.externalResumePrefKey)
        : SettingsStore.instance.setString(MusicAudioHandler.externalResumePrefKey, encoded),
    // Music another app paused plays again when that app stops (Android,
    // Settings → Resume after other apps).
    otherAudio: PlatformInfo.isAndroid ? MethodChannelOtherAudioWatcher() : null,
    resumeAfterOtherApps: ResumeAfterOtherAppsNotifier.isOn,
  );
  // "Resume when headphones reconnect" turned off stays off from launch on
  // (it used to reach the handler only once Settings had been opened).
  handler.setResumeOnHeadphonesReconnect(ResumeOnHeadphonesReconnectNotifier.isOn());
  final audioHandler = await startAudioService<MusicAudioHandler>(
    handler,
    connect: (builder) => AudioService.init(
      builder: builder,
      // The same session carries local music and, while it plays, the Online
      // tab's YouTube video (MusicAudioHandler.setExternalSource). audio_service
      // starts the mediaPlayback foreground service (and its wake lock) whenever
      // the broadcast state turns to playing, whichever source it comes from, so
      // YouTube audio keeps the process alive with the screen off. It stays in
      // the foreground while paused (androidStopForegroundOnPause: false), and
      // swiping the app away from recents stops nothing (onTaskRemoved; the
      // service is stopWithTask="false"). It stops only once the state goes
      // idle, which happens when the user closes the session: a pause never
      // times out (MusicAudioHandler.defaultPausedIdleTimeout is off).
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.mediahub.app.audio',
        androidNotificationChannelName: 'MediaHub Playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        // A white-on-transparent status bar glyph (the launcher icon shows as a
        // grey square there).
        androidNotificationIcon: 'drawable/ic_stat_mediahub',
      ),
    ),
  );

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      libraryRepositoryProvider.overrideWithValue(libraryRepo),
      audioHandlerProvider.overrideWithValue(audioHandler),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MediaHubApp(),
    ),
  );

  // No notification-permission prompt at launch: the media-session (playback)
  // notification is exempt on Android 13+, and both download flows ask for
  // the permission in context, right before a download starts.

  // Repair downloads interrupted by the app being killed and resume them.
  unawaited(container.read(downloadStartupProvider.future).catchError((Object e) {
    DiagnosticsService.instance.logEvent('download_startup_failed', {
      'type': e.runtimeType.toString(),
    });
  }));
}
