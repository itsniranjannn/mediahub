/// What the web link downloader's error codes mean for the app, and the plain
/// words shown for each.
///
/// The codes come from the native side (`ExtractorChannel.mapException`). A
/// failed download row stores them as `x_<code in lower case>`.
class ExtractorErrors {
  ExtractorErrors._();

  /// The site may have changed: a newer yt-dlp may read it again, so the app
  /// updates yt-dlp and tries once more.
  static const Set<String> updateMayHelp = {
    'EXTRACTION_FAILED',
    'FORMAT_UNAVAILABLE',
    'BOT_CHECK',
    'EMPTY_METADATA',
  };

  /// yt-dlp could not run, or could not read YouTube: for a YouTube link the
  /// path without yt-dlp may still save the video (at a lower quality).
  /// Problems with the video itself (private, age-restricted, removed, live,
  /// offline ...) are not on this list: no other way can save those.
  static const Set<String> youtubeFallbackMayHelp = {
    'INIT_FAILED',
    'INIT_ERROR',
    'FEATURE_DISABLED',
    'EXTRACTION_FAILED',
    'FORMAT_UNAVAILABLE',
    'BOT_CHECK',
    'EMPTY_METADATA',
    'RATE_LIMITED',
  };

  static const String tooSlow = 'This link is taking too long. Try again later.';
  static const String hostNotAllowed = 'This website is not supported by the web link downloader.';

  /// Shown after a quality lookup failed with [code].
  static String lookupMessage(String code) {
    switch (code) {
      case 'HOST_NOT_ALLOWED':
        return hostNotAllowed;
      case 'LOGIN_REQUIRED':
        return 'This video needs a login. Only public videos are supported.';
      case 'PRIVATE_CONTENT':
        return 'This video is private and cannot be downloaded.';
      case 'DRM_PROTECTED':
        return 'This content is DRM protected and cannot be downloaded.';
      case 'NOT_FOUND':
        return 'The video was not found. Check the link.';
      case 'NETWORK_ERROR':
        return 'Network problem. Check your connection and try again.';
      case 'PLAYLIST_NOT_SUPPORTED':
        return "Playlists and channels can't be downloaded. Open a single video link instead.";
      case 'LIVE_NOT_SUPPORTED':
        return "Live streams can't be downloaded.";
      case 'INFO_TIMEOUT':
        // The native watchdog stopped a slow or stuck yt-dlp lookup.
        return tooSlow;
      default:
        return _videoProblem(code) ?? 'Could not read this link. Please try again later.';
    }
  }

  /// Shown under a failed download whose row has [errorCode] (`x_...`).
  static String downloadMessage(String errorCode) {
    final code = errorCode.startsWith('x_') ? errorCode.substring(2).toUpperCase() : errorCode.toUpperCase();
    switch (code) {
      case 'LOGIN_REQUIRED':
        return 'This video needs a login. Only public videos can be downloaded.';
      case 'PRIVATE_CONTENT':
        return 'This video is private and cannot be downloaded.';
      case 'DRM_PROTECTED':
        return 'This content is DRM protected and cannot be downloaded.';
      case 'NOT_FOUND':
        return 'The video was not found. It may have been removed.';
      case 'FILE_TOO_LARGE':
        return 'The video is larger than the 2 GB limit.';
      case 'NETWORK_ERROR':
        return 'Network problem while downloading. Check your connection and retry.';
      case 'NO_OUTPUT':
        return 'The downloader finished but produced no file. Please retry.';
      case 'HOST_NOT_ALLOWED':
        return hostNotAllowed;
      case 'INIT_FAILED':
      case 'INIT_ERROR':
        return 'The downloader engine could not start. Please retry.';
      case 'PLAYLIST_NOT_SUPPORTED':
        return "Playlists and channels can't be downloaded. Open a single video link instead.";
      case 'CANCELLED':
        return 'The download was stopped. Tap Retry to start it again.';
      case 'EXTRACTION_FAILED':
        // MediaHub has already updated its downloader and tried again by now.
        return 'Could not fetch this video. The site may have changed. Tap Retry later.';
      default:
        return _videoProblem(code) ?? 'Web link download failed. Tap Retry to try again.';
    }
  }

  /// The same words for a lookup and a download: problems with the video.
  static String? _videoProblem(String code) {
    switch (code) {
      case 'AGE_RESTRICTED':
        return "This video is age-restricted, so it can't be downloaded.";
      case 'UNAVAILABLE':
        return 'This video is unavailable. It may have been removed or blocked in your country.';
      case 'LIVE_NOT_SUPPORTED':
        return "Live streams can't be downloaded. Try again after the stream has ended.";
      case 'BOT_CHECK':
        return 'YouTube is not letting this phone save the video right now. Try again later, or on another network.';
      case 'RATE_LIMITED':
        // YouTube's "Video unavailable ... try again later": a pause for this
        // phone's address, not a removed video.
        return 'YouTube is limiting downloads on this phone for a while. Try again in an hour.';
      case 'FORMAT_UNAVAILABLE':
        return 'This video has no version that can be saved right now. Try again later.';
      case 'NO_MEDIA':
        return 'This link has no video or audio to save.';
    }
    return null;
  }
}
