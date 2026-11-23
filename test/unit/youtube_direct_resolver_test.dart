import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/data/downloads/download_engine.dart';
import 'package:mediahub/data/downloads/youtube_link.dart';
import 'package:mediahub/features/downloads/youtube_direct_resolver.dart';
import 'package:mediahub/features/explore/online_models.dart';

import 'fake_online_source.dart';

const _id = 'dQw4w9WgXcQ';
final _link = YoutubeLink.tryParse('https://youtu.be/$_id')!;

OnlineStream _video(int height, {String container = 'mp4', int size = 1000, int kbps = 500, String? url}) =>
    OnlineStream(
      url: url ?? 'https://rr1---sn-test.googlevideo.com/videoplayback?itag=$height$container',
      kind: OnlineStreamKind.video,
      label: '${height}p',
      container: container,
      sizeBytes: size,
      bitrateKbps: kbps,
      height: height,
    );

OnlineStream _audio({String container = 'mp4', int size = 500, int kbps = 128, String? url}) => OnlineStream(
      url: url ?? 'https://rr1---sn-test.googlevideo.com/videoplayback?itag=a$kbps$container',
      kind: OnlineStreamKind.audio,
      label: '$kbps kbps',
      container: container,
      sizeBytes: size,
      bitrateKbps: kbps,
    );

const _details = YoutubeVideoDetails(
  id: _id,
  title: 'Mountain Song',
  author: 'Himal Sessions',
  duration: Duration(minutes: 3, seconds: 30),
  thumbnailUrl: 'https://i.ytimg.com/vi/$_id/mqdefault.jpg',
);

