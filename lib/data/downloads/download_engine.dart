import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'thumbnail_fetcher.dart';
import 'youtube_link.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/downloads/download_state_machine.dart';
import '../../core/downloads/media_sniffer.dart';
import '../../core/security/safe_filename.dart';
import '../../core/security/safe_http_client.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/download_state.dart';
import '../../domain/models/media_item.dart';
import '../database/app_database.dart';

typedef FreeSpaceProvider = Future<int> Function();

/// Size of the byte ranges a download from [url] is fetched in, or null to
/// fetch it in one response (resuming with a Range request after a break).
typedef RangeChunkPolicy = int? Function(Uri url);

class DownloadEngine {
  final AppDatabase _db;
  final SafeHttpClient _httpClient;

  /// The download folder. It may still be resolving when the engine is created
  /// (see `downloadEngineProvider`): every file operation awaits it, so a file
  /// is never written to any other place (there is no temp-dir fallback).
  final Future<Directory> _downloadDirFuture;
  final FreeSpaceProvider _freeSpaceProvider;
  final RangeChunkPolicy _rangeChunkBytes;

  /// The engine's own partial-file name: `<id>.part`, where the id is the
  /// millisecond timestamp the callers use as task id. The startup orphan sweep
  /// only ever considers names of exactly this shape.
  static final RegExp _partialFileName = RegExp(r'^(\d+)\.part$');

  static const int maxDownloadSizeBytes = 2 * 1024 * 1024 * 1024; // 2 GB

  /// Free space a download needs on top of its own size before it starts.
  static const int freeSpaceMarginBytes = 100 * 1024 * 1024;

  /// Range size for YouTube's media servers (the size yt-dlp uses too). They
  /// slow down or cut off one long response for a whole file, but serve
  /// back-to-back 10 MB ranges at full speed.
  static const int youtubeRangeChunkBytes = 10 * 1024 * 1024;

  static const MethodChannel _platformChannel = MethodChannel('mediahub/media_store');

  final StreamController<DownloadProgressUpdate> _progressController =
      StreamController<DownloadProgressUpdate>.broadcast();

  final Map<String, bool> _cancelledTasks = {};
  final Map<String, bool> _pausedTasks = {};
  final Map<String, Completer<void>> _activeTaskCompleters = {};
  final Map<String, Completer<void>> _activeAttemptCompleters = {};
  final Map<String, SafeStreamResponse> _activeStreamResponses = {};
  final Map<String, StreamSubscription<List<int>>> _activeSubscriptions = {};

  /// [downloadDir] is either the folder itself or a future of it (the app's
  /// documents folder resolves asynchronously at startup).
  DownloadEngine({
    required AppDatabase db,
    required SafeHttpClient httpClient,
    required FutureOr<Directory> downloadDir,
    FreeSpaceProvider? freeSpaceProvider,
    RangeChunkPolicy? rangeChunkBytes,
  })  : _db = db, // ignore: prefer_initializing_formals
        _httpClient = httpClient, // ignore: prefer_initializing_formals
        _downloadDirFuture = settleDirectory(downloadDir),
        _freeSpaceProvider = freeSpaceProvider ?? defaultFreeSpaceProvider,
        _rangeChunkBytes = rangeChunkBytes ?? defaultRangeChunkBytes;

  Stream<DownloadProgressUpdate> get progressStream => _progressController.stream;

  /// YouTube's media servers get [youtubeRangeChunkBytes] ranges; every other
  /// host is fetched in one response.
  static int? defaultRangeChunkBytes(Uri url) =>
      YoutubeLink.isYoutubeMediaHost(url.host) ? youtubeRangeChunkBytes : null;

  /// Wraps a folder (or a future of one) in a future that can be awaited any
  /// number of times. If it fails before anyone awaits it, the error is not
  /// reported as unhandled: every later `await` still receives it.
  static Future<Directory> settleDirectory(FutureOr<Directory> dir) {
    final future = Future<Directory>.value(dir);
    future.ignore();
    return future;
  }

  Future<Directory> _dir() => _downloadDirFuture;

  /// `<id>.part` in the download folder, or null when the folder could not be
  /// resolved (then nothing can have been written for this task either).
  Future<File?> _partFileOrNull(String id) async {
    try {
      final dir = await _dir();
      return File(p.join(dir.path, '$id.part'));
    } catch (_) {
      return null;
    }
  }

  /// Free bytes on the storage that holds the download folder. Shared with
  /// the web-link runner so both use the same check.
  static Future<int> defaultFreeSpaceProvider() async {
    try {
      final res = await _platformChannel.invokeMethod<int>('freeSpaceBytes');
      return res ?? (10 * 1024 * 1024 * 1024);
    } catch (_) {
      // Fallback for desktop / non-android or mock tests
      return 10 * 1024 * 1024 * 1024;
    }
  }

