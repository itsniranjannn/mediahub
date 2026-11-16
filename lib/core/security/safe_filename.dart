import 'dart:math';

class SafeFilename {
  SafeFilename._();

  static const int maxFilenameLength = 120;

  static const Set<String> _windowsReservedNames = {
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// Sanitizes [rawName] into a safe filename:
  /// - Strips path separators ('/', '\')
  /// - Strips '..' traversal sequences
  /// - Strips control characters (ASCII 0..31, 127) and illegal chars (<, >, :, ", |, ?, *)
  /// - Strips leading dots (hidden files on Unix)
  /// - Strips trailing spaces and dots (problematic on Windows)
  /// - Checks against reserved Windows device names
  /// - Limits length to 120 characters while preserving extension
  /// - Falls back to 'download_' + random suffix if the result is empty or invalid
  static String sanitize(String? rawName, {String defaultExtension = ''}) {
    if (rawName == null || rawName.trim().isEmpty) {
      return _generateFallback(defaultExtension);
    }

    String name = rawName.trim();

    // 1. Strip path components if a full path was passed
    name = name.split(RegExp(r'[/\\]')).last;

    // 2. Remove illegal/control characters and ..
    name = name.replaceAll('..', '');
    name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"/\\|?*]'), '');

    // 3. Remove leading dots
    name = name.replaceFirst(RegExp(r'^\.+'), '');

    // 4. Remove trailing dots and spaces
    name = name.replaceAll(RegExp(r'[\. ]+$'), '');

    if (name.isEmpty) {
      return _generateFallback(defaultExtension);
    }

    // 5. Separate basename and extension
    String baseName = name;
    String extension = '';
    final lastDot = name.lastIndexOf('.');
    if (lastDot > 0 && lastDot < name.length - 1) {
      baseName = name.substring(0, lastDot).trimRight();
      extension = name.substring(lastDot); // includes dot
    } else if (defaultExtension.isNotEmpty) {
      extension = defaultExtension.startsWith('.') ? defaultExtension : '.$defaultExtension';
    }

    // 6. Check reserved names (case-insensitive check on basename)
    if (_windowsReservedNames.contains(baseName.toUpperCase())) {
      baseName = '${baseName}_file';
    }

    // 7. Enforce max length (120 chars) keeping the extension
    final maxBaseLength = maxFilenameLength - extension.length;
    if (maxBaseLength <= 0) {
      // Very long extension edge case
      return _generateFallback(extension.isNotEmpty ? extension : defaultExtension);
    }

    if (baseName.length > maxBaseLength) {
      baseName = baseName.substring(0, maxBaseLength);
      // Clean any trailing spaces or dots introduced by truncation
      baseName = baseName.replaceAll(RegExp(r'[\. ]+$'), '');
    }

    if (baseName.isEmpty) {
      return _generateFallback(extension);
    }

    return '$baseName$extension';
  }

  /// Extensions the download code uses for its own work files: `<id>.part`
  /// (direct-link partial), `<id>.thumb` (cover image) and yt-dlp's `.part`,
  /// `.ytdl` and `.temp` files; `.tmp` is the usual scratch suffix for atomic
  /// writes. A finished library file must never carry one of these, or a
  /// cleanup pass could mistake it for garbage and delete it.
  static const Set<String> reservedExtensions = {'.part', '.thumb', '.ytdl', '.temp', '.tmp'};

  /// True when [name] ends in one of [reservedExtensions] (case-insensitive).
  static bool hasReservedExtension(String name) {
    final lastDot = name.lastIndexOf('.');
    if (lastDot < 0) return false;
    return reservedExtensions.contains(name.substring(lastDot).toLowerCase());
  }

  /// Makes [name] safe to use as a finished media file name.
  ///
  /// Returns `sanitize(name)` unchanged unless it ends in a reserved internal
  /// extension (see [reservedExtensions]). In that case every trailing
  /// reserved extension is removed and [mediaExtension] (for example the one
  /// matching the sniffed MIME type, with or without the dot) is used instead,
  /// without doubling it: with `mp3`, `song.part` -> `song.mp3` and
  /// `song.mp3.part` -> `song.mp3`. If [mediaExtension] is empty or itself
  /// reserved, `.bin` is used.
  static String finalMediaName(String name, {required String mediaExtension}) {
    var safe = sanitize(name);
    if (!hasReservedExtension(safe)) return safe;

    var ext = mediaExtension.trim().toLowerCase();
    if (ext.isNotEmpty && !ext.startsWith('.')) ext = '.$ext';
    if (ext.length < 2 || reservedExtensions.contains(ext)) ext = '.bin';

    while (hasReservedExtension(safe)) {
      safe = safe.substring(0, safe.lastIndexOf('.'));
    }
    safe = safe.replaceAll(RegExp(r'[\. ]+$'), '');
    if (safe.isEmpty) safe = 'download';
    if (safe.toLowerCase().endsWith(ext)) return sanitize(safe);
    return sanitize('$safe$ext');
  }

  static String _generateFallback(String ext) {
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final cleanExt = ext.isNotEmpty ? (ext.startsWith('.') ? ext : '.$ext') : '';
    return 'download_$rand$cleanExt';
  }
}
