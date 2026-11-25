// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../storage/app_private_dir.dart';

class DiagnosticsService {
  static final DiagnosticsService instance = DiagnosticsService._();
  DiagnosticsService._();

  static const int maxLines = 300;
  final DoubleLinkedQueue<String> _buffer = DoubleLinkedQueue<String>();
  File? _logFile;
  bool _initialized = false;
  Timer? _debounceTimer;
  bool _isWriting = false;
  bool _hasPendingWrite = false;

  final ValueNotifier<List<String>> logsNotifier = ValueNotifier<List<String>>([]);

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await appPrivateDataDir();
      await initWithFile(File('${dir.path}/diagnostics.log'));
    } catch (e) {
      debugPrint('[Diagnostics] Init error: $e');
    }
  }

  /// Loads the log from [file] and keeps saving there ([init] passes the
  /// app's `diagnostics.log`; tests pass a temp file).
  @visibleForTesting
  Future<void> initWithFile(File file) async {
    _logFile = file;
    var redactedOldLines = false;
    if (await file.exists()) {
      final lines = await file.readAsLines();
      for (final line in lines) {
        // Lines written by older versions were only redacted when a value
        // started with a link or path; scrub them again on the way in.
        final clean = redact(line);
        if (clean != line) redactedOldLines = true;
        _buffer.add(clean);
        if (_buffer.length > maxLines) {
          _buffer.removeFirst();
        }
      }
    }
    _initialized = true;
    _updateNotifier();
    if (redactedOldLines) {
      // The file itself still holds the old text: rewrite it once from the
      // scrubbed buffer now, rather than whenever the next event is logged.
      // Awaited: at most [maxLines] short lines, and only on the first start
      // after an upgrade, so the old text is gone before the app runs.
      _hasPendingWrite = true;
      await flush();
    }
  }

  void logEvent(String eventName, [Map<String, dynamic>? details]) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    String entry = '[$timestamp] $eventName';
    if (details != null && details.isNotEmpty) {
      final sanitized = details.map((k, v) => MapEntry(k, _sanitizeValue(v)));
      entry += ' ${jsonEncode(sanitized)}';
    }

    _buffer.add(entry);
    if (_buffer.length > maxLines) {
      _buffer.removeFirst();
    }
    _updateNotifier();
    _schedulePersist();
  }

  // ---------------------------------------------------------------------------
  // Redaction
  //
  // Logged values often embed links or file paths inside longer text (error
  // messages, "Failed for https://..."), so redaction looks for them anywhere
  // in the text, not only at the start. Each kind of secret is replaced by a
  // short placeholder; the rest of the text (error codes, host names) is kept.
  // ---------------------------------------------------------------------------

  /// Patterns that start something private, with the placeholder that replaces
  /// it. Order matters: whole links first, so a `file:///storage/...` link is
  /// one `<file>` rather than `file://<path>`.
  static const List<(String, String)> _privatePrefixes = [
    (r'https?://', '<url>'),
    (r'file://', '<file>'),
    // Android document/media links can embed folder and file names.
    (r'content://', '<file>'),
    // Android and iOS storage locations (app data, shared storage, SD cards).
    (r'/(?:data|storage|sdcard|mnt|private/var|var/mobile)/', '<path>'),
    // Windows drive paths (C:\..., D:/...), not "content:/" or "https:/".
    (r'(?<![A-Za-z0-9])[A-Za-z]:[\\/]', '<path>'),
  ];

  /// Media file extensions; a path ending in one names what was played.
  static const String _mediaExtensions =
      r'(?:mp3|mp4|m4a|aac|flac|wav|ogg|opus|webm|mkv|mov|3gp)';

  /// One character of a link or path that is neither a double quote nor a
  /// backslash escaping one (`\"`), so redacting an already-written JSON log
  /// line in [init] keeps it valid JSON.
  static const String _noQuote = r'(?:[^"\\\r\n]|\\(?!"))';
  static const String _noSpaceOrQuote = r'(?:[^\s"\\]|\\(?!"))';

  /// For each prefix: a match anywhere in the text, tried in this order:
  /// 1. single-quoted ('...', as Dart's `FileSystemException` prints
  ///    `path = '...'`): runs to the *last* closing quote that is followed by
  ///    a space, punctuation or the end, so apostrophes inside a name
  ///    ("Don't Stop.mp3", "Rock 'n' Roll") are hidden too. It never crosses a
  ///    double quote, so fields of an old JSON line are never merged;
  /// 2. double-quoted ("..."): runs to the first closing quote;
  /// 3. unquoted, up to the last media file name on the line, so names with
  ///    spaces ("/storage/.../Private Song.mp3 (ENOENT)") are hidden;
  /// 4. unquoted otherwise: runs to the next space or double quote.
  /// Hiding a little too much (two paths on one line become one placeholder)
  /// is fine; leaking part of a name is not.
  static final List<(RegExp, String)> _anywhereRules = [
    for (final (prefix, placeholder) in _privatePrefixes)
      (
        RegExp(
          "(?<=')(?:$prefix)[^\"\\r\\n]*(?='(?:[\\s,;)\\]}\"]|\$))"
          '|(?<=")(?:$prefix)$_noQuote*'
          '|(?:$prefix)[^"\\r\\n]*\\.$_mediaExtensions\\b$_noSpaceOrQuote*'
          '|(?:$prefix)$_noSpaceOrQuote*',
          caseSensitive: false,
        ),
        placeholder,
      ),
  ];

  /// For each prefix: the value *starts* with it, so the whole value is the
  /// link or path (it may contain spaces, e.g. ".../My Music/song.mp3").
  static final List<(RegExp, String)> _wholeValueRules = [
    for (final (prefix, placeholder) in _privatePrefixes)
      (RegExp('^\\s*(?:$prefix)', caseSensitive: false), placeholder),
  ];

  /// A bare media file name ("Song title.mp3") still names what was played.
  static final RegExp _mediaFileName = RegExp(
    '\\.$_mediaExtensions\\s*\$',
    caseSensitive: false,
  );

  /// Replaces every link (`<url>`, `<file>`) and storage path (`<path>`)
  /// found anywhere in [text]. Everything else is returned unchanged.
  static String redact(String text) {
    var result = text;
    for (final (pattern, placeholder) in _anywhereRules) {
      result = result.replaceAll(pattern, placeholder);
    }
    return result;
  }

  /// Redacts one logged value. Strings (and anything that is not a plain JSON
  /// number/bool/null) are scrubbed with [redact]; lists and maps are scrubbed
  /// item by item so the log keeps its JSON shape.
  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is List) return value.map(_sanitizeValue).toList();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _sanitizeValue(v)));
    }
    final text = value.toString();
    for (final (pattern, placeholder) in _wholeValueRules) {
      if (pattern.hasMatch(text)) return placeholder;
    }
    final redacted = redact(text);
    if (_mediaFileName.hasMatch(redacted)) return '<sanitized>';
    return redacted;
  }

  void _updateNotifier() {
    logsNotifier.value = _buffer.toList();
  }

  // Optional hook for tests to disable background debounce timer
  static bool enableDebounce = true;

  void _schedulePersist() {
    _hasPendingWrite = true;
    _debounceTimer?.cancel();
    if (!enableDebounce) {
      flush();
      return;
    }
    _debounceTimer = Timer(const Duration(seconds: 3), () {
      flush();
    });
  }

  Future<void> flush() async {
    _debounceTimer?.cancel();
    final file = _logFile;
    if (file == null || !_hasPendingWrite || _isWriting) return;
    _isWriting = true;
    _hasPendingWrite = false;
    try {
      final content = _buffer.join('\n');
      await file.writeAsString(content, flush: true);
    } catch (_) {
    } finally {
      _isWriting = false;
      if (_hasPendingWrite) {
        _schedulePersist();
      }
    }
  }

  Future<void> clear() async {
    _debounceTimer?.cancel();
    _buffer.clear();
    _updateNotifier();
    final file = _logFile;
    if (file != null && await file.exists()) {
      try {
        await file.writeAsString('', flush: true);
      } catch (_) {}
    }
  }

  List<String> get logs => _buffer.toList();
}