  /// Lets other runners (yt-dlp) feed the same progress stream the UI listens to.
  void publishProgress(DownloadProgressUpdate update) {
    if (!_progressController.isClosed) _progressController.add(update);
  }

  /// App startup recovery. Returns the ids of direct-link tasks that were
  /// interrupted and can be resumed (state `paused`).
  Future<List<String>> reconcileOnStartup() async {
    final recovered = <String>[];
    final downloadDir = await _dir();
    final activeDownloads = await (_db.select(_db.downloadsTable)
          ..where((tbl) =>
              tbl.engine.equals('http') &
              tbl.state.isIn([
                DownloadTaskState.preparing.name,
                DownloadTaskState.downloading.name,
                DownloadTaskState.finalizing.name,
              ])))
        .get();

    for (final dl in activeDownloads) {
      final currentState = DownloadTaskState.values.firstWhere(
        (e) => e.name == dl.state,
        orElse: () => DownloadTaskState.failed,
      );
      final partPath = p.join(downloadDir.path, '${dl.id}.part');
      final reconciled = DownloadStateMachine.reconcileStartupState(
        currentState: currentState,
        partFilePath: partPath,
        receivedBytes: dl.receivedBytes,
      );

      await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(dl.id))).write(
        DownloadsTableCompanion(
          state: Value(reconciled.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (reconciled == DownloadTaskState.paused) recovered.add(dl.id);
    }

    // Orphan .part cleanup: delete partial files that no unfinished task owns.
    // Only names of the engine's own shape (`<numeric id>.part`) are candidates,
    // and a file any row records as its finished file (`finalPath`) is never
    // touched: a completed download may legitimately have been saved as e.g.
    // "song.part" (or even "1700000000000.part") before finished names were
    // kept clear of internal extensions.
    try {
      if (downloadDir.existsSync()) {
        final allDownloads = await _db.select(_db.downloadsTable).get();
        final validPartIds = allDownloads
            .where((d) => d.state != DownloadTaskState.completed.name && d.state != DownloadTaskState.cancelled.name)
            .map((d) => d.id)
            .toSet();
        // Compared by file name: on iOS the app's absolute folder path changes
        // between installs, so a stored absolute path may no longer match.
        final finishedNames = allDownloads
            .map((d) => d.finalPath)
            .whereType<String>()
            .map((path) => p.basename(path).toLowerCase())
            .toSet();

        final entities = downloadDir.listSync();
        for (final entity in entities) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          final match = _partialFileName.firstMatch(name);
          if (match == null) continue;
          if (validPartIds.contains(match.group(1))) continue;
          if (finishedNames.contains(name.toLowerCase())) continue;
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return recovered;
  }

  /// Pause an in-flight or queued task
  Future<void> pause(String id) async {
    _pausedTasks[id] = true;
    _activeSubscriptions[id]?.cancel();
    _activeSubscriptions.remove(id);
    _activeStreamResponses[id]?.close();
    _activeStreamResponses.remove(id);
    if (_activeAttemptCompleters.containsKey(id)) {
      if (!_activeAttemptCompleters[id]!.isCompleted) {
        _activeAttemptCompleters[id]!.complete();
      }
      _activeAttemptCompleters.remove(id);
    }

    final row = await (_db.select(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (row != null && row.state != DownloadTaskState.paused.name && row.state != DownloadTaskState.completed.name) {
      // If server doesn't support Range, pause behaves as cancel-and-restart
      if (!row.supportsRange && row.receivedBytes > 0) {
        // Range not supported: reset to 0
        final partFile = await _partFileOrNull(id);
        if (partFile != null && partFile.existsSync()) {
          try {
            partFile.deleteSync();
          } catch (_) {}
        }
        await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).write(
          DownloadsTableCompanion(
            state: Value(DownloadTaskState.paused.name),
            receivedBytes: const Value(0),
            updatedAt: Value(DateTime.now()),
          ),
        );
        return;
      }

      await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).write(
        DownloadsTableCompanion(
          state: Value(DownloadTaskState.paused.name),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Cancel a task and delete .part
  Future<void> cancel(String id) async {
    _cancelledTasks[id] = true;
    _activeSubscriptions[id]?.cancel();
    _activeSubscriptions.remove(id);
    _activeStreamResponses[id]?.close();
    _activeStreamResponses.remove(id);
    if (_activeAttemptCompleters.containsKey(id)) {
      if (!_activeAttemptCompleters[id]!.isCompleted) {
        _activeAttemptCompleters[id]!.complete();
      }
      _activeAttemptCompleters.remove(id);
    }

    final partFile = await _partFileOrNull(id);
    if (partFile != null && partFile.existsSync()) {
      try {
        partFile.deleteSync();
      } catch (_) {}
    }

    await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).write(
      DownloadsTableCompanion(
        state: Value(DownloadTaskState.cancelled.name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Enqueue and optionally start download
  Future<void> enqueueDownload({
    required String id,
    required Uri url,
    required String displayName,
    required String suggestedFileName,
    String? kind,
    String? thumbnailUrl,
    String? qualityLabel,
    String? uploader,
    int? durationSec,
    int? totalBytes,
  }) async {
    // Queueing only writes the row and never waits for the download folder:
    // runTask resolves the folder (creating it if needed) before writing.
    final safeName = SafeFilename.sanitize(suggestedFileName, defaultExtension: 'bin');
    final now = DateTime.now();

    await _db.into(_db.downloadsTable).insertOnConflictUpdate(
      DownloadsTableCompanion.insert(
        id: id,
        url: url.toString(),
        host: url.host,
        displayName: displayName,
        fileName: safeName,
        state: DownloadTaskState.queued.name,
        kind: Value(kind),
        thumbnailUrl: Value(thumbnailUrl),
        qualityLabel: Value(qualityLabel),
        uploader: Value(uploader),
        durationSec: Value(durationSec),
        totalBytes: Value(totalBytes),
        createdAt: now,
        updatedAt: now,
      ),
    );

    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      unawaited(_fetchThumbnail(id, thumbnailUrl));
    }
  }

  /// Cover images are cosmetic: wait for the real folder, never fail over it.
  Future<void> _fetchThumbnail(String id, String url) async {
    try {
      final dir = await _dir();
      await ThumbnailFetcher(db: _db, http: _httpClient, dir: dir).fetchFor(id, url);
    } catch (_) {}
  }

  /// Start or resume download task execution
  Future<void> runTask(String id) async {
    // A quick pause -> resume must not start a second worker while the first one
    // is still unwinding (both would write the same .part file).
    final previous = _activeTaskCompleters[id];
    if (previous != null && !previous.isCompleted) {
      await previous.future;
    }

    final completer = Completer<void>();
    _activeTaskCompleters[id] = completer;
    _pausedTasks[id] = false;
    _cancelledTasks[id] = false;

    var host = '';
    try {
      final task = await (_db.select(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
      if (task == null) return;
      host = task.host;

      // State writes below are each preceded by a pause/cancel check with no
      // await in between: a pause or cancel that landed while this task was
      // waiting has already written its state, and overwriting it would leave
      // the row active with no worker (a lost slot, a service that never stops).
      // A pause/cancel after the check writes later, so it still wins.
      if (_isPausedOrCancelled(id)) return;

      // Transition to preparing
      await _updateState(id, DownloadTaskState.preparing);

      // The real download folder (waits for it at app start; recreated if it
      // was removed). Never a fallback folder: without it the task fails.
      final Directory downloadDir;
      try {
        downloadDir = await _dir();
        if (!downloadDir.existsSync()) downloadDir.createSync(recursive: true);
      } catch (_) {
        await _failTask(id, 'write_failed', task.host);
        return;
      }

      final partFile = File(p.join(downloadDir.path, '$id.part'));
      int existingBytes = partFile.existsSync() ? partFile.lengthSync() : 0;

      // Free disk space check
      final freeBytes = await _freeSpaceProvider();
      final requiredBytes = (task.totalBytes != null && task.totalBytes! > 0)
          ? (task.totalBytes! - existingBytes + freeSpaceMarginBytes)
          : (200 * 1024 * 1024);

      if (freeBytes < requiredBytes) {
        await _failTask(id, 'insufficient_disk_space', task.host);
        return;
      }

      // Waiting for the folder (app start) and the free-space query gave a
      // pause/cancel time to land: it wins (see above).
      if (_isPausedOrCancelled(id)) return;

      // Transition to downloading
      await _updateState(id, DownloadTaskState.downloading);

      // Perform download with up to 3 retries for transient errors
      int attempts = 0;
      bool success = false;
      const maxRetries = 3;

      while (attempts <= maxRetries && !success) {
        if (_isPausedOrCancelled(id)) return;
        attempts++;

        try {
          final currentTask = await (_db.select(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).getSingle();
          final moreToFetch = await _executeDownloadAttempt(
            task: currentTask,
            partFile: partFile,
            startByte: existingBytes,
          );
          if (moreToFetch) {
            // One byte range is saved (see [RangeChunkPolicy]): ask for the
            // next one, with a fresh retry budget. Every range adds at least
            // one chunk's worth of bytes, so this ends.
            existingBytes = partFile.existsSync() ? partFile.lengthSync() : existingBytes;
            attempts = 0;
            continue;
          }
          success = true;
        } catch (e) {
          if (_isPausedOrCancelled(id)) return;

          final isTransient = _isTransientError(e);
          if (isTransient && attempts <= maxRetries) {
            final jitterMs = Random().nextInt(500);
            final backoffMs = (pow(2, attempts) * 500).toInt() + jitterMs;
            await Future.delayed(Duration(milliseconds: backoffMs));
            if (partFile.existsSync()) {
              existingBytes = partFile.lengthSync();
            }
          } else {
            final errorCode = (e is SafeHttpClientException)
                ? (e.code ?? 'download_error')
                : (e is FileSystemException && e.osError?.errorCode == 28
                    ? 'insufficient_disk_space'
                    : (e is FileSystemException ? 'write_failed' : 'download_error'));
            await _failTask(id, errorCode, task.host);
            return;
          }
        }
      }

      if (_isPausedOrCancelled(id)) return;

      // Finalizing phase
      await _updateState(id, DownloadTaskState.finalizing);
      await _finalizeDownload(id, task, partFile, downloadDir);
    } catch (e) {
      // Anything unexpected (open/rename/database error while finalizing, a
      // database error while preparing, ...) must end in a terminal state. Otherwise
      // the row stays preparing/downloading/finalizing with no worker: the
      // queue coordinator keeps counting it, a download slot is lost and the
      // foreground service + wake lock never stop.
      await _failAfterUnexpectedError(id, host, e);
    } finally {
      completer.complete();
      _activeTaskCompleters.remove(id);
    }
  }

  Future<void> _failAfterUnexpectedError(String id, String host, Object error) async {
    // A pause/cancel that raced the error already put the row where it belongs.
    if (_isPausedOrCancelled(id)) return;
    try {
      await _failTask(id, unexpectedErrorCode(error), host, detail: sanitizedErrorReason(error));
    } catch (_) {
      // The database itself is failing: nothing more can be recorded.
    }
  }

  /// Error code for an unexpected exception, using the codes the Downloads
  /// screen already explains to the user.
  static String unexpectedErrorCode(Object error) {
    if (error is FileSystemException) {
      return error.osError?.errorCode == 28 ? 'insufficient_disk_space' : 'write_failed';
    }
    return 'download_error';
  }

  /// A short reason for the card's "Reason:" line. Never the raw exception
  /// text: file errors embed full paths (and other errors may embed links), so
  /// only the OS message or the error type is kept, and it is redacted too.
  static String sanitizedErrorReason(Object error) {
    if (error is FileSystemException) {
      final os = error.osError?.message.trim() ?? '';
      return DiagnosticsService.redact(os.isEmpty ? 'File system error' : 'File system error: $os');
    }
    return 'Unexpected error (${error.runtimeType})';
  }

  bool _isPausedOrCancelled(String id) {
    return (_pausedTasks[id] == true) || (_cancelledTasks[id] == true);
  }

  bool _isTransientError(dynamic e) {
    if (e is SocketException || e is TimeoutException) return true;
    if (e is SafeHttpClientException) {
      if (e.code == 'connection_error') return true;
      if (e.code == 'incomplete_download') return true;
      if (e.code != null && e.code!.startsWith('http_5')) return true; // 5xx server errors are transient
      if (e.code == 'http_408' || e.code == 'http_429') return true; // timeout / rate limit
      // Cert errors or policy blocks are NOT transient
      if (e.code == 'blocked_private_ip' ||
          e.code == 'blocked_domain' ||
          e.code == 'too_many_redirects' ||
          e.code == 'max_body_size_exceeded' ||
          e.code == 'write_failed' ||
          e.code == 'insufficient_disk_space') {
        return false;
      }
    }
    return false;
  }

  SafeHttpClientException _classifyWriteError(dynamic err, String host) {
    if (err is FileSystemException) {
      if (err.osError?.errorCode == 28) {
        return SafeHttpClientException(
          'Disk full: insufficient disk space to write download chunk (OS error 28 ENOSPC)',
          code: 'insufficient_disk_space',
          host: host,
        );
      }
    }
    return SafeHttpClientException(
      'Write failed while writing download chunk: $err',
      code: 'write_failed',
      host: host,
    );
  }

  /// One request. Returns true when it saved one byte range of a file that is
  /// fetched in ranges ([RangeChunkPolicy]) and more of the file is still to
  /// come; false when the file is complete (or the task was paused/cancelled).
  Future<bool> _executeDownloadAttempt({
    required DownloadEntry task,
    required File partFile,
    required int startByte,
  }) async {
    final uri = Uri.parse(task.url);
    final headers = <String, String>{};

    // Inclusive last byte of the range asked for; null = up to the end.
    int? rangeEnd;
    final chunk = _rangeChunkBytes(uri);
    if (chunk != null && chunk > 0) {
      final knownTotal = task.totalBytes;
      final end = startByte + chunk - 1;
      // The last piece of a file of known size is asked for open-ended.
      if (knownTotal == null || knownTotal <= 0 || end < knownTotal - 1) rangeEnd = end;
    }

    if (startByte > 0 || rangeEnd != null) {
      headers['Range'] = 'bytes=$startByte-${rangeEnd ?? ''}';
    }
    if (startByte > 0) {
      if (task.etag != null && task.etag!.isNotEmpty) {
        headers['If-Range'] = task.etag!;
      } else if (task.lastModified != null && task.lastModified!.isNotEmpty) {
        headers['If-Range'] = task.lastModified!;
      }
    }

    // The per-chunk check below enforces the 2 GB total (it includes startByte);
    // the client limit is only a safety net, so it must not be tightened by the
    // resume offset (a server may answer a Range request with a full 200 body).
    final response = await _httpClient.openStream(
      uri,
      method: 'GET',
      headers: headers,
      maxBodySize: maxDownloadSizeBytes,
    );
    _activeStreamResponses[task.id] = response;

    if (_isPausedOrCancelled(task.id)) {
      response.close();
      return false;
    }

    final status = response.statusCode;
    if (status == 416 && startByte > 0) {
      // "Range Not Satisfiable" for a resume that starts exactly at the end: the
      // part file already holds the whole file (e.g. the app stopped, or an error
      // happened, while finalizing). Treat it as downloaded; finalize checks it.
      final range = response.headers.value('content-range');
      final total = (range != null && range.contains('/')) ? int.tryParse(range.split('/').last.trim()) : null;
      if (total != null && total == startByte) {
        response.close();
        await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).write(
          DownloadsTableCompanion(totalBytes: Value(total), receivedBytes: Value(total)),
        );
        return false;
      }
    }
    if (status >= 400 && status < 500) {
      response.close();
      throw SafeHttpClientException('Client error: $status', code: 'http_$status', host: uri.host);
    }
    if (status >= 500) {
      response.close();
      throw SafeHttpClientException('Server error: $status', code: 'http_$status', host: uri.host);
    }

    final etag = response.headers.value(HttpHeaders.etagHeader) ?? task.etag;
    final lastModified = response.headers.value(HttpHeaders.lastModifiedHeader) ?? task.lastModified;
    final acceptRanges = response.headers.value(HttpHeaders.acceptRangesHeader);
    bool supportsRange = (acceptRanges == 'bytes') || status == 206;

    final contentRange = response.headers.value('content-range');

    // Handle Range response validation & ETag change
    if (startByte > 0 || rangeEnd != null) {
      if (status == 206) {
        // Validate Content-Range header matches requested startByte
        if (contentRange == null || !contentRange.toLowerCase().startsWith('bytes $startByte-')) {
          response.close();
          throw SafeHttpClientException(
            'Content-Range mismatch on 206: expected start byte $startByte, got $contentRange',
            code: 'content_range_mismatch',
            host: uri.host,
          );
        }
      } else if (status == 200) {
        if (startByte > 0) {
          // Server refused Range (e.g. ETag changed or Range not supported): restart from zero and truncate .part
          startByte = 0;
          supportsRange = false;
          try {
            if (partFile.existsSync()) {
              partFile.writeAsBytesSync([], flush: true);
            }
          } catch (_) {}
        }
        // A 200 carries the whole file, not one range of it.
        rangeEnd = null;
      }
    }

    final sinkMode = (status == 206 && startByte > 0) ? FileMode.append : FileMode.write;

    int? totalBytes = task.totalBytes;
    if (contentRange != null && contentRange.contains('/')) {
      final totalStr = contentRange.split('/').last.trim();
      totalBytes = int.tryParse(totalStr);
      supportsRange = true;
    } else {
      final cl = response.headers.value(HttpHeaders.contentLengthHeader);
      if (cl != null) {
        final parsedCl = int.tryParse(cl);
        if (parsedCl != null) {
          totalBytes = (status == 206) ? (startByte + parsedCl) : parsedCl;
        }
      }
    }

    if (totalBytes != null && totalBytes > maxDownloadSizeBytes) {
      response.close();
      throw SafeHttpClientException(
        'Size exceeded max allowed limit of 2GB',
        code: 'max_size_exceeded',
        host: uri.host,
      );
    }

    // For one range of a longer file: where this response must end
    // (exclusive), and whether another range follows it.
    int? rangeStop;
    var moreAfterThis = false;
    if (rangeEnd != null && status == 206) {
      final last = _lastByteOf(contentRange);
      final finalPiece = totalBytes != null && totalBytes > 0 && last == totalBytes - 1;
      if (last == rangeEnd && !finalPiece) {
        rangeStop = last! + 1;
        moreAfterThis = true;
      } else if (finalPiece || (last != null && last < rangeEnd && (totalBytes == null || totalBytes <= 0))) {
        // The end of the file (a server may shorten a range that runs past it).
        rangeStop = last! + 1;
      } else {
        // Anything else would make the loop ask for ever-smaller ranges.
        response.close();
        throw SafeHttpClientException(
          'Content-Range mismatch on 206: asked for bytes $startByte-$rangeEnd, got $contentRange',
          code: 'content_range_mismatch',
          host: uri.host,
        );
      }
    }

    // Persist header metadata
    await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).write(
      DownloadsTableCompanion(
        etag: Value(etag),
        lastModified: Value(lastModified),
        supportsRange: Value(supportsRange),
        totalBytes: Value(totalBytes),
      ),
    );

    final raf = await partFile.open(mode: sinkMode);
    int receivedBytes = (sinkMode == FileMode.append) ? startByte : 0;
    final startTime = DateTime.now();
    DateTime lastDbSaveTime = startTime;
    int lastDbSaveBytes = receivedBytes;
    DateTime lastUiUpdateTime = startTime;

    final completer = Completer<void>();
    _activeAttemptCompleters[task.id] = completer;
    StreamSubscription<List<int>>? subscription;
    // A chunk write can still be in flight when pause()/cancel() completes the
    // attempt. Closing a RandomAccessFile while a write is pending throws
    // "An async operation is currently pending" and skips all cleanup, so the
    // finally block waits for it first.
    Future<void> pendingWrite = Future<void>.value();

    try {
      subscription = response.body.listen(
        (chunk) async {
          try {
            if (_isPausedOrCancelled(task.id)) {
              subscription?.cancel();
              response.close();
              if (!completer.isCompleted) completer.complete();
              return;
            }

            subscription?.pause();
            try {
              final write = raf.writeFrom(chunk);
              pendingWrite = write.then<void>((_) {}, onError: (Object _) {});
              await write;
              receivedBytes += chunk.length;

              if (receivedBytes > maxDownloadSizeBytes) {
                subscription?.cancel();
                response.close();
                if (!completer.isCompleted) {
                  completer.completeError(
                    SafeHttpClientException(
                      'Size exceeded max allowed limit of 2GB',
                      code: 'max_size_exceeded',
                      host: uri.host,
                    ),
                  );
                }
                return;
              }

              final now = DateTime.now();

              // 1. Persist to DB at most every 1s or 512 KB
              if (now.difference(lastDbSaveTime).inMilliseconds >= 1000 ||
                  (receivedBytes - lastDbSaveBytes) >= 512 * 1024) {
                await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).write(
                  DownloadsTableCompanion(
                    receivedBytes: Value(receivedBytes),
                    updatedAt: Value(now),
                  ),
                );
                lastDbSaveTime = now;
                lastDbSaveBytes = receivedBytes;
              }

              // 2. UI stream throttled to ~4 updates per second (>= 250ms)
              if (now.difference(lastUiUpdateTime).inMilliseconds >= 250) {
                double? speed;
                Duration? eta;
                final elapsedSec = now.difference(startTime).inMilliseconds / 1000.0;
                if (elapsedSec > 0.5) {
                  speed = (receivedBytes - startByte) / elapsedSec;
                  if (totalBytes != null && speed > 0) {
                    final remaining = totalBytes - receivedBytes;
                    if (remaining > 0) {
                      eta = Duration(seconds: (remaining / speed).ceil());
                    }
                  }
                }

                _progressController.add(DownloadProgressUpdate(
                  id: task.id,
                  receivedBytes: receivedBytes,
                  totalBytes: totalBytes,
                  progress: totalBytes != null && totalBytes > 0 ? receivedBytes / totalBytes : null,
                  speedBytesPerSec: speed,
                  eta: eta,
                ));
                lastUiUpdateTime = now;
              }
            } finally {
              if (!_isPausedOrCancelled(task.id)) {
                subscription?.resume();
              }
            }
          } catch (writeErr, writeStack) {
            subscription?.cancel();
            response.close();

            final typedErr = _classifyWriteError(writeErr, uri.host);
            if (!completer.isCompleted) {
              completer.completeError(typedErr, writeStack);
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            // Check if stream closed early before expected total bytes arrived
            // (for one range of a longer file: before the end of that range).
            final expectedEnd = rangeStop ?? totalBytes;
            if (expectedEnd != null && expectedEnd > 0 && receivedBytes < expectedEnd) {
              completer.completeError(
                SafeHttpClientException(
                  'Stream closed early: received $receivedBytes bytes of expected $expectedEnd',
                  code: 'incomplete_download',
                  host: uri.host,
                ),
              );
              return;
            }
            completer.complete();
          }
        },
        cancelOnError: true,
      );

      _activeSubscriptions[task.id] = subscription;

      await completer.future;

      // Final save of received bytes equal to file length
      final finalLen = partFile.existsSync() ? partFile.lengthSync() : receivedBytes;
      await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).write(
        DownloadsTableCompanion(
          receivedBytes: Value(finalLen),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (moreAfterThis) {
        // Only one range of the file: the next request carries on (no
        // "finished" update, so the speed line does not blink between ranges).
        return true;
      }

      // Emit final completion progress update
      _progressController.add(DownloadProgressUpdate(
        id: task.id,
        receivedBytes: finalLen,
        totalBytes: totalBytes,
        progress: totalBytes != null && totalBytes > 0 ? finalLen / totalBytes : 1.0,
        speedBytesPerSec: null,
        eta: Duration.zero,
      ));
      return false;
    } finally {
      _activeAttemptCompleters.remove(task.id);
      _activeSubscriptions.remove(task.id);
      _activeStreamResponses.remove(task.id);
      subscription?.cancel();
      response.close();
      await pendingWrite;
      try {
        await raf.close();
      } catch (_) {}

      // Ensure receivedBytes in DB matches part file length even on error
      if (partFile.existsSync()) {
        final currentLen = partFile.lengthSync();
        await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(task.id))).write(
          DownloadsTableCompanion(
            receivedBytes: Value(currentLen),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      if (_cancelledTasks[task.id] == true && partFile.existsSync()) {
        try {
          partFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// The last byte position in a `Content-Range: bytes <first>-<last>/<total>`
  /// header, or null when the header has another shape.
  static int? _lastByteOf(String? contentRange) {
    if (contentRange == null) return null;
    final match = RegExp(r'^bytes\s+\d+-(\d+)/(\d+|\*)$', caseSensitive: false).firstMatch(contentRange.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// MP4 and WebM hold audio as well as video. YouTube's audio-only M4A
  /// starts with a "dash" brand that [MediaSniffer] reports as video/mp4, so a
  /// row queued as audio keeps that kind (file type, extension and library tab).
  static String? applyKindHint(String? sniffedMime, String? queuedKind) {
    if (sniffedMime == null || queuedKind != 'audio') return sniffedMime;
    if (sniffedMime == 'video/mp4') return 'audio/mp4';
    if (sniffedMime == 'video/webm') return 'audio/webm';
    return sniffedMime;
  }

  Future<void> _finalizeDownload(String id, DownloadEntry task, File partFile, Directory downloadDir) async {
    final updatedTask = await (_db.select(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).getSingle();
    final fileSize = partFile.existsSync() ? partFile.lengthSync() : 0;

    // Check size against Content-Length if known
    if (updatedTask.totalBytes != null && updatedTask.totalBytes! > 0) {
      if (fileSize != updatedTask.totalBytes!) {
        await _failTask(id, 'size_mismatch', task.host);
        return;
      }
    }

    // Sniff magic bytes
    final sniffBytes = <int>[];
    final raf = partFile.openSync(mode: FileMode.read);
    try {
      final header = raf.readSync(min(64, fileSize));
      sniffBytes.addAll(header);
    } finally {
      raf.closeSync();
    }

    final detectedMime = applyKindHint(MediaSniffer.sniff(sniffBytes), updatedTask.kind);
    if (detectedMime == null) {
      // Anything else (HTML, JSON, text) fails with "not_media" and .part is deleted
      if (partFile.existsSync()) {
        try {
          partFile.deleteSync();
        } catch (_) {}
      }
      await _failTask(id, 'not_media', task.host);
      return;
    }

    // A finished file never keeps an internal extension (.part, .thumb, ...):
    // "song.part" is saved as "song.mp3" (extension from the sniffed type), so
    // no cleanup pass can ever mistake it for a work file.
    final hadReservedExtension = SafeFilename.hasReservedExtension(SafeFilename.sanitize(task.fileName));
    final safeOriginalName = SafeFilename.finalMediaName(
      task.fileName,
      mediaExtension: extensionForMime(detectedMime),
    );
    final ext = p.extension(safeOriginalName);
    final baseWithoutExt = p.basenameWithoutExtension(safeOriginalName);

    // Final destination filename uniqueness check (" (1)")
    String finalFileName = safeOriginalName;
    File finalDest = File(p.join(downloadDir.path, finalFileName));
    int duplicateIndex = 1;
    while (finalDest.existsSync()) {
      finalFileName = '$baseWithoutExt ($duplicateIndex)$ext';
      finalDest = File(p.join(downloadDir.path, finalFileName));
      duplicateIndex++;
    }

    // Atomic rename
    partFile.renameSync(finalDest.path);

    final mediaId = 'dl_$id';
    final mediaType = detectedMime.startsWith('video') ? MediaType.video : MediaType.audio;

    try {
      // Insert into media_items table
      await _db.into(_db.mediaItemsTable).insertOnConflictUpdate(
        MediaItemsTableCompanion.insert(
          id: mediaId,
          uri: finalDest.path,
          mediaType: mediaType.name,
          title: task.displayName,
          artist: Value(updatedTask.uploader),
          durationMs: (updatedTask.durationSec ?? 0) * 1000,
          sizeBytes: fileSize,
          format: Value(ext.isNotEmpty ? ext.substring(1) : detectedMime.split('/').last),
          dateAdded: DateTime.now(),
          availability: const Value('available'),
          source: const Value('download'),
          artworkPath: Value(_existingFile(updatedTask.thumbnailPath)),
        ),
      );

      // Update download row to completed
      await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).write(
        DownloadsTableCompanion(
          state: Value(DownloadTaskState.completed.name),
          // The card shows the real name when the extension had to be replaced.
          fileName: hadReservedExtension ? Value(finalFileName) : const Value.absent(),
          kind: Value(mediaType.name),
          mimeType: Value(detectedMime),
          finalPath: Value(finalDest.path),
          mediaId: Value(mediaId),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (_) {
      // Not recorded as finished: move the file back to `<id>.part` so the
      // failed row still owns it (the startup sweep keeps it while the row
      // exists and removes it once the row is deleted; a retry reuses the
      // name). Left in place it would be an invisible file no row knows
      // about, and a retry would save "name (1)". runTask then marks the
      // task failed.
      await undoFinalMove(_db, finalFile: finalDest, workFile: partFile, mediaId: mediaId);
      rethrow;
    }

    DiagnosticsService.instance.logEvent('download_completed', {
      'host': task.host,
      'mime': detectedMime,
      'bytes': fileSize,
    });
  }

  String? _existingFile(String? path) =>
      (path != null && File(path).existsSync()) ? path : null;

  /// Undoes the last step of a finalize whose database writes failed: moves
  /// [finalFile] back to [workFile] (the partial / work file it was renamed
  /// from) and removes the library row [mediaId] if it was already written,
  /// so no row points at a file that is no longer there. Best effort and
  /// never throws: the caller rethrows the original error. Shared with the
  /// web-link runner.
  static Future<void> undoFinalMove(
    AppDatabase db, {
    required File finalFile,
    required File workFile,
    required String mediaId,
  }) async {
    try {
      if (finalFile.existsSync() && !workFile.existsSync()) {
        try {
          finalFile.renameSync(workFile.path);
        } catch (_) {
          finalFile.copySync(workFile.path);
          finalFile.deleteSync();
        }
      }
    } catch (_) {}
    try {
      await (db.delete(db.mediaItemsTable)..where((tbl) => tbl.id.equals(mediaId))).go();
    } catch (_) {}
  }

  /// File extension (no dot) for a MIME type returned by [MediaSniffer].
  static String extensionForMime(String mime) {
    switch (mime) {
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/mp4':
        return 'm4a';
      case 'video/mp4':
        return 'mp4';
      case 'video/webm':
        return 'webm';
      case 'audio/ogg':
        return 'ogg';
      case 'audio/flac':
        return 'flac';
      case 'audio/wav':
        return 'wav';
      case 'audio/aac':
        return 'aac';
      default:
        final sub = mime.split('/').last.toLowerCase();
        return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(sub) ? sub : 'bin';
    }
  }

  /// Marks the task failed. [detail] (already sanitized) fills the card's
  /// "Reason:" line; it is always written so a stale reason from an earlier
  /// attempt never sticks to a new error.
  Future<void> _failTask(String id, String errorCode, String host, {String? detail}) async {
    if (errorCode == 'not_media') {
      final partFile = await _partFileOrNull(id);
      if (partFile != null && partFile.existsSync()) {
        try {
          partFile.deleteSync();
        } catch (_) {}
      }
    }

    await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).write(
      DownloadsTableCompanion(
        state: Value(DownloadTaskState.failed.name),
        errorCode: Value(errorCode),
        errorDetail: Value(detail),
        updatedAt: Value(DateTime.now()),
      ),
    );

    DiagnosticsService.instance.logEvent('download_failed', {
      'host': host,
      'code': errorCode,
    });
  }

  Future<void> _updateState(String id, DownloadTaskState state) async {
    await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).write(
      DownloadsTableCompanion(
        state: Value(state.name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  void dispose() {
    _progressController.close();
  }
}
