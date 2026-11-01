import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/security/safe_http_client.dart';
import '../../core/services/download_service_controller.dart';
import '../../data/downloads/download_engine.dart';
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

final downloadEngineProvider = Provider<DownloadEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final client = SafeHttpClient();
  // Using late / temporary directory if future not resolved yet, or app documents dir
  final dirAsync = ref.watch(downloadDirectoryProvider);
  final dir = dirAsync.asData?.value ?? Directory.systemTemp;

  final engine = DownloadEngine(
    db: db,
    httpClient: client,
    downloadDir: dir,
  );

  ref.onDispose(() {
    engine.dispose();
  });

  return engine;
});

