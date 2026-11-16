import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/security/safe_http_client.dart';
import '../../core/services/download_service_controller.dart';
import '../../data/downloads/download_engine.dart';
import '../../data/downloads/extractor_download_runner.dart';
import '../../personal/personal_tools_notifier.dart';
import '../music_player/playback_notifier.dart';

final downloadServiceControllerProvider = Provider<DownloadServiceController>((ref) {
  final controller = AndroidDownloadServiceController();
  ref.onDispose(() {
    controller.dispose();
  });
  return controller;
});

final downloadDirectoryProvider = FutureProvider<Directory>((ref) async {
  final appDir = await getApplicationDocumentsDirectory();
  final dir = Directory('${appDir.path}/downloads');
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
final downloadEngineProvider = Provider<DownloadEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final client = SafeHttpClient();

  final engine = DownloadEngine(
    db: db,
    httpClient: client,
    downloadDir: ref.watch(downloadDirectoryProvider.future),
  );

  ref.onDispose(() {
    engine.dispose();
  });

  return engine;
});

/// Runs yt-dlp web-link downloads. Shares the engine's progress stream so both
/// kinds of download update the same list.
final extractorDownloadRunnerProvider = Provider<ExtractorDownloadRunner>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final backend = ref.watch(extractorBackendProvider);
  final engine = ref.watch(downloadEngineProvider);
  return ExtractorDownloadRunner(
    db: db,
    backend: backend,
    // Same folder future as the engine (see above): no temp-dir fallback.
    downloadDir: ref.watch(downloadDirectoryProvider.future),
    publish: engine.publishProgress,
  );
});
