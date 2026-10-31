import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mediahub/app/app.dart';
import 'package:mediahub/core/app_config.dart';
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/domain/repositories/playback_repository.dart';
import 'package:mediahub/features/library/library_notifier.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import '../unit/permission_service_test.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}
class FakeAudioSource extends Fake implements AudioSource {}
class FakePlaybackState extends Fake implements domain.PlaybackState {}
class MockPlaybackRepository extends Mock implements PlaybackRepository {}

void main() {
  setUpAll(() {
    DiagnosticsService.enableDebounce = false;
    registerFallbackValue(Duration.zero);
    registerFallbackValue(FakeAudioSource());
    registerFallbackValue(LoopMode.off);
    registerFallbackValue(FakePlaybackState());
  });

  testWidgets('MediaHubApp launches and navigates through tabs',
      (WidgetTester tester) async {
    final mockPlayer = MockAudioPlayer();
    when(() => mockPlayer.playbackEventStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.playerStateStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.currentIndexStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.positionStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.durationStream).thenAnswer((_) => const Stream.empty());
    when(() => mockPlayer.playing).thenReturn(false);
    when(() => mockPlayer.processingState).thenReturn(ProcessingState.ready);
    when(() => mockPlayer.position).thenReturn(Duration.zero);
    when(() => mockPlayer.bufferedPosition).thenReturn(Duration.zero);
    when(() => mockPlayer.speed).thenReturn(1.0);
    when(() => mockPlayer.duration).thenReturn(null);
    when(() => mockPlayer.currentIndex).thenReturn(null);
    when(() => mockPlayer.shuffleModeEnabled).thenReturn(false);
    when(() => mockPlayer.hasNext).thenReturn(false);
    when(() => mockPlayer.hasPrevious).thenReturn(false);
    when(() => mockPlayer.setShuffleModeEnabled(any())).thenAnswer((_) async {});
    when(() => mockPlayer.setLoopMode(any())).thenAnswer((_) async {});
    when(() => mockPlayer.dispose()).thenAnswer((_) async {});

    final handler = MusicAudioHandler(player: mockPlayer);
    final mockRepo = MockPlaybackRepository();
    when(() => mockRepo.loadLastPlaybackState()).thenAnswer((_) async => null);
    when(() => mockRepo.savePlaybackState(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          playbackRepositoryProvider.overrideWithValue(mockRepo),
          mediaPermissionServiceProvider.overrideWithValue(MockMediaPermissionService()),
        ],
        child: const MediaHubApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(AppConfig.appName), findsWidgets);

    // Tap Music tab
    await tester.tap(find.text('Music'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Permission Required'), findsOneWidget);

    // Tap Videos tab
    await tester.tap(find.text('Videos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Permission Required'), findsOneWidget);

    // Tap Downloads tab
    await tester.tap(find.text('Downloads'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
        find.text(
            'Active and completed downloads in ${AppConfig.appName} will appear here.'),
        findsOneWidget);

    // Tap Settings tab
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Audio & Headset'), findsOneWidget);
    expect(find.text('Diagnostics Log'), findsOneWidget);
  });
}
