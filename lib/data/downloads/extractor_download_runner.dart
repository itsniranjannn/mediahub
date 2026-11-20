import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import '../../core/downloads/media_kind_classifier.dart';
import '../../core/downloads/media_sniffer.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/security/safe_filename.dart';
import '../../core/security/safe_http_client.dart';
import '../../domain/models/download_progress.dart';
import '../../domain/models/download_state.dart';
import '../../domain/models/media_item.dart';
import '../../personal/extractor_auto_updater.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/extractor_errors.dart';
import '../../personal/format_options.dart';
import '../database/app_database.dart';
import 'download_engine.dart';
import 'thumbnail_fetcher.dart';
import 'youtube_link.dart';

/// Saves [row], a YouTube web-link download yt-dlp could not save, another
/// way (the files YouTube serves directly), as a new download. Returns true
/// when that download was queued. [stillWanted] is false once the user paused
/// or cancelled [row]: nothing may be queued then.
typedef ExtractorFallback = Future<bool> Function(DownloadEntry row, {required bool Function() stillWanted});

/// Runs web-link downloads (yt-dlp) and keeps the `downloads` table in sync so
/// they show up in the same list, with the same pause / resume / cancel /
/// retry controls, as direct-link downloads.
///
/// When yt-dlp fails in a way a newer yt-dlp may fix, it is updated (see
/// [ExtractorAutoUpdater]) and the download tried once more. When a YouTube
/// download still fails, the [ExtractorFallback] saves it at a lower quality
/// as a new download, and this one leaves the list.
class ExtractorDownloadRunner {
  final AppDatabase _db;
  final ExtractorBackend _backend;
  final ExtractorAutoUpdater? _autoUpdater;
  final ExtractorFallback? _fallback;

  /// The download folder; may still be resolving at app start. Every file
  /// operation awaits it, so nothing is ever written to a fallback folder.
  final Future<Directory> _downloadDirFuture;
  Directory? _resolvedDir;
  final SafeHttpClient _http;
  final void Function(DownloadProgressUpdate update) _publish;
  final FreeSpaceProvider _freeSpaceProvider;

  /// Told how many web-link downloads run whenever that changes (Settings
  /// keeps the yt-dlp Update and Reset buttons off while any run).
  final void Function(int running)? _onRunningChanged;

  final Set<String> _running = {};
  final Set<String> _paused = {};
  final Set<String> _cancelled = {};

  /// Downloads inside a yt-dlp run right now (yt-dlp's files are in use).
  final Set<String> _inYtDlp = {};

  /// Failed downloads waiting to update yt-dlp. While there are any, new
  /// downloads hold back before starting yt-dlp, so the update never
  /// replaces it under a running one.
  int _updateWaiters = 0;

  /// Longest a failed download waits for the others to finish before it
  /// updates yt-dlp (after that it gives up on the update).
  final Duration _updateWaitLimit;

  /// Something the waits above depend on changed (a run ended, a pause or
  /// cancel, an update finished).
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Added to the quality chip when the file is lower than the chosen
  /// quality (the same words as the YouTube fallback's chip).
  static const String lowerQualityNote = 'lower quality';

  static const _videoExts = {'mp4', 'webm', 'mkv', 'mov', 'm4v'};

  /// [downloadDir] is either the folder itself or a future of it.
  /// [freeSpaceProvider] defaults to the same check [DownloadEngine] uses.
  /// [autoUpdater] and [fallback] are optional (without them a failure just
  /// ends the download as failed).
  ExtractorDownloadRunner({
    required AppDatabase db,
    required ExtractorBackend backend,
    required FutureOr<Directory> downloadDir,
    required void Function(DownloadProgressUpdate update) publish,
    SafeHttpClient? httpClient,
    FreeSpaceProvider? freeSpaceProvider,
    void Function(int running)? onRunningChanged,
    ExtractorAutoUpdater? autoUpdater,
    ExtractorFallback? fallback,
    Duration updateWaitLimit = const Duration(minutes: 10),
  })  : _db = db, // ignore: prefer_initializing_formals
        _updateWaitLimit = updateWaitLimit, // ignore: prefer_initializing_formals
        _onRunningChanged = onRunningChanged, // ignore: prefer_initializing_formals
        _autoUpdater = autoUpdater, // ignore: prefer_initializing_formals
        _fallback = fallback, // ignore: prefer_initializing_formals
        _backend = backend, // ignore: prefer_initializing_formals
        _downloadDirFuture = DownloadEngine.settleDirectory(downloadDir),
        _publish = publish, // ignore: prefer_initializing_formals
        _http = httpClient ?? SafeHttpClient(),
        _freeSpaceProvider = freeSpaceProvider ?? DownloadEngine.defaultFreeSpaceProvider {
    if (downloadDir is Directory) {
      _resolvedDir = downloadDir;
    } else {
      _downloadDirFuture.then<void>((dir) => _resolvedDir = dir, onError: (Object _) {});
    }
  }

