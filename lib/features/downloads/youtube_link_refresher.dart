import 'dart:async';

import '../../data/database/app_database.dart';
import '../../data/downloads/download_engine.dart';
import '../../data/downloads/youtube_link.dart';
import '../../data/downloads/youtube_stream_source.dart';
import '../explore/online_models.dart';
import 'youtube_direct_resolver.dart';

/// Finds YouTube's link to a file again for downloads made without yt-dlp
/// (the iPhone way, [YoutubeDirectDownloadFlow]).
///
/// Those downloads save YouTube's link to the file itself, which stops
/// working after about six hours. The row also keeps a [YoutubeStreamSource]
/// (video id and chosen quality), so a resume or retry later can look the
/// video up again with the same lookup the quality sheet used:
/// 1. the very same file (same `itag`) when YouTube still offers it, so a
///    partial download carries on where it stopped;
/// 2. otherwise today's file for the same choice (for example 360p or audio
///    only), which starts the download over.
///
/// Only links on YouTube's media servers are ever returned
/// ([YoutubeLink.trustedStreamUri]), within the 2 GB limit.
class YoutubeLinkRefresher implements StreamLinkRefresher {
  YoutubeLinkRefresher({
    required YoutubeDirectResolver Function() resolver,
    DateTime Function()? clock,
    this.lookupTimeout = const Duration(seconds: 30),
  })  : _resolver = resolver, // ignore: prefer_initializing_formals
        _clock = clock ?? DateTime.now;

  /// Read when a lookup is needed (not when the engine is built).
  final YoutubeDirectResolver Function() _resolver;
  final DateTime Function() _clock;
  final Duration lookupTimeout;

  static YoutubeStreamSource? _sourceOf(DownloadEntry task) =>
      task.engine == 'http' ? YoutubeStreamSource.tryDecode(task.formatSelector) : null;

  @override
  bool canRefresh(DownloadEntry task) => _sourceOf(task) != null;

  @override
  bool isStale(DownloadEntry task, DateTime now) {
    final source = _sourceOf(task);
    if (source == null) return false;
    return YoutubeStreamSource.linkExpired(Uri.tryParse(task.url), source.resolvedAt, now);
  }

  @override
  Future<RefreshedStreamLink?> refresh(DownloadEntry task) async {
    final source = _sourceOf(task);
    if (source == null) return null;
    final resolver = _resolver();

    final OnlineStreams streams;
    try {
      streams = await Future<OnlineStreams>.sync(() => resolver.source.streams(source.videoId)).timeout(lookupTimeout);
    } catch (_) {
      return null;
    }
    if (YoutubeDirectOptions.looksLive(streams)) return null;
    final now = _clock();

    // 1. The same file, when YouTube still offers it.
    final itag = source.itag ?? YoutubeStreamSource.itagOf(Uri.tryParse(task.url));
    if (itag != null) {
      for (final s in [...streams.video, ...streams.audio]) {
        final uri = YoutubeLink.trustedStreamUri(s.url);
        if (uri == null || YoutubeStreamSource.itagOf(uri) != itag) continue;
        if (s.sizeBytes > DownloadEngine.maxDownloadSizeBytes) return null;
        return RefreshedStreamLink(
          uri: uri,
          linkSource: source.copyWith(itag: itag, resolvedAt: now).encode(),
          sizeBytes: s.sizeBytes > 0 ? s.sizeBytes : null,
          sameFile: true,
        );
      }
    }

    // 2. The same choice in today's file: a different file, so it starts over.
    final List<YoutubeDirectChoice> choices;
    try {
      choices = YoutubeDirectOptions.build(streams, mp4Only: resolver.mp4Only);
    } catch (_) {
      return null;
    }
    final match = choices.where((c) => c.id == source.choiceId).firstOrNull;
    if (match == null) return null;
    return RefreshedStreamLink(
      uri: match.uri,
      linkSource: source.copyWith(itag: YoutubeStreamSource.itagOf(match.uri), resolvedAt: now).encode(),
      sizeBytes: match.sizeBytes,
      sameFile: false,
    );
  }
}
