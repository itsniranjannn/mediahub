// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/services.dart';
import '../core/platform_info.dart';

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
  final double tbr;
  final double abr;
  final double fps;
  final String vcodec;
  final String acodec;

  /// The direct https link to this format, when the extractor gave one.
  final String? url;

  const ExtractorFormat({
    required this.formatId,
    required this.ext,
    required this.formatNote,
    required this.hasVideo,
    required this.hasAudio,
    required this.height,
    required this.width,
    required this.filesize,
    this.tbr = 0,
    this.abr = 0,
    this.fps = 0,
    this.vcodec = '',
    this.acodec = '',
    this.url,
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
      tbr: (map['tbr'] as num?)?.toDouble() ?? 0,
      abr: (map['abr'] as num?)?.toDouble() ?? 0,
      fps: (map['fps'] as num?)?.toDouble() ?? 0,
      vcodec: map['vcodec']?.toString() ?? '',
      acodec: map['acodec']?.toString() ?? '',
      url: map['url'] is String && (map['url'] as String).startsWith('https://') ? map['url'] as String : null,
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

  /// yt-dlp `--extractor-args` value that produced [formats] (e.g. a YouTube
  /// player client override). Must be passed back unchanged when downloading.
  final String? extractorArgs;

  const ExtractorMetadata({
    required this.id,
    required this.title,
    required this.uploader,
    required this.durationSec,
    required this.thumbnailUrl,
    required this.formats,
    this.extractorArgs,
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
      extractorArgs: map['extractorArgs']?.toString(),
    );
  }
}

/// What a finished yt-dlp download left behind.
class ExtractorDownloadResult {
  const ExtractorDownloadResult({required this.filePath, this.hasVideo, this.height});

  /// The finished file (empty when yt-dlp reported none).
  final String filePath;

  /// True when the file holds a picture track, false for sound only, null
  /// when the phone could not tell. A "video" link can turn out to be audio
  /// only (and then belongs in Music).
  final bool? hasVideo;

  /// The video's height in pixels, as the phone read it from the file (null
  /// for sound only, or when it could not tell). When the chosen quality was
  /// missing, yt-dlp saves the nearest one, and this says which.
  final int? height;
}

/// Abstract contract for extractor backends.
abstract class ExtractorBackend {
  Future<bool> init();
  Future<String> getVersion();
  Future<String> update();

  /// Goes back to the yt-dlp copy shipped inside the app (undoes [update]).
  Future<void> resetToBundled();

  /// True on metered data (mobile data, a metered hotspot), false on Wi-Fi,
  /// null when the phone cannot tell. The quiet weekly update skips metered data.
  Future<bool?> isMeteredNetwork();

  /// Reads the qualities of [url]. Pass a [requestId] (letters, digits, `_`, `-`)
  /// to be able to stop the lookup with [cancelInfo].
  Future<ExtractorMetadata> getInfo(String url, {String? requestId});

  /// Stops a running [getInfo] started with the same [requestId]. Best effort.
  Future<void> cancelInfo(String requestId);

  /// Downloads [url] with yt-dlp format selector [formatSelector] and format
  /// sort [formatSort] (yt-dlp `-S`, which of the matching formats wins).
  Future<ExtractorDownloadResult> download({
    required String taskId,
    required String url,
    required String outDir,
    String? formatSelector,
    String? formatSort,
    String? extractorArgs,
    String? audioFormat,
    String? audioQuality,
    void Function(double progress, int eta)? onProgress,
    void Function(String line)? onLine,
  });
  Future<bool> cancel(String taskId);
}

/// Android native implementation using the `mediahub/extractor` MethodChannel.
class AndroidExtractorBackend implements ExtractorBackend {
  static const MethodChannel _channel = MethodChannel('mediahub/extractor');
  final Map<String, void Function(double progress, int eta, String line)> _progressListeners = {};
  bool _handlerRegistered = false;

  // The channel handler is registered lazily (not in the constructor) so the
  // backend can be created before the Flutter binding exists, e.g. in unit tests.
  void _ensureHandler() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          final taskId = args['taskId']?.toString();
          final progress = (args['progress'] as num?)?.toDouble() ?? 0.0;
          final eta = (args['eta'] as num?)?.toInt() ?? 0;
          final line = args['line']?.toString() ?? '';
          if (taskId != null && _progressListeners.containsKey(taskId)) {
            _progressListeners[taskId]!(progress, eta, line);
          }
        }
      }
    });
  }

  @override
  Future<bool> init() async {
    if (!PlatformInfo.isAndroid || !kPersonalToolsEnabled) {
      throw UnsupportedError('Extractor backend is only supported on Android with personal tools enabled');
    }
    _ensureHandler();
    try {
      final res = await _channel.invokeMethod<bool>('init');
      return res ?? false;
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Init failed');
    }
  }

  @override
  Future<String> getVersion() async {
    if (!PlatformInfo.isAndroid || !kPersonalToolsEnabled) return 'N/A';
    try {
      final res = await _channel.invokeMethod<String>('version');
      return res ?? 'Unknown';
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Could not get version');
    }
  }

  @override
  Future<String> update() async {
    if (!PlatformInfo.isAndroid || !kPersonalToolsEnabled) {
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
  Future<void> resetToBundled() async {
    if (!PlatformInfo.isAndroid || !kPersonalToolsEnabled) {
      throw UnsupportedError('Reset only supported on Android');
    }
    try {
      await _channel.invokeMethod<bool>('resetToBundled');
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Reset failed');
    }
  }

  @override
  Future<bool?> isMeteredNetwork() async {
    if (!PlatformInfo.isAndroid || !kPersonalToolsEnabled) return null;
    try {
      return await _channel.invokeMethod<bool>('isMetered');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancelInfo(String requestId) async {
    if (!PlatformInfo.isAndroid || !kPersonalToolsEnabled) return;
    try {
      await _channel.invokeMethod<bool>('cancelInfo', {'requestId': requestId});
    } catch (_) {
      // Best effort: the native watchdog still ends the lookup after 85 s.
    }
  }

  @override
  Future<ExtractorMetadata> getInfo(String url, {String? requestId}) async {
    if (!PlatformInfo.isAndroid || !kPersonalToolsEnabled) {
      throw UnsupportedError('Extractor is only supported on Android');
    }
    try {
      final res = await _channel.invokeMapMethod<dynamic, dynamic>('getInfo', {
        'url': url,
        'requestId': ?requestId,
      });
      if (res == null) throw ExtractorException('EMPTY_METADATA', 'No info returned');
      return ExtractorMetadata.fromMap(res);
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Failed to inspect link', details: e.details?.toString());
    }
  }

  @override
  Future<ExtractorDownloadResult> download({
    required String taskId,
    required String url,
    required String outDir,
    String? formatSelector,
    String? formatSort,
    String? extractorArgs,
    String? audioFormat,
    String? audioQuality,
    void Function(double progress, int eta)? onProgress,
    void Function(String line)? onLine,
  }) async {
    if (!PlatformInfo.isAndroid || !kPersonalToolsEnabled) {
      throw UnsupportedError('Extractor is only supported on Android');
    }
    _ensureHandler();
    if (onProgress != null || onLine != null) {
      _progressListeners[taskId] = (progress, eta, line) {
        onProgress?.call(progress, eta);
        if (line.isNotEmpty) onLine?.call(line);
      };
    }
    try {
      final res = await _channel.invokeMapMethod<dynamic, dynamic>('download', {
        'taskId': taskId,
        'url': url,
        'formatSelector': formatSelector,
        'formatSort': formatSort,
        'outDir': outDir,
        'extractorArgs': extractorArgs,
        'audioFormat': audioFormat,
        'audioQuality': audioQuality,
      });
      final hasVideo = res?['hasVideo'];
      final height = res?['height'];
      return ExtractorDownloadResult(
        filePath: res?['filePath']?.toString() ?? '',
        hasVideo: hasVideo is bool ? hasVideo : null,
        height: height is int && height > 0 ? height : null,
      );
    } on PlatformException catch (e) {
      throw ExtractorException(e.code, e.message ?? 'Download failed', details: e.details?.toString());
    } finally {
      _progressListeners.remove(taskId);
    }
  }

  @override
  Future<bool> cancel(String taskId) async {
    _progressListeners.remove(taskId);
    if (!PlatformInfo.isAndroid || !kPersonalToolsEnabled) return false;
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
  /// Machine-readable reason from the native side, e.g. `HOST_NOT_ALLOWED`,
  /// `LOGIN_REQUIRED`, `NETWORK_ERROR`, `PLAYLIST_NOT_SUPPORTED` (playlist or
  /// channel link), `LIVE_NOT_SUPPORTED` (live stream), `INFO_TIMEOUT` (the
  /// native watchdog stopped a quality lookup that took too long),
  /// `FORMAT_UNAVAILABLE`, `BOT_CHECK`, `AGE_RESTRICTED`, `UNAVAILABLE` or
  /// `NO_MEDIA`. `ExtractorErrors` turns these into the text shown to the user.
  final String code;
  final String message;

  /// Short sanitized reason from yt-dlp (no URLs / paths), for display and logs.
  final String? details;

  const ExtractorException(this.code, this.message, {this.details});

  @override
  String toString() => 'ExtractorException($code): $message${details == null ? '' : ' [$details]'}';
}

