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

  static String _generateFallback(String ext) {
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final cleanExt = ext.isNotEmpty ? (ext.startsWith('.') ? ext : '.$ext') : '';
    return 'download_$rand$cleanExt';
  }
}
