// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/platform_info.dart';
import '../../core/utils/formatters.dart';
import '../../data/downloads/download_engine.dart';
import '../../data/downloads/youtube_link.dart';
import '../explore/online_models.dart';
import '../explore/online_source.dart';

// YouTube links without yt-dlp (iOS, or Android with the web link downloader
// off or not working): the ready-made files YouTube serves directly, found
// with youtube_explode_dart (the Online tab's [OnlineSource]) and downloaded
// by the direct-link engine like any other link. Video files that already
// contain sound only come in low qualities (usually 360p, sometimes 720p);
// audio-only files come in every bitrate.

/// Title, channel and cover of one video.
class YoutubeVideoDetails {
  const YoutubeVideoDetails({
    required this.id,
    required this.title,
    required this.author,
    this.duration,
    this.thumbnailUrl = '',
    this.isLive = false,
  });

  final String id;
  final String title;

  /// Channel name ("Artist - Topic" channels lose the " - Topic").
  final String author;
  final Duration? duration;
  final String thumbnailUrl;

  /// A live stream that is on air right now (or a premiere that has not ended).
  final bool isLive;
}

/// Looks up a video's details (title, channel, cover, live or not).
typedef YoutubeDetailsFetcher = Future<YoutubeVideoDetails> Function(String videoId);

/// One file the user can pick in the quality sheet.
class YoutubeDirectChoice {
  const YoutubeDirectChoice({
    required this.id,
    required this.uri,
    required this.isAudio,
    required this.label,
    required this.container,
    required this.fileExtension,
    required this.qualityLabel,
    this.sizeBytes,
    this.bitrateKbps,
    this.height,
  });

  /// Stable id within one lookup, e.g. `yt_v360` or `yt_audio`.
  final String id;

  /// The stream address, already checked by [YoutubeLink.trustedStreamUri].
  final Uri uri;
  final bool isAudio;

  /// Headline in the sheet, e.g. "360p" or "Audio only (M4A, 128 kbps)".
  final String label;

  /// Container YouTube reported: mp4 or webm.
  final String container;

  /// Extension of the saved file: mp4, m4a or webm.
  final String fileExtension;

  /// Stored on the download row and shown as a chip ("360p", "Audio 128 kbps").
  final String qualityLabel;

  /// Exact size when YouTube reported it.
  final int? sizeBytes;
  final int? bitrateKbps;
  final int? height;

  /// "MP4 · 23.4 MB" (or "size unknown").
  String get subtitle =>
      '${fileExtension.toUpperCase()} · ${sizeBytes != null ? formatFileSize(sizeBytes!) : 'size unknown'}';
}

/// What a lookup found: the video and the files to choose from.
class YoutubeDirectResult {
  const YoutubeDirectResult({required this.link, required this.details, required this.choices});

  final YoutubeLink link;
  final YoutubeVideoDetails details;

  /// Video qualities first (highest first), then audio only.
  final List<YoutubeDirectChoice> choices;
}

/// A lookup that ended without anything to download. [message] is plain
/// words, ready for the user.
class YoutubeDirectException implements Exception {
  const YoutubeDirectException(this.message);

  final String message;

  static const live = YoutubeDirectException(
    "Live streams can't be downloaded. Try again after the stream has ended.",
  );
  static const notAVideo = YoutubeDirectException(
    "This YouTube link doesn't open a single video. Open the video and copy its link.",
  );
  static const collection = YoutubeDirectException(
    "Playlists and channels can't be downloaded. Open a single video link instead.",
  );
  static const tooLarge = YoutubeDirectException('This video is larger than the 2 GB download limit.');
  static const unexpectedAddress = YoutubeDirectException(
    'YouTube answered with an unexpected download address, so nothing was downloaded.',
  );
  static const nothingToDownload = YoutubeDirectException(
    'YouTube offers no file of this video that this phone can save. Try another video.',
  );
  static const tooSlow = YoutubeDirectException('YouTube is taking too long to answer. Try again later.');
  static const failed = YoutubeDirectException('Could not read this YouTube link. Please try again.');

  @override
  String toString() => message;
}

/// Turns the streams of a video into the choices shown in the quality sheet.
class YoutubeDirectOptions {
  YoutubeDirectOptions._();

