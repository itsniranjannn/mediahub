// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'thumbnail_fetcher.dart';
import 'youtube_link.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/downloads/download_state_machine.dart';
import '../../core/downloads/ios_playable_formats.dart';
import '../../core/downloads/media_kind_classifier.dart';
import '../../core/downloads/media_sniffer.dart';
import '../../core/platform_info.dart';
import '../../core/security/safe_filename.dart';
import '../../core/security/safe_http_client.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/download_state.dart';
import '../../domain/models/media_item.dart';
import '../database/app_database.dart';

/// Free bytes where downloads are saved, or null when the phone cannot tell
/// (iOS has no free-space call here): then no up-front check is made, and a
/// phone that fills up fails while writing (`insufficient_disk_space`).
typedef FreeSpaceProvider = Future<int?> Function();

/// Size of the byte ranges a download from [url] is fetched in, or null to
/// fetch it in one response (resuming with a Range request after a break).
typedef RangeChunkPolicy = int? Function(Uri url);

/// A new address for a download whose link to its file stopped working.
class RefreshedStreamLink {
  const RefreshedStreamLink({
    required this.uri,
    this.linkSource,
    this.sizeBytes,
    this.sameFile = true,
  });

  final Uri uri;

  /// Replaces the row's saved link source (for example with the new lookup
  /// time); null keeps the old one.
  final String? linkSource;

  /// The file's size at the new address, when known.
  final int? sizeBytes;

  /// The new address serves the very same file, so a partial download
  /// carries on from where it stopped. False: it starts over.
  final bool sameFile;
}

/// Finds a new link for downloads whose links expire (YouTube's links to its
/// files stop working after about six hours). The engine asks before a
/// download starts or resumes, and once more when the server refuses the
/// link (HTTP 403 or 410).
abstract class StreamLinkRefresher {
  /// True when [task] carries what is needed to look its link up again.
  bool canRefresh(DownloadEntry task);

  /// True when [task]'s link has expired or is about to.
  bool isStale(DownloadEntry task, DateTime now);

  /// A fresh link for [task], or null when none was found.
  Future<RefreshedStreamLink?> refresh(DownloadEntry task);
}

class DownloadEngine {
  final AppDatabase _db;
  final SafeHttpClient _httpClient;

  /// The download folder. It may still be resolving when the engine is created
  /// (see `downloadEngineProvider`): every file operation awaits it, so a file
  /// is never written to any other place (there is no temp-dir fallback).
  final Future<Directory> _downloadDirFuture;
  final FreeSpaceProvider _freeSpaceProvider;
  final RangeChunkPolicy _rangeChunkBytes;