void main() {
  group('YoutubeDirectOptions.build (the quality list)', () {
    test('video qualities highest first, one per height, MP4 before WebM, then every audio quality (M4A first)', () {
      final choices = YoutubeDirectOptions.build(OnlineStreams(
        video: [
          _video(360, size: 12 * 1024 * 1024),
          _video(720, container: 'webm', size: 40 * 1024 * 1024),
          _video(720, size: 30 * 1024 * 1024, kbps: 900),
          _video(144, container: '3gpp'),
        ],
        audio: [
          _audio(container: 'webm', kbps: 160, size: 4000),
          _audio(kbps: 128, size: 3 * 1024 * 1024),
          _audio(kbps: 48, size: 1000),
        ],
      ));

      expect(choices.map((c) => c.label), [
        '720p',
        '360p',
        'Audio only (M4A, 128 kbps)',
        'Audio only (M4A, 48 kbps)',
        'Audio only (WEBM, 160 kbps)',
      ]);
      final hd = choices.first;
      expect(hd.container, 'mp4', reason: 'MP4 wins over WebM at the same height');
      expect(hd.fileExtension, 'mp4');
      expect(hd.subtitle, 'MP4 · 30.0 MB');
      expect(hd.qualityLabel, '720p');
      expect(hd.isAudio, isFalse);

      final audio = choices[2];
      expect(audio.id, 'yt_audio', reason: 'the best audio keeps the stable id');
      expect(audio.isAudio, isTrue);
      expect(audio.fileExtension, 'm4a', reason: 'M4A is preferred even over a higher-bitrate WebM');
      expect(audio.qualityLabel, 'Audio 128 kbps');
      expect(audio.subtitle, 'M4A · 3.0 MB');
      expect(audio.uri.host, 'rr1---sn-test.googlevideo.com');
      expect(choices.map((c) => c.id).toSet(), hasLength(choices.length), reason: 'ids are unique');
    });

    test('iOS (MP4 only): WebM video and audio are never offered', () {
      final choices = YoutubeDirectOptions.build(
        OnlineStreams(
          video: [_video(480, container: 'webm'), _video(360)],
          audio: [_audio(container: 'webm', kbps: 160)],
        ),
        mp4Only: true,
      );
      expect(choices.map((c) => c.label), ['360p']);
    });

    test('iOS: audio rows say M4A (AAC), never MP3', () {
      final choices = YoutubeDirectOptions.build(
        OnlineStreams(video: const [], audio: [_audio(kbps: 128), _audio(kbps: 48, size: 300)]),
        mp4Only: true,
      );
      expect(choices.map((c) => c.label), ['M4A (AAC) · 128 kbps', 'M4A (AAC) · 48 kbps']);
      expect(choices.any((c) => c.label.contains('MP3')), isFalse);
    });

    test('Android: a WebM audio fills in when there is no M4A', () {
      final choices = YoutubeDirectOptions.build(OnlineStreams(
        video: const [],
        audio: [_audio(container: 'webm', kbps: 160)],
      ));
      expect(choices.single.label, 'Audio only (WEBM, 160 kbps)');
      expect(choices.single.fileExtension, 'webm');
    });

    test('unknown sizes say so instead of showing 0 bytes', () {
      final choices = YoutubeDirectOptions.build(OnlineStreams(video: [_video(360, size: 0)], audio: const []));
      expect(choices.single.sizeBytes, isNull);
      expect(choices.single.subtitle, 'MP4 · size unknown');
    });

    test('host allowlist: streams outside googlevideo.com (or not https) are dropped', () {
      final choices = YoutubeDirectOptions.build(OnlineStreams(
        video: [
          _video(720, url: 'https://evil.example/videoplayback?itag=22'),
          _video(480, url: 'http://rr1.googlevideo.com/videoplayback?itag=35'),
          _video(360),
        ],
        audio: [_audio(url: 'https://googlevideo.com.evil.example/a')],
      ));
      expect(choices.map((c) => c.label), ['360p']);
    });

    test('nothing trusted left: the error says the address was unexpected', () {
      expect(
        () => YoutubeDirectOptions.build(OnlineStreams(
          video: [_video(360, url: 'https://evil.example/v')],
          audio: [_audio(url: 'https://evil.example/a')],
        )),
        throwsA(same(YoutubeDirectException.unexpectedAddress)),
      );
    });

    test('2 GB cap: larger files are not offered, and only-too-large says so', () {
      final big = DownloadEngine.maxDownloadSizeBytes + 1;
      final choices = YoutubeDirectOptions.build(OnlineStreams(
        video: [_video(720, size: big), _video(360, size: 100)],
        audio: const [],
      ));
      expect(choices.map((c) => c.label), ['360p']);

      expect(
        () => YoutubeDirectOptions.build(OnlineStreams(video: [_video(720, size: big)], audio: [_audio(size: big)])),
        throwsA(same(YoutubeDirectException.tooLarge)),
      );
    });

    test('no playable stream at all', () {
      expect(
        () => YoutubeDirectOptions.build(const OnlineStreams(video: [], audio: [])),
        throwsA(same(YoutubeDirectException.nothingToDownload)),
      );
    });

    test('live broadcast addresses are recognised', () {
      expect(
        YoutubeDirectOptions.looksLive(OnlineStreams(
          video: [_video(360, url: 'https://rr1.googlevideo.com/videoplayback?source=yt_live_broadcast')],
          audio: const [],
        )),
        isTrue,
      );
      expect(YoutubeDirectOptions.looksLive(OnlineStreams(video: [_video(360)], audio: [_audio()])), isFalse);
    });
  });

  group('YoutubeDirectResolver (fake online source, no network)', () {
    late FakeOnlineSource source;

    setUp(() => source = FakeOnlineSource());

    YoutubeDirectResolver resolver({
      Future<YoutubeVideoDetails> Function(String id)? details,
      bool mp4Only = false,
    }) =>
        YoutubeDirectResolver(
          source: source,
          fetchDetails: details ?? (_) async => _details,
          mp4Only: mp4Only,
          detailsTimeout: const Duration(seconds: 2),
        );

    test('resolves a canonical youtu.be link into details and choices', () async {
      source.onStreams = (_) async => OnlineStreams(video: [_video(360)], audio: [_audio()]);
      final result = await resolver().resolve(_link);

      expect(source.streamCalls, [_id]);
      expect(result.details.title, 'Mountain Song');
      expect(result.details.author, 'Himal Sessions');
      expect(result.choices.map((c) => c.label), ['360p', 'Audio only (M4A, 128 kbps)']);
      expect(result.link.videoId, _id);
    });

    test('every accepted link shape asks for the same video', () async {
      source.onStreams = (_) async => OnlineStreams(video: [_video(360)], audio: const []);
      for (final url in [
        'https://www.youtube.com/watch?v=$_id&si=x',
        'https://youtube.com/shorts/$_id',
        'https://music.youtube.com/watch?v=$_id',
        'https://www.youtube.com/live/$_id',
      ]) {
        await resolver().resolve(YoutubeLink.tryParse(url)!);
      }
      expect(source.streamCalls, List.filled(4, _id));
    });

    test('a live video is refused with a plain message', () async {
      source.onStreams = (_) async => OnlineStreams(video: [_video(360)], audio: const []);
      final live = resolver(
        details: (_) async => const YoutubeVideoDetails(id: _id, title: 'On air', author: 'X', isLive: true),
      );
      await expectLater(
        live.resolve(_link),
        throwsA(isA<YoutubeDirectException>().having(
          (e) => e.message,
          'message',
          "Live streams can't be downloaded. Try again after the stream has ended.",
        )),
      );
    });

    test('a live video whose stream lookup fails still says "live", with no stray error', () async {
      source.onStreams = (_) async => throw const OnlineException('This video has no playable streams.');
      final live = resolver(
        details: (_) async => const YoutubeVideoDetails(id: _id, title: 'On air', author: 'X', isLive: true),
      );
      await expectLater(live.resolve(_link), throwsA(same(YoutubeDirectException.live)));
    });

    test('live is caught from the stream addresses when the details are missing', () async {
      source.onStreams = (_) async => OnlineStreams(
            video: [_video(360, url: 'https://rr1.googlevideo.com/videoplayback?live=1')],
            audio: const [],
          );
      final r = resolver(details: (_) async => throw StateError('watch page changed'));
      await expectLater(r.resolve(_link), throwsA(same(YoutubeDirectException.live)));
    });

    test('details failing is not fatal: the Online title names the download', () async {
      source.onStreams = (_) async => OnlineStreams(video: [_video(360)], audio: const []);
      final r = resolver(details: (_) async => throw const SocketException('offline'));
      final result = await r.resolve(_link, titleHint: '  Title from Online  ');
      expect(result.details.title, 'Title from Online');
      expect(result.details.author, '');

      final noHint = await r.resolve(_link);
      expect(noHint.details.title, 'YouTube video');
    });

    test('slow details do not hold up the result beyond their timeout', () async {
      source.onStreams = (_) async => OnlineStreams(video: [_video(360)], audio: const []);
      final r = resolver(details: (_) => Completer<YoutubeVideoDetails>().future);
      final result = await r.resolve(_link, titleHint: 'Hint');
      expect(result.details.title, 'Hint');
    });

    test('iOS: MP4 / M4A only', () async {
      source.onStreams = (_) async => OnlineStreams(
            video: [_video(360, container: 'webm')],
            audio: [_audio(container: 'webm'), _audio()],
          );
      final result = await resolver(mp4Only: true).resolve(_link);
      expect(result.choices.map((c) => c.fileExtension), ['m4a']);
    });

    group('errors are plain words', () {
      final cases = <String, (Object, String)>{
        'source message, passed on': (
          const OnlineException('No internet connection.'),
          'No internet connection.',
        ),
        'private video, worded for downloading': (
          const OnlineException('This video cannot be played here (private, age-restricted or unavailable).'),
          "This video can't be downloaded: it is private, age-restricted or unavailable.",
        ),
        'no streams, worded for downloading': (
          const OnlineException('This video has no playable streams.'),
          'YouTube offers no file of this video that this phone can save. Try another video.',
        ),
        'timeout': (TimeoutException('x'), 'YouTube is taking too long to answer. Try again later.'),
        'offline': (const SocketException('x'), 'No internet connection.'),
        'TLS': (const HandshakeException('x'), 'Could not make a secure connection to YouTube.'),
        'anything else': (StateError('boom'), 'Could not read this YouTube link. Please try again.'),
      };
      cases.forEach((name, c) {
        test(name, () async {
          source.onStreams = (_) async => throw c.$1;
          await expectLater(
            resolver().resolve(_link),
            throwsA(isA<YoutubeDirectException>().having((e) => e.message, 'message', c.$2)),
          );
        });
      });

      test('a source that throws synchronously is handled too', () async {
        source.onStreams = (_) => throw const OnlineException('Invalid video.');
        await expectLater(
          resolver().resolve(_link),
          throwsA(isA<YoutubeDirectException>().having((e) => e.message, 'message', 'Invalid video.')),
        );
      });
    });
  });
}
