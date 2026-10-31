import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/logging/diagnostics_service.dart';
import 'data/database/app_database.dart';
import 'data/repositories/library_repository_impl.dart';
import 'features/music_player/music_audio_handler.dart';
import 'features/music_player/playback_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DiagnosticsService.instance.init();

  final db = AppDatabase();
  final libraryRepo = LibraryRepositoryImpl(db);

  final audioHandler = await AudioService.init(
    builder: () => MusicAudioHandler(
      onRecordPlay: (id) => libraryRepo.recordPlay(id),
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.mediahub.app.audio',
      androidNotificationChannelName: 'MediaHub Playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryRepositoryProvider.overrideWithValue(libraryRepo),
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const MediaHubApp(),
    ),
  );
}
