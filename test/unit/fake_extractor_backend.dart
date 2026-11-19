import 'dart:async';
import 'dart:io';
import 'package:mediahub/personal/extractor_backend.dart';

/// Scriptable stand-in for the yt-dlp backend (no platform channel needed).
class FakeExtractorBackend implements ExtractorBackend {
  bool initialized = false;
  String currentVersion = '2026.11.01';
  bool simulateError = false;
  String errorCode = 'LOGIN_REQUIRED';
  String? errorDetail;

  /// Emit the yt-dlp merge line once the "download" finished.
  bool emitMergeLine = false;

  /// When set, [download] waits on it (completed with an error by [cancel]).
  Completer<void>? blockDownload;

  /// Overrides the extension of the file [download] returns (for example
  /// 'mp4.part' to hand back a yt-dlp work file).
  String? outputExtension;

  /// Overrides the content of the returned file (default: 2048 x 0x01).
  List<int>? outputBytes;

  /// What the phone "found" in the returned file (null: could not tell).
  bool? outputHasVideo;

  /// The video height the phone "read" from the returned file (null: none).
  int? outputHeight;

  /// Scripted answers for the next [download] calls, in order: an error to
  /// throw, or null for a normal download. Used before [simulateError].
  final List<ExtractorException?> downloadErrors = [];

  final List<String> cancelled = [];
  final List<Map<String, Object?>> downloadCalls = [];

  @override
  Future<bool> init() async {
    initialized = true;
    return true;
  }

  @override
  Future<String> getVersion() async => currentVersion;

  /// How often [update] ran.
  int updateCalls = 0;

  @override
  Future<String> update() async {
    updateCalls++;
    currentVersion = '2026.11.02';
    return 'DONE';
  }

  /// What [isMeteredNetwork] answers.
  bool? metered;

  @override
  Future<bool?> isMeteredNetwork() async => metered;

  /// Request ids passed to [cancelInfo], in order.
  final List<String> cancelledInfo = [];
  int resetCalls = 0;

  @override
  Future<void> resetToBundled() async {
    resetCalls++;
    currentVersion = '2025.10.22';
  }

  @override
  Future<void> cancelInfo(String requestId) async {
    cancelledInfo.add(requestId);
  }

  @override
  Future<ExtractorMetadata> getInfo(String url, {String? requestId}) async {
    if (simulateError) {
      throw const ExtractorException('EXTRACTION_FAILED', 'Failed to extract info');
    }
    return sampleMetadata();
  }

  static ExtractorMetadata sampleMetadata() {
    return const ExtractorMetadata(
      id: 'test_vid_1',
      title: 'Sample Test Video',
      uploader: 'Test Author',
      durationSec: 120,
      thumbnailUrl: '',
      formats: [
        ExtractorFormat(
          formatId: '137',
          ext: 'mp4',
          formatNote: '1080p',
          hasVideo: true,
          hasAudio: false,
          height: 1080,
          width: 1920,
          filesize: 15000000,
          tbr: 4000,
          vcodec: 'avc1',
        ),
        ExtractorFormat(
          formatId: '136',
          ext: 'mp4',
          formatNote: '720p',
          hasVideo: true,
          hasAudio: false,
          height: 720,
          width: 1280,
          filesize: 9000000,
          tbr: 2000,
          vcodec: 'avc1',
        ),
        ExtractorFormat(
          formatId: '140',
          ext: 'm4a',
          formatNote: 'medium',
          hasVideo: false,
          hasAudio: true,
          height: 0,
          width: 0,
          filesize: 3000000,
          abr: 128,
          acodec: 'mp4a',
        ),
        ExtractorFormat(
          formatId: '18',
          ext: 'mp4',
          formatNote: '360p',
          hasVideo: true,
          hasAudio: true,
          height: 360,
          width: 640,
          filesize: 8000000,
          tbr: 500,
          vcodec: 'avc1',
          acodec: 'mp4a',
        ),
      ],
    );
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
    void Function(double progress, int eta)? onProgress,
    void Function(String line)? onLine,
  }) async {
    downloadCalls.add({
      'taskId': taskId,
      'url': url,
      'formatSelector': formatSelector,
      'formatSort': formatSort,
      'extractorArgs': extractorArgs,
      'audioFormat': audioFormat,
    });
    if (downloadErrors.isNotEmpty) {
      final scripted = downloadErrors.removeAt(0);
      if (scripted != null) throw scripted;
    } else if (simulateError) {
      throw ExtractorException(errorCode, 'simulated failure', details: errorDetail);
    }
    onLine?.call('[download]  50.0% of ~ 10.00MiB at 1.00MiB/s ETA 00:05');
    onProgress?.call(50.0, 5);
    final gate = blockDownload;
    if (gate != null) {
      await gate.future;
    }
    onProgress?.call(100.0, 0);
    if (emitMergeLine) onLine?.call('[Merger] Merging formats into "x.mp4"');

    final selector = formatSelector ?? '';
    final audioSelector = selector.startsWith('bestaudio') || selector.startsWith('ba');
    final ext = outputExtension ?? audioFormat ?? (audioSelector ? 'm4a' : 'mp4');
    final file = File('$outDir/$taskId.$ext');
    await file.create(recursive: true);
    await file.writeAsBytes(outputBytes ?? List<int>.filled(2048, 1));
    return ExtractorDownloadResult(filePath: file.path, hasVideo: outputHasVideo, height: outputHeight);
  }

  @override
  Future<bool> cancel(String taskId) async {
    cancelled.add(taskId);
    final gate = blockDownload;
    if (gate != null && !gate.isCompleted) {
      gate.completeError(const ExtractorException('CANCELLED', 'cancelled'));
    }
    return true;
  }
}
