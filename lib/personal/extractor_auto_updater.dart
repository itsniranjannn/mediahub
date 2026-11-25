// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/platform_info.dart';
import '../core/storage/settings_store.dart';
import 'extractor_backend.dart';

/// How one update attempt ended.
enum ExtractorUpdateOutcome {
  /// A newer yt-dlp was installed: worth trying the failed link again.
  updated,

  /// yt-dlp was already the newest.
  upToDate,

  /// Not tried: too soon since the last try, a web link download is running,
  /// metered data, or not on Android.
  skipped,

  /// Tried and failed (offline, GitHub not reachable ...).
  failed,
}

/// Keeps yt-dlp current without the user having to think about it.
///
/// * After a lookup or download fails in a way a newer yt-dlp may fix
///   ([updateAfterFailure]): update, at most once every 12 hours, never while
///   another web link download runs (the native side also refuses then).
/// * A quiet check at app start ([backgroundCheck]), at most once a week, not
///   on metered data when the phone can tell.
/// * Settings' Update button ([updateNow]) is remembered the same way.
///
/// When each happened is kept in the settings file, so Settings can say when
/// yt-dlp was last updated or checked.
class ExtractorAutoUpdater extends ChangeNotifier {
  ExtractorAutoUpdater({
    required ExtractorBackend backend,
    SettingsStore? store,
    DateTime Function()? clock,
    bool Function()? enabled,
    this.backgroundChecks = false,
    this.updateTimeout = const Duration(minutes: 2),
  })  : _backend = backend, // ignore: prefer_initializing_formals
        _store = store ?? SettingsStore.instance,
        _clock = clock ?? DateTime.now,
        _enabled = enabled ?? (() => PlatformInfo.isAndroid && kPersonalToolsEnabled);

  final ExtractorBackend _backend;
  final SettingsStore _store;
  final DateTime Function() _clock;
  final bool Function() _enabled;

  /// Whether [backgroundCheck] may run at all (off in debug builds and tests,
  /// so no test or development run ever downloads a new yt-dlp by itself).
  final bool backgroundChecks;

  /// Longest an update may take before the caller stops waiting for it.
  final Duration updateTimeout;

  /// Least time between two updates started by a failure.
  static const Duration failureCooldown = Duration(hours: 12);

  /// Least time between two quiet checks at app start.
  static const Duration backgroundInterval = Duration(days: 7);

  /// A quiet check that did not get through (offline, GitHub not reachable)
  /// is tried again after this long, not at every start.
  static const Duration backgroundRetryInterval = Duration(days: 1);

  /// When the quiet check last tried, whatever came of it.
  static const String lastBackgroundAttemptKey = 'ytdlp_bg_attempt_at';

  /// When an update after a failure last ran (milliseconds since epoch).
  static const String lastFailureUpdateKey = 'ytdlp_failure_update_at';

  /// When yt-dlp was last checked for a new version, by any of the three ways.
  static const String lastCheckKey = 'ytdlp_checked_at';

  /// When a new yt-dlp version was last installed.
  static const String lastUpdatedKey = 'ytdlp_updated_at';

  Future<ExtractorUpdateOutcome>? _running;

  DateTime? get lastChecked => _time(lastCheckKey);
  DateTime? get lastUpdated => _time(lastUpdatedKey);

  /// True while an update started here is running.
  bool get isUpdating => _running != null;

  DateTime? _time(String key) {
    final ms = int.tryParse(_store.getString(key) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _remember(String key, DateTime at) => _store.setString(key, '${at.millisecondsSinceEpoch}');

  /// True when [key] was set less than [interval] ago. A time in the future
  /// (the phone's clock was moved back) does not count.
  bool _tooSoon(String key, Duration interval) {
    final last = _time(key);
    if (last == null) return false;
    final now = _clock();
    if (last.isAfter(now)) return false;
    return now.difference(last) < interval;
  }

  /// A lookup or download just failed with an error a newer yt-dlp may fix.
  /// Updates yt-dlp unless that was tried in the last 12 hours or
  /// [otherDownloadsRunning] (replacing yt-dlp would break them). Only
  /// [ExtractorUpdateOutcome.updated] makes trying again worthwhile.
  Future<ExtractorUpdateOutcome> updateAfterFailure({bool otherDownloadsRunning = false}) async {
    if (!_enabled() || otherDownloadsRunning) return ExtractorUpdateOutcome.skipped;
    final running = _running;
    // Another failure already started one: share its result.
    if (running != null) return running;
    if (_tooSoon(lastFailureUpdateKey, failureCooldown)) return ExtractorUpdateOutcome.skipped;
    final outcome = await _run();
    // A refusal because something was running is not a try: the next failure may try.
    if (outcome != ExtractorUpdateOutcome.skipped) await _remember(lastFailureUpdateKey, _clock());
    return outcome;
  }

  /// The quiet check at app start: at most once a week (a try that failed:
  /// again the next day), not on metered data.
  Future<ExtractorUpdateOutcome> backgroundCheck() async {
    if (!backgroundChecks || !_enabled() || _running != null) return ExtractorUpdateOutcome.skipped;
    if (_tooSoon(lastCheckKey, backgroundInterval)) return ExtractorUpdateOutcome.skipped;
    if (_tooSoon(lastBackgroundAttemptKey, backgroundRetryInterval)) return ExtractorUpdateOutcome.skipped;
    bool? metered;
    try {
      metered = await _backend.isMeteredNetwork();
    } catch (_) {
      metered = null;
    }
    if (metered == true) return ExtractorUpdateOutcome.skipped;
    await _remember(lastBackgroundAttemptKey, _clock());
    return _run();
  }

  /// Settings' Update button: the native status ('DONE' or
  /// 'ALREADY_UP_TO_DATE'), remembered like the automatic updates. Throws
  /// what the backend throws (an `ExtractorException` with code `BUSY` while
  /// a download runs).
  Future<String> updateNow() async {
    final status = await _backend.update();
    await _recordSuccess(status);
    return status;
  }

  Future<void> _recordSuccess(String status) async {
    final now = _clock();
    await _remember(lastCheckKey, now);
    if (status.toUpperCase() != 'ALREADY_UP_TO_DATE') await _remember(lastUpdatedKey, now);
    // An update can finish after the app let go of this object.
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<ExtractorUpdateOutcome> _run() {
    final running = _running;
    if (running != null) return running;
    final future = _update();
    _running = future;
    future.whenComplete(() => _running = null).ignore();
    return future;
  }

  Future<ExtractorUpdateOutcome> _update() async {
    try {
      final status = await _backend.update().timeout(updateTimeout);
      await _recordSuccess(status);
      return status.toUpperCase() == 'ALREADY_UP_TO_DATE'
          ? ExtractorUpdateOutcome.upToDate
          : ExtractorUpdateOutcome.updated;
    } on ExtractorException catch (e) {
      // A lookup or download is running yt-dlp right now.
      if (e.code == 'BUSY') return ExtractorUpdateOutcome.skipped;
      return ExtractorUpdateOutcome.failed;
    } catch (_) {
      return ExtractorUpdateOutcome.failed;
    }
  }
}
