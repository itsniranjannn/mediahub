import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/storage/settings_store.dart';
import 'core/logging/diagnostics_service.dart';
import 'data/database/app_database.dart';
import 'data/repositories/library_repository_impl.dart';
import 'features/downloads/downloads_notifier.dart';
import 'features/music_player/music_audio_handler.dart';
import 'features/music_player/playback_notifier.dart';

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

  final audioHandler = await AudioService.init(
    builder: () => MusicAudioHandler(
      onRecordPlay: (id) => libraryRepo.recordPlay(id),
      onDurationKnown: (id, ms) => libraryRepo.updateDurationIfUnknown(id, ms),
    ),
    // The same session carries local music and, while it plays, the Online
    // tab's YouTube video (MusicAudioHandler.setExternalSource). audio_service
    // starts the mediaPlayback foreground service (and its wake lock) whenever
    // the broadcast state turns to playing, whichever source it comes from, so
    // YouTube audio keeps the process alive with the screen off. It stays in
    // the foreground while paused (androidStopForegroundOnPause: false) and
    // stops once the state goes idle.
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.mediahub.app.audio',
      androidNotificationChannelName: 'MediaHub Playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
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
