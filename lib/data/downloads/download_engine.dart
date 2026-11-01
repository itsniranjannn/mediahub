import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
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

class DownloadEngine {
  final AppDatabase _db;
  final SafeHttpClient _httpClient;
  final Directory _downloadDir;
  final FreeSpaceProvider _freeSpaceProvider;

  static const int maxDownloadSizeBytes = 2 * 1024 * 1024 * 1024; // 2 GB
  static const MethodChannel _platformChannel = MethodChannel('mediahub/media_store');

  final StreamController<DownloadProgressUpdate> _progressController =
      StreamController<DownloadProgressUpdate>.broadcast();

  final Map<String, bool> _cancelledTasks = {};
  final Map<String, bool> _pausedTasks = {};
  final Map<String, Completer<void>> _activeTaskCompleters = {};
  final Map<String, Completer<void>> _activeAttemptCompleters = {};
  final Map<String, SafeStreamResponse> _activeStreamResponses = {};
  final Map<String, StreamSubscription<List<int>>> _activeSubscriptions = {};

  DownloadEngine({
    required AppDatabase db,
    required SafeHttpClient httpClient,
    required Directory downloadDir,
    FreeSpaceProvider? freeSpaceProvider,
  })  : _db = db, // ignore: prefer_initializing_formals
        _httpClient = httpClient, // ignore: prefer_initializing_formals
        _downloadDir = downloadDir, // ignore: prefer_initializing_formals
        _freeSpaceProvider = freeSpaceProvider ?? _defaultFreeSpaceProvider;

  Stream<DownloadProgressUpdate> get progressStream => _progressController.stream;

  static Future<int> _defaultFreeSpaceProvider() async {
    try {
      final res = await _platformChannel.invokeMethod<int>('freeSpaceBytes');
      return res ?? (10 * 1024 * 1024 * 1024);
    } catch (_) {
      // Fallback for desktop / non-android or mock tests
      return 10 * 1024 * 1024 * 1024;
    }
  }

