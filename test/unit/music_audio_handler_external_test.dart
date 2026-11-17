import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/features/music_player/music_audio_handler.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

class FakeAudioSource extends Fake implements AudioSource {}

/// Records the notification's commands as the Online tab would receive them.
class RecordingDelegate implements ExternalPlaybackDelegate {
  final List<String> calls = [];

  @override
  Future<void> externalPlay() async => calls.add('play');

  @override
  Future<void> externalPause() async => calls.add('pause');

  @override
  Future<void> externalSeek(Duration position) async => calls.add('seek ${position.inSeconds}');

  @override
  Future<void> externalSkipToNext() async => calls.add('next');

  @override
  Future<void> externalSkipToPrevious() async => calls.add('previous');

  @override
  void onExternalSourceReleased() => calls.add('released');
}

domain.MediaItem _song(String id) => domain.MediaItem(
      id: id,
      uri: 'file:///music/$id.mp3',
      mediaType: domain.MediaType.audio,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      durationMs: 180000,
      sizeBytes: 1024,
      dateAdded: DateTime(2026, 1, 1),
    );

ExternalMediaSnapshot _yt({
  bool playing = true,
  Duration position = const Duration(seconds: 30),
  bool canSkipNext = true,
  String title = 'A YouTube video',
}) =>
    ExternalMediaSnapshot(
      id: 'online:dQw4w9WgXcQ',
      title: title,
      artist: 'A Channel',
      artUri: Uri.parse('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'),
      playing: playing,
      position: position,
      duration: const Duration(minutes: 3, seconds: 33),
      canSkipNext: canSkipNext,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(FakeAudioSource());
    registerFallbackValue(LoopMode.off);
  });

  late MockAudioPlayer player;
  late MusicAudioHandler handler;
  late RecordingDelegate yt;
  var index = 0;
  var playing = false;
  var stopped = false;
  late StreamController<PlayerState> playerStates;

  setUp(() {
    index = 0;
    playing = false;
    stopped = false;
    player = MockAudioPlayer();
    playerStates = StreamController<PlayerState>.broadcast();
    when(() => player.playbackEventStream).thenAnswer((_) => const Stream.empty());
    when(() => player.playerStateStream).thenAnswer((_) => playerStates.stream);
    when(() => player.currentIndexStream).thenAnswer((_) => const Stream.empty());
    when(() => player.positionStream).thenAnswer((_) => const Stream.empty());
    when(() => player.durationStream).thenAnswer((_) => const Stream.empty());
    when(() => player.playing).thenAnswer((_) => playing);
    when(() => player.processingState).thenAnswer((_) => stopped ? ProcessingState.idle : ProcessingState.ready);
    when(() => player.position).thenReturn(Duration.zero);
    when(() => player.bufferedPosition).thenReturn(Duration.zero);
    when(() => player.speed).thenReturn(1.0);
    when(() => player.volume).thenReturn(1.0);
    when(() => player.duration).thenReturn(const Duration(minutes: 3));
    when(() => player.currentIndex).thenAnswer((_) => index);
    when(() => player.hasNext).thenAnswer((_) => index < 1);
    when(() => player.hasPrevious).thenAnswer((_) => index > 0);
    when(() => player.setAudioSource(any(),
        initialIndex: any(named: 'initialIndex'),
        initialPosition: any(named: 'initialPosition'),
        preload: any(named: 'preload'))).thenAnswer((inv) async {
      index = inv.namedArguments[#initialIndex] ?? 0;
      stopped = false;
      return const Duration(minutes: 3);
    });
    when(() => player.setLoopMode(any())).thenAnswer((_) async {});
    when(() => player.seekToNext()).thenAnswer((_) async => index++);
    when(() => player.seekToPrevious()).thenAnswer((_) async => index--);
    when(() => player.play()).thenAnswer((_) async => playing = true);
    when(() => player.pause()).thenAnswer((_) async => playing = false);
    when(() => player.stop()).thenAnswer((_) async {
      playing = false;
      stopped = true;
    });
    when(() => player.seek(any(), index: any(named: 'index'))).thenAnswer((inv) async {
      if (inv.namedArguments[#index] != null) index = inv.namedArguments[#index];
    });
    when(() => player.dispose()).thenAnswer((_) async {});

    handler = MusicAudioHandler(player: player);
    yt = RecordingDelegate();
  });

  tearDown(() async {
    await handler.dispose();
    await playerStates.close();
  });

  test('YouTube taking over pauses local music and shows the video', () async {
    await handler.loadQueue([_song('1'), _song('2')]);
    expect(playing, isTrue);

    handler.setExternalSource(yt, _yt());
    await Future<void>.delayed(Duration.zero);

    verify(() => player.pause()).called(1);
    expect(playing, isFalse);
    expect(handler.isExternalActive, isTrue);
    expect(handler.wantPlaying, isFalse);

    final item = handler.mediaItem.value!;
    expect(item.id, 'online:dQw4w9WgXcQ');
    expect(item.title, 'A YouTube video');
    expect(item.artist, 'A Channel');
    expect(item.artUri.toString(), 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    expect(item.duration, const Duration(minutes: 3, seconds: 33));

    final s = handler.playbackState.value;
    expect(s.playing, isTrue);
    expect(s.processingState, AudioProcessingState.ready);
    expect(s.updatePosition, const Duration(seconds: 30));
    expect(s.controls, [MediaControl.skipToPrevious, MediaControl.pause, MediaControl.skipToNext]);
    expect(s.androidCompactActionIndices, [0, 1, 2]);
    expect(s.systemActions, containsAll([MediaAction.seek, MediaAction.skipToNext, MediaAction.skipToPrevious]));
    expect(s.queueIndex, isNull);
  });

  test('no stale local controls while YouTube plays: no shuffle / repeat, no queue index', () async {
    await handler.loadQueue([_song('1'), _song('2')], autoPlay: false);
    expect(handler.playbackState.value.controls.length, 5, reason: 'local: shuffle, prev, play, next, repeat');
    handler.setExternalSource(yt, _yt(canSkipNext: false));
    final s = handler.playbackState.value;
    expect(s.controls, [MediaControl.skipToPrevious, MediaControl.pause]);
    expect(s.androidCompactActionIndices, [0, 1]);
    expect(s.controls.any((c) => c.action == MediaAction.custom), isFalse);
    expect(s.systemActions.contains(MediaAction.skipToNext), isFalse);
    expect(s.repeatMode, AudioServiceRepeatMode.none);
    expect(s.shuffleMode, AudioServiceShuffleMode.none);
  });

  test('notification, lock screen and headset commands go to the page', () async {
    handler.setExternalSource(yt, _yt());
    await handler.pause();
    await handler.play();
    await handler.seek(const Duration(seconds: 90));
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.click(MediaButton.media); // headset button while playing → pause
    await handler.click(MediaButton.next);
    expect(yt.calls, ['pause', 'play', 'seek 90', 'next', 'previous', 'pause', 'next']);
    verifyNever(() => player.play());
    verifyNever(() => player.seekToNext());
    verifyNever(() => player.seekToPrevious());
  });

  test('local player events do not overwrite the video in the notification', () async {
    await handler.loadQueue([_song('1')], autoPlay: false);
    handler.setExternalSource(yt, _yt());
    playerStates.add(PlayerState(false, ProcessingState.ready));
    await Future<void>.delayed(Duration.zero);
    expect(handler.mediaItem.value!.id, 'online:dQw4w9WgXcQ');
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.controls.length, 3);
  });

  test('updates: ticks do not re-send the item; a pause and a seek do send state', () async {
    handler.setExternalSource(yt, _yt());
    final items = <MediaItem?>[];
    final states = <PlaybackState>[];
    final s1 = handler.mediaItem.skip(1).listen(items.add);
    final s2 = handler.playbackState.skip(1).listen(states.add);

    handler.updateExternalMedia(yt, _yt(position: const Duration(seconds: 31)));
    await Future<void>.delayed(Duration.zero);
    expect(items, isEmpty);
    expect(states, isEmpty, reason: 'the system extrapolates a playing position itself');

    handler.updateExternalMedia(yt, _yt(playing: false, position: const Duration(seconds: 31)));
    await Future<void>.delayed(Duration.zero);
    expect(states.single.playing, isFalse);
    expect(states.single.controls[1], MediaControl.play);

    handler.updateExternalMedia(yt, _yt(playing: false, position: const Duration(seconds: 100)));
    handler.updateExternalMedia(yt, _yt(title: 'Next video'));
    await Future<void>.delayed(Duration.zero);
    expect(states.length, 3);
    expect(items.single!.title, 'Next video');
    await s1.cancel();
    await s2.cancel();
  });

  test('starting local music hands the session back: YouTube pauses, local controls return', () async {
    await handler.loadQueue([_song('1'), _song('2')], autoPlay: false);
    handler.setExternalSource(yt, _yt());

    await handler.playLocal();

    expect(yt.calls, ['pause', 'released']);
    expect(handler.isExternalActive, isFalse);
    expect(handler.externalMedia, isNull);
    expect(playing, isTrue);
    expect(handler.mediaItem.value!.id, '1');
    final s = handler.playbackState.value;
    expect(s.controls.length, 5);
    expect(s.androidCompactActionIndices, [1, 2, 3]);
    // And the system's buttons are local again.
    await handler.skipToNext();
    expect(index, 1);
    expect(yt.calls, ['pause', 'released']);
  });

  test('loading a new local queue also hands it back', () async {
    handler.setExternalSource(yt, _yt());
    await handler.loadQueue([_song('3')]);
    expect(yt.calls, ['pause', 'released']);
    expect(handler.isExternalActive, isFalse);
    expect(handler.mediaItem.value!.id, '3');
  });

  test('local next / previous from the app hand it back too', () async {
    await handler.loadQueue([_song('1'), _song('2')], autoPlay: false);
    handler.setExternalSource(yt, _yt());
    await handler.skipToNextLocal();
    expect(yt.calls, ['pause', 'released']);
    expect(index, 1);
    handler.setExternalSource(yt, _yt());
    await handler.skipToPreviousLocal();
    expect(yt.calls, ['pause', 'released', 'pause', 'released']);
  });

  test('the page clearing the source restores the paused local track', () async {
    await handler.loadQueue([_song('1'), _song('2')], autoPlay: false);
    handler.setExternalSource(yt, _yt());
    handler.clearExternalSource(yt);
    expect(handler.isExternalActive, isFalse);
    expect(yt.calls, isEmpty, reason: 'it was the page that let go');
    expect(handler.mediaItem.value!.id, '1');
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.controls.length, 5);
    verifyNever(() => player.play());
  });

  test('with no local queue, clearing leaves no item', () async {
    handler.setExternalSource(yt, _yt());
    handler.clearExternalSource(yt);
    expect(handler.mediaItem.value, isNull);
  });

  test('a stale delegate cannot update or clear another source', () async {
    final other = RecordingDelegate();
    handler.setExternalSource(yt, _yt());
    handler.setExternalSource(other, _yt(title: 'Other'));
    expect(yt.calls, ['released']);
    handler.updateExternalMedia(yt, _yt(title: 'Stale'));
    handler.clearExternalSource(yt);
    expect(handler.isExternalActive, isTrue);
    expect(handler.mediaItem.value!.title, 'Other');
  });

  test('stop from the notification pauses the page and ends the session', () async {
    handler.setExternalSource(yt, _yt());
    await handler.stop();
    expect(yt.calls, ['pause', 'released']);
    expect(handler.isExternalActive, isFalse);
    expect(handler.playbackState.value.processingState, AudioProcessingState.idle,
        reason: 'idle: audio_service stops the service and removes the notification');
  });

  test('shuffle / repeat custom actions are ignored while YouTube owns the session', () async {
    await handler.loadQueue([_song('1'), _song('2')], autoPlay: false);
    handler.setExternalSource(yt, _yt());
    await handler.customAction(MusicAudioHandler.actionCycleRepeat);
    expect(handler.repeatMode.name, 'off');
  });

  test('the external stream feeds the mini player and ends with null', () async {
    final seen = <ExternalMediaSnapshot?>[];
    final sub = handler.externalMediaStream.listen(seen.add);
    handler.setExternalSource(yt, _yt());
    handler.updateExternalMedia(yt, _yt(playing: false));
    handler.clearExternalSource(yt);
    await Future<void>.delayed(Duration.zero);
    expect(seen.length, 3);
    expect(seen[0]!.playing, isTrue);
    expect(seen[1]!.playing, isFalse);
    expect(seen[2], isNull);
    await sub.cancel();
  });
}