  /// yt-dlp writes its partial and intermediate files here (kept apart from
  /// the finished library files). Throws [StateError] while the download
  /// folder is still resolving; internal code awaits [_workDirOrNull] instead.
  Directory get workDir {
    final dir = _resolvedDir;
    if (dir == null) throw StateError('The download folder is not known yet.');
    return _workDirIn(dir);
  }

  static Directory _workDirIn(Directory downloadDir) => Directory(p.join(downloadDir.path, 'ytdlp'));

  /// The work folder, or null when the download folder cannot be resolved.
  Future<Directory?> _workDirOrNull() async {
    try {
      return _workDirIn(await _downloadDirFuture);
    } catch (_) {
      return null;
    }
  }

  static const int _freeSpaceMarginBytes = 200 * 1024 * 1024;

  /// Space a web-link download needs before yt-dlp starts: while ffmpeg merges,
  /// the separate streams and the merged output exist at the same time, plus a
  /// 200 MB margin. An unknown size counts as the 2 GB limit.
  ///
  /// [existingWorkBytes] is what earlier attempts already left in `ytdlp/`
  /// (a resume continues from it), so it is not needed a second time. The
  /// result never drops below the 200 MB margin.
  static int requiredFreeBytes(int? totalBytes, {int existingWorkBytes = 0}) {
    final size = (totalBytes != null && totalBytes > 0) ? totalBytes : DownloadEngine.maxDownloadSizeBytes;
    final needed = size * 2 + _freeSpaceMarginBytes - (existingWorkBytes > 0 ? existingWorkBytes : 0);
    return needed < _freeSpaceMarginBytes ? _freeSpaceMarginBytes : needed;
  }

  bool isRunning(String id) => _running.contains(id);

  /// Web-link downloads running now.
  int get runningCount => _running.length;

  void _reportRunning() {
    try {
      _onRunningChanged?.call(_running.length);
    } catch (_) {}
    _signalChange();
  }