  /// App startup recovery
  Future<void> reconcileOnStartup() async {
    final activeDownloads = await (_db.select(_db.downloadsTable)
          ..where((tbl) => tbl.state.isIn([
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
      final partPath = p.join(_downloadDir.path, '${dl.id}.part');
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
    }

    // Orphan .part cleanup: delete any .part that has no corresponding active or paused DB row
    try {
      if (_downloadDir.existsSync()) {
        final allDownloads = await _db.select(_db.downloadsTable).get();
        final validPartIds = allDownloads
            .where((d) => d.state != DownloadTaskState.completed.name && d.state != DownloadTaskState.cancelled.name)
            .map((d) => d.id)
            .toSet();

        final entities = _downloadDir.listSync();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.part')) {
            final filename = p.basenameWithoutExtension(entity.path);
            if (!validPartIds.contains(filename)) {
              try {
                entity.deleteSync();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
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
        final partFile = File(p.join(_downloadDir.path, '$id.part'));
        if (partFile.existsSync()) {
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

    final partFile = File(p.join(_downloadDir.path, '$id.part'));
    if (partFile.existsSync()) {
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
  }) async {
    if (!_downloadDir.existsSync()) {
      _downloadDir.createSync(recursive: true);
    }

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
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Start or resume download task execution
  Future<void> runTask(String id) async {
    final completer = Completer<void>();
    _activeTaskCompleters[id] = completer;
    _pausedTasks[id] = false;
    _cancelledTasks[id] = false;

    try {
      final task = await (_db.select(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
      if (task == null) return;

      // Transition to preparing
      await _updateState(id, DownloadTaskState.preparing);

      final partFile = File(p.join(_downloadDir.path, '$id.part'));
      int existingBytes = partFile.existsSync() ? partFile.lengthSync() : 0;

      // Free disk space check
      final freeBytes = await _freeSpaceProvider();
      final requiredBytes = (task.totalBytes != null && task.totalBytes! > 0)
          ? (task.totalBytes! - existingBytes + (100 * 1024 * 1024))
          : (200 * 1024 * 1024);

      if (freeBytes < requiredBytes) {
        await _failTask(id, 'insufficient_disk_space', task.host);
        return;
      }

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
          await _executeDownloadAttempt(
            task: currentTask,
            partFile: partFile,
            startByte: existingBytes,
          );
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
            final errorCode = (e is SafeHttpClientException) ? (e.code ?? 'download_error') : 'download_error';
            await _failTask(id, errorCode, task.host);
            return;
          }
        }
      }

      if (_isPausedOrCancelled(id)) return;

      // Finalizing phase
      await _updateState(id, DownloadTaskState.finalizing);
      await _finalizeDownload(id, task, partFile);
    } finally {
      completer.complete();
      _activeTaskCompleters.remove(id);
    }
  }

  bool _isPausedOrCancelled(String id) {
    return (_pausedTasks[id] == true) || (_cancelledTasks[id] == true);
  }

  bool _isTransientError(dynamic e) {
    if (e is SocketException || e is TimeoutException) return true;
    if (e is SafeHttpClientException) {
      if (e.code == 'connection_error') return true;
      if (e.code != null && e.code!.startsWith('http_5')) return true; // 5xx server errors are transient
      // Cert errors or policy blocks are NOT transient
      if (e.code == 'blocked_private_ip' ||
          e.code == 'blocked_domain' ||
          e.code == 'too_many_redirects' ||
          e.code == 'max_body_size_exceeded') {
        return false;
      }
    }
    return false;
  }

  Future<void> _executeDownloadAttempt({
    required DownloadEntry task,
    required File partFile,
    required int startByte,
  }) async {
    final uri = Uri.parse(task.url);
    final headers = <String, String>{};

    if (startByte > 0) {
      headers['Range'] = 'bytes=$startByte-';
      if (task.etag != null && task.etag!.isNotEmpty) {
        headers['If-Range'] = task.etag!;
      } else if (task.lastModified != null && task.lastModified!.isNotEmpty) {
        headers['If-Range'] = task.lastModified!;
      }
    }

    final response = await _httpClient.openStream(
      uri,
      method: 'GET',
      headers: headers,
    );
    _activeStreamResponses[task.id] = response;

    if (_isPausedOrCancelled(task.id)) {
      response.close();
      return;
    }

    final status = response.statusCode;
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
    if (startByte > 0) {
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
        // Server refused Range (e.g. ETag changed or Range not supported): restart from zero and truncate .part
        startByte = 0;
        supportsRange = false;
        try {
          if (partFile.existsSync()) {
            partFile.writeAsBytesSync([], flush: true);
          }
        } catch (_) {}
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

    try {
      subscription = response.body.listen(
        (chunk) async {
          if (_isPausedOrCancelled(task.id)) {
            subscription?.cancel();
            response.close();
            if (!completer.isCompleted) completer.complete();
            return;
          }

          subscription?.pause();
          try {
            await raf.writeFrom(chunk);
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
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
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

      // Emit final completion progress update
      _progressController.add(DownloadProgressUpdate(
        id: task.id,
        receivedBytes: finalLen,
        totalBytes: totalBytes,
        progress: totalBytes != null && totalBytes > 0 ? finalLen / totalBytes : 1.0,
        speedBytesPerSec: null,
        eta: Duration.zero,
      ));
    } finally {
      _activeAttemptCompleters.remove(task.id);
      _activeSubscriptions.remove(task.id);
      _activeStreamResponses.remove(task.id);
      subscription?.cancel();
      response.close();
      await raf.close();

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

  Future<void> _finalizeDownload(String id, DownloadEntry task, File partFile) async {
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

    final detectedMime = MediaSniffer.sniff(sniffBytes);
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

    // Final destination filename uniqueness check (" (1)")
    final safeOriginalName = SafeFilename.sanitize(task.fileName);
    final ext = p.extension(safeOriginalName);
    final baseWithoutExt = p.basenameWithoutExtension(safeOriginalName);

    String finalFileName = safeOriginalName;
    File finalDest = File(p.join(_downloadDir.path, finalFileName));
    int duplicateIndex = 1;
    while (finalDest.existsSync()) {
      finalFileName = '$baseWithoutExt ($duplicateIndex)$ext';
      finalDest = File(p.join(_downloadDir.path, finalFileName));
      duplicateIndex++;
    }

    // Atomic rename
    partFile.renameSync(finalDest.path);

    final mediaId = 'dl_$id';
    final mediaType = detectedMime.startsWith('video') ? MediaType.video : MediaType.audio;

    // Insert into media_items table
    await _db.into(_db.mediaItemsTable).insertOnConflictUpdate(
      MediaItemsTableCompanion.insert(
        id: mediaId,
        uri: finalDest.path,
        mediaType: mediaType.name,
        title: task.displayName,
        durationMs: 0,
        sizeBytes: fileSize,
        format: Value(ext.isNotEmpty ? ext.substring(1) : detectedMime.split('/').last),
        dateAdded: DateTime.now(),
        availability: const Value('available'),
        source: const Value('download'),
      ),
    );

    // Update download row to completed
    await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).write(
      DownloadsTableCompanion(
        state: Value(DownloadTaskState.completed.name),
        mimeType: Value(detectedMime),
        finalPath: Value(finalDest.path),
        mediaId: Value(mediaId),
        updatedAt: Value(DateTime.now()),
      ),
    );

    DiagnosticsService.instance.logEvent('download_completed', {
      'host': task.host,
      'mime': detectedMime,
      'bytes': fileSize,
    });
  }

  Future<void> _failTask(String id, String errorCode, String host) async {
    final partFile = File(p.join(_downloadDir.path, '$id.part'));
    if (errorCode == 'not_media' && partFile.existsSync()) {
      try {
        partFile.deleteSync();
      } catch (_) {}
    }

    await (_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).write(
      DownloadsTableCompanion(
        state: Value(DownloadTaskState.failed.name),
        errorCode: Value(errorCode),
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
