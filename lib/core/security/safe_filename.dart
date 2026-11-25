// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:convert';
import 'dart:math';

// Grapheme clusters (re-exported by Flutter; no extra dependency).
import 'package:flutter/widgets.dart' show StringCharacters;

class SafeFilename {
  SafeFilename._();

  static const int maxFilenameLength = 120;

  /// Android (ext4, f2fs) and iOS (APFS) refuse a file name longer than 255
  /// bytes of UTF-8. A Devanagari letter takes 3 bytes, so 120 characters
  /// of a Nepali title are 360 bytes: the name must be measured in bytes.
  static const int maxFilenameBytes = 255;

  /// Bytes the base name (without extension) may take. The rest of the 255
  /// leaves room for the extension and a " (n)" duplicate counter.
  static const int maxBaseNameBytes = 200;

  /// Room kept for the " (n)" counter of a duplicate name.
  static const int _counterReserve = 12;

  static int utf8Length(String s) => utf8.encode(s).length;

  /// The longest start of [s] that fits [maxBytes] of UTF-8 and [maxUnits]
  /// UTF-16 code units, cut between whole characters (graphemes): never in
  /// the middle of a Devanagari conjunct, an accented letter or an emoji.
  static String fitWithin(String s, {required int maxBytes, int? maxUnits}) {
    final units = maxUnits ?? s.length;
    if (s.length <= units && utf8Length(s) <= maxBytes) return s;
    final out = StringBuffer();
    var usedUnits = 0;
    var usedBytes = 0;
    for (final g in s.characters) {
      final b = utf8Length(g);
      if (usedUnits + g.length > units || usedBytes + b > maxBytes) break;
      out.write(g);
      usedUnits += g.length;
      usedBytes += b;
    }
    return out.toString();
  }

  static String _trimEnd(String s) => s.replaceAll(RegExp(r'[\. ]+$'), '');

  /// "[baseName] ([n])[extension]" for the n-th duplicate, with the base
  /// shortened (on a character boundary) so the whole name stays within
  /// [maxFilenameBytes]. [extension] includes its dot, or is empty.
  static String numbered(String baseName, int n, String extension) {
    final counter = ' ($n)';
    final budget = maxFilenameBytes - utf8Length(counter) - utf8Length(extension);
    var base = fitWithin(baseName, maxBytes: budget < 1 ? 1 : budget);
    base = _trimEnd(base);
    if (base.isEmpty) base = 'download';
    return '$base$counter$extension';
  }

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
  /// - Limits length to 120 characters while preserving extension, and the
  ///   base name to [maxBaseNameBytes] bytes of UTF-8 (the whole name within
  ///   [maxFilenameBytes]), cut between whole characters
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

    // 7. Enforce max length (120 chars, and the byte budget) keeping the extension
    final maxBaseLength = maxFilenameLength - extension.length;
    final extensionBytes = utf8Length(extension);
    var maxBaseBytes = maxFilenameBytes - _counterReserve - extensionBytes;
    if (maxBaseBytes > maxBaseNameBytes) maxBaseBytes = maxBaseNameBytes;
    if (maxBaseLength <= 0 || maxBaseBytes <= 0) {
      // Very long extension edge case: too long to keep as it is.
      final keep = extension.isNotEmpty && extensionBytes <= 32;
      return _generateFallback(keep ? extension : defaultExtension);
    }

    if (baseName.length > maxBaseLength || utf8Length(baseName) > maxBaseBytes) {
      baseName = fitWithin(baseName, maxBytes: maxBaseBytes, maxUnits: maxBaseLength);
      // Clean any trailing spaces or dots introduced by truncation
      baseName = _trimEnd(baseName);
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