  /// Builds the choices, keeping only streams that may be downloaded:
  /// https on YouTube's media servers, at most [maxBytes], and a container
  /// this phone plays. With [mp4Only] (iOS: its players cannot open WebM)
  /// only MP4 / M4A files are offered; otherwise WebM fills a gap when no MP4
  /// of that quality exists.
  ///
  /// Throws a [YoutubeDirectException] that says why when nothing is left.
  static List<YoutubeDirectChoice> build(
    OnlineStreams streams, {
    bool mp4Only = false,
    int maxBytes = DownloadEngine.maxDownloadSizeBytes,
  }) {
    var untrusted = 0;
    var tooLarge = 0;

    /// The stream's address when it passes the host and size rules.
    Uri? accept(OnlineStream s) {
      final uri = YoutubeLink.trustedStreamUri(s.url);
      if (uri == null) {
        untrusted++;
        return null;
      }
      if (s.sizeBytes > maxBytes) {
        tooLarge++;
        return null;
      }
      return uri;
    }

    bool playable(String container) => container == 'mp4' || (!mp4Only && container == 'webm');

    // --- video with sound: the best stream per height, MP4 before WebM ---
    final byHeight = <int, (OnlineStream, Uri)>{};
    for (final s in streams.video) {
      final container = s.container.toLowerCase();
      if (!playable(container)) continue;
      final height = s.height ?? _heightFromLabel(s.label);
      if (height == null || height <= 0) continue;
      final uri = accept(s);
      if (uri == null) continue;
      final current = byHeight[height];
      if (current == null || _betterVideo(s, current.$1)) byHeight[height] = (s, uri);
    }
    final heights = byHeight.keys.toList()..sort((a, b) => b.compareTo(a));
    final video = [
      for (final h in heights)
        _videoChoice(h, byHeight[h]!.$1, byHeight[h]!.$2),
    ];

    // --- audio only: every distinct quality, M4A first, then highest bitrate.
    // The best one keeps the stable id `yt_audio` (link refresh looks it up).
    final audioStreams = [
      for (final s in streams.audio)
        if (playable(s.container.toLowerCase())) s,
    ]..sort((a, b) => _betterAudio(a, b) ? -1 : (_betterAudio(b, a) ? 1 : 0));
    final audioChoices = <YoutubeDirectChoice>[];
    final seen = <String>{};
    for (final s in audioStreams) {
      final uri = accept(s);
      if (uri == null) continue;
      final key = '${s.container.toLowerCase()}${s.bitrateKbps ?? 0}';
      if (!seen.add(key)) continue;
      audioChoices.add(_audioChoice(s, uri, id: audioChoices.isEmpty ? 'yt_audio' : 'yt_audio_$key', apple: mp4Only));
    }
    final choices = [
      ...video,
      ...audioChoices,
    ];
    if (choices.isNotEmpty) return choices;
    if (tooLarge > 0) throw YoutubeDirectException.tooLarge;
    if (untrusted > 0) throw YoutubeDirectException.unexpectedAddress;
    throw YoutubeDirectException.nothingToDownload;
  }

  /// True when any stream address marks a live broadcast (belt and braces:
  /// the video details say so too, but may be missing).
  static bool looksLive(OnlineStreams streams) {
    for (final s in [...streams.video, ...streams.audio]) {
      final q = Uri.tryParse(s.url)?.queryParameters ?? const <String, String>{};
      if (q['source'] == 'yt_live_broadcast' || q['live'] == '1') return true;
    }
    return false;
  }

  static int? _heightFromLabel(String label) => int.tryParse(RegExp(r'^(\d+)p').firstMatch(label)?.group(1) ?? '');

  /// MP4 wins over WebM at the same height, then the higher bitrate.
  static bool _betterVideo(OnlineStream a, OnlineStream b) {
    final am = a.container.toLowerCase() == 'mp4' ? 1 : 0;
    final bm = b.container.toLowerCase() == 'mp4' ? 1 : 0;
    if (am != bm) return am > bm;
    return (a.bitrateKbps ?? 0) > (b.bitrateKbps ?? 0);
  }

  /// M4A (AAC) wins over WebM (Opus) whatever the bitrate, then the higher bitrate.
  static bool _betterAudio(OnlineStream a, OnlineStream b) {
    final am = a.container.toLowerCase() == 'mp4' ? 1 : 0;
    final bm = b.container.toLowerCase() == 'mp4' ? 1 : 0;
    if (am != bm) return am > bm;
    return (a.bitrateKbps ?? 0) > (b.bitrateKbps ?? 0);
  }

  static YoutubeDirectChoice _videoChoice(int height, OnlineStream s, Uri uri) {
    final container = s.container.toLowerCase();
    return YoutubeDirectChoice(
      id: 'yt_v$height',
      uri: uri,
      isAudio: false,
      label: '${height}p',
      container: container,
      fileExtension: container,
      qualityLabel: '${height}p',
      sizeBytes: s.sizeBytes > 0 ? s.sizeBytes : null,
      bitrateKbps: s.bitrateKbps,
      height: height,
    );
  }

  /// [apple] (iOS): "M4A (AAC) · 128 kbps", so nobody looks for an MP3 there.
  static YoutubeDirectChoice _audioChoice(OnlineStream s, Uri uri, {String id = 'yt_audio', bool apple = false}) {
    final container = s.container.toLowerCase();
    final ext = container == 'mp4' ? 'm4a' : container;
    final kbps = s.bitrateKbps;
    final rate = kbps != null && kbps > 0 ? ', $kbps kbps' : '';
    final label = apple && ext == 'm4a'
        ? 'M4A (AAC)${kbps != null && kbps > 0 ? ' · $kbps kbps' : ''}'
        : 'Audio only (${ext.toUpperCase()}$rate)';
    return YoutubeDirectChoice(
      id: id,
      uri: uri,
      isAudio: true,
      label: label,
      container: container,
      fileExtension: ext,
      qualityLabel: kbps != null && kbps > 0 ? 'Audio $kbps kbps' : 'Audio',
      sizeBytes: s.sizeBytes > 0 ? s.sizeBytes : null,
      bitrateKbps: kbps,
    );
  }
}