  /// Looks up expired links again (iOS YouTube downloads); null: never.
  final StreamLinkRefresher? _streamLinkRefresher;

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
    StreamLinkRefresher? streamLinkRefresher,
  })  : _db = db, // ignore: prefer_initializing_formals
        _httpClient = httpClient, // ignore: prefer_initializing_formals
        _downloadDirFuture = settleDirectory(downloadDir),
        _freeSpaceProvider = freeSpaceProvider ?? defaultFreeSpaceProvider,
        _rangeChunkBytes = rangeChunkBytes ?? defaultRangeChunkBytes,
        _streamLinkRefresher = streamLinkRefresher; // ignore: prefer_initializing_formals

  Stream<DownloadProgressUpdate> get progressStream => _progressController.stream;

  /// True when expired links are looked up again (iOS YouTube downloads).
  @visibleForTesting
  bool get refreshesExpiredLinks => _streamLinkRefresher != null;

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
  /// the web-link runner so both use the same check. Null on iOS: nothing
  /// there answers the question (it used to report a made-up 10 GB).
  static Future<int?> defaultFreeSpaceProvider() async {
    if (PlatformInfo.isIOS) return null;
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

  /// Name of the empty file in the download folder that says the one-time
  /// check of [repairLibraryKinds] is done.
  static const String kindsCheckedMarker = '.kinds-checked-v1';

  /// Once per install: puts every finished download in the library section
  /// its file really belongs to.
  ///
  /// Before files were classified by their tracks, an MP4 or WebM with sound
  /// only (a song served as `video/mp4`, a web-link audio file) was saved as
  /// a video and showed in Videos, and a video served as `audio/mp4` showed
  /// in Music. Each downloaded file is checked with [MediaKindClassifier];
  /// only a file that itself says what it is changes rows, and only its own
  /// library row (`media_type`) and download row (`kind`, `mime_type`).
  ///
  /// Never touches songs and videos from the phone (MediaStore), web links,
  /// or any file outside the download folder, and never moves a web-link
  /// download the user asked to save as sound ("Original audio", MP3) to
  /// Videos: that one stays in Music even when the site only had a file
  /// with pictures. Returns how many library rows
  /// moved. Running it again does nothing (a marker file records it), and a
  /// run that fails part way is simply repeated at the next start.
  Future<int> repairLibraryKinds() async {
    final Directory dir;
    try {
      dir = await _dir();
      if (!dir.existsSync()) return 0;
    } catch (_) {
      return 0;
    }
    final marker = File(p.join(dir.path, kindsCheckedMarker));
    if (marker.existsSync()) return 0;

    var moved = 0;
    final rows = await (_db.select(_db.mediaItemsTable)..where((t) => t.source.equals('download'))).get();
    for (final row in rows) {
      final path = row.uri;
      if (path.contains('://') || !p.isWithin(p.normalize(dir.path), p.normalize(path))) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      final decision = MediaKindClassifier.classifyFile(file, fileName: path);
      // Let the app breathe between files.
      await Future<void>.delayed(Duration.zero);
      if (decision == null || !decision.byContent) continue;
      final type = decision.isVideo ? MediaType.video : MediaType.audio;
      if (row.mediaType == type.name) continue;
      if (type == MediaType.video && await _askedForSound(row.id)) continue;

      await (_db.update(_db.mediaItemsTable)..where((t) => t.id.equals(row.id))).write(
        MediaItemsTableCompanion(mediaType: Value(type.name)),
      );
      await (_db.update(_db.downloadsTable)..where((t) => t.mediaId.equals(row.id))).write(
        DownloadsTableCompanion(kind: Value(decision.kind), mimeType: Value(decision.mimeType)),
      );
      moved++;
    }

    try {
      marker.writeAsStringSync('1', flush: true);
    } catch (_) {
      // Checked again next start; nothing changes then.
    }
    if (moved > 0) DiagnosticsService.instance.logEvent('download_kinds_repaired', {'rows': moved});
    return moved;
  }

  /// True when library row [mediaId] is a web-link (yt-dlp) download the
  /// user asked to save as sound.
  Future<bool> _askedForSound(String mediaId) async {
    final rows = await (_db.select(_db.downloadsTable)..where((t) => t.mediaId.equals(mediaId))).get();
    return rows.any((d) =>
        d.engine == 'extractor' &&
        (d.kind == 'audio' || (d.audioFormat ?? '').isNotEmpty || _isSoundSelector(d.formatSelector)));
  }

  /// yt-dlp's "sound only" selectors ('ba/b', 'bestaudio...').
  static bool _isSoundSelector(String? selector) {
    final s = selector?.trim() ?? '';
    return s.startsWith('ba') || s.startsWith('bestaudio');
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
    String? linkSource,
  }) async {
    // [linkSource]: what finds the file again once [url] expires (see
    // [StreamLinkRefresher]), kept in the row's formatSelector column, which
    // direct-link rows do not use otherwise.
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
        formatSelector: linkSource == null ? const Value.absent() : Value(linkSource),
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

      // A link that expires (YouTube's, after some hours) and is too old by
      // now is looked up again before it is used: a resume or retry later
      // that day still finds the file. Only one new lookup per run.
      final refresher = _streamLinkRefresher;
      var linkRefreshed = false;
      var sized = task;
      if (refresher != null && refresher.canRefresh(task) && refresher.isStale(task, DateTime.now())) {
        linkRefreshed = true;
        final updated = await _refreshLink(id, partFile);
        if (_isPausedOrCancelled(id)) return;
        if (updated != null) {
          sized = updated;
          existingBytes = partFile.existsSync() ? partFile.lengthSync() : 0;
        }
      }

      // Free disk space check (skipped where the phone cannot tell: iOS).
      final freeBytes = await _freeSpaceProvider();
      final requiredBytes = (sized.totalBytes != null && sized.totalBytes! > 0)
          ? (sized.totalBytes! - existingBytes + freeSpaceMarginBytes)
          : (200 * 1024 * 1024);

      if (freeBytes != null && freeBytes < requiredBytes) {
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

          // The server refused an expiring link (YouTube's, once it is too old
          // or the phone's address changed): look it up once more, go on.
          if (!linkRefreshed && refresher != null && _isRefusedLinkError(e)) {
            linkRefreshed = true;
            final updated = await _refreshLink(id, partFile);
            if (_isPausedOrCancelled(id)) return;
            if (updated != null) {
              existingBytes = partFile.existsSync() ? partFile.lengthSync() : 0;
              attempts = 0;
              continue;
            }
          }

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

  static const Set<String> _mediaExtensions = {
    'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'oga', 'opus', 'weba', 'wma',
    'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', '3gp', 'ts',
  };

  /// The library title for a download named [displayName]: a direct link's
  /// name is its file name ("Song-1.mp3"), so a media extension at the end is
  /// dropped ("Song-1"). Anything else, an empty result included, stays as it is.
  static String libraryTitleFor(String displayName) {
    final name = displayName.trim();
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return displayName;
    if (!_mediaExtensions.contains(name.substring(dot + 1).toLowerCase())) return displayName;
    final base = name.substring(0, dot).trim();
    return base.isEmpty ? displayName : base;
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

  /// HTTP 403 / 410: what YouTube's servers answer for an expired link.
  static bool _isRefusedLinkError(Object e) =>
      e is SafeHttpClientException && (e.code == 'http_403' || e.code == 'http_410');

  /// Asks [_streamLinkRefresher] for a new link for task [id] and saves it on
  /// the row. When the new address serves a different file, the download
  /// starts over (its partial file is removed). Returns the updated row, or
  /// null when no new link was found (the row is then left as it was).
  Future<DownloadEntry?> _refreshLink(String id, File partFile) async {
    final refresher = _streamLinkRefresher;
    if (refresher == null) return null;
    DownloadEntry? row = await (_db.select(_db.downloadsTable)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null || !refresher.canRefresh(row)) return null;

    RefreshedStreamLink? fresh;
    try {
      fresh = await refresher.refresh(row);
    } catch (_) {
      fresh = null;
    }
    DiagnosticsService.instance.logEvent('download_link_refresh', {
      'host': row.host,
      'found': fresh != null,
    });
    if (fresh == null) return null;

    final known = (row.totalBytes != null && row.totalBytes! > 0) ? row.totalBytes : null;
    final startOver = !fresh.sameFile || (fresh.sizeBytes != null && known != null && fresh.sizeBytes != known);
    if (startOver && partFile.existsSync()) {
      try {
        partFile.deleteSync();
      } catch (_) {
        // Appending another file's bytes to it would corrupt the download.
        return null;
      }
    }

    await (_db.update(_db.downloadsTable)..where((t) => t.id.equals(id))).write(
      DownloadsTableCompanion(
        url: Value(fresh.uri.toString()),
        host: Value(fresh.uri.host),
        formatSelector: fresh.linkSource == null ? const Value.absent() : Value(fresh.linkSource),
        totalBytes: startOver || (known == null && fresh.sizeBytes != null)
            ? Value(fresh.sizeBytes)
            : const Value.absent(),
        receivedBytes: startOver ? const Value(0) : const Value.absent(),
        etag: startOver ? const Value(null) : const Value.absent(),
        lastModified: startOver ? const Value(null) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
    row = await (_db.select(_db.downloadsTable)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row;
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

    // Magic bytes say whether it is media at all; for MP4 / WebM / Ogg the
    // file's own track list then says song or video (an MP4 with sound only
    // belongs in Music, whatever the server called it).
    final decision = MediaKindClassifier.classifyFile(
      partFile,
      kindHint: updatedTask.kind,
      fileName: task.fileName,
    );
    if (decision == null) {
      // Anything else (HTML, JSON, text) fails with "not_media" and .part is deleted
      if (partFile.existsSync()) {
        try {
          partFile.deleteSync();
        } catch (_) {}
      }
      await _failTask(id, 'not_media', task.host);
      return;
    }
    final detectedMime = decision.mimeType;

    // iPhone's players cannot open some kinds of file (WebM, MKV, Ogg): kept,
    // it would sit in the library and never play. The Downloads card refuses
    // such links up front; this catches a file whose link did not say so.
    if (PlatformInfo.isIOS && IosPlayableFormats.unplayableFormat(mimeType: detectedMime) != null) {
      if (partFile.existsSync()) {
        try {
          partFile.deleteSync();
        } catch (_) {}
      }
      await _failTask(id, IosPlayableFormats.errorCode, task.host);
      return;
    }

    // A finished file never keeps an internal extension (.part, .thumb, ...):
    // "song.part" is saved as "song.mp3" (extension from the sniffed type), so
    // no cleanup pass can ever mistake it for a work file. A name with no
    // media extension ("track", "get.bin", "download.php": links without one)
    // gets the real one, so every player knows what the file is.
    final mediaExtension = extensionForMime(detectedMime);
    final sanitizedName = SafeFilename.sanitize(task.fileName);
    final reservedName = SafeFilename.finalMediaName(task.fileName, mediaExtension: mediaExtension);
    final safeOriginalName = SafeFilename.sanitize(
      MediaKindClassifier.nameWithMediaExtension(reservedName, mediaExtension),
    );
    final nameChanged = safeOriginalName != sanitizedName;
    final ext = p.extension(safeOriginalName);
    final baseWithoutExt = p.basenameWithoutExtension(safeOriginalName);

    // Final destination filename uniqueness check (" (1)")
    String finalFileName = safeOriginalName;
    File finalDest = File(p.join(downloadDir.path, finalFileName));
    int duplicateIndex = 1;
    while (finalDest.existsSync()) {
      // Kept within the 255-byte name limit (long Devanagari titles).
      finalFileName = SafeFilename.numbered(baseWithoutExt, duplicateIndex, ext);
      finalDest = File(p.join(downloadDir.path, finalFileName));
      duplicateIndex++;
    }

    // Atomic rename
    partFile.renameSync(finalDest.path);

    final mediaId = 'dl_$id';
    final mediaType = decision.isVideo ? MediaType.video : MediaType.audio;

    try {
      // Insert into media_items table
      await _db.into(_db.mediaItemsTable).insertOnConflictUpdate(
        MediaItemsTableCompanion.insert(
          id: mediaId,
          uri: finalDest.path,
          mediaType: mediaType.name,
          title: libraryTitleFor(task.displayName),
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
          fileName: nameChanged ? Value(finalFileName) : const Value.absent(),
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
      case 'audio/webm':
        return 'webm';
      case 'video/x-matroska':
        return 'mkv';
      case 'audio/x-matroska':
        return 'mka';
      case 'video/quicktime':
        return 'mov';
      case 'video/x-msvideo':
        return 'avi';
      case 'video/ogg':
        return 'ogv';
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
