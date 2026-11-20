// Shuffle is a sticky toggle (Spotify, YT Music): with shuffle on, tapping a
// song plays it first and keeps the rest of the list shuffled; it never
// switches shuffle off. Runs the real PlaybackNotifier, playCollection and
// MusicAudioHandler over the just_audio double.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/domain/repositories/playback_repository.dart';
import 'package:mediahub/features/library/playable.dart';
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/now_playing_art.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

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

final _list = [for (var i = 0; i < 8; i++) _song(i)];

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class _NoSession implements PlaybackRepository {
  @override
  Future<domain.PlaybackState?> loadLastPlaybackState() async => null;
  @override
  Future<void> savePlaybackState(domain.PlaybackState state) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DiagnosticsService.enableDebounce = false);

  late MusicAudioHandler handler;
  late ProviderContainer container;
  late PlaybackNotifier playback;

  setUp(() async {
    handler = MusicAudioHandler(player: FakeAudioPlayer(), art: NowPlayingArt(cacheDirectory: () async => null));
    container = ProviderContainer(overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      playbackRepositoryProvider.overrideWithValue(_NoSession()),
    ]);
    container.read(playbackNotifierProvider);
    playback = container.read(playbackNotifierProvider.notifier);
    await _settle();
  });

  tearDown(() async {
    container.dispose();
    await handler.dispose();
  });

  Future<void> shuffleOn() async {
    await playback.loadQueue(_list, autoPlay: true, shuffle: true);
    await _settle();
    expect(playback.shuffleMode, isTrue);
  }

  void expectShuffledFrom(String id) {
    final s = handler.getCurrentDomainState();
    expect(handler.shuffleEnabled, isTrue, reason: 'tapping a song must not switch shuffle off');
    expect(s.shuffle, isTrue);
    expect(s.currentItemId, id, reason: 'the tapped song plays');
    expect(s.queueIndex, 0, reason: 'first, with the rest of the list after it in shuffled order');
    expect({for (final m in s.queue) m.id}, {for (final m in _list) m.id}, reason: 'every song is still there');
    expect([for (final m in s.originalQueue) m.id], [for (final m in _list) m.id],
        reason: 'turning shuffle off goes back to the list order');
  }

  test('a tapped row (playCollection from a song) keeps shuffle on', () async {
    await shuffleOn();
    await playCollection(playback, _list, start: _list[3]);
    await _settle();
    expectShuffledFrom('s3');
  });

  test('playTrack keeps shuffle on', () async {
    await shuffleOn();
    await playback.playTrack(_list[5], _list);
    await _settle();
    expectShuffledFrom('s5');
  });

  test('Play on a list with shuffle on starts from a random song, shuffled', () async {
    await shuffleOn();
    await playCollection(playback, _list, randomIndex: (_) => 6);
    await _settle();
    expectShuffledFrom('s6');
  });

  test('with shuffle off a tap plays in list order, and shuffle stays off', () async {
    await playCollection(playback, _list, start: _list[2]);
    await _settle();
    final s = handler.getCurrentDomainState();
    expect(handler.shuffleEnabled, isFalse);
    expect(s.currentItemId, 's2');
    expect([for (final m in s.queue) m.id], [for (final m in _list) m.id]);
    expect(s.queueIndex, 2);
  });
}