/// Finds what can be downloaded for one YouTube video, without yt-dlp.
class YoutubeDirectResolver {
  YoutubeDirectResolver({
    required this.source,
    required this.fetchDetails,
    this.mp4Only = false,
    this.detailsTimeout = const Duration(seconds: 20),
  });

  /// The stream lookup (the Online tab's youtube_explode_dart source).
  final OnlineSource source;
  final YoutubeDetailsFetcher fetchDetails;

  /// Offer MP4 / M4A files only (iOS).
  final bool mp4Only;
  final Duration detailsTimeout;

  /// Looks up [link]. [titleHint] (the title the Online tab saw) is used when
  /// the details lookup fails. Throws a [YoutubeDirectException] with a plain
  /// message when there is nothing to download.
  Future<YoutubeDirectResult> resolve(YoutubeLink link, {String? titleHint}) async {
    final id = link.videoId;
    if (!YoutubeLink.isValidId(id)) throw YoutubeDirectException.notAVideo;

    // Both lookups run at once. Each is wrapped so that whichever is not
    // awaited (details said "live") never reports an unhandled error.
    final streamsLookup = Future<OnlineStreams>.sync(() => source.streams(id))
        .then<_Outcome<OnlineStreams>>(
          _Outcome<OnlineStreams>.value,
          onError: (Object e) => _Outcome<OnlineStreams>.error(e),
        );
    final details = await Future<YoutubeVideoDetails>.sync(() => fetchDetails(id))
        .timeout(detailsTimeout)
        .then<YoutubeVideoDetails?>((d) => d, onError: (Object _) => null);

    if (details != null && details.isLive) throw YoutubeDirectException.live;

    final streams = await streamsLookup;
    final error = streams.error;
    if (error != null) throw friendlyError(error);
    final found = streams.result!;
    if (YoutubeDirectOptions.looksLive(found)) throw YoutubeDirectException.live;

    final choices = YoutubeDirectOptions.build(found, mp4Only: mp4Only);
    final hint = titleHint?.trim() ?? '';
    return YoutubeDirectResult(
      link: link,
      details: details ??
          YoutubeVideoDetails(
            id: id,
            title: hint.isNotEmpty ? hint : 'YouTube video',
            author: '',
          ),
      choices: choices,
    );
  }

  /// Plain words for anything a lookup can throw.
  static YoutubeDirectException friendlyError(Object error) {
    if (error is YoutubeDirectException) return error;
    // The Online source already words its errors for people (for playing);
    // the two that talk about playing are reworded for downloading.
    if (error is OnlineException) {
      final text = error.message.toLowerCase();
      if (text.contains('private') || text.contains('age-restricted')) {
        return const YoutubeDirectException(
          "This video can't be downloaded: it is private, age-restricted or unavailable.",
        );
      }
      if (text.contains('no playable streams')) return YoutubeDirectException.nothingToDownload;
      return YoutubeDirectException(error.message);
    }
    if (error is TimeoutException) return YoutubeDirectException.tooSlow;
    if (error is SocketException) return const YoutubeDirectException('No internet connection.');
    if (error is HandshakeException) {
      return const YoutubeDirectException('Could not make a secure connection to YouTube.');
    }
    return YoutubeDirectException.failed;
  }
}

class _Outcome<T> {
  const _Outcome.value(T this.result) : error = null;
  const _Outcome.error(Object this.error) : result = null;

  final T? result;
  final Object? error;
}

/// Video details through youtube_explode_dart's watch page lookup.
Future<YoutubeVideoDetails> fetchYoutubeDetails(YoutubeExplode yt, String videoId) async {
  final v = await yt.videos.get(VideoId(videoId));
  final thumb = v.thumbnails.mediumResUrl;
  final thumbHost = Uri.tryParse(thumb)?.host.toLowerCase() ?? '';
  return YoutubeVideoDetails(
    id: videoId,
    title: v.title,
    author: v.author.replaceFirst(RegExp(r' - Topic$'), ''),
    duration: v.duration,
    // Only YouTube's own image host; otherwise the still built from the id.
    thumbnailUrl: thumb.startsWith('https://') && (thumbHost == 'i.ytimg.com' || thumbHost.endsWith('.ytimg.com'))
        ? thumb
        : 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg',
    isLive: v.isLive,
  );
}

/// The resolver the Downloads screen uses. Tests override it with a fake source.
final youtubeDirectResolverProvider = Provider<YoutubeDirectResolver>((ref) {
  final yt = YoutubeExplode();
  ref.onDispose(yt.close);
  return YoutubeDirectResolver(
    source: ref.watch(onlineSourceProvider),
    fetchDetails: kMediaHubDemo
        ? (_) async => throw const OnlineException('Demo mode')
        : (id) => fetchYoutubeDetails(yt, id),
    mp4Only: PlatformInfo.isIOS,
  );
});
