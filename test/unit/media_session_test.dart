import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/logging/diagnostics_service.dart';
import 'package:mediahub/domain/models/media_item.dart' as domain;
import 'package:mediahub/domain/models/playback_state.dart' as domain;
import 'package:mediahub/features/music_player/music_audio_handler.dart';
import 'package:mediahub/features/music_player/now_playing_art.dart';

import 'fake_audio_player.dart';

domain.MediaItem _song(int i, {String source = 'device'}) => domain.MediaItem(
      id: 's$i',
      uri: 'content://media/external/audio/media/$i',
      mediaType: domain.MediaType.audio,
      title: 'Song $i',
      artist: 'Artist $i',
      album: 'Album',
      durationMs: 180000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
      source: source,
    );

NowPlayingArt _noArt() => NowPlayingArt(cacheDirectory: () async => null);

Future<void> _settle() async {
  for (var i = 0; i < 3; i++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

List<String?> _customs(PlaybackState s) => [for (final c in s.controls) c.customAction?.name];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DiagnosticsService.enableDebounce = false);

  group('F14 like from the notification', () {
    late FakeAudioPlayer player;
    late MusicAudioHandler handler;
    late Map<String, StreamController<bool>> flags;
    late List<String> toggled;

    setUp(() {
      player = FakeAudioPlayer();
      flags = {};
      toggled = [];
      handler = MusicAudioHandler(
        player: player,
        art: _noArt(),
        watchFavorite: (id) => (flags[id] ??= StreamController<bool>.broadcast()).stream,
        onToggleFavorite: (id) async => toggled.add(id),
      );
    });

    tearDown(() async {
      await handler.dispose();
      for (final c in flags.values) {
        await c.close();
      }
    });

    test('a heart before shuffle and repeat (Android 13+ shows the first two custom actions)', () async {
      await handler.loadQueue([_song(0), _song(1)], autoPlay: false);
      await _settle();
      final s = handler.playbackState.value;
      expect(_customs(s).whereType<String>(), [
        MusicAudioHandler.actionToggleFavorite,
        MusicAudioHandler.actionToggleShuffle,
        MusicAudioHandler.actionCycleRepeat,
      ]);
      expect(s.androidCompactActionIndices, [0, 1, 2], reason: 'the transport stays the compact view');
      final like = s.controls.firstWhere((c) => c.customAction?.name == MusicAudioHandler.actionToggleFavorite);
      expect(like.androidIcon, 'drawable/ic_action_favorite_off');
      expect(like.label, 'Add to Favourites');
    });

    test('the heart toggles the playing song and follows the library', () async {
      await handler.loadQueue([_song(0), _song(1)], autoPlay: false);
      await _settle();
      await handler.customAction(MusicAudioHandler.actionToggleFavorite);
      expect(toggled, ['s0']);
      String icon() => handler.playbackState.value.controls
          .firstWhere((c) => c.customAction?.name == MusicAudioHandler.actionToggleFavorite)
          .androidIcon;
      expect(icon(), 'drawable/ic_action_favorite_on', reason: 'shown at once');

      // Un-liked in the app: the notification follows.
      flags['s0']!.add(false);
      await _settle();
      expect(icon(), 'drawable/ic_action_favorite_off');

      // The next song has its own flag.
      await handler.skipToNext();
      flags['s1']!.add(true);
      await _settle();
      expect(icon(), 'drawable/ic_action_favorite_on');
      await handler.customAction(MusicAudioHandler.actionToggleFavorite);
      expect(toggled, ['s0', 's1']);
    });

    test('no heart for an online stream item or while YouTube owns the session', () async {
      await handler.loadQueue([_song(0, source: 'online')], autoPlay: false);
      await _settle();
      expect(_customs(handler.playbackState.value), isNot(contains(MusicAudioHandler.actionToggleFavorite)));
      await handler.customAction(MusicAudioHandler.actionToggleFavorite);
      expect(toggled, isEmpty);
    });
  });

  group('F12 media resumption (quick-settings player after the app was closed)', () {
    late Directory cache;
    late FakeAudioPlayer player;
    late MusicAudioHandler handler;
    var loads = 0;

    final saved = domain.PlaybackState(
      currentItemId: 's1',
      queue: [_song(0), _song(1), _song(2)],
      originalQueue: [_song(0), _song(1), _song(2)],
      queueIndex: 1,
      position: const Duration(seconds: 42),
      repeatMode: domain.PlaybackRepeatMode.all,
      updatedAt: DateTime(2026),
    );

    setUp(() {
      loads = 0;
      cache = Directory.systemTemp.createTempSync('np_resume');
      player = FakeAudioPlayer();
      handler = MusicAudioHandler(
        player: player,
        art: NowPlayingArt(
          cacheDirectory: () async => cache,
          embeddedArt: (_) async => Uint8List.fromList([0xFF, 0xD8, 1, 2, 0xFF, 0xD9]),
        ),
        loadLastSession: () async {
          loads++;
          return saved;
        },
      );
    });

    tearDown(() async {
      await handler.dispose();
      try {
        cache.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('the "recent" root offers the last song with its cover', () async {
      final items = await handler.getChildren(AudioService.recentRootId);
      expect(items, hasLength(1));
      expect(items.single.id, 's1');
      expect(items.single.title, 'Song 1');
      expect(items.single.artUri?.scheme, 'file');
      expect(await handler.getChildren(AudioService.browsableRootId), isEmpty);
    });

    test('play from the system player restores the session and plays where it stopped', () async {
      await handler.play();
      await _settle();
      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 's1');
      expect(player.position, const Duration(seconds: 42));
      expect(player.playing, isTrue);
      expect(handler.repeatMode, domain.PlaybackRepeatMode.all);

      // The app's own restore (PlaybackNotifier) later must not clobber it.
      await handler.restoreSession(domain.PlaybackState(
        queue: [_song(9)],
        queueIndex: 0,
        updatedAt: DateTime(2026),
      ));
      expect(handler.playOrderQueue.map((m) => m.id), ['s0', 's1', 's2']);
      expect(player.playing, isTrue);
    });

    test('prepare restores without playing; playFromMediaId plays that song', () async {
      await handler.prepare();
      await _settle();
      expect(handler.mediaItem.value?.id, 's1');
      expect(player.playing, isFalse);
      await handler.playFromMediaId('s2');
      await _settle();
      expect(handler.mediaItem.value?.id, 's2');
      expect(player.playing, isTrue);
      expect(loads, 1, reason: 'restored once');
    });
  });

  group('session updates', () {
    test('an identical state is not sent again (no notification redraws while paused)', () async {
      final player = FakeAudioPlayer();
      final handler = MusicAudioHandler(player: player, art: _noArt());
      addTearDown(handler.dispose);
      await handler.loadQueue([_song(0), _song(1)], autoPlay: false);
      await _settle();
      var sent = 0;
      final sub = handler.playbackState.skip(1).listen((_) => sent++);
      for (var i = 0; i < 5; i++) {
        await handler.setSpeed(1.0);
        player.repeatState();
      }
      await _settle();
      expect(sent, 0);
      await handler.setSpeed(1.5);
      await _settle();
      expect(sent, 1);
      await sub.cancel();
    });
  });

  group('external sources name themselves (P3 interface)', () {
    test('the snapshot album shows in the notification, "YouTube" when not given', () async {
      final handler = MusicAudioHandler(player: FakeAudioPlayer(), art: _noArt());
      addTearDown(handler.dispose);
      final page = _Delegate();
      handler.setExternalSource(page, const ExternalMediaSnapshot(id: 'online:a', title: 'A', playing: true));
      expect(handler.mediaItem.value?.album, 'YouTube');
      handler.updateExternalMedia(
          page, const ExternalMediaSnapshot(id: 'video:1', title: 'Holiday', album: 'Videos', playing: true));
      expect(handler.mediaItem.value?.album, 'Videos');
      expect(
        const ExternalMediaSnapshot(id: 'x', title: 't', album: 'A', playing: true) ==
            const ExternalMediaSnapshot(id: 'x', title: 't', album: 'B', playing: true),
        isFalse,
      );
      expect(const ExternalMediaSnapshot(id: 'x', title: 't', playing: true).albumOrDefault, 'YouTube');
    });
  });
}

class _Delegate implements ExternalPlaybackDelegate {
  @override
  Future<void> externalPause() async {}
  @override
  Future<void> externalPlay() async {}
  @override
  Future<void> externalSeek(Duration position) async {}
  @override
  Future<void> externalSkipToNext() async {}
  @override
  Future<void> externalSkipToPrevious() async {}
  @override
  void onExternalSourceReleased() {}
}
