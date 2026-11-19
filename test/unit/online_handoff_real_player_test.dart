// The iOS Online hand-off (ONL-1) on the real music player: the real
// MusicHandoffPlayer, PlaybackNotifier and MusicAudioHandler over the
// just_audio double. online_background_handoff_test drives a fake
// HandoffPlayer, so it could not see the handler's restore guard leaving the
// YouTube stream loaded, or the save during the hand-off emptying the
// stored session.
import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show LoopMode, ProcessingState;
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/domain/repositories/playback_repository.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/now_playing_art.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/features/online/online_background_handoff.dart';

import 'fake_audio_player.dart';

domain.MediaItem _song(int i) => domain.MediaItem(
      id: 's$i',
      uri: 'content://media/external/audio/media/$i',
      mediaType: domain.MediaType.audio,
      title: 'Song $i',
      durationMs: 180000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

List<domain.MediaItem> _songs(int n) => [for (var i = 0; i < n; i++) _song(i)];

final _stream = domain.MediaItem(
  id: 'yt_dQw4w9WgXcQ',
  uri: 'https://rr1---sn.googlevideo.com/videoplayback?itag=140&x=1',
  mediaType: domain.MediaType.audio,
  title: 'A video',
  album: 'YouTube',
  durationMs: 200000,
  sizeBytes: 0,
  dateAdded: DateTime(2026),
  source: 'online',
);

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class _RecordingRepo implements PlaybackRepository {
  final List<domain.PlaybackState> saved = [];
  @override
  Future<domain.PlaybackState?> loadLastPlaybackState() async => null;
  @override
  Future<void> savePlaybackState(domain.PlaybackState state) async => saved.add(state);
}

final _handoffPlayer = Provider<MusicHandoffPlayer>((ref) => MusicHandoffPlayer(ref));
final _quickHandoffPlayer = Provider<MusicHandoffPlayer>(
  (ref) => MusicHandoffPlayer(ref, startTimeout: const Duration(milliseconds: 100)),
);

List<String> _ids(Iterable<domain.MediaItem> items) => [for (final m in items) m.id];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DiagnosticsService.enableDebounce = false);

  late FakeAudioPlayer player;
  late MusicAudioHandler handler;
  late _RecordingRepo repo;
  late ProviderContainer container;

  setUp(() async {
    player = FakeAudioPlayer();
    handler = MusicAudioHandler(player: player, art: NowPlayingArt(cacheDirectory: () async => null));
    repo = _RecordingRepo();
    container = ProviderContainer(overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      playbackRepositoryProvider.overrideWithValue(repo),
    ]);
    container.read(playbackNotifierProvider);
    await _settle();
  });

  tearDown(() async {
    container.dispose();
    await handler.dispose();
  });

  test('coming back gives the local queue back, paused where it was, and saves it again', () async {
    await handler.loadQueue(_songs(5), startIndex: 2, autoPlay: true);
    await _settle();
    handler.toggleShuffle(); // the user's own modes come back too
    await _settle();
    await handler.pause();
    await _settle();

    final hp = container.read(_handoffPlayer);
    final saved = hp.captureLocal();
    expect(saved, isNotNull);
    final before = _ids(saved!.queue);
    final current = saved.currentItemId;

    // Leaving the app: the stream plays natively, alone.
    await hp.playAlone(_stream, const Duration(seconds: 30));
    await _settle();
    expect(_ids(handler.getCurrentDomainState().queue), ['yt_dQw4w9WgXcQ']);
    expect(player.playing, isTrue);

    // Back in the app.
    await hp.pause();
    await hp.restoreLocal(saved);
    await _settle();
    await Future<void>.delayed(const Duration(milliseconds: 700)); // the track-change save

    final now = handler.getCurrentDomainState();
    expect(_ids(now.queue), before, reason: 'the queue the user had before locking the phone');
    expect(now.currentItemId, current);
    expect(now.shuffle, isTrue);
    expect(player.playing, isFalse, reason: 'it comes back paused');
    expect(player.loadedIds, before, reason: 'the player itself holds the local queue, not the stream');
    expect(_ids(repo.saved.last.queue), before, reason: 'and it is saved again');
  });

  test('a save during the hand-off keeps the stored local session (app killed in the background)', () async {
    await handler.loadQueue(_songs(3), autoPlay: true);
    await _settle();
    await handler.pause();
    await _settle();
    final storedBefore = repo.saved.length;
    expect(storedBefore, greaterThan(0));
    expect(_ids(repo.saved.last.queue), ['s0', 's1', 's2']);

    final hp = container.read(_handoffPlayer);
    await hp.playAlone(_stream, const Duration(seconds: 30));
    await _settle();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await hp.pause(); // a pause saves at once
    await _settle();

    expect(_ids(repo.saved.last.queue), ['s0', 's1', 's2'],
        reason: 'the stored session must not become empty while only the online item is queued');
  });

  group('a stream Apple\'s player does not play', () {
    test('refused (an expired link, or one made on another network): playAlone throws, nothing plays', () async {
      player.brokenIds.add(_stream.id);
      final hp = container.read(_handoffPlayer);
      await expectLater(
        hp.playAlone(_stream, const Duration(seconds: 30)),
        throwsA(isA<HandoffPlaybackException>()),
      );
      await _settle();
      expect(player.playing, isFalse);
      expect(handler.wantPlaying, isFalse);
    });

    test('a link that never answers: playAlone gives up in time, and it cannot start later', () async {
      player.hangingIds.add(_stream.id);
      final hp = container.read(_quickHandoffPlayer);
      await expectLater(
        hp.playAlone(_stream, const Duration(seconds: 30)).timeout(const Duration(seconds: 2)),
        throwsA(isA<HandoffPlaybackException>().having((e) => e.reason, 'reason', 'timeout')),
      );
      expect(player.stopCalls, greaterThan(0), reason: 'the load is stopped');
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(player.playing, isFalse);
      expect(player.playCalls, 0);
    });

    test('time up while it still seeks to the page\'s spot: it does not start afterwards', () async {
      player.seekDelay = const Duration(milliseconds: 300);
      final hp = container.read(_quickHandoffPlayer);
      await expectLater(
        hp.playAlone(_stream, const Duration(seconds: 30)),
        throwsA(isA<HandoffPlaybackException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _settle();
      expect(player.playing, isFalse, reason: 'the page was asked to play on: two sounds at once otherwise');
      expect(player.playCalls, 0);
    });

    test('a stream that plays: playAlone returns once it really plays', () async {
      final hp = container.read(_handoffPlayer);
      await hp.playAlone(_stream, Duration.zero);
      expect(player.playing, isTrue);
      expect(player.processingState, ProcessingState.ready);
      expect(player.currentId, _stream.id);
    });
  });

  group('the user\'s repeat mode', () {
    test('the stream plays once (repeat one would loop it for good); repeat comes back with the queue', () async {
      await handler.loadQueue(_songs(3), autoPlay: true);
      await _settle();
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      await handler.pause();
      await _settle();

      final hp = container.read(_handoffPlayer);
      final saved = hp.captureLocal();
      await hp.playAlone(_stream, Duration.zero);
      await _settle();
      expect(handler.repeatMode, domain.PlaybackRepeatMode.off);
      expect(player.loopMode, LoopMode.off);

      await hp.pause();
      await hp.restoreLocal(saved);
      await _settle();
      expect(handler.repeatMode, domain.PlaybackRepeatMode.one);
      expect(player.loopMode, LoopMode.one);
    });

    test('no queue before: the mode still comes back', () async {
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      final hp = container.read(_handoffPlayer);
      final saved = hp.captureLocal();
      await hp.playAlone(_stream, Duration.zero);
      expect(handler.repeatMode, domain.PlaybackRepeatMode.off);
      await hp.restoreLocal(saved);
      await _settle();
      expect(handler.repeatMode, domain.PlaybackRepeatMode.all);
    });

    test('other music took over meanwhile: it stays, and only the mode comes back', () async {
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      final hp = container.read(_handoffPlayer);
      await hp.playAlone(_stream, Duration.zero);
      await handler.loadQueue(_songs(2), autoPlay: true); // e.g. Siri started a playlist
      await _settle();
      await hp.restoreSettings();
      expect(handler.repeatMode, domain.PlaybackRepeatMode.all);
      expect(_ids(handler.getCurrentDomainState().queue), ['s0', 's1']);
      expect(player.playing, isTrue);
    });

    test('a failed try leaves the mode to be put back too', () async {
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      player.brokenIds.add(_stream.id);
      final hp = container.read(_handoffPlayer);
      final saved = hp.captureLocal();
      await expectLater(hp.playAlone(_stream, Duration.zero), throwsA(isA<HandoffPlaybackException>()));
      await hp.restoreLocal(saved);
      await _settle();
      expect(handler.repeatMode, domain.PlaybackRepeatMode.one);
    });
  });

  test('a plain restore still leaves a loaded queue alone (media resumption got there first)', () async {
    await handler.loadQueue(_songs(2), autoPlay: false);
    await _settle();
    await handler.restoreSession(domain.PlaybackState(
      updatedAt: DateTime(2026),
      queue: [_song(7), _song(8)],
      originalQueue: [_song(7), _song(8)],
      queueIndex: 0,
      currentItemId: 's7',
    ));
    await _settle();
    expect(_ids(handler.getCurrentDomainState().queue), ['s0', 's1']);
  });
}
