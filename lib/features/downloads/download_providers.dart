// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform_info.dart';
import '../../core/security/safe_http_client.dart';
import '../../core/services/download_service_controller.dart';
import '../../data/downloads/download_engine.dart';
import '../../data/downloads/extractor_download_runner.dart';
import '../../data/storage/download_folder.dart';
import '../../personal/personal_tools_notifier.dart';
import '../music_player/playback_notifier.dart';
import 'extractor_youtube_fallback.dart';
import 'youtube_direct_resolver.dart';
import 'youtube_link_refresher.dart';

final downloadServiceControllerProvider = Provider<DownloadServiceController>((ref) {
  final controller = AndroidDownloadServiceController();
  ref.onDispose(() {
    controller.dispose();
  });
  return controller;
});

final downloadDirectoryProvider = FutureProvider<Directory>((ref) async {
  // The same folder the database heals saved paths against when it opens.
  final dir = await appDownloadsFolder();
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
});

// The engine and the web-link runner get the download folder as a *future* and
// await it before any file operation. They used to fall back to the system temp
// folder until the documents folder resolved: a download finalized in that
// window landed in purgeable cache, and the engine was rebuilt (and the old one
// disposed mid-download) once the folder arrived. Watching `.future` does not
// rebuild when the future completes, only if the folder provider itself is
// recomputed, so one engine lives for the whole session. Queueing never waits
// for the folder; only the download itself does.
/// Free bytes where downloads are saved (overridden in tests). The engine
/// checks it before every download; the YouTube flow also checks it before
/// queueing, so a too-large file is refused at once instead of failing later.
/// It gives null on iOS (the phone cannot tell here), and both checks are
/// skipped.
final downloadFreeSpaceProvider = Provider<FreeSpaceProvider>((ref) => DownloadEngine.defaultFreeSpaceProvider);

final downloadEngineProvider = Provider<DownloadEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final client = SafeHttpClient();

  final engine = DownloadEngine(
    db: db,
    httpClient: client,
    downloadDir: ref.watch(downloadDirectoryProvider.future),
    freeSpaceProvider: ref.watch(downloadFreeSpaceProvider),
    // iPhone YouTube downloads keep YouTube's link to the file, which expires
    // after some hours: a resume or retry looks it up again. The resolver is
    // read only then, so the engine never rebuilds because of it. Android
    // keeps its yt-dlp path and its old behaviour (no lookups).
    streamLinkRefresher: PlatformInfo.isIOS
        ? YoutubeLinkRefresher(resolver: () => ref.read(youtubeDirectResolverProvider))
        : null,
  );

  ref.onDispose(() {
    engine.dispose();
  });

  return engine;
});

/// How many yt-dlp web-link downloads run right now. The runner reports into
/// it, so Settings can keep "Update" and "Use the built-in yt-dlp" off
/// meanwhile without building the download machinery itself.
class ExtractorRunningDownloadsNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int running) {
    final value = running < 0 ? 0 : running;
    if (value != state) state = value;
  }
}

final extractorRunningDownloadsProvider =
    NotifierProvider<ExtractorRunningDownloadsNotifier, int>(ExtractorRunningDownloadsNotifier.new);

/// Runs yt-dlp web-link downloads. Shares the engine's progress stream so both
/// kinds of download update the same list.
final extractorDownloadRunnerProvider = Provider<ExtractorDownloadRunner>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final backend = ref.watch(extractorBackendProvider);
  final engine = ref.watch(downloadEngineProvider);
  final running = ref.read(extractorRunningDownloadsProvider.notifier);
  return ExtractorDownloadRunner(
    db: db,
    backend: backend,
    // Same folder future as the engine (see above): no temp-dir fallback.
    downloadDir: ref.watch(downloadDirectoryProvider.future),
    publish: engine.publishProgress,
    onRunningChanged: running.set,
    // yt-dlp out of date: it updates itself and tries again (see ExtractorAutoUpdater).
    autoUpdater: ref.watch(extractorAutoUpdaterProvider),
    // Last resort for YouTube: the file YouTube serves directly, at a lower quality.
    fallback: ExtractorYoutubeFallback(
      engine: engine,
      resolver: () => ref.read(youtubeDirectResolverProvider),
    ).call,
  );
});
