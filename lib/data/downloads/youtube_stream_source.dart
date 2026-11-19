import 'dart:convert';

import 'youtube_link.dart';

/// What a YouTube download without yt-dlp needs to find its file again.
///
/// Such a download saves YouTube's link to the file itself (on a
/// `googlevideo.com` server). That link stops working after about six hours,
/// so a download paused, stopped or retried later would fail. This keeps the
/// video id and the quality the user chose, so the link can be looked up
/// again ([YoutubeLinkRefresher]).
///
/// Stored, [encode]d, in the download row's `formatSelector` column, which
/// direct-link rows do not use otherwise (yt-dlp rows keep their own format
/// selector there and are never read as this).
class YoutubeStreamSource {
  const YoutubeStreamSource({
    required this.videoId,
    required this.choiceId,
    required this.resolvedAt,
    this.itag,
  });

  /// The 11-character video id.
  final String videoId;

  /// The quality sheet's choice, e.g. `yt_v360` or `yt_audio`.
  final String choiceId;

  /// YouTube's number for the exact file (`itag` in the link), when known.
  final int? itag;

  /// When the saved link was looked up.
  final DateTime resolvedAt;

  static const String _prefix = 'youtube-direct:';

  /// A YouTube link is looked up again once it is this old, even when it
  /// does not say when it ends (YouTube's last about six hours).
  static const Duration maxLinkAge = Duration(hours: 5);

  /// Looked up again this long before the end time the link states.
  static const Duration expiryMargin = Duration(minutes: 10);

  String encode() => '$_prefix${jsonEncode({
        'v': videoId,
        'c': choiceId,
        if (itag != null) 'i': itag,
        't': resolvedAt.millisecondsSinceEpoch ~/ 1000,
      })}';

  /// The source saved in [stored], or null when it holds none (or anything
  /// malformed).
  static YoutubeStreamSource? tryDecode(String? stored) {
    if (stored == null || !stored.startsWith(_prefix)) return null;
    try {
      final map = jsonDecode(stored.substring(_prefix.length));
      if (map is! Map) return null;
      final id = map['v'];
      final choice = map['c'];
      final itag = map['i'];
      final at = map['t'];
      if (id is! String || !YoutubeLink.isValidId(id)) return null;
      if (choice is! String || choice.isEmpty) return null;
      if (at is! int) return null;
      return YoutubeStreamSource(
        videoId: id,
        choiceId: choice,
        itag: itag is int ? itag : null,
        resolvedAt: DateTime.fromMillisecondsSinceEpoch(at * 1000),
      );
    } catch (_) {
      return null;
    }
  }

  YoutubeStreamSource copyWith({int? itag, DateTime? resolvedAt}) => YoutubeStreamSource(
        videoId: videoId,
        choiceId: choiceId,
        itag: itag ?? this.itag,
        resolvedAt: resolvedAt ?? this.resolvedAt,
      );

  /// YouTube's number for the file a stream [link] serves, or null.
  static int? itagOf(Uri? link) => int.tryParse(link?.queryParameters['itag'] ?? '');

  /// True when [link] (looked up at [resolvedAt]) has expired or is about to:
  /// past the end time it states (`expire`, seconds since 1970) less
  /// [expiryMargin], or older than [maxLinkAge].
  static bool linkExpired(Uri? link, DateTime resolvedAt, DateTime now) {
    if (!now.isBefore(resolvedAt.add(maxLinkAge))) return true;
    final expire = int.tryParse(link?.queryParameters['expire'] ?? '');
    if (expire == null) return false;
    final end = DateTime.fromMillisecondsSinceEpoch(expire * 1000);
    return !now.isBefore(end.subtract(expiryMargin));
  }
}
