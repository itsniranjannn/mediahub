import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/diagnostics.log');
      _logFile = file;
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          _buffer.add(line);
          if (_buffer.length > maxLines) {
            _buffer.removeFirst();
          }
        }
      }
      _initialized = true;
      _updateNotifier();
    } catch (e) {
      debugPrint('[Diagnostics] Init error: $e');
    }
  }

  void logEvent(String eventName, [Map<String, dynamic>? details]) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    String entry = '[$timestamp] $eventName';
    if (details != null && details.isNotEmpty) {
      final sanitized = details.map((k, v) {
        final str = v.toString();
        // Redact only genuine URLs, file paths, and media file extensions (not caller tokens or names)
        if (str.startsWith('http://') ||
            str.startsWith('https://') ||
            str.startsWith('file://') ||
            str.startsWith('/storage/') ||
            str.contains(r'C:\') ||
            str.endsWith('.mp3') ||
            str.endsWith('.mp4')) {
          return MapEntry(k, '<sanitized>');
        }
        return MapEntry(k, v);
      });
      entry += ' ${jsonEncode(sanitized)}';
    }

    _buffer.add(entry);
    if (_buffer.length > maxLines) {
      _buffer.removeFirst();
    }
    _updateNotifier();
    _schedulePersist();
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
