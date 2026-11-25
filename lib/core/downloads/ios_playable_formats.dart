// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
/// Kinds of file that download fine but can never play on an iPhone.
///
/// MediaHub plays files on iOS through Apple's own players (AVFoundation,
/// behind just_audio and video_player), which cannot open Ogg, Opus, WebM,
/// MKV or AVI files. Android plays all of them, so only iOS checks this: the
/// Downloads card refuses such a direct link up front, and the download
/// engine refuses a finished file that turns out to be one.
class IosPlayableFormats {
  IosPlayableFormats._();

  /// The download row's error code when the engine refused such a file.
  static const String errorCode = 'ios_unplayable_format';

  static const Map<String, String> _byMime = {
    'audio/ogg': 'Ogg',
    'video/ogg': 'Ogg',
    'application/ogg': 'Ogg',
    'audio/opus': 'Opus',
    'audio/webm': 'WebM',
    'video/webm': 'WebM',
    'audio/x-matroska': 'MKV',
    'video/x-matroska': 'MKV',
    'video/x-msvideo': 'AVI',
    'video/avi': 'AVI',
    'video/msvideo': 'AVI',
  };

  static const Map<String, String> _byExtension = {
    'ogg': 'Ogg',
    'oga': 'Ogg',
    'ogv': 'Ogg',
    'opus': 'Opus',
    'webm': 'WebM',
    'mkv': 'MKV',
    'mka': 'MKV',
    'avi': 'AVI',
  };

  /// The format's name ("WebM") when a file of [mimeType], or named
  /// [fileName], cannot play on an iPhone; null when it can or nothing says.
  ///
  /// A specific audio or video type the server sends wins over the name (a
  /// `video/mp4` file called "clip.mkv" is an MP4); the name only decides when
  /// the type is missing or generic (`application/octet-stream`).
  static String? unplayableFormat({String? mimeType, String? fileName}) {
    final mime = mimeType?.split(';').first.trim().toLowerCase() ?? '';
    final byMime = _byMime[mime];
    if (byMime != null) return byMime;
    if (mime.startsWith('audio/') || mime.startsWith('video/')) return null;
    final name = fileName?.trim().toLowerCase() ?? '';
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    return _byExtension[name.substring(dot + 1)];
  }

  /// Shown on the Downloads card instead of the Download button.
  static String refusal(String format) =>
      "iPhone can't play $format files, so this link can't be saved here. "
      'Look for an MP3, M4A or MP4 link instead.';

  /// Shown under a download the engine refused for [errorCode].
  static const String refusedAfterDownload =
      "iPhone can't play this kind of file (such as WebM, MKV or Ogg), so it was not saved. "
      'Look for an MP3, M4A or MP4 link instead.';
}
