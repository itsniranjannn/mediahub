import 'dart:io';
import 'package:flutter/services.dart';

/// Configuration flag for personal tools.
/// Set to false to completely compile-out or disable personal tools.
const bool kPersonalToolsEnabled = true;

/// Format representation returned by extractor.
class ExtractorFormat {
  final String formatId;
  final String ext;
  final String formatNote;
  final bool hasVideo;
  final bool hasAudio;
  final int height;
  final int width;
  final int filesize;

  const ExtractorFormat({
    required this.formatId,
    required this.ext,
    required this.formatNote,
    required this.hasVideo,
    required this.hasAudio,
    required this.height,
    required this.width,
    required this.filesize,
  });

  factory ExtractorFormat.fromMap(Map<dynamic, dynamic> map) {
    return ExtractorFormat(
      formatId: map['formatId']?.toString() ?? '',
      ext: map['ext']?.toString() ?? '',
      formatNote: map['formatNote']?.toString() ?? '',
      hasVideo: map['hasVideo'] == true,
      hasAudio: map['hasAudio'] == true,
      height: (map['height'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      filesize: (map['filesize'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isAudioOnly => hasAudio && !hasVideo;
  bool get isVideo => hasVideo;
}

/// Metadata extracted for a public media URL.
class ExtractorMetadata {
  final String id;
  final String title;
  final String uploader;
  final int durationSec;
  final String thumbnailUrl;
  final List<ExtractorFormat> formats;

  const ExtractorMetadata({
    required this.id,
    required this.title,
    required this.uploader,
    required this.durationSec,
    required this.thumbnailUrl,
    required this.formats,
  });

  factory ExtractorMetadata.fromMap(Map<dynamic, dynamic> map) {
    final rawFormats = map['formats'] as List<dynamic>? ?? [];
    return ExtractorMetadata(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Media',
      uploader: map['uploader']?.toString() ?? '',
      durationSec: (map['duration'] as num?)?.toInt() ?? 0,
      thumbnailUrl: map['thumbnail']?.toString() ?? '',
      formats: rawFormats
          .map((f) => ExtractorFormat.fromMap(f as Map<dynamic, dynamic>))
          .toList(),
    );
  }
}

/// Abstract contract for extractor backends.
abstract class ExtractorBackend {
  Future<bool> init();
  Future<String> getVersion();
  Future<String> update();
  Future<ExtractorMetadata> getInfo(String url);
  Future<String> download({
    required String taskId,
    required String url,
    required String outDir,
    String? formatSelector,
    void Function(double progress, int eta)? onProgress,
  });
  Future<bool> cancel(String taskId);
}

/// Android native implementation using the `mediahub/extractor` MethodChannel.
class AndroidExtractorBackend implements ExtractorBackend {
  static const MethodChannel _channel = MethodChannel('mediahub/extractor');
  final Map<String, void Function(double progress, int eta)> _progressListeners = {};

  AndroidExtractorBackend() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          final taskId = args['taskId']?.toString();
          final progress = (args['progress'] as num?)?.toDouble() ?? 0.0;
          final eta = (args['eta'] as num?)?.toInt() ?? 0;
          if (taskId != null && _progressListeners.containsKey(taskId)) {
            _progressListeners[taskId]!(progress, eta);
          }
        }
      }
    });
  }

  @override
  Future<bool> init() async {
    if (!Platform.isAndroid || !kPersonalToolsEnabled) {
      throw UnsupportedError('Extractor backend is only supported on Android with personal tools enabled');
    }
    try {
      final res = await _channel.invokeMethod<bool>('init');
      return res ?? false;
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Init failed');
    }
  }

  @override
  Future<String> getVersion() async {
    if (!Platform.isAndroid || !kPersonalToolsEnabled) return 'N/A';
    try {
      final res = await _channel.invokeMethod<String>('version');
      return res ?? 'Unknown';
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Could not get version');
    }
  }

  @override
  Future<String> update() async {
    if (!Platform.isAndroid || !kPersonalToolsEnabled) {
      throw UnsupportedError('Update only supported on Android');
    }
    try {
      final res = await _channel.invokeMethod<String>('update');
      return res ?? 'DONE';
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Update failed');
    }
  }

  @override
  Future<ExtractorMetadata> getInfo(String url) async {
    if (!Platform.isAndroid || !kPersonalToolsEnabled) {
      throw UnsupportedError('Extractor is only supported on Android');
    }
    try {
      final res = await _channel.invokeMapMethod<dynamic, dynamic>('getInfo', {'url': url});
      if (res == null) throw ExtractorException('EMPTY_METADATA', 'No info returned');
      return ExtractorMetadata.fromMap(res);
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Failed to inspect link');
    }
  }

  @override
  Future<String> download({
    required String taskId,
    required String url,
    required String outDir,
    String? formatSelector,
    void Function(double progress, int eta)? onProgress,
  }) async {
    if (!Platform.isAndroid || !kPersonalToolsEnabled) {
      throw UnsupportedError('Extractor is only supported on Android');
    }
    if (onProgress != null) {
      _progressListeners[taskId] = onProgress;
    }
    try {
      final res = await _channel.invokeMapMethod<dynamic, dynamic>('download', {
        'taskId': taskId,
        'url': url,
        'formatSelector': formatSelector,
        'outDir': outDir,
      });
      final filePath = res?['filePath']?.toString() ?? '';
      return filePath;
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Download failed');
    } finally {
      _progressListeners.remove(taskId);
    }
  }

  @override
  Future<bool> cancel(String taskId) async {
    _progressListeners.remove(taskId);
    if (!Platform.isAndroid || !kPersonalToolsEnabled) return false;
    try {
      final res = await _channel.invokeMethod<bool>('cancel', {'taskId': taskId});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Typed exception for extractor errors.
class ExtractorException implements Exception {
  final String code;
  final String message;

  const ExtractorException(this.code, this.message);

  @override
  String toString() => 'ExtractorException($code): $message';
}