  void _signalChange() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// The next change (see [_changes]), or [deadline], or 5 seconds: the
  /// caller checks its condition again either way.
  Future<void> _nextChange(DateTime deadline) {
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) return Future<void>.value();
    final wait = left < const Duration(seconds: 5) ? left : const Duration(seconds: 5);
    return _changes.stream.first.timeout(wait, onTimeout: () {});
  }

  /// A failed download is about to update yt-dlp: a new one starts its own
  /// yt-dlp run only after that.
  Future<void> _holdForUpdate(String id) async {
    while (_updateWaiters > 0 && !_stopped(id)) {
      await _nextChange(DateTime.now().add(const Duration(seconds: 5)));
    }
  }

  // ---------------------------------------------------------------- enqueue

  static int _lastIdMicros = 0;

  /// 'x' and the time in microseconds, never the same twice (two downloads
  /// queued within the clock's resolution got the same id).
  static String _newId() {
    var t = DateTime.now().microsecondsSinceEpoch;
    if (t <= _lastIdMicros) t = _lastIdMicros + 1;
    _lastIdMicros = t;
    return 'x$t';
  }

  /// Creates the queue row (state `queued`) and starts fetching the thumbnail.
  /// The caller triggers the queue coordinator afterwards.
  Future<String> enqueue({
    required ExtractorMetadata meta,
    required String pageUrl,
    required FormatChoice choice,
  }) async {
    final id = _newId();
    final host = Uri.tryParse(pageUrl)?.host ?? '';
    final title = meta.title.trim().isEmpty ? 'Media' : meta.title.trim();
    final guessedExt = choice.isAudio ? (AudioConversion.parse(choice.audioFormat)?.codec ?? 'm4a') : 'mp4';
    final now = DateTime.now();

    // Queueing only writes the row; run() creates the folders it writes to.
    await _db.into(_db.downloadsTable).insert(
          DownloadsTableCompanion.insert(
            id: id,
            url: pageUrl,
            host: host,
            displayName: title,
            fileName: SafeFilename.sanitize('$title.$guessedExt'),
            state: DownloadTaskState.queued.name,
            createdAt: now,
            updatedAt: now,
            totalBytes: Value(choice.estimatedBytes),
            kind: Value(choice.isAudio ? 'audio' : 'video'),
            engine: const Value('extractor'),
            thumbnailUrl: Value(meta.thumbnailUrl.isEmpty ? null : meta.thumbnailUrl),
            qualityLabel: Value(choice.qualityLabel),
            formatSelector: Value(choice.selector),
            audioFormat: Value(choice.audioFormat),
            extractorArgs: Value(meta.extractorArgs),
            uploader: Value(meta.uploader.isEmpty ? null : meta.uploader),
            durationSec: Value(meta.durationSec > 0 ? meta.durationSec : null),
            streamSizes: Value(jsonEncode(choice.streamSizes)),
          ),
        );

    DiagnosticsService.instance.logEvent('extractor_download_queued', {
      'host': host,
      'quality': choice.qualityLabel,
    });

    unawaited(_fetchThumbnail(id, meta.thumbnailUrl));
    return id;
  }

  /// Cover images are cosmetic: wait for the real folder, never fail over it.
  Future<void> _fetchThumbnail(String id, String url) async {
    try {
      final dir = await _downloadDirFuture;
      await ThumbnailFetcher(db: _db, http: _http, dir: dir).fetchFor(id, url);
    } catch (_) {}
  }

  // -------------------------------------------------------------------- run

  Future<void> run(String id) async {
    if (!_running.add(id)) return;
    _reportRunning();
    _paused.remove(id);
    _cancelled.remove(id);
    try {
      await _runInner(id);
    } catch (e) {
      // Anything unexpected (rename / database error while finalizing, ...)
      // must still end in a terminal state, or the row stays active with no
      // worker: the coordinator loses a slot and the foreground service and
      // wake lock never stop.
      await _failAfterUnexpectedError(id, e);
    } finally {
      _running.remove(id);
      _reportRunning();
    }
  }

  Future<void> _failAfterUnexpectedError(String id, Object error) async {
    // A pause/cancel that raced the error already put the row where it belongs.
    if (_stopped(id)) return;
    try {
      final host = (await _row(id))?.host ?? '';
      await _fail(
        id,
        host,
        DownloadEngine.unexpectedErrorCode(error),
        detail: DownloadEngine.sanitizedErrorReason(error),
      );
    } catch (_) {
      // The database itself is failing: nothing more can be recorded.
    }
  }

  bool _stopped(String id) => _paused.contains(id) || _cancelled.contains(id);

  Future<void> _runInner(String id) async {
    final row = await _row(id);
    if (row == null) return;

    // Every state write below is preceded by a stop check with no await in
    // between: a pause / cancel that landed while this task was waiting has
    // already written its state, and overwriting it would leave the row
    // active with no worker (a lost slot, a service that never stops). A
    // pause / cancel after a check writes later, so it still wins.
    if (_stopped(id)) return;
    await _setState(id, DownloadTaskState.preparing);

    // The real download folder (never a fallback): waits for it at app start.
    // Resolved first because the free-space check below needs the work files.
    final Directory downloadDir;
    final Directory workDir;
    try {
      downloadDir = await _downloadDirFuture;
      workDir = _workDirIn(downloadDir);
      workDir.createSync(recursive: true);
    } catch (_) {
      await _fail(id, row.host, 'write_failed');
      return;
    }
    // A pause / cancel while the folder was resolving (app start) wins.
    if (_stopped(id)) return;

    // Same free-space check (and error) as direct-link downloads, sized for the
    // merge step: refuse up front rather than filling the device mid-merge. A
    // resume does not need room again for the parts it already has.
    final freeBytes = await _freeSpaceProvider();
    final existingWorkBytes = _workBytesIn(workDir, id);
    if (freeBytes != null && freeBytes < requiredFreeBytes(row.totalBytes, existingWorkBytes: existingWorkBytes)) {
      await _fail(id, row.host, 'insufficient_disk_space');
      return;
    }

    try {
      await _backend.init();
    } catch (e) {
      final code = e is ExtractorException ? e.code : 'INIT_FAILED';
      // yt-dlp cannot run at all: a YouTube video can still be saved without it.
      if (ExtractorErrors.youtubeFallbackMayHelp.contains(code) && await _saveAnotherWay(id, row)) return;
      if (_stopped(id)) return;
      await _fail(id, row.host, 'x_${code.toLowerCase()}');
      return;
    }
    // Another download failed and is about to update yt-dlp: this one starts
    // after that (it then runs with the new yt-dlp too).
    await _holdForUpdate(id);
    // Covers every wait above (folder, free space, init, update): see the top.
    if (_stopped(id)) return;

    await _setState(id, DownloadTaskState.downloading);
    // A pause / cancel during that write may already have called
    // backend.cancel, which a download started afterwards would not see (the
    // native side forgets earlier cancels when a download starts): do not
    // start yt-dlp at all. Nothing awaits between here and the download call.
    if (_stopped(id)) return;

    // Downloads queued by older versions keep their strict selector: give them
    // the catch-all too, so a retry saves the nearest quality instead of
    // failing with "Requested format is not available" again.
    final isAudio = row.kind == 'audio' || (row.audioFormat ?? '').isNotEmpty;
    final storedSelector = row.formatSelector;
    final selector = storedSelector == null || storedSelector.isEmpty
        ? storedSelector
        : FormatOptions.withCatchAll(storedSelector, audio: isAudio);
    final formatSort = FormatOptions.formatSortFor(selector, audioFormat: row.audioFormat);

    final expected = _decodeSizes(row.streamSizes);
    final parsed = <int>[];
    var streamIndex = 0;
    var lastPct = 0.0;
    var received = 0;
    int? total = row.totalBytes;
    double? speed;
    var lastDbWrite = DateTime.fromMillisecondsSinceEpoch(0);
    var startedAt = DateTime.now();
    var mergeStateShown = false;

    List<int> sizes() => expected.isNotEmpty ? expected : parsed;

    void onLine(String line) {
      // After the last stream yt-dlp merges / converts with ffmpeg: say so.
      if (!mergeStateShown &&
          (line.contains('[Merger]') || line.contains('[ExtractAudio]') || line.contains('[VideoConvertor]'))) {
        mergeStateShown = true;
        unawaited(_setState(id, DownloadTaskState.finalizing));
      }
      final s = _parseSpeed(line);
      if (s != null) speed = s;
      final sz = _parseStreamSize(line);
      if (sz != null && expected.isEmpty) {
        while (parsed.length <= streamIndex) {
          parsed.add(0);
        }
        parsed[streamIndex] = sz;
        total = parsed.fold<int>(0, (a, b) => a + b);
      }
    }

    void onProgress(double pct, int etaSec) {
      if (_stopped(id)) return;
      // yt-dlp reports each stream (video, then audio) from 0..100%.
      if (pct + 40 < lastPct) streamIndex++;
      lastPct = pct;

      final all = sizes();
      var done = 0;
      for (var i = 0; i < streamIndex && i < all.length; i++) {
        done += all[i];
      }
      final current = streamIndex < all.length ? all[streamIndex] : 0;

      if (all.isNotEmpty) {
        received = (done + current * (pct / 100)).round();
      } else if (total != null && total! > 0) {
        received = (total! * (pct / 100)).round();
      }
      final t = total;
      if (t != null && t > 0 && received > t) received = t;

      final now = DateTime.now();
      double? effSpeed = speed;
      if (effSpeed == null || effSpeed <= 0) {
        final secs = now.difference(startedAt).inMilliseconds / 1000.0;
        if (secs > 1 && received > 0) effSpeed = received / secs;
      }

      Duration? eta;
      if (etaSec > 0) {
        var remaining = etaSec;
        if (t != null && effSpeed != null && effSpeed > 0 && all.isNotEmpty) {
          // Streams that have not started yet add to the remaining time.
          var later = 0;
          for (var i = streamIndex + 1; i < all.length; i++) {
            later += all[i];
          }
          remaining += (later / effSpeed).round();
        }
        eta = Duration(seconds: remaining);
      }

      _publish(DownloadProgressUpdate(
        id: id,
        receivedBytes: received,
        totalBytes: t,
        progress: (t != null && t > 0) ? (received / t).clamp(0.0, 1.0) : pct / 100,
        speedBytesPerSec: effSpeed,
        eta: eta,
      ));

      if (now.difference(lastDbWrite).inMilliseconds >= 1000) {
        lastDbWrite = now;
        unawaited((_db.update(_db.downloadsTable)..where((tbl) => tbl.id.equals(id))).write(
          DownloadsTableCompanion(
            receivedBytes: Value(received),
            totalBytes: Value(t),
            updatedAt: Value(now),
          ),
        ));
      }
    }

    ExtractorDownloadResult result;
    var updateTried = false;
    while (true) {
      // When this try began: a newer yt-dlp installed after it (by another
      // download's update) is worth one more try without updating again.
      final triedAt = DateTime.now();
      try {
        _inYtDlp.add(id);
        try {
          result = await _backend.download(
            taskId: id,
            url: row.url,
            outDir: workDir.path,
            formatSelector: selector,
            formatSort: formatSort,
            extractorArgs: row.extractorArgs,
            audioFormat: AudioConversion.parse(row.audioFormat)?.codec,
            audioQuality: AudioConversion.parse(row.audioFormat)?.quality,
            onProgress: onProgress,
            onLine: onLine,
          );
        } finally {
          _inYtDlp.remove(id);
          _signalChange();
        }
        break;
      } on ExtractorException catch (e) {
        if (_stopped(id)) return;
        DiagnosticsService.instance.logEvent('extractor_download_failed', {
          'host': row.host,
          'code': e.code,
          if (e.details != null) 'reason': e.details,
        });
        // The site may have changed: a newer yt-dlp, then one more try.
        if (!updateTried && ExtractorErrors.updateMayHelp.contains(e.code) && await _updateYtDlp(id, triedAt)) {
          updateTried = true;
          if (_stopped(id)) return;
          await _setState(id, DownloadTaskState.downloading);
          // See the first start above: no await between this and the download.
          if (_stopped(id)) return;
          // The retry reports its streams from the start again.
          parsed.clear();
          streamIndex = 0;
          lastPct = 0;
          received = 0;
          total = row.totalBytes;
          speed = null;
          startedAt = DateTime.now();
          mergeStateShown = false;
          continue;
        }
        updateTried = true;
        // YouTube: save the file YouTube serves directly (lower quality).
        if (ExtractorErrors.youtubeFallbackMayHelp.contains(e.code) && await _saveAnotherWay(id, row)) return;
        if (_stopped(id)) return;
        await _fail(id, row.host, 'x_${e.code.toLowerCase()}', detail: e.details);
        return;
      } catch (e) {
        if (_stopped(id)) return;
        await _fail(id, row.host, 'x_error');
        return;
      }
    }

    if (_stopped(id)) return;
    await _setState(id, DownloadTaskState.finalizing);
    await _finalize(id, result.filePath, downloadDir, hasVideo: result.hasVideo, height: result.height);
  }

  /// Updates yt-dlp after a failure it may fix (see [ExtractorAutoUpdater]).
  /// True when a newer yt-dlp is in place and the download should be tried
  /// again: installed now, or by another download's update since [triedAt].
  ///
  /// yt-dlp is never replaced under a running download: while other
  /// downloads run it, this one waits for them (shown as Preparing, at most
  /// [_updateWaitLimit]) and new ones hold back; then one update serves every
  /// download that failed meanwhile. Before, downloads that failed together
  /// all skipped the update and went straight to the lower-quality fallback.
  Future<bool> _updateYtDlp(String id, DateTime triedAt) async {
    final updater = _autoUpdater;
    if (updater == null) return false;
    if (_stopped(id)) return false;
    await _setState(id, DownloadTaskState.preparing);
    if (_updatedSince(updater, triedAt)) return true;
    _updateWaiters++;
    try {
      final deadline = DateTime.now().add(_updateWaitLimit);
      while (_inYtDlp.isNotEmpty && !_stopped(id) && DateTime.now().isBefore(deadline)) {
        await _nextChange(deadline);
      }
      if (_stopped(id)) return false;
      if (_updatedSince(updater, triedAt)) return true;
      ExtractorUpdateOutcome outcome;
      try {
        outcome = await updater.updateAfterFailure(otherDownloadsRunning: _inYtDlp.isNotEmpty);
      } catch (_) {
        outcome = ExtractorUpdateOutcome.failed;
      }
      DiagnosticsService.instance.logEvent('extractor_auto_update', {'outcome': outcome.name});
      return outcome == ExtractorUpdateOutcome.updated || _updatedSince(updater, triedAt);
    } finally {
      _updateWaiters--;
      _signalChange();
    }
  }

  static bool _updatedSince(ExtractorAutoUpdater updater, DateTime since) {
    final at = updater.lastUpdated;
    return at != null && at.isAfter(since);
  }

  /// yt-dlp could not save YouTube video [row]: queue the file YouTube serves
  /// directly instead (see [ExtractorFallback]) and take this download out of
  /// the list. False (nothing changed) when that is not possible, so the
  /// caller marks the download failed.
  Future<bool> _saveAnotherWay(String id, DownloadEntry row) async {
    final fallback = _fallback;
    if (fallback == null || YoutubeLink.tryParse(row.url) == null) return false;
    if (_stopped(id)) return false;
    await _setState(id, DownloadTaskState.preparing);
    bool queued;
    try {
      queued = await fallback(row, stillWanted: () => !_stopped(id));
    } catch (_) {
      queued = false;
    }
    if (!queued) return false;
    DiagnosticsService.instance.logEvent('extractor_download_replaced', {'host': row.host});
    await _removeReplaced(id, row);
    return true;
  }

  /// Deletes the row of a download that was replaced by another one, with
  /// its yt-dlp work files and its cover image.
  Future<void> _removeReplaced(String id, DownloadEntry row) async {
    final dir = await _downloadDirFuture;
    _deleteWorkFilesIn(_workDirIn(dir), id);
    final thumb = row.thumbnailPath;
    if (thumb != null && p.isWithin(dir.path, thumb)) {
      try {
        final f = File(thumb);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    await (_db.delete(_db.downloadsTable)..where((t) => t.id.equals(id))).go();
  }

  /// Whether a finished download goes to Videos (true) or Music (false).
  /// Sound asked for ([kind] 'audio': "Original audio", MP3) is always Music,
  /// even when the site had only a file with pictures (TikTok and many X,
  /// Facebook and Instagram links). Otherwise what is in the file decides,
  /// as everywhere else in the app: first what the phone found when yt-dlp
  /// finished ([hasVideo]), then the shared [MediaKindClassifier]
  /// ([decision], when the file itself told it), so a "video" link that
  /// turns out to be sound only goes to Music. Only when neither could tell:
  /// the extension.
  static bool isVideoResult({
    required String ext,
    required String? kind,
    bool? hasVideo,
    MediaKindDecision? decision,
  }) {
    if (kind == 'audio') return false;
    if (hasVideo != null) return hasVideo;
    if (decision != null && decision.byContent) return decision.isVideo;
    return _videoExts.contains(ext);
  }

  /// The quality chip of a finished video. yt-dlp saves the nearest quality
  /// when the chosen one is missing, so when the file's own height
  /// ([savedHeight]) differs from the one in [label] ("1080p", "720p 60fps")
  /// the chip says what was saved: "360p · lower quality", or "1440p" for a
  /// higher one. Anything else keeps [label].
  static String? qualityLabelAfter(String? label, {int? savedHeight}) {
    if (label == null || savedHeight == null || savedHeight <= 0) return label;
    final m = RegExp(r'^(\d{3,4})p').firstMatch(label.trim());
    if (m == null) return label;
    final chosen = int.parse(m.group(1)!);
    if (chosen == savedHeight) return label;
    return savedHeight < chosen ? '${savedHeight}p · $lowerQualityNote' : '${savedHeight}p';
  }

  Future<void> _finalize(String id, String path, Directory downloadDir, {bool? hasVideo, int? height}) async {
    final row = await _row(id);
    if (row == null) return;
    final src = File(path);
    if (path.isEmpty || !src.existsSync() || src.lengthSync() == 0) {
      await _fail(id, row.host, 'x_no_output');
      return;
    }

    var ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (SafeFilename.reservedExtensions.contains('.$ext')) {
      // yt-dlp handed back one of its work files (.part, .ytdl, ...). A
      // finished file must never keep such an extension (cleanup would treat
      // it as garbage): name it after what it really is, or give up if it is
      // not recognisable media.
      final sniffed = _sniff(src);
      if (sniffed == null) {
        await _fail(id, row.host, 'x_no_output');
        return;
      }
      ext = DownloadEngine.extensionForMime(sniffed);
    }
    final decision = MediaKindClassifier.classifyFile(src, kindHint: row.kind, fileName: '${row.displayName}.$ext');
    final askedForSound = row.kind == 'audio' || (row.audioFormat ?? '').isNotEmpty;
    final isVideo =
        isVideoResult(ext: ext, kind: askedForSound ? 'audio' : row.kind, hasVideo: hasVideo, decision: decision);
    final qualityLabel = isVideo ? qualityLabelAfter(row.qualityLabel, savedHeight: height) : row.qualityLabel;
    final mimeType = decision != null && decision.isVideo == isVideo ? decision.mimeType : _mimeFor(ext, isVideo);
    final mediaType = isVideo ? MediaType.video : MediaType.audio;

    final baseName = p.basenameWithoutExtension(SafeFilename.sanitize('${row.displayName}.$ext'));
    var finalName = '$baseName.$ext';
    var dest = File(p.join(downloadDir.path, finalName));
    var n = 1;
    while (dest.existsSync()) {
      // Kept within the 255-byte name limit (long Devanagari titles).
      finalName = SafeFilename.numbered(baseName, n, '.$ext');
      dest = File(p.join(downloadDir.path, finalName));
      n++;
    }

    try {
      src.renameSync(dest.path);
    } catch (_) {
      try {
        src.copySync(dest.path);
        src.deleteSync();
      } catch (_) {
        // The work file is still there: drop a partial or duplicate copy so
        // no file without a row is left in the library folder.
        if (src.existsSync()) {
          try {
            if (dest.existsSync()) dest.deleteSync();
          } catch (_) {}
        }
        await _fail(id, row.host, 'write_failed');
        return;
      }
    }

    final mediaId = 'dl_$id';
    final int size;
    try {
      size = dest.lengthSync();
      final thumb = row.thumbnailPath;
      final hasThumb = thumb != null && File(thumb).existsSync();

      await _db.into(_db.mediaItemsTable).insertOnConflictUpdate(
            MediaItemsTableCompanion.insert(
              id: mediaId,
              uri: dest.path,
              mediaType: mediaType.name,
              title: row.displayName,
              artist: Value(row.uploader),
              durationMs: (row.durationSec ?? 0) * 1000,
              sizeBytes: size,
              format: Value(ext),
              dateAdded: DateTime.now(),
              availability: const Value('available'),
              source: const Value('download'),
              artworkPath: Value(hasThumb ? thumb : null),
            ),
          );

      await (_db.update(_db.downloadsTable)..where((t) => t.id.equals(id))).write(
        DownloadsTableCompanion(
          state: Value(DownloadTaskState.completed.name),
          kind: Value(isVideo ? 'video' : 'audio'),
          fileName: Value(finalName),
          finalPath: Value(dest.path),
          mediaId: Value(mediaId),
          mimeType: Value(mimeType),
          qualityLabel: Value(qualityLabel),
          receivedBytes: Value(size),
          totalBytes: Value(size),
          errorCode: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (_) {
      // Not recorded as finished: put the file back where yt-dlp left it
      // (`ytdlp/<id>.<ext>`, which a retry treats as already downloaded), so
      // the failed row still owns it. Otherwise it would stay in the library
      // folder with no row (invisible, never deleted) and a retry would
      // download it again as "name (1)". run() then marks the task failed.
      await DownloadEngine.undoFinalMove(_db, finalFile: dest, workFile: src, mediaId: mediaId);
      rethrow;
    }

    _publish(DownloadProgressUpdate(
      id: id,
      receivedBytes: size,
      totalBytes: size,
      progress: 1.0,
      eta: Duration.zero,
    ));

    _deleteWorkFilesIn(_workDirIn(downloadDir), id);
    DiagnosticsService.instance.logEvent('download_completed', {
      'host': row.host,
      'mime': mimeType,
      'bytes': size,
    });
  }

  // ---------------------------------------------------------- pause / cancel

  /// Stops the yt-dlp process but keeps its partial files so [run] can continue.
  Future<void> pause(String id) async {
    _paused.add(id);
    _signalChange();
    final row = await _row(id);
    if (row == null) return;
    if (row.state == DownloadTaskState.completed.name) return;
    await _backend.cancel(id);
    await _setState(id, DownloadTaskState.paused);
  }

  Future<void> cancel(String id) async {
    _cancelled.add(id);
    _signalChange();
    await _backend.cancel(id);
    await deleteWorkFiles(id);
    await _setState(id, DownloadTaskState.cancelled);
  }

  /// Deletes yt-dlp's partial and intermediate files of task [id]
  /// (`ytdlp/<id>.*`: `.part`, `.fNNN.*`, `.ytdl`, `.temp`, ...). Called on
  /// cancel, after a successful finalize, and when the user deletes the task
  /// from the Downloads list (otherwise a failed task's files would stay).
  Future<void> deleteWorkFiles(String id) async {
    final dir = await _workDirOrNull();
    if (dir != null) _deleteWorkFilesIn(dir, id);
  }

  /// Marks tasks that were interrupted by the app being killed as queued again.
  /// yt-dlp resumes from its partial files, so nothing is lost. Then removes
  /// work files that no unfinished task owns any more.
  Future<List<String>> reconcileOnStartup() async {
    final rows = await (_db.select(_db.downloadsTable)
          ..where((t) =>
              t.engine.equals('extractor') &
              t.state.isIn([
                DownloadTaskState.preparing.name,
                DownloadTaskState.downloading.name,
                DownloadTaskState.finalizing.name,
              ])))
        .get();
    for (final r in rows) {
      await _setState(r.id, DownloadTaskState.queued);
    }
    await _sweepOrphanWorkFiles();
    return rows.map((r) => r.id).toList();
  }

  /// Startup cleanup of `ytdlp/`: deletes every file whose task id (the name
  /// up to the first dot) has no unfinished row: rows the user deleted, and
  /// completed / cancelled tasks whose files a crash left behind. Failed and
  /// paused tasks keep their files, so a retry still resumes.
  Future<void> _sweepOrphanWorkFiles() async {
    try {
      final dir = await _workDirOrNull();
      if (dir == null || !dir.existsSync()) return;
      final rows = await _db.select(_db.downloadsTable).get();
      final liveIds = rows
          .where((r) => r.state != DownloadTaskState.completed.name && r.state != DownloadTaskState.cancelled.name)
          .map((r) => r.id)
          .toSet()
        ..addAll(_running);
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        final dot = name.indexOf('.');
        final ownerId = dot > 0 ? name.substring(0, dot) : name;
        if (liveIds.contains(ownerId)) continue;
        try {
          e.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  // ----------------------------------------------------------------- helpers

  /// yt-dlp's files of task [id] in [workDir] (`<id>.*`); empty if unreadable.
  static List<File> _workFilesIn(Directory workDir, String id) {
    try {
      if (!workDir.existsSync()) return const [];
      return workDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('$id.'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static void _deleteWorkFilesIn(Directory workDir, String id) {
    for (final f in _workFilesIn(workDir, id)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// Total size of task [id]'s work files (what a resume continues from).
  static int _workBytesIn(Directory workDir, String id) {
    var total = 0;
    for (final f in _workFilesIn(workDir, id)) {
      try {
        total += f.lengthSync();
      } catch (_) {}
    }
    return total;
  }

  /// MIME type from the first bytes of [file], or null if it is not media.
  static String? _sniff(File file) {
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        return MediaSniffer.sniff(raf.readSync(64));
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return null;
    }
  }

  Future<DownloadEntry?> _row(String id) {
    return (_db.select(_db.downloadsTable)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> _setState(String id, DownloadTaskState state) async {
    await (_db.update(_db.downloadsTable)..where((t) => t.id.equals(id))).write(
      DownloadsTableCompanion(
        state: Value(state.name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _fail(String id, String host, String code, {String? detail}) async {
    await (_db.update(_db.downloadsTable)..where((t) => t.id.equals(id))).write(
      DownloadsTableCompanion(
        state: Value(DownloadTaskState.failed.name),
        errorCode: Value(code),
        errorDetail: Value(detail == null || detail.isEmpty ? null : detail),
        updatedAt: Value(DateTime.now()),
      ),
    );
    DiagnosticsService.instance.logEvent('download_failed', {'host': host, 'code': code});
  }

  static List<int> _decodeSizes(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => (e as num).toInt()).where((e) => e > 0).toList();
    } catch (_) {
      return const [];
    }
  }

  static int _unit(String u) {
    switch (u.toUpperCase()) {
      case 'K':
        return 1024;
      case 'M':
        return 1024 * 1024;
      case 'G':
        return 1024 * 1024 * 1024;
      default:
        return 1;
    }
  }

  /// "[download]  45.3% of ~ 12.34MiB at  1.20MiB/s ETA 00:10" -> bytes/s
  static double? _parseSpeed(String line) {
    final m = RegExp(r'at\s+([\d.]+)\s*([KMG]?)i?B/s', caseSensitive: false).firstMatch(line);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null) return null;
    return v * _unit(m.group(2) ?? '');
  }

  /// "[download]  45.3% of ~ 12.34MiB ..." -> bytes of the current stream
  static int? _parseStreamSize(String line) {
    final m = RegExp(r'of\s+~?\s*([\d.]+)\s*([KMG]?)i?B', caseSensitive: false).firstMatch(line);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null) return null;
    return (v * _unit(m.group(2) ?? '')).round();
  }

  static String _mimeFor(String ext, bool isVideo) {
    switch (ext) {
      case 'mp4':
      case 'm4v':
        return isVideo ? 'video/mp4' : 'audio/mp4';
      case 'm4a':
        return 'audio/mp4';
      case 'webm':
        return isVideo ? 'video/webm' : 'audio/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'mov':
        return 'video/quicktime';
      case 'mp3':
        return 'audio/mpeg';
      case 'opus':
      case 'ogg':
        return 'audio/ogg';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/wav';
      default:
        return isVideo ? 'video/$ext' : 'audio/$ext';
    }
  }
}
