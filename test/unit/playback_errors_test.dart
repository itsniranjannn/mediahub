// A song that cannot play (a missing or moved file, one the phone cannot
// decode, a refused stream), the way just_audio 0.10.6 reports it: on the
// player's errorStream only (never as an error on playbackEventStream),
// and, for a load, also by the load throwing. The handler used to listen to
// playbackEventStream errors only, so such a song stopped silently.
import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/now_playing_art.dart';

import 'fake_audio_player.dart';

domain.MediaItem _song(int i) => domain.MediaItem(
      id: 's$i',
      uri: 'file:///music/s$i.mp3',
      mediaType: domain.MediaType.audio,
      title: 'Song $i',
      durationMs: 180000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

List<domain.MediaItem> _songs(int n) => [for (var i = 0; i < n; i++) _song(i)];

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DiagnosticsService.enableDebounce = false);

  late FakeAudioPlayer player;
  late MusicAudioHandler handler;
  late List<String> messages;
  late List<String> failures;

  setUp(() {
    player = FakeAudioPlayer();
    handler = MusicAudioHandler(player: player, art: NowPlayingArt(cacheDirectory: () async => null));
    messages = [];
    failures = [];
    handler.errorEvents.listen(messages.add);
    handler.trackFailures.listen(failures.add);
  });

  tearDown(() => handler.dispose());

  test('a song that fails while the queue plays: one message, then the next song plays', () async {
    player.brokenIds.add('s1');
    await handler.loadQueue(_songs(4), autoPlay: true);
    await _settle();

    player.finishTrack(); // Song 0 ends; Song 1 cannot play
    await _settle();

    expect(player.currentId, 's2');
    expect(player.playing, isTrue);
    expect(player.processingState, ProcessingState.ready);
    expect(messages, ['Can\'t play "Song 1"']);
    expect(failures, ['s1']);
    expect(handler.wantPlaying, isTrue);
  });

  test('a tapped song that cannot load: the next playable one plays, and it is dealt with once', () async {
    player.brokenIds.add('s1');
    await handler.loadQueue(_songs(4), startIndex: 1, autoPlay: true);
    await _settle();

    // The load reported it twice (the error stream, and the load throwing):
    // one message, one step on, not two.
    expect(player.errorsSent, hasLength(1));
    expect(messages, ['Can\'t play "Song 1"']);
    expect(failures, ['s1']);
    expect(player.currentId, 's2');
    expect(player.playing, isTrue);
  });

  test('every song fails: it stops, paused, and does not try for ever', () async {
    player.brokenIds.addAll(['s0', 's1', 's2']);
    await handler.loadQueue(_songs(3), autoPlay: true);
    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    await _settle();

    expect(messages, ['Can\'t play "Song 0"', 'Can\'t play any song in the queue']);
    expect(handler.wantPlaying, isFalse);
    expect(player.playing, isFalse);
    final loads = player.loads;
    final errors = player.errorsSent.length;
    expect(errors, 3, reason: 'each song tried once');

    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _settle();
    expect(player.loads, loads, reason: 'nothing more is tried');
    expect(player.errorsSent, hasLength(errors));
    expect(handler.getCurrentDomainState().isPlaying, isFalse);
  });

  test('a one-song queue that fails stops at once', () async {
    player.brokenIds.add('s0');
    await handler.loadQueue(_songs(1), autoPlay: true);
    await _settle();
    expect(messages, ['Can\'t play "Song 0"']);
    expect(failures, ['s0'], reason: 'reported twice by the player, dealt with once');
    expect(handler.wantPlaying, isFalse);
    expect(player.playing, isFalse);
  });

  test('restored at launch, paused: a missing song is only noted; play then moves on', () async {
    player.brokenIds.add('s0');
    await handler.restoreSession(domain.PlaybackState(
      queue: _songs(3),
      originalQueue: _songs(3),
      queueIndex: 0,
      currentItemId: 's0',
      updatedAt: DateTime(2026),
    ));
    await _settle();
    expect(messages, isEmpty, reason: 'no message while nothing was asked to play');
    expect(failures, ['s0']);
    expect(player.currentId, 's0');

    await handler.playLocal();
    await _settle();
    expect(messages, ['Can\'t play "Song 0"']);
    expect(player.currentId, 's1');
    expect(player.playing, isTrue);
  });

  test('"connection aborted" (a newer load stopped an older one) is no failure', () async {
    await handler.loadQueue(_songs(3), autoPlay: true);
    await _settle();
    player.failCurrent(code: MusicAudioHandler.abortedErrorCode, message: 'Connection aborted');
    await _settle();
    expect(messages, isEmpty);
    expect(failures, isEmpty);
    expect(player.currentId, 's0');
  });

  test('a Next pressed as a song fails wins: no second skip on top of it', () async {
    player.brokenIds.add('s1');
    await handler.loadQueue(_songs(5), autoPlay: true);
    await _settle();

    player.finishTrack(); // Song 1 fails ...
    final next = handler.skipToNext(); // ... as the user presses Next
    await next;
    await _settle();

    expect(player.currentId, 's2', reason: 'where the press went, not one further');
    expect(player.playing, isTrue);
  });

  test('a new queue loaded as a song fails: the failure is dropped', () async {
    player.brokenIds.add('s1');
    await handler.loadQueue(_songs(3), autoPlay: true);
    await _settle();

    player.finishTrack();
    final other = [for (var i = 10; i < 13; i++) _song(i)];
    await handler.loadQueue(other, startIndex: 1, autoPlay: true);
    await _settle();

    expect(player.currentId, 's11');
    expect(player.playing, isTrue);
  });

  test('failures in a row count again after a song played', () async {
    player.brokenIds.addAll(['s1', 's3']);
    await handler.loadQueue(_songs(5), autoPlay: true);
    await _settle();
    player.finishTrack(); // s1 fails, s2 plays
    await _settle();
    expect(player.currentId, 's2');
    player.finishTrack(); // s3 fails, s4 plays
    await _settle();
    expect(player.currentId, 's4');
    expect(messages, ['Can\'t play "Song 1"', 'Can\'t play "Song 3"']);
    expect(handler.wantPlaying, isTrue);
  });
}
